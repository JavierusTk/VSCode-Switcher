unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  System.JSON, System.Threading;

type
  TLogEvent = procedure(const Text: string) of object;
  TMessageEvent = procedure(const Message: string) of object;

  TPipeServerThread = class(TThread)
  private
    FPipeName: string;
    FOnMessage: TMessageEvent;
    FOnLog: TLogEvent;
    FPipeHandle: THandle;
    FTerminating: Boolean;
    procedure ClosePipe;
  protected
    procedure Execute; override;
  public
    constructor Create(const APipeName: string; AOnMessage: TMessageEvent; AOnLog: TLogEvent);
    destructor Destroy; override;
    procedure TerminateAndWait;
  end;

  TFormMain = class(TForm)
    PageControl1: TPageControl;
    TabSheetSend: TTabSheet;
    TabSheetReceive: TTabSheet;
    TabSheetLog: TTabSheet;
    TabSheetMockVSCode: TTabSheet;

    // Send tab controls
    GroupBox1: TGroupBox;
    Label1: TLabel;
    EditFilePath: TEdit;
    Label2: TLabel;
    EditLine: TEdit;
    Label3: TLabel;
    EditColumn: TEdit;
    ButtonSendToVSCode: TButton;
    ButtonSendToDelphi: TButton;

    // Receive tab controls
    GroupBox2: TGroupBox;
    ButtonStartServer: TButton;
    ButtonStopServer: TButton;
    LabelServerStatus: TLabel;
    MemoReceived: TMemo;

    // Mock VS Code tab controls
    GroupBoxMockVSCode: TGroupBox;
    ButtonStartMockVSCode: TButton;
    ButtonStopMockVSCode: TButton;
    LabelMockStatus: TLabel;
    MemoMockReceived: TMemo;
    ButtonTestDelphiPlugin: TButton;
    CheckBoxAutoRespond: TCheckBox;

    // Log tab
    MemoLog: TMemo;
    ButtonClearLog: TButton;

    // Status bar
    StatusBar1: TStatusBar;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ButtonSendToVSCodeClick(Sender: TObject);
    procedure ButtonSendToDelphiClick(Sender: TObject);
    procedure ButtonStartServerClick(Sender: TObject);
    procedure ButtonStopServerClick(Sender: TObject);
    procedure ButtonStartMockVSCodeClick(Sender: TObject);
    procedure ButtonStopMockVSCodeClick(Sender: TObject);
    procedure ButtonTestDelphiPluginClick(Sender: TObject);
    procedure ButtonClearLogClick(Sender: TObject);
  private
    FServerThread: TPipeServerThread;
    FMockVSCodeThread: TPipeServerThread;
    procedure SendMessageToPipe(const PipeName, Message: string);
    procedure HandleReceivedMessage(const Message: string);
    procedure HandleMockVSCodeMessage(const Message: string);
    procedure AddLog(const Text: string);
    procedure UpdateServerStatus(Running: Boolean);
    procedure UpdateMockVSCodeStatus(Running: Boolean);
    procedure SimulateDelphiIDEResponse;
  public
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

const
  PIPE_NAME_TO_VSCODE = '\\.\pipe\IDESwitcher_ToVSCode';
  PIPE_NAME_FROM_VSCODE = '\\.\pipe\IDESwitcher_ToDelphi';

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  PageControl1.ActivePageIndex := 0;
  EditFilePath.Text := 'C:\Projects\TestFile.pas';
  EditLine.Text := '42';
  EditColumn.Text := '15';
  UpdateServerStatus(False);
  UpdateMockVSCodeStatus(False);

  StatusBar1.SimpleText := 'Ready to test IDE Switcher communication';
  AddLog('Application started');
  AddLog('This tester can simulate both Delphi and VS Code sides');
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  if Assigned(FServerThread) then
  begin
    FServerThread.TerminateAndWait;
    FServerThread.Free;
  end;

  if Assigned(FMockVSCodeThread) then
  begin
    FMockVSCodeThread.TerminateAndWait;
    FMockVSCodeThread.Free;
  end;
end;

procedure TFormMain.ButtonSendToVSCodeClick(Sender: TObject);
var
  JSONMsg: TJSONObject;
  MessageStr: string;
begin
  // Create JSON message
  JSONMsg := TJSONObject.Create;
  try
    JSONMsg.AddPair('action', 'switch');
    JSONMsg.AddPair('filePath', EditFilePath.Text);
    JSONMsg.AddPair('line', TJSONNumber.Create(StrToIntDef(EditLine.Text, 1)));
    JSONMsg.AddPair('column', TJSONNumber.Create(StrToIntDef(EditColumn.Text, 1)));
    JSONMsg.AddPair('source', 'delphi');
    JSONMsg.AddPair('timestamp', DateTimeToStr(Now));

    MessageStr := JSONMsg.ToString;
    AddLog('Sending to VS Code: ' + MessageStr);

    // Send to pipe
    try
      SendMessageToPipe(PIPE_NAME_TO_VSCODE, MessageStr);
      AddLog('Message sent successfully');
      StatusBar1.SimpleText := 'Message sent to VS Code pipe';
    except
      on E: Exception do
      begin
        AddLog('Error sending: ' + E.Message);
        StatusBar1.SimpleText := 'Error: ' + E.Message;
      end;
    end;
  finally
    JSONMsg.Free;
  end;
end;

procedure TFormMain.ButtonStartServerClick(Sender: TObject);
begin
  if not Assigned(FServerThread) then
  begin
    AddLog('Starting pipe server on ' + PIPE_NAME_FROM_VSCODE);
    FServerThread := TPipeServerThread.Create(
      PIPE_NAME_FROM_VSCODE,
      HandleReceivedMessage,
      AddLog
    );
    UpdateServerStatus(True);
    AddLog('Server started');
  end;
end;

procedure TFormMain.ButtonStopServerClick(Sender: TObject);
begin
  if Assigned(FServerThread) then
  begin
    AddLog('Stopping pipe server');
    FServerThread.TerminateAndWait;
    FreeAndNil(FServerThread);
    UpdateServerStatus(False);
    AddLog('Server stopped');
  end;
end;

procedure TFormMain.ButtonClearLogClick(Sender: TObject);
begin
  MemoLog.Clear;
  AddLog('Log cleared');
end;

procedure TFormMain.ButtonSendToDelphiClick(Sender: TObject);
var
  JSONMsg: TJSONObject;
  MessageStr: string;
begin
  // Create JSON message to send to Delphi IDE plugin
  JSONMsg := TJSONObject.Create;
  try
    JSONMsg.AddPair('action', 'switch');
    JSONMsg.AddPair('filePath', EditFilePath.Text);
    JSONMsg.AddPair('line', TJSONNumber.Create(StrToIntDef(EditLine.Text, 1)));
    JSONMsg.AddPair('column', TJSONNumber.Create(StrToIntDef(EditColumn.Text, 1)));
    JSONMsg.AddPair('source', 'vscode');
    JSONMsg.AddPair('timestamp', DateTimeToStr(Now));

    MessageStr := JSONMsg.ToString;
    AddLog('Sending to Delphi IDE: ' + MessageStr);

    // Send to Delphi IDE plugin pipe
    try
      SendMessageToPipe(PIPE_NAME_FROM_VSCODE, MessageStr);
      AddLog('Message sent successfully to Delphi IDE plugin');
      StatusBar1.SimpleText := 'Message sent to Delphi IDE pipe';
    except
      on E: Exception do
      begin
        AddLog('Error sending to Delphi: ' + E.Message);
        StatusBar1.SimpleText := 'Error: ' + E.Message;
        ShowMessage('Failed to send to Delphi IDE plugin: ' + E.Message + #13#10 +
          'Make sure the Delphi IDE is running with the plugin installed.');
      end;
    end;
  finally
    JSONMsg.Free;
  end;
end;

procedure TFormMain.ButtonStartMockVSCodeClick(Sender: TObject);
begin
  if not Assigned(FMockVSCodeThread) then
  begin
    AddLog('Starting Mock VS Code server on ' + PIPE_NAME_TO_VSCODE);
    AddLog('This simulates VS Code extension listening for Delphi messages');
    FMockVSCodeThread := TPipeServerThread.Create(
      PIPE_NAME_TO_VSCODE,
      HandleMockVSCodeMessage,
      AddLog
    );
    UpdateMockVSCodeStatus(True);
    AddLog('Mock VS Code server started - Press Ctrl+Shift+D in Delphi IDE to test');
  end;
end;

procedure TFormMain.ButtonStopMockVSCodeClick(Sender: TObject);
begin
  if Assigned(FMockVSCodeThread) then
  begin
    AddLog('Stopping Mock VS Code server');
    FMockVSCodeThread.TerminateAndWait;
    FreeAndNil(FMockVSCodeThread);
    UpdateMockVSCodeStatus(False);
    AddLog('Mock VS Code server stopped');
  end;
end;

procedure TFormMain.ButtonTestDelphiPluginClick(Sender: TObject);
begin
  // Test complete round-trip communication
  AddLog('--- Starting Delphi Plugin Test ---');

  if not Assigned(FMockVSCodeThread) then
  begin
    ShowMessage('Please start the Mock VS Code server first');
    Exit;
  end;

  AddLog('Test: Waiting for Delphi IDE to send a message...');
  AddLog('Action: Press Ctrl+Shift+D in Delphi IDE');
  AddLog('Expected: Should receive file info from Delphi plugin');

  StatusBar1.SimpleText := 'Waiting for Delphi IDE plugin message...';
end;

procedure TFormMain.SendMessageToPipe(const PipeName, Message: string);
var
  PipeHandle: THandle;
  BytesWritten: DWORD;
  MessageBytes: TBytes;
  Retries: Integer;
  Success: Boolean;
begin
  Success := False;
  Retries := 0;

  while (not Success) and (Retries < 3) do
  begin
    PipeHandle := CreateFile(
      PChar(PipeName),
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
        MessageBytes := TEncoding.UTF8.GetBytes(Message);
        if WriteFile(PipeHandle, MessageBytes[0], Length(MessageBytes), BytesWritten, nil) then
        begin
          FlushFileBuffers(PipeHandle);
          Success := True;
        end
        else
          raise Exception.Create('WriteFile failed');
      finally
        CloseHandle(PipeHandle);
      end;
    end
    else
    begin
      Inc(Retries);
      if Retries < 3 then
      begin
        AddLog('Pipe not available, retrying...');
        Sleep(500);
      end
      else
        raise Exception.Create('Could not connect to pipe (is VS Code extension running?)');
    end;
  end;
end;

procedure TFormMain.HandleReceivedMessage(const Message: string);
var
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  FilePath: string;
  Line, Column: Integer;
begin
  TThread.Synchronize(nil,
    procedure
    begin
      MemoReceived.Lines.Add('Received at ' + TimeToStr(Now) + ':');
      MemoReceived.Lines.Add(Message);
      MemoReceived.Lines.Add('---');

      // Parse JSON
      try
        JSONValue := TJSONObject.ParseJSONValue(Message);
        if Assigned(JSONValue) and (JSONValue is TJSONObject) then
        begin
          JSONObject := TJSONObject(JSONValue);
          try
            if JSONObject.GetValue<string>('action') = 'switch' then
            begin
              FilePath := JSONObject.GetValue<string>('filePath', '');
              Line := JSONObject.GetValue<Integer>('line', 1);
              Column := JSONObject.GetValue<Integer>('column', 1);

              StatusBar1.SimpleText := Format('Received switch request: %s [%d:%d]',
                [ExtractFileName(FilePath), Line, Column]);

              AddLog(Format('Switch request from VS Code: %s at %d:%d',
                [FilePath, Line, Column]));
            end;
          finally
            JSONObject.Free;
          end;
        end;
      except
        on E: Exception do
          AddLog('Error parsing message: ' + E.Message);
      end;
    end);
end;

procedure TFormMain.AddLog(const Text: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      MemoLog.Lines.Add('[' + TimeToStr(Now) + '] ' + Text);
      // Auto-scroll to bottom
      MemoLog.Perform(WM_VSCROLL, SB_BOTTOM, 0);
    end);
end;

procedure TFormMain.UpdateServerStatus(Running: Boolean);
begin
  if Running then
  begin
    LabelServerStatus.Caption := 'Server Status: RUNNING';
    LabelServerStatus.Font.Color := clGreen;
    ButtonStartServer.Enabled := False;
    ButtonStopServer.Enabled := True;
  end
  else
  begin
    LabelServerStatus.Caption := 'Server Status: STOPPED';
    LabelServerStatus.Font.Color := clRed;
    ButtonStartServer.Enabled := True;
    ButtonStopServer.Enabled := False;
  end;
end;

procedure TFormMain.UpdateMockVSCodeStatus(Running: Boolean);
begin
  if Running then
  begin
    LabelMockStatus.Caption := 'Mock VS Code: RUNNING (listening for Delphi)';
    LabelMockStatus.Font.Color := clGreen;
    ButtonStartMockVSCode.Enabled := False;
    ButtonStopMockVSCode.Enabled := True;
    ButtonTestDelphiPlugin.Enabled := True;
  end
  else
  begin
    LabelMockStatus.Caption := 'Mock VS Code: STOPPED';
    LabelMockStatus.Font.Color := clRed;
    ButtonStartMockVSCode.Enabled := True;
    ButtonStopMockVSCode.Enabled := False;
    ButtonTestDelphiPlugin.Enabled := False;
  end;
end;

procedure TFormMain.HandleMockVSCodeMessage(const Message: string);
var
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  FilePath: string;
  Line, Column: Integer;
begin
  TThread.Synchronize(nil,
    procedure
    begin
      // Display received message in Mock VS Code tab
      MemoMockReceived.Lines.Add('=== Received from Delphi IDE at ' + TimeToStr(Now) + ' ===');
      MemoMockReceived.Lines.Add(Message);
      MemoMockReceived.Lines.Add('');

      // Parse and analyze the message
      try
        JSONValue := TJSONObject.ParseJSONValue(Message);
        if Assigned(JSONValue) and (JSONValue is TJSONObject) then
        begin
          JSONObject := TJSONObject(JSONValue);
          try
            if JSONObject.GetValue<string>('action') = 'switch' then
            begin
              FilePath := JSONObject.GetValue<string>('filePath', '');
              Line := JSONObject.GetValue<Integer>('line', 1);
              Column := JSONObject.GetValue<Integer>('column', 1);

              MemoMockReceived.Lines.Add('Parsed Information:');
              MemoMockReceived.Lines.Add('  File: ' + FilePath);
              MemoMockReceived.Lines.Add('  Position: Line ' + IntToStr(Line) + ', Column ' + IntToStr(Column));
              MemoMockReceived.Lines.Add('  Source: ' + JSONObject.GetValue<string>('source', ''));
              MemoMockReceived.Lines.Add('---');

              StatusBar1.SimpleText := Format('Received from Delphi: %s [%d:%d]',
                [ExtractFileName(FilePath), Line, Column]);

              AddLog(Format('Mock VS Code received: %s at %d:%d',
                [FilePath, Line, Column]));

              // Auto-respond if checkbox is checked
              if CheckBoxAutoRespond.Checked then
              begin
                AddLog('Auto-responding to Delphi IDE...');
                SimulateDelphiIDEResponse;
              end;
            end;
          finally
            JSONObject.Free;
          end;
        end;
      except
        on E: Exception do
        begin
          MemoMockReceived.Lines.Add('ERROR parsing message: ' + E.Message);
          AddLog('Error parsing message from Delphi: ' + E.Message);
        end;
      end;
    end);
end;

procedure TFormMain.SimulateDelphiIDEResponse;
var
  JSONMsg: TJSONObject;
  MessageStr: string;
begin
  // Simulate VS Code sending a response back to Delphi
  JSONMsg := TJSONObject.Create;
  try
    JSONMsg.AddPair('action', 'switch');
    JSONMsg.AddPair('filePath', 'C:\MockResponse\TestFile.pas');
    JSONMsg.AddPair('line', TJSONNumber.Create(100));
    JSONMsg.AddPair('column', TJSONNumber.Create(25));
    JSONMsg.AddPair('source', 'vscode');
    JSONMsg.AddPair('timestamp', DateTimeToStr(Now));

    MessageStr := JSONMsg.ToString;
    AddLog('Auto-response: Sending back to Delphi IDE');

    try
      SendMessageToPipe(PIPE_NAME_FROM_VSCODE, MessageStr);
      AddLog('Auto-response sent successfully');
    except
      on E: Exception do
        AddLog('Auto-response failed: ' + E.Message);
    end;
  finally
    JSONMsg.Free;
  end;
end;

{ TPipeServerThread }

constructor TPipeServerThread.Create(const APipeName: string;
  AOnMessage: TMessageEvent; AOnLog: TLogEvent);
begin
  inherited Create(False);
  FPipeName := APipeName;
  FOnMessage := AOnMessage;
  FOnLog := AOnLog;
  FPipeHandle := INVALID_HANDLE_VALUE;
  FTerminating := False;
  FreeOnTerminate := False;
end;

destructor TPipeServerThread.Destroy;
begin
  ClosePipe;
  inherited;
end;

procedure TPipeServerThread.ClosePipe;
begin
  if FPipeHandle <> INVALID_HANDLE_VALUE then
  begin
    DisconnectNamedPipe(FPipeHandle);
    CloseHandle(FPipeHandle);
    FPipeHandle := INVALID_HANDLE_VALUE;
  end;
end;

procedure TPipeServerThread.TerminateAndWait;
var
  DummyHandle: THandle;
  BytesWritten: DWORD;
  DummyData: AnsiString;
begin
  FTerminating := True;
  Terminate;

  // Connect to our own pipe to unblock ConnectNamedPipe
  if FPipeHandle <> INVALID_HANDLE_VALUE then
  begin
    DummyHandle := CreateFile(
      PChar(FPipeName),
      GENERIC_WRITE,
      0,
      nil,
      OPEN_EXISTING,
      0,
      0
    );

    if DummyHandle <> INVALID_HANDLE_VALUE then
    begin
      DummyData := 'TERMINATE';
      WriteFile(DummyHandle, DummyData[1], Length(DummyData), BytesWritten, nil);
      CloseHandle(DummyHandle);
    end;
  end;

  // Wait for thread to finish
  WaitFor;
end;

procedure TPipeServerThread.Execute;
var
  Buffer: array[0..4095] of Byte;
  BytesRead: DWORD;
  Message: string;
  Connected: Boolean;
  Overlapped: TOverlapped;
  Event: THandle;
  WaitResult: DWORD;
begin
  while not Terminated and not FTerminating do
  begin
    FPipeHandle := CreateNamedPipe(
      PChar(FPipeName),
      PIPE_ACCESS_DUPLEX or FILE_FLAG_OVERLAPPED,
      PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT,
      PIPE_UNLIMITED_INSTANCES,
      4096,
      4096,
      0,
      nil
    );

    if FPipeHandle <> INVALID_HANDLE_VALUE then
    begin
      try
        if Assigned(FOnLog) then
          FOnLog('Waiting for connection on ' + FPipeName);

        // Create event for overlapped I/O
        Event := CreateEvent(nil, True, False, nil);
        try
          FillChar(Overlapped, SizeOf(Overlapped), 0);
          Overlapped.hEvent := Event;

          // Start async connection
          Connected := ConnectNamedPipe(FPipeHandle, @Overlapped);
          if not Connected then
          begin
            case GetLastError of
              ERROR_IO_PENDING:
                begin
                  // Wait for connection with timeout
                  repeat
                    WaitResult := WaitForSingleObject(Event, 100);
                    if Terminated or FTerminating then
                      Break;
                  until WaitResult <> WAIT_TIMEOUT;

                  if WaitResult = WAIT_OBJECT_0 then
                    Connected := True;
                end;
              ERROR_PIPE_CONNECTED:
                Connected := True;
            end;
          end;

          if Connected and not (Terminated or FTerminating) then
          begin
            if Assigned(FOnLog) then
              FOnLog('Client connected');

            if ReadFile(FPipeHandle, Buffer, SizeOf(Buffer) - 1, BytesRead, nil) then
            begin
              SetString(Message, PAnsiChar(@Buffer[0]), BytesRead);

              // Check if this is a termination message
              if Message = 'TERMINATE' then
              begin
                if Assigned(FOnLog) then
                  FOnLog('Received termination signal');
                Break;
              end;

              if Assigned(FOnLog) then
                FOnLog('Received ' + IntToStr(BytesRead) + ' bytes');

              if Assigned(FOnMessage) then
                FOnMessage(Message);
            end;
          end;
        finally
          CloseHandle(Event);
        end;
      finally
        ClosePipe;
      end;
    end
    else
    begin
      if Assigned(FOnLog) then
        FOnLog('Failed to create pipe: ' + SysErrorMessage(GetLastError));
    end;

    if not (Terminated or FTerminating) then
      Sleep(100);
  end;

  if Assigned(FOnLog) then
    FOnLog('Pipe server thread ending');
end;

end.