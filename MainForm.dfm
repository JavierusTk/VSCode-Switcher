object FormMain: TFormMain
  Left = 0
  Top = 0
  Caption = 'IDE Switcher Test Application'
  ClientHeight = 450
  ClientWidth = 650
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 13
  object PageControl1: TPageControl
    Left = 0
    Top = 0
    Width = 650
    Height = 431
    ActivePage = TabSheetSend
    Align = alClient
    TabOrder = 0
    object TabSheetSend: TTabSheet
      Caption = 'Send Messages'
      object GroupBox1: TGroupBox
        Left = 16
        Top = 16
        Width = 609
        Height = 241
        Caption = 'Message Parameters'
        TabOrder = 0
        object Label1: TLabel
          Left = 24
          Top = 40
          Width = 45
          Height = 13
          Caption = 'File Path:'
        end
        object Label2: TLabel
          Left = 24
          Top = 88
          Width = 23
          Height = 13
          Caption = 'Line:'
        end
        object Label3: TLabel
          Left = 160
          Top = 88
          Width = 39
          Height = 13
          Caption = 'Column:'
        end
        object EditFilePath: TEdit
          Left = 24
          Top = 56
          Width = 561
          Height = 21
          TabOrder = 0
          Text = 'C:\Projects\TestFile.pas'
        end
        object EditLine: TEdit
          Left = 24
          Top = 104
          Width = 121
          Height = 21
          TabOrder = 1
          Text = '42'
        end
        object EditColumn: TEdit
          Left = 160
          Top = 104
          Width = 121
          Height = 21
          TabOrder = 2
          Text = '15'
        end
        object ButtonSendToVSCode: TButton
          Left = 24
          Top = 160
          Width = 185
          Height = 41
          Caption = 'Send to VS Code Pipe'
          TabOrder = 3
          OnClick = ButtonSendToVSCodeClick
        end
        object ButtonSendToDelphi: TButton
          Left = 224
          Top = 160
          Width = 185
          Height = 41
          Caption = 'Send to Delphi IDE Pipe'
          TabOrder = 4
          OnClick = ButtonSendToDelphiClick
        end
      end
    end
    object TabSheetReceive: TTabSheet
      Caption = 'Receive from VS Code'
      ImageIndex = 1
      object GroupBox2: TGroupBox
        Left = 16
        Top = 16
        Width = 609
        Height = 369
        Caption = 'Pipe Server'
        TabOrder = 0
        object LabelServerStatus: TLabel
          Left = 24
          Top = 32
          Width = 118
          Height = 13
          Caption = 'Server Status: STOPPED'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clRed
          Font.Height = -11
          Font.Name = 'Tahoma'
          Font.Style = []
          ParentFont = False
        end
        object ButtonStartServer: TButton
          Left = 24
          Top = 56
          Width = 121
          Height = 33
          Caption = 'Start Server'
          TabOrder = 0
          OnClick = ButtonStartServerClick
        end
        object ButtonStopServer: TButton
          Left = 160
          Top = 56
          Width = 121
          Height = 33
          Caption = 'Stop Server'
          Enabled = False
          TabOrder = 1
          OnClick = ButtonStopServerClick
        end
        object MemoReceived: TMemo
          Left = 24
          Top = 104
          Width = 561
          Height = 241
          Font.Charset = ANSI_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Courier New'
          Font.Style = []
          ParentFont = False
          ReadOnly = True
          ScrollBars = ssVertical
          TabOrder = 2
        end
      end
    end
    object TabSheetMockVSCode: TTabSheet
      Caption = 'Mock VS Code Server'
      ImageIndex = 3
      object GroupBoxMockVSCode: TGroupBox
        Left = 16
        Top = 16
        Width = 609
        Height = 369
        Caption = 'Mock VS Code Server (Test Delphi Plugin)'
        TabOrder = 0
        object LabelMockStatus: TLabel
          Left = 24
          Top = 32
          Width = 119
          Height = 13
          Caption = 'Mock VS Code: STOPPED'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clRed
          Font.Height = -11
          Font.Name = 'Tahoma'
          Font.Style = []
          ParentFont = False
        end
        object ButtonStartMockVSCode: TButton
          Left = 24
          Top = 56
          Width = 121
          Height = 33
          Caption = 'Start Mock VS Code'
          TabOrder = 0
          OnClick = ButtonStartMockVSCodeClick
        end
        object ButtonStopMockVSCode: TButton
          Left = 160
          Top = 56
          Width = 121
          Height = 33
          Caption = 'Stop Mock VS Code'
          Enabled = False
          TabOrder = 1
          OnClick = ButtonStopMockVSCodeClick
        end
        object ButtonTestDelphiPlugin: TButton
          Left = 296
          Top = 56
          Width = 145
          Height = 33
          Caption = 'Test Delphi Plugin'
          Enabled = False
          TabOrder = 2
          OnClick = ButtonTestDelphiPluginClick
        end
        object CheckBoxAutoRespond: TCheckBox
          Left = 456
          Top = 64
          Width = 129
          Height = 17
          Caption = 'Auto-respond to Delphi'
          TabOrder = 3
        end
        object MemoMockReceived: TMemo
          Left = 24
          Top = 104
          Width = 561
          Height = 241
          Font.Charset = ANSI_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Courier New'
          Font.Style = []
          ParentFont = False
          ReadOnly = True
          ScrollBars = ssVertical
          TabOrder = 4
        end
      end
    end
    object TabSheetLog: TTabSheet
      Caption = 'Communication Log'
      ImageIndex = 2
      object MemoLog: TMemo
        Left = 0
        Top = 0
        Width = 642
        Height = 360
        Align = alClient
        Font.Charset = ANSI_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Courier New'
        Font.Style = []
        ParentFont = False
        ReadOnly = True
        ScrollBars = ssVertical
        TabOrder = 0
      end
      object ButtonClearLog: TButton
        Left = 0
        Top = 360
        Width = 642
        Height = 43
        Align = alBottom
        Caption = 'Clear Log'
        TabOrder = 1
        OnClick = ButtonClearLogClick
      end
    end
  end
  object StatusBar1: TStatusBar
    Left = 0
    Top = 431
    Width = 650
    Height = 19
    Panels = <>
    SimplePanel = True
    SimpleText = 'Ready'
  end
end
