program IDESwitcherTest;

uses
  Vcl.Forms,
  MainForm in 'MainForm.pas' {FormMain};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'IDE Switcher Test Application';
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.