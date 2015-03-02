unit fMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.StdCtrls,
  defs, PCSCConnector, CardUtils, EMVsys, EMVConst;

type
  TForm1 = class(TForm)
    Panel1: TPanel;
    Label1: TLabel;
    cbReaders: TComboBox;
    btRefresh: TButton;
    Memo1: TMemo;
    Button1: TButton;
    cbATR: TCheckBox;
    cbTLV: TCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure btRefreshClick(Sender: TObject);
  private
    { Private declarations }

    procedure ClearLog;
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure LoggerAddLog(s: string);
begin
  Form1.Memo1.Lines.Add(s);
end;

procedure TForm1.btRefreshClick(Sender: TObject);
var
  pcscC: TPCSCConnector;
  indx: integer;
begin
  try
    indx := cbReaders.ItemIndex;
    cbReaders.Items.Clear;

    pcscC := TPCSCConnector.Create(Application);

    pcscC.Init;
    cbReaders.Items.Assign(pcscC.ReaderList);
    pcscC.UseReaderNum := 0;

    pcscC.Disconnect;
    pcscC.Close;

    pcscC.Destroy;

    if cbReaders.Items.Count > indx then
      cbReaders.ItemIndex := indx;

    if (cbReaders.Items.Count > 0) and (cbReaders.ItemIndex < 0) then
      cbReaders.ItemIndex := 0;

  except
  end;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  pcscC: TPCSCConnector;
  Result: boolean;
//  a: ATRrec;
//  strRes: AnsiString;
  i: Integer;
//  sw: word;
//  tlv: TTLV;
  emv: TEMV;
begin
  try
    if cbReaders.ItemIndex < 0 then exit;
    ClearLog;

    pcscC := TPCSCConnector.Create(Application);

    AddLog('* PCSC init');
    pcscC.Init;
    pcscC.UseReaderNum := cbReaders.ItemIndex;

    AddLog('* PCSC inited. readers count=' + IntToStr(pcscC.NumReaders));

    emv := nil;
    try
      Result := pcscC.Open;
      if not Result then
      begin
        AddLog('PCSC open error');
        exit;
      end;

      AddLog('* PCSC opened');

      Result := pcscC.Connect;
      if not Result then exit;

      AddLog('* PCSC connected. InterfaceState=' + IntToStr(pcscC.AttrInterfaceStatus) +' protocol=' + IntToStr(pcscC.AttrProtocol));
      if cbATR.Checked then
      begin
        AddLog('ICC=' + pcscC.AttrICCType);
      end;
      AddLog('ATR=' + Bin2HexExt(pcscC.AttrCardATR, true, true) + ' hist=' + pcscC.AttrATRHistBytes);
      if cbATR.Checked then
      begin
        AddLog('Default data rate=' + IntToStr(pcscC.AttrProtocol));
        AddLog('Default clock=' + IntToStr(pcscC.AttrProtocol));
        AddLog('ATR:' + #$0D#$0A + pcscC.AttrATR.GetStr);
      end;

      if pcscC.AttrCardATR = '' then
      begin
        AddLog('Card not present. exiting...');
        exit;
      end;

      emv := TEMV.Create(pcscC);
      emv.LoggingTLV := cbTLV.Checked;

      AddLog('');
      AddLog('* * * Trying  PSE');
      emv.GetAIDsByPSE('1PAY.SYS.DDF01');
      emv.GetAIDsByPSE('2PAY.SYS.DDF01');

      emv.AIDList.Clear; // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      if emv.AIDList.Count < 1 then
      begin
        AddLog('');
        AddLog('* * * The card have no PSE, switching to List of AIDs');

        emv.GetAIDsByConstAIDList;
      end;

     AddLog('* * * List Definition Files:');
     for i := 0 to emv.AIDList.Count - 1 do
       AddLog('- ' + emv.AIDList[i].ToString);

     AddLog('');
     // select definition file
     emv.SelectAppByList;

     if emv.SelectedAID = '' then
     begin
       AddLog('* Cant select app. EXIT!');
       exit;
     end;

     AddLog('* * * Get Processing Options');

     // fill PDOL fields

     // 9F1A	Terminal Country Code
     emv.SetGPO_PDOL(#$9F#$1A, 'ru');
     // 9F66 ������������� ���������� ��� ���������. � ���������� ������ ����� ����� ���: 86 40 00 00
     emv.SetGPO_PDOL(#$9F#$66, #$A6#$00#$00#$00);
     // 9F02 Amount, Authorised (Numeric)
     emv.SetGPO_PDOL(#$9F#$02, #$01#$00); //amount
     // 9F37 Unpredictable Number
     emv.SetGPO_PDOL(#$9F#$37, #$01#$23#$45#$67);
     // 5F2A Transaction Currency Code
     emv.SetGPO_PDOL(#$5F#$2A, #$09#$99);  //rub


     AddLog('PDOL: ');
     AddLog(emv.FCIPTSelectedApp.PDOL.DecodeStr('^'));

     if not emv.GPO then
     begin
       AddLog('GPO failed(');
       exit;
     end;

     // EMV 4.3 book3 10.3 page 111. Auth priority CDA --> DDA --> SDA
     //* Updated Input to Authentication as valid 9F4A is present
     if emv.GPORes1.AIP.SDAsupported then
     begin
       if not emv.SDA then exit;
     end
     else
       AddLog('* SDA is not supported according to AIP');

     if emv.GPORes1.AIP.DDAsupported then
     begin
       AddLog('* DDA');
     end
     else
       AddLog('* DDA is not supported according to AIP');

    finally
      emv.Free;

      AddLog('* PCSC done');
      if pcscC.Connected then pcscC.Disconnect;
      if pcscC.Opened then pcscC.Close;

      pcscC.Destroy;
    end;

  except
  end;
end;

procedure TForm1.ClearLog;
begin
  Memo1.Lines.Clear;
  Memo1.Lines.Add(FormatDateTime('', Now));
  SLogger := LoggerAddLog;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  btRefreshClick(Sender);
end;

end.
