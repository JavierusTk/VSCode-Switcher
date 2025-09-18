unit DelphiIDESwitcherPlugin;

{
  Delphi IDE Plugin for IDE Switcher
  
  FEATURES:
  - Handles Ctrl+Shift+D hotkey within Delphi IDE
  - Automatically saves current file before switching
  - Sends file path and cursor position to VS Code
  - Receives switch requests from VS Code and opens files at correct position
}

interface

uses
  Windows, SysUtils, Classes, ToolsAPI, Menus, ActnList, Dialogs, Forms,
  System.JSON, System.IOUtils, System.Threading, System.DateUtils;

type
  TIDESwitcherNotifier = class(TNotifierObject, IOTAKeyboardBinding)
  private
    FPipeName: string;
    FVSCodeCommand: string;
    FBindingAdded: Boolean;

    procedure HandleSwitchToVSCode(const Context: IOTAKeyContext; KeyCode: TShortcut;
      var BindingResult: TKeyBindingResult);
    function GetCurrentEditorInfo: TJSONObject;
    procedure SaveCurrentFile;
    procedure SendToVSCode(const FileInfo: TJSONObject);
    procedure LaunchVSCodeWithFile(const FilePath: string; Line, Column: Integer);
    procedure BringVSCodeToForeground;
    class procedure Log(const Msg: string);
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
    FTerminating: Boolean;
    FPipeHandle: THandle;
    FEventHandle: THandle;
    procedure HandleVSCodeRequest(const JSONData: string);
    procedure OpenFileInDelphi(const FilePath: string; Line, Column: Integer);
    procedure Log(const Msg: string);
  protected
    procedure Execute; override;
  public
    constructor Create(const PipeName: string);
    destructor Destroy; override;
    procedure SafeTerminate;
  end;

  TIDESwitcherWizard = class(TNotifierObject, IOTAWizard)
  private
    FKeyBindingIndex: Integer;
    FServerThread: TPipeServerThread;
    procedure Log(const Msg: string);
  public
    constructor Create;
    destructor Destroy; override;
    
    // IOTAWizard
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
    procedure HandleKeyboardShortcut(const Context: IOTAKeyContext; KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
  end;

var
  WizardIndex: Integer = -1;
  LastVSCodePID: DWORD = 0;  // Store the last known VS Code/Windsurf process ID

implementation

const
  PIPE_NAME_TO_VSCODE = '\\.\pipe\IDESwitcher_ToVSCode';
  PIPE_NAME_FROM_VSCODE = '\\.\pipe\IDESwitcher_ToDelphi';
  VSCODE_COMMAND = 'code'; // Or full path to WindSurf executable
  DEBUG_MODE = True; // Set to False to disable logging

type
  TFindWindowData = record
    PID: DWORD;
    WindowHandle: HWND;
  end;
  PFindWindowData = ^TFindWindowData;

function EnumWindowsForPID(hwndParam: HWND; lParam: LPARAM): BOOL; stdcall;
var
  ProcessID: DWORD;
  Data: PFindWindowData;
begin
  Result := True; // Continue enumeration
  Data := PFindWindowData(lParam);

  GetWindowThreadProcessId(hwndParam, @ProcessID);
  if ProcessID = Data^.PID then
  begin
    // Check if this is a main window (has no parent and is visible)
    if (GetParent(hwndParam) = 0) and IsWindowVisible(hwndParam) then
    begin
      Data^.WindowHandle := hwndParam;
      Result := False; // Stop enumeration, we found it
    end;
  end;
end;

function GetMainWindowFromPID(PID: DWORD): HWND;
var
  Data: TFindWindowData;
begin
  Data.PID := PID;
  Data.WindowHandle := 0;
  EnumWindows(@EnumWindowsForPID, LPARAM(@Data));
  Result := Data.WindowHandle;
end;

function FindVSCodeWindow(hwndParam: HWND; lParam: LPARAM): BOOL; stdcall;
var
  ClassName: array[0..255] of Char;
  WindowText: array[0..255] of Char;
  ResultHWnd: ^HWND;
begin
  Result := True; // Continue enumeration by default

  GetClassName(hwndParam, ClassName, 256);
  GetWindowText(hwndParam, WindowText, 256);

  // Check if this is a VS Code or Windsurf window
  // They use Chrome_WidgetWin_1 class and have specific window titles
  if (string(ClassName) = 'Chrome_WidgetWin_1') then
  begin
    // Check if window title contains VS Code or Windsurf indicators
    if (Pos('Visual Studio Code', string(WindowText)) > 0) or
       (Pos('Windsurf', string(WindowText)) > 0) or
       (Pos(' - ', string(WindowText)) > 0) then // Most code editors have " - " in title
    begin
      ResultHWnd := Pointer(lParam);
      ResultHWnd^ := hwndParam;
      Result := False; // Stop enumeration, we found it
    end;
  end;
end;

function GetLogFilePath: string;
var
  TempPath: array[0..MAX_PATH] of Char;
begin
  // Use user's temp directory which is always writable
  GetTempPath(MAX_PATH, TempPath);
  Result := IncludeTrailingPathDelimiter(TempPath) + 'IDESwitcher.log';
end;

procedure WriteLog(const Msg: string);
var
  F: TextFile;
  Timestamp: string;
  LogFile: string;
begin
  if not DEBUG_MODE then Exit;

  try
    LogFile := GetLogFilePath;
    Timestamp := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now);

    // Write to file
    try
      AssignFile(F, LogFile);
      if FileExists(LogFile) then
        Append(F)
      else
      begin
        Rewrite(F);
        WriteLn(F, '=== IDESwitcher Log Started ' + DateTimeToStr(Now) + ' ===');
        WriteLn(F, 'Log file: ' + LogFile);
        WriteLn(F, '');
      end;
      WriteLn(F, '[' + Timestamp + '] ' + Msg);
      CloseFile(F);
    except
      // If file write fails, at least try other outputs
    end;

    // Also output to IDE's message view (less intrusive than ShowMessage)
    if BorlandIDEServices <> nil then
    begin
      try
        (BorlandIDEServices as IOTAMessageServices).AddTitleMessage('IDESwitcher: ' + Msg);
      except
        // Ignore if message service not available
      end;
    end;

    // And to debug output (viewable with DebugView or similar)
    OutputDebugString(PChar('IDESwitcher: ' + Msg));
  except
    // Silently ignore all logging errors
  end;
end;

{ TIDESwitcherNotifier }

class procedure TIDESwitcherNotifier.Log(const Msg: string);
begin
  WriteLog('Notifier: ' + Msg);
end;

constructor TIDESwitcherNotifier.Create;
begin
  inherited;
  FPipeName := PIPE_NAME_TO_VSCODE;
  FVSCodeCommand := VSCODE_COMMAND;
  FBindingAdded := False;
  Log('Created');
end;

destructor TIDESwitcherNotifier.Destroy;
begin
  Log('Destroying');
  inherited;
end;

function TIDESwitcherNotifier.GetBindingType: TBindingType;
begin
  Result := btPartial;
  Log('GetBindingType called - returning btPartial');
end;

function TIDESwitcherNotifier.GetDisplayName: string;
begin
  Result := 'IDE Switcher - Switch to VS Code/WindSurf';
  Log('GetDisplayName called');
end;

function TIDESwitcherNotifier.GetName: string;
begin
  Result := 'IDESwitcher.SwitchToVSCode';
  Log('GetName called');
end;

procedure TIDESwitcherNotifier.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  // Only add the binding once - the IDE calls this multiple times for different contexts
  if not FBindingAdded then
  begin
    Log('BindKeyboard called - binding Ctrl+Shift+D');
    try
      // Bind Ctrl+Shift+D to switch to VS Code
      BindingServices.AddKeyBinding([TextToShortCut('Ctrl+Shift+D')], HandleSwitchToVSCode, nil);
      FBindingAdded := True;
      Log('Keyboard binding added successfully');
    except
      on E: Exception do
        Log('ERROR binding keyboard: ' + E.Message);
    end;
  end
  else
  begin
    Log('BindKeyboard called - binding already added, skipping');
  end;
end;

procedure TIDESwitcherNotifier.HandleSwitchToVSCode(const Context: IOTAKeyContext;
  KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
var
  FileInfo: TJSONObject;
begin
  Log('HandleSwitchToVSCode called - Ctrl+Shift+D pressed');
  BindingResult := krHandled;

  try
    // Step 1: Save current file
    Log('Step 1: Saving current file');
    SaveCurrentFile;

    // Step 2: Get current editor information (file path, line, column)
    Log('Step 2: Getting current editor info');
    FileInfo := GetCurrentEditorInfo;
    try
      if FileInfo.GetValue<string>('filePath') <> '' then
      begin
        Log('Step 3: Sending to VS Code - File: ' + FileInfo.GetValue<string>('filePath'));
        // Step 3: Send to VS Code (which will open the file and position cursor)
        SendToVSCode(FileInfo);
      end
      else
      begin
        Log('No active file to switch');
        // Don't show message box - just log
      end;
    finally
      FileInfo.Free;
    end;
  except
    on E: Exception do
    begin
      Log('ERROR in HandleSwitchToVSCode: ' + E.Message);
      ShowMessage('Error switching to VS Code: ' + E.Message);
    end;
  end;
end;

procedure TIDESwitcherNotifier.SaveCurrentFile;
var
  ModuleServices: IOTAModuleServices;
  Module: IOTAModule;
begin
  Log('SaveCurrentFile called');
  try
    ModuleServices := BorlandIDEServices as IOTAModuleServices;
    Module := ModuleServices.CurrentModule;

    if Module <> nil then
    begin
      Log('Current module found: ' + Module.FileName);
      if Module.GetCurrentEditor <> nil then
      begin
        Log('Saving module');
        Module.Save(False, True);
        Log('Module saved successfully');
      end
      else
        Log('No current editor in module');
    end
    else
      Log('No current module');
  except
    on E: Exception do
      Log('ERROR saving file: ' + E.Message);
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
  ErrorCode: DWORD;
begin
  Success := False;
  Retries := 0;

  Log('SendToVSCode: Starting, pipe: ' + FPipeName);

  // Try to connect to VS Code extension's pipe server
  while (not Success) and (Retries < 3) do
  begin
    Log('Attempt ' + IntToStr(Retries + 1) + ' to connect to pipe');

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
      Log('Pipe opened successfully');
      try
        Message := AnsiString(FileInfo.ToString);
        Log('Sending message: ' + string(Message));

        if WriteFile(PipeHandle, Message[1], Length(Message), BytesWritten, nil) then
        begin
          Log('Message written: ' + IntToStr(BytesWritten) + ' bytes');
          FlushFileBuffers(PipeHandle);
          Success := True;
          Log('Message sent successfully to VS Code');
        end
        else
        begin
          ErrorCode := GetLastError;
          Log('ERROR: WriteFile failed - ' + SysErrorMessage(ErrorCode));
        end;
      finally
        CloseHandle(PipeHandle);
      end;
    end
    else
    begin
      ErrorCode := GetLastError;
      Log('ERROR: CreateFile failed - ' + SysErrorMessage(ErrorCode));
      Inc(Retries);
      if Retries < 3 then
      begin
        Log('Waiting 100ms before retry...');
        Sleep(100);
      end;
    end;
  end;

  if not Success then
  begin
    Log('Pipe communication failed, launching VS Code directly');
    // If pipe communication fails, launch VS Code directly with command line
    LaunchVSCodeWithFile(
      FileInfo.GetValue<string>('filePath'),
      FileInfo.GetValue<Integer>('line'),
      FileInfo.GetValue<Integer>('column')
    );
  end
  else
  begin
    // Successfully sent message, now bring VS Code/Windsurf to foreground
    BringVSCodeToForeground;
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
    BringVSCodeToForeground;
  end;
end;

procedure TIDESwitcherNotifier.BringVSCodeToForeground;
var
  WindowHandle: HWND;
  ThreadID: DWORD;
  ProcessID: DWORD;
begin
  Log('Attempting to bring VS Code/Windsurf to foreground');
  WindowHandle := 0;

  // First try to find window by process ID if we have it
  if LastVSCodePID > 0 then
  begin
    Log('Using stored PID: ' + IntToStr(LastVSCodePID));
    // Find the main window of this process
    WindowHandle := GetMainWindowFromPID(LastVSCodePID);
  end;

  // If not found by PID, try by class name
  if WindowHandle = 0 then
  begin
    Log('Trying to find by class name Chrome_WidgetWin_1');
    WindowHandle := FindWindow('Chrome_WidgetWin_1', nil);
  end;

  // If still not found, try enumerating all windows
  if WindowHandle = 0 then
  begin
    Log('Window not found by class name, trying by enumeration');
    EnumWindows(@FindVSCodeWindow, LPARAM(@WindowHandle));
  end;

  if WindowHandle <> 0 then
  begin
    Log('Window found (handle: ' + IntToStr(WindowHandle) + '), bringing to foreground');

    // Get the process ID of the found window (for verification)
    GetWindowThreadProcessId(WindowHandle, @ProcessID);
    if ProcessID > 0 then
    begin
      LastVSCodePID := ProcessID; // Update our stored PID
      Log('Window belongs to process: ' + IntToStr(ProcessID));
    end;

    // Method 1: Standard approach
    if IsIconic(WindowHandle) then
    begin
      Log('Window is minimized, restoring');
      ShowWindow(WindowHandle, SW_RESTORE);
    end;

    // Method 2: Force foreground using AttachThreadInput
    ThreadID := GetWindowThreadProcessId(WindowHandle, nil);
    AttachThreadInput(GetCurrentThreadId, ThreadID, True);

    BringWindowToTop(WindowHandle);
    SetForegroundWindow(WindowHandle);

    AttachThreadInput(GetCurrentThreadId, ThreadID, False);

    // Give it a moment and try again to ensure focus
    Sleep(50);
    SetForegroundWindow(WindowHandle);

    Log('Window should now be in foreground');
  end
  else
  begin
    Log('Could not find VS Code/Windsurf window');
  end;
end;

{ TPipeServerThread }

procedure TPipeServerThread.Log(const Msg: string);
begin
  WriteLog('PipeServer: ' + Msg);
end;

constructor TPipeServerThread.Create(const PipeName: string);
begin
  FPipeName := PipeName;
  FTerminating := False;
  FPipeHandle := INVALID_HANDLE_VALUE;
  FEventHandle := 0;
  inherited Create(True); // Create suspended, will be started later
  FreeOnTerminate := False;
  Log('Created for pipe: ' + PipeName);
end;

destructor TPipeServerThread.Destroy;
begin
  Log('Destroying pipe server thread');
  FTerminating := True;

  // Close handles if still open
  if FPipeHandle <> INVALID_HANDLE_VALUE then
  begin
    CancelIo(FPipeHandle);
    CloseHandle(FPipeHandle);
    FPipeHandle := INVALID_HANDLE_VALUE;
  end;

  if FEventHandle <> 0 then
  begin
    SetEvent(FEventHandle); // Signal the event to wake up any waits
    CloseHandle(FEventHandle);
    FEventHandle := 0;
  end;

  inherited;
end;

procedure TPipeServerThread.SafeTerminate;
begin
  Log('SafeTerminate called');
  FTerminating := True;

  // Cancel any pending I/O operations
  if FPipeHandle <> INVALID_HANDLE_VALUE then
  begin
    CancelIo(FPipeHandle);
    DisconnectNamedPipe(FPipeHandle);
  end;

  // Signal event to wake up any waits
  if FEventHandle <> 0 then
    SetEvent(FEventHandle);

  Terminate;
end;

procedure TPipeServerThread.Execute;
var
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  Message: string;
  Connected: Boolean;
  ErrorCode: DWORD;
  Overlapped: TOverlapped;
  WaitResult: DWORD;
begin
  Log('Pipe server thread started');
  FPipeHandle := INVALID_HANDLE_VALUE;
  FEventHandle := CreateEvent(nil, True, False, nil);

  try
    while not Terminated and not FTerminating do
    begin
      Log('Creating named pipe: ' + FPipeName);

      // Create named pipe to receive requests from VS Code
      FPipeHandle := CreateNamedPipe(
        PChar(FPipeName),
        PIPE_ACCESS_DUPLEX or FILE_FLAG_OVERLAPPED, // Enable overlapped mode for better termination
        PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT,
        PIPE_UNLIMITED_INSTANCES,
        4096,
        4096,
        100, // Timeout in milliseconds
        nil
      );

      if FPipeHandle <> INVALID_HANDLE_VALUE then
      begin
        Log('Pipe created successfully, waiting for connection');
        try
          // Set up overlapped structure for cancellable wait
          FillChar(Overlapped, SizeOf(Overlapped), 0);
          Overlapped.hEvent := FEventHandle;

          // Wait for VS Code to connect with overlapped IO
          Connected := ConnectNamedPipe(FPipeHandle, @Overlapped);
          ErrorCode := GetLastError;

          if not Connected and (ErrorCode = ERROR_IO_PENDING) then
          begin
            // Wait for connection or termination signal
            while not (Terminated or FTerminating) do
            begin
              WaitResult := WaitForSingleObject(FEventHandle, 100);
              if WaitResult = WAIT_OBJECT_0 then
              begin
                Connected := True;
                Break;
              end;
            end;
          end
          else if ErrorCode = ERROR_PIPE_CONNECTED then
          begin
            Connected := True;
          end;

          if Connected and not (Terminated or FTerminating) then
          begin
            Log('Client connected to pipe');

            // Read the request
            if ReadFile(FPipeHandle, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then
            begin
              SetString(Message, PAnsiChar(@Buffer[0]), BytesRead);
              Log('Received ' + IntToStr(BytesRead) + ' bytes: ' + Message);

              // Handle the request in main thread - CRITICAL!
              // OTA calls must be made from the main thread
              TThread.Synchronize(nil,
                procedure
                begin
                  HandleVSCodeRequest(Message);
                end
              );
            end
            else
              Log('ERROR: ReadFile failed - ' + SysErrorMessage(GetLastError));
          end;
        finally
          DisconnectNamedPipe(FPipeHandle);
          CloseHandle(FPipeHandle);
          FPipeHandle := INVALID_HANDLE_VALUE;
        end;
      end
      else
      begin
        ErrorCode := GetLastError;
        Log('ERROR: CreateNamedPipe failed - ' + SysErrorMessage(ErrorCode));
        // Wait before retrying
        if not (Terminated or FTerminating) then
          Sleep(100);
      end;

      if not Terminated and not FTerminating then
      begin
        Sleep(50); // Small delay between pipe recreations
      end;
    end;
  except
    on E: Exception do
      Log('EXCEPTION in pipe server thread: ' + E.Message);
  end;

  if FEventHandle <> 0 then
  begin
    CloseHandle(FEventHandle);
    FEventHandle := 0;
  end;
  Log('Pipe server thread ending normally');
end;

procedure TPipeServerThread.HandleVSCodeRequest(const JSONData: string);
var
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  FilePath: string;
  Line, Column: Integer;
  VSCodePID: Integer;
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

          // Get VS Code process ID if available
          if JSONObject.TryGetValue<Integer>('pid', VSCodePID) then
          begin
            Log('VS Code/Windsurf PID received: ' + IntToStr(VSCodePID));
            // Store it for later use when we need to bring VS Code to foreground
            LastVSCodePID := VSCodePID;
          end;

          // Open the file in Delphi at the specified position
          OpenFileInDelphi(FilePath, Line, Column);

          // Bring Delphi to foreground - use BorlandIDEServices to get main form
          if (BorlandIDEServices as IOTAServices).GetParentHandle <> 0 then
            SetForegroundWindow((BorlandIDEServices as IOTAServices).GetParentHandle);
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
        
        // Paint the view
        EditView.Paint;
      end;
    end;
  end;
end;

{ TIDESwitcherWizard }

procedure TIDESwitcherWizard.Log(const Msg: string);
begin
  WriteLog('Wizard: ' + Msg);
end;

constructor TIDESwitcherWizard.Create;
var
  KeyboardServices: IOTAKeyboardServices;
begin
  inherited;
  FKeyBindingIndex := -1;
  FServerThread := nil;

  Log('Creating wizard');
  WriteLog('Log file location: ' + GetLogFilePath);

  try
    // Create and register keyboard binding notifier
    Log('Creating keyboard binding notifier');
    var NotifierObj: IOTAKeyboardBinding;
    NotifierObj := TIDESwitcherNotifier.Create;
    // Register with keyboard services
    Log('Registering keyboard binding with IDE');
    if Supports(BorlandIDEServices, IOTAKeyboardServices, KeyboardServices) then
    begin
      Log('IOTAKeyboardServices available');
      KeyboardServices.AddKeyboardBinding(NotifierObj);
      Log('Keyboard binding registered via IOTAKeyboardServices');
    end
    else
    begin
      Log('WARNING: No keyboard service available!');
    end;

    // Start pipe server to receive requests from VS Code
    Log('Starting pipe server thread');
    try
      FServerThread := TPipeServerThread.Create(PIPE_NAME_FROM_VSCODE);
      Log('Pipe server thread created');
      // Now start the thread after it's been properly created
      FServerThread.Start;
      Log('Pipe server thread started');
    except
      on E: Exception do
      begin
        Log('ERROR starting pipe server: ' + E.Message);
        if Assigned(FServerThread) then
          FreeAndNil(FServerThread);
      end;
    end;

    // Don't show message box - it blocks IDE startup
    // Just log the information instead
    Log('IDE Switcher Plugin Loaded - Press Ctrl+Shift+D to switch to VS Code/WindSurf');
    Log('Wizard created successfully');
  except
    on E: Exception do
    begin
      Log('ERROR in wizard creation: ' + E.Message);
      raise;
    end;
  end;
end;

destructor TIDESwitcherWizard.Destroy;
begin
  Log('Destroying wizard');

  // Stop the pipe server thread
  if Assigned(FServerThread) then
  begin
    try
      Log('Stopping pipe server thread');
      FServerThread.SafeTerminate;

      // Wait with timeout to prevent hanging
      if WaitForSingleObject(FServerThread.Handle, 500) <> WAIT_TIMEOUT then
        Log('Thread terminated successfully')
      else
      begin
        Log('WARNING: Thread did not terminate quickly, waiting longer');
        // Give it more time
        if WaitForSingleObject(FServerThread.Handle, 1500) <> WAIT_TIMEOUT then
          Log('Thread terminated after extended wait')
        else
        begin
          Log('WARNING: Thread still running after 2 seconds total');
          // Don't force terminate - let it finish naturally
        end;
      end;

      FreeAndNil(FServerThread);
      Log('Pipe server thread stopped');
    except
      on E: Exception do
        Log('ERROR stopping pipe server: ' + E.Message);
    end;
  end;


  Log('Wizard destroyed');
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

procedure TIDESwitcherWizard.HandleKeyboardShortcut(const Context: IOTAKeyContext;
  KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
var
  Notifier: TIDESwitcherNotifier;
begin
  Log('HandleKeyboardShortcut called');
  // Delegate to the notifier
  Notifier := TIDESwitcherNotifier.Create;
  try
    Notifier.HandleSwitchToVSCode(Context, KeyCode, BindingResult);
  finally
    Notifier.Free;
  end;
end;


initialization
  WriteLog('=== IDESwitcher Plugin Initialization ===');
  try
    WizardIndex := (BorlandIDEServices as IOTAWizardServices).AddWizard(TIDESwitcherWizard.Create);
    WriteLog('Wizard registered with index: ' + IntToStr(WizardIndex));
  except
    on E: Exception do
    begin
      WriteLog('ERROR during initialization: ' + E.Message);
      ShowMessage('IDESwitcher failed to initialize: ' + E.Message);
    end;
  end;

finalization
  WriteLog('=== IDESwitcher Plugin Finalization ===');
  if WizardIndex >= 0 then
  begin
    try
      WriteLog('Removing wizard with index: ' + IntToStr(WizardIndex));
      (BorlandIDEServices as IOTAWizardServices).RemoveWizard(WizardIndex);
      WriteLog('Wizard removed successfully');
    except
      on E: Exception do
        WriteLog('ERROR during finalization: ' + E.Message);
    end;
  end;
  WriteLog('=== IDESwitcher Plugin Finalization Complete ===');

end.
