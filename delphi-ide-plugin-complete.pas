unit DelphiIDESwitcherPlugin;

{
  Delphi IDE Plugin for IDE Switcher
  
  FEATURES:
  - Handles Ctrl+Shift+D hotkey within Delphi IDE
  - Automatically saves current file before switching
  - Sends file path and cursor position to VS Code
  - Receives switch requests from VS Code and opens files at correct position
  - No global hotkey needed - all handled within the IDEs
}

interface

uses
  Windows, SysUtils, Classes, ToolsAPI, Menus, ActnList, Dialogs,
  System.JSON, System.IOUtils, System.Threading;

type
  TIDESwitcherNotifier = class(TNotifierObject, IOTAKeyboardBinding)
  private
    FPipeName: string;
    FVSCodeCommand: string;
    
    procedure HandleSwitchToVSCode(const Context: IOTAKeyContext; KeyCode: TShortcut;
      var BindingResult: TKeyBindingResult);
    function GetCurrentEditorInfo: TJSONObject;
    procedure SaveCurrentFile;
    procedure SendToVSCode(const FileInfo: TJSONObject);
    procedure LaunchVSCodeWithFile(const FilePath: string; Line, Column: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    
    // IOTAKeyboardBinding
    function GetBindingType: TBindingType;
    function GetDisplayName: string;
    function GetName: string;
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
  end;

  TPipeServerThread = class(TThread)
  private
    FPipeName: string;
    procedure HandleVSCodeRequest(const JSONData: string);
    procedure OpenFileInDelphi(const FilePath: string; Line, Column: Integer);
  protected
    procedure Execute; override;
  public
    constructor Create(const PipeName: string);
  end;

  TIDESwitcherWizard = class(TNotifierObject, IOTAWizard)
  private
    FKeyBindingIndex: Integer;
    FServerThread: TPipeServerThread;
  public
    constructor Create;
    destructor Destroy; override;
    
    // IOTAWizard
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

var
  WizardIndex: Integer = -1;

implementation

const
  PIPE_NAME_TO_VSCODE = '\\.\pipe\IDESwitcher_ToVSCode';
  PIPE_NAME_FROM_VSCODE = '\\.\pipe\IDESwitcher_ToDelphi';
  VSCODE_COMMAND = 'code'; // Or full path to WindSurf executable

{ TIDESwitcherNotifier }

constructor TIDESwitcherNotifier.Create;
begin
  inherited;
  FPipeName := PIPE_NAME_TO_VSCODE;
  FVSCodeCommand := VSCODE_COMMAND;
end;

destructor TIDESwitcherNotifier.Destroy;
begin
  inherited;
end;

function TIDESwitcherNotifier.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TIDESwitcherNotifier.GetDisplayName: string;
begin
  Result := 'IDE Switcher - Switch to VS Code/WindSurf';
end;

function TIDESwitcherNotifier.GetName: string;
begin
  Result := 'IDESwitcher.SwitchToVSCode';
end;

procedure TIDESwitcherNotifier.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  // Bind Ctrl+Shift+D to switch to VS Code
  BindingServices.AddKeyBinding([TextToShortCut('Ctrl+Shift+D')], HandleSwitchToVSCode, nil);
end;

procedure TIDESwitcherNotifier.HandleSwitchToVSCode(const Context: IOTAKeyContext;
  KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
var
  FileInfo: TJSONObject;
begin
  BindingResult := krHandled;
  
  try
    // Step 1: Save current file
    SaveCurrentFile;
    
    // Step 2: Get current editor information (file path, line, column)
    FileInfo := GetCurrentEditorInfo;
    try
      if FileInfo.GetValue<string>('filePath') <> '' then
      begin
        // Step 3: Send to VS Code (which will open the file and position cursor)
        SendToVSCode(FileInfo);
      end
      else
        ShowMessage('No active file to switch');
    finally
      FileInfo.Free;
    end;
  except
    on E: Exception do
      ShowMessage('Error switching to VS Code: ' + E.Message);
  end;
end;

procedure TIDESwitcherNotifier.SaveCurrentFile;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
begin
  ModuleServices := BorlandIDEServices as IOTAModuleServices;
  Module := ModuleServices.CurrentModule;
  
  if (Module <> nil) and Module.Modified then
  begin
    Module.Save(False, True);
  end;
end;

function TIDESwitcherNotifier.GetCurrentEditorInfo: TJSONObject;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
  EditView: IOTAEditView;
  EditPos: TOTAEditPos;
  CharPos: TOTACharPos;
  FilePath: string;
begin
  Result := TJSONObject.Create;
  
  ModuleServices := BorlandIDEServices as IOTAModuleServices;
  Module := ModuleServices.CurrentModule;
  
  if Module <> nil then
  begin
    Editor := Module.CurrentEditor;
    if (Editor <> nil) and (Editor.QueryInterface(IOTASourceEditor, SourceEditor) = S_OK) then
    begin
      FilePath := SourceEditor.FileName;
      Result.AddPair('filePath', FilePath);
      Result.AddPair('action', 'switch');
      
      // Get cursor position
      EditView := SourceEditor.GetEditView(0);
      if EditView <> nil then
      begin
        EditPos := EditView.CursorPos;
        EditView.ConvertPos(True, EditPos, CharPos);
        
        Result.AddPair('line', TJSONNumber.Create(EditPos.Line));
        Result.AddPair('column', TJSONNumber.Create(EditPos.Col));
      end
      else
      begin
        Result.AddPair('line', TJSONNumber.Create(1));
        Result.AddPair('column', TJSONNumber.Create(1));
      end;
      
      // Add context
      Result.AddPair('source', 'delphi');
      Result.AddPair('timestamp', DateTimeToStr(Now));
    end
    else
      Result.AddPair('filePath', '');
  end
  else
    Result.AddPair('filePath', '');
end;

procedure TIDESwitcherNotifier.SendToVSCode(const FileInfo: TJSONObject);
var
  PipeHandle: THandle;
  BytesWritten: DWORD;
  Message: AnsiString;
  Retries: Integer;
  Success: Boolean;
begin
  Success := False;
  Retries := 0;
  
  // Try to connect to VS Code extension's pipe server
  while (not Success) and (Retries < 3) do
  begin
    PipeHandle := CreateFile(
      PChar(FPipeName),
      GENERIC_WRITE,
      0,
      nil,
      OPEN_EXISTING,
      0,
      0
    );
    
    if PipeHandle <> INVALID_HANDLE_VALUE then
    begin
      try
        Message := AnsiString(FileInfo.ToString);
        if WriteFile(PipeHandle, Message[1], Length(Message), BytesWritten, nil) then
        begin
          FlushFileBuffers(PipeHandle);
          Success := True;
        end;
      finally
        CloseHandle(PipeHandle);
      end;
    end
    else
    begin
      Inc(Retries);
      if Retries < 3 then
        Sleep(100);
    end;
  end;
  
  if not Success then
  begin
    // If pipe communication fails, launch VS Code directly with command line
    LaunchVSCodeWithFile(
      FileInfo.GetValue<string>('filePath'),
      FileInfo.GetValue<Integer>('line'),
      FileInfo.GetValue<Integer>('column')
    );
  end;
end;

procedure TIDESwitcherNotifier.LaunchVSCodeWithFile(const FilePath: string; 
  Line, Column: Integer);
var
  CommandLine: string;
  StartInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
begin
  // Use VS Code's --goto parameter to open file at specific position
  CommandLine := Format('"%s" --goto "%s:%d:%d"',
    [FVSCodeCommand, FilePath, Line, Column]);
  
  FillChar(StartInfo, SizeOf(StartInfo), 0);
  StartInfo.cb := SizeOf(StartInfo);
  StartInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartInfo.wShowWindow := SW_SHOW;
  
  if CreateProcess(nil, PChar(CommandLine), nil, nil, False,
    CREATE_DEFAULT_ERROR_MODE, nil, nil, StartInfo, ProcessInfo) then
  begin
    CloseHandle(ProcessInfo.hProcess);
    CloseHandle(ProcessInfo.hThread);
    
    // Give VS Code time to start and bring to foreground
    Sleep(1000);
    SetForegroundWindow(FindWindow('Chrome_WidgetWin_1', nil));
  end;
end;

{ TPipeServerThread }

constructor TPipeServerThread.Create(const PipeName: string);
begin
  inherited Create(False);
  FPipeName := PipeName;
  FreeOnTerminate := False;
end;

procedure TPipeServerThread.Execute;
var
  PipeHandle: THandle;
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  Message: string;
  Connected: Boolean;
begin
  while not Terminated do
  begin
    // Create named pipe to receive requests from VS Code
    PipeHandle := CreateNamedPipe(
      PChar(FPipeName),
      PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT,
      PIPE_UNLIMITED_INSTANCES,
      4096,
      4096,
      0,
      nil
    );
    
    if PipeHandle <> INVALID_HANDLE_VALUE then
    begin
      try
        // Wait for VS Code to connect
        Connected := ConnectNamedPipe(PipeHandle, nil);
        if Connected or (GetLastError = ERROR_PIPE_CONNECTED) then
        begin
          // Read the request
          if ReadFile(PipeHandle, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then
          begin
            SetString(Message, PAnsiChar(@Buffer[0]), BytesRead);
            
            // Handle the request in main thread
            TThread.Synchronize(nil,
              procedure
              begin
                HandleVSCodeRequest(Message);
              end
            );
          end;
        end;
      finally
        DisconnectNamedPipe(PipeHandle);
        CloseHandle(PipeHandle);
      end;
    end;
    
    if not Terminated then
      Sleep(100);
  end;
end;

procedure TPipeServerThread.HandleVSCodeRequest(const JSONData: string);
var
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  FilePath: string;
  Line, Column: Integer;
begin
  try
    JSONValue := TJSONObject.ParseJSONValue(JSONData);
    if JSONValue is TJSONObject then
    begin
      JSONObject := TJSONObject(JSONValue);
      try
        if JSONObject.GetValue<string>('action') = 'switch' then
        begin
          FilePath := JSONObject.GetValue<string>('filePath');
          Line := JSONObject.GetValue<Integer>('line');
          Column := JSONObject.GetValue<Integer>('column');
          
          // Open the file in Delphi at the specified position
          OpenFileInDelphi(FilePath, Line, Column);
          
          // Bring Delphi to foreground
          SetForegroundWindow(Application.MainForm.Handle);
        end;
      finally
        JSONObject.Free;
      end;
    end;
  except
    on E: Exception do
      // Log error silently - don't interrupt user
      OutputDebugString(PChar('IDESwitcher error: ' + E.Message));
  end;
end;

procedure TPipeServerThread.OpenFileInDelphi(const FilePath: string; 
  Line, Column: Integer);
var
  ActionServices: IOTAActionServices;
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
  EditView: IOTAEditView;
  EditPos: TOTAEditPos;
begin
  if not FileExists(FilePath) then
    Exit;
    
  ActionServices := BorlandIDEServices as IOTAActionServices;
  ModuleServices := BorlandIDEServices as IOTAModuleServices;
  
  // Check if file is already open
  Module := ModuleServices.FindModule(FilePath);
  
  if Module = nil then
  begin
    // Open the file
    ActionServices.OpenFile(FilePath);
    Module := ModuleServices.FindModule(FilePath);
  end;
  
  if Module <> nil then
  begin
    // Make it the active module
    Module.Show;
    
    Editor := Module.CurrentEditor;
    if (Editor <> nil) and (Editor.QueryInterface(IOTASourceEditor, SourceEditor) = S_OK) then
    begin
      EditView := SourceEditor.GetEditView(0);
      if EditView <> nil then
      begin
        // Set cursor position
        EditPos.Line := Line;
        EditPos.Col := Column;
        EditView.CursorPos := EditPos;
        
        // Center the view on the cursor
        EditView.Center(Line, Column);
        
        // Ensure the editor is focused
        if EditView.Form <> nil then
          EditView.Form.SetFocus;
          
        EditView.Paint;
      end;
    end;
  end;
end;

{ TIDESwitcherWizard }

constructor TIDESwitcherWizard.Create;
var
  BindingServices: IOTAKeyBindingServices;
begin
  inherited;
  
  // Register keyboard binding
  BindingServices := BorlandIDEServices as IOTAKeyBindingServices;
  FKeyBindingIndex := BindingServices.AddKeyboardBinding(TIDESwitcherNotifier.Create);
  
  // Start pipe server to receive requests from VS Code
  FServerThread := TPipeServerThread.Create(PIPE_NAME_FROM_VSCODE);
  
  ShowMessage('IDE Switcher Plugin Loaded' + #13#10 +
    'Press Ctrl+Shift+D to switch to VS Code/WindSurf' + #13#10 +
    'The same hotkey in VS Code will switch back here');
end;

destructor TIDESwitcherWizard.Destroy;
var
  BindingServices: IOTAKeyBindingServices;
begin
  if FServerThread <> nil then
  begin
    FServerThread.Terminate;
    FServerThread.WaitFor;
    FServerThread.Free;
  end;
  
  if FKeyBindingIndex >= 0 then
  begin
    BindingServices := BorlandIDEServices as IOTAKeyBindingServices;
    BindingServices.RemoveKeyboardBinding(FKeyBindingIndex);
  end;
  
  inherited;
end;

function TIDESwitcherWizard.GetIDString: string;
begin
  Result := 'IDESwitcher.DelphiPlugin.1.0';
end;

function TIDESwitcherWizard.GetName: string;
begin
  Result := 'IDE Switcher for Delphi';
end;

function TIDESwitcherWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TIDESwitcherWizard.Execute;
begin
  // Nothing to do here - wizard runs in background
end;

initialization
  WizardIndex := (BorlandIDEServices as IOTAWizardServices).AddWizard(TIDESwitcherWizard.Create);

finalization
  if WizardIndex >= 0 then
    (BorlandIDEServices as IOTAWizardServices).RemoveWizard(WizardIndex);

end.