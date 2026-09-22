unit gemini_browser_unit;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls,
  Process,
  SynEdit,
  IdGlobal, IdSSL, IdSSLOpenSSL, IdSSLOpenSSLHeaders, IdGemini, IdURI;

type
  TIdentEntry = record
    LabelText: string;
    Crt, Key: string;
  end;

  TMainForm = class(TForm)
    TopBar: TPanel;
    BackBtn: TButton;
    FwdBtn: TButton;
    UrlEdit: TEdit;
    GoBtn: TButton;
    IdentityBox: TComboBox;
    GmiView: TSynEdit;
    StatusBar: TStatusBar;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure UrlEditKeyPress(Sender: TObject; var Key: Char);
    procedure GoBtnClick(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure FwdClick(Sender: TObject);
    procedure IdentityBoxChange(Sender: TObject);
  private
    FGemini: TIdGemini;
    FCurrentURL: string;
    FPageStatus: string;
    FIdents: array of TIdentEntry;
    FDocLinks: array of string;      // line index -> resolved target ('' = not a link)
    FDocLinkEnd: array of Integer;   // line index -> last column of the visible label
    FLinkLine: Integer;              // hovered link line, -1 = none
    FStarted: Boolean;
    FRefreshing: Boolean;
    FHistory: array of string;
    FHistoryPos: Integer;
    function CertSubject(const AFileName: string): string;
    procedure LoadIdents;
    procedure SelectIdentity(AIndex: Integer);
    function ResolveLink(const ARelative: string): string;
    procedure Fetch(const AURL: string; APush: Boolean = True);
    procedure Render(const ABody: string);
    procedure AddCreateIdentityHint;
    procedure GmiMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GmiMouseLeave(Sender: TObject);
    procedure GmiPaint(Sender: TObject; ACanvas: TCanvas);
    procedure GmiMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure PushHistory(const AURL: string);
    procedure UpdateNavButtons;
    function RunCli(const AArgs: TStringList; ANeedOutput: Boolean; out AOutput: string): Boolean;
    procedure CreateNewIdentity(out ACreated: Boolean; out ANewKey: string);
  end;

  TNewIdentityDialog = class(TForm)
  public
    EdName, EdEmail: TEdit;
    constructor CreateDialog;
  end;

var
  MainForm: TMainForm;

implementation

uses IdException;

{$R *.lfm}

const
  kOpenSSL = '/opt/openssl-1.0.2u/bin/openssl';
  kNewIdentityCmd = '^NEWID';

function IdentsDir: string;
begin
  Result := GetEnvironmentVariable('HOME') + '/.config/pishmish/idents/';
  ForceDirectories(Result);
end;

function StreamToUtf8(AStream: TStream): string;
var
  Buf: TBytes;
begin
  Result := '';
  if (AStream = nil) or (AStream.Size = 0) then Exit;
  AStream.Position := 0;
  SetLength(Buf, AStream.Size);
  AStream.ReadBuffer(Buf[0], Length(Buf));
  Result := TEncoding.UTF8.GetString(Buf);
end;

function AskIdentityParams(out AName, AEmail: string): Boolean;
var
  Dlg: TNewIdentityDialog;
  LblName, LblEmail: TLabel;
  OkBtn, CancelBtn: TButton;
begin
  Result := False;
  Dlg := TNewIdentityDialog.CreateDialog;
  try
    LblName := TLabel.Create(Dlg);
    LblName.Parent := Dlg;
    LblName.Left := 12; LblName.Top := 10;
    LblName.Caption := 'Identity name (shown to servers)';
    Dlg.EdName := TEdit.Create(Dlg);
    Dlg.EdName.Parent := Dlg;
    Dlg.EdName.Left := 12; Dlg.EdName.Top := 32; Dlg.EdName.Width := 316;
    LblEmail := TLabel.Create(Dlg);
    LblEmail.Parent := Dlg;
    LblEmail.Left := 12; LblEmail.Top := 60;
    LblEmail.Caption := 'Email (optional)';
    Dlg.EdEmail := TEdit.Create(Dlg);
    Dlg.EdEmail.Parent := Dlg;
    Dlg.EdEmail.Left := 12; Dlg.EdEmail.Top := 82; Dlg.EdEmail.Width := 316;
    OkBtn := TButton.Create(Dlg);
    OkBtn.Parent := Dlg;
    OkBtn.Caption := 'OK';
    OkBtn.ModalResult := mrOk;
    OkBtn.Default := True;
    OkBtn.Left := 160; OkBtn.Top := 118; OkBtn.Width := 84; OkBtn.Height := 30;
    CancelBtn := TButton.Create(Dlg);
    CancelBtn.Parent := Dlg;
    CancelBtn.Caption := 'Cancel';
    CancelBtn.ModalResult := mrCancel;
    CancelBtn.Cancel := True;
    CancelBtn.Left := 248; CancelBtn.Top := 118; CancelBtn.Width := 84; CancelBtn.Height := 30;
    Dlg.ActiveControl := Dlg.EdName;
    if Dlg.ShowModal = mrOk then
    begin
      AName := Trim(Dlg.EdName.Text);
      AEmail := Trim(Dlg.EdEmail.Text);
      Result := AName <> '';
    end;
  finally
    Dlg.Free;
  end;
end;

constructor TNewIdentityDialog.CreateDialog;
begin
  inherited CreateNew(nil);
  Caption := 'Create identity';
  ClientWidth := 340;
  ClientHeight := 158;
  Position := poScreenCenter;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FGemini := TIdGemini.Create(Self);
  LoadIdents;
  IdentityBox.ItemIndex := 0;
  FLinkLine := -1;
  FPageStatus := '';
  FHistoryPos := -1;
  UpdateNavButtons;
  // heliko-style mouse link handling; note: no '@' prefix, see ../etest
  GmiView.OnMouseMove := GmiMouseMove;
  GmiView.OnMouseLeave := GmiMouseLeave;
  GmiView.OnPaint := GmiPaint;
  GmiView.OnMouseUp := GmiMouseUp;
  // Ctrl + mouse wheel zooms the text (same as heliko)
  GmiView.OnMouseWheel := FormMouseWheel;
  OnMouseWheel := FormMouseWheel;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  if not FStarted then
  begin
    FStarted := True;
    Fetch(Trim(UrlEdit.Text));
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FGemini);
end;

function TMainForm.CertSubject(const AFileName: string): string;
var
  Bio: PBIO;
  X: PX509;
  Name: PIdAnsiChar;
  ResBuf: array[0..1023] of AnsiChar;
begin
  Result := '';
  if not IdSSLOpenSSL.LoadOpenSSLLibrary then Exit;
  X := nil;
  Name := nil;
  Bio := BIO_new_file(PIdAnsiChar(AnsiString(AFileName)), 'r');
  if Bio = nil then Exit;
  try
    X := PEM_read_bio_X509(Bio, nil, nil, nil);
    if X = nil then Exit;
    Name := X509_NAME_oneline(X509_get_subject_name(X), @ResBuf[0], SizeOf(ResBuf));
    if Name <> nil then
      Result := string(StrPas(PChar(Name)));
  finally
    if X <> nil then X509_free(X);
    BIO_free(Bio);
  end;
end;

procedure TMainForm.LoadIdents;
var
  SR: TSearchRec;
  Entry: TIdentEntry;
  FP, Subject, Dir: string;
begin
  Dir := IdentsDir;
  FRefreshing := True;
  try
    SetLength(FIdents, 0);
    IdentityBox.Items.BeginUpdate;
    try
      IdentityBox.Items.Clear;
      IdentityBox.Items.Add('(no identity)');
      if FindFirst(Dir + '*.crt', faAnyFile, SR) = 0 then
      try
        repeat
          FP := ChangeFileExt(SR.Name, '');
          Subject := CertSubject(Dir + SR.Name);
          if Subject = '' then Continue;
          Entry.LabelText := Subject + '  [' + Copy(FP, 1, 8) + ']';
          Entry.Crt := Dir + SR.Name;
          Entry.Key := Dir + FP + '.key';
          SetLength(FIdents, Length(FIdents) + 1);
          FIdents[High(FIdents)] := Entry;
          IdentityBox.Items.Add(Entry.LabelText);
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
      IdentityBox.Items.Add('＋ create new identity…');
    finally
      IdentityBox.Items.EndUpdate;
    end;
  finally
    FRefreshing := False;
  end;
  if Length(FIdents) = 0 then
    StatusBar.SimpleText := 'No identities yet — pick "create new identity" in the list';
end;

procedure TMainForm.SelectIdentity(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < IdentityBox.Items.Count) then
  begin
    FRefreshing := True;
    try
      IdentityBox.ItemIndex := AIndex;
    finally
      FRefreshing := False;
    end;
  end;
end;

function TMainForm.ResolveLink(const ARelative: string): string;
var
  Rel: string;
  U: TIdURI;
  Dir, S: string;
  P: Integer;
begin
  Rel := Trim(ARelative);
  Result := Rel;
  if Rel = '' then Exit;
  if Rel[1] = '#' then
  begin
    Result := FCurrentURL;
    Exit;
  end;
  U := TIdURI.Create(Rel);
  try
    if U.Protocol <> '' then Exit;
  finally
    U.Free;
  end;
  U := TIdURI.Create(FCurrentURL);
  try
    if Copy(Rel, 1, 2) = '//' then
      Result := U.Protocol + ':' + Rel
    else if Rel[1] = '/' then
    begin
      Result := U.Protocol + '://' + U.Host;
      if U.Port <> '' then Result := Result + ':' + U.Port;
      Result := Result + Rel;
    end
    else
    begin
      Result := U.Protocol + '://' + U.Host;
      if U.Port <> '' then Result := Result + ':' + U.Port;
      S := U.Path + U.Document;
      P := LastDelimiter('/', S);
      if P <= 0 then
        Dir := '/'
      else
        Dir := Copy(S, 1, P);
      Result := Result + Dir + Rel;
    end;
  finally
    U.Free;
  end;
end;

procedure TMainForm.AddCreateIdentityHint;
var
  LineNo: Integer;
  S: string;
begin
  GmiView.Lines.Add('');
  S := '＋ create an identity, then try again';
  LineNo := GmiView.Lines.Count;
  GmiView.Lines.Add(S);
  if LineNo >= Length(FDocLinks) then
  begin
    SetLength(FDocLinks, LineNo + 1);
    SetLength(FDocLinkEnd, LineNo + 1);
  end;
  FDocLinks[LineNo] := kNewIdentityCmd;
  FDocLinkEnd[LineNo] := Length(S);
end;

procedure TMainForm.Render(const ABody: string);
var
  SL: TStringList;
  I, LineNo: Integer;
  L, Target, LabelTxt: string;
  P: Integer;
  InPre: Boolean;
begin
  SL := TStringList.Create;
  try
    SetLength(FDocLinks, 0);
    SetLength(FDocLinkEnd, 0);
    SL.Text := ABody;
    InPre := False;
    for I := 0 to SL.Count - 1 do
    begin
      L := SL[I];
      if (Length(L) >= 3) and (Copy(L, 1, 3) = '```') then
      begin
        InPre := not InPre;
        GmiView.Lines.Add('');
        Continue;
      end;
      if InPre then
      begin
        GmiView.Lines.Add(L);
        Continue;
      end;
      if Copy(L, 1, 2) = '=>' then
      begin
        // rocketlink: '=>' followed directly (or after whitespace) by the URL.
        // Show only the label (the URL is the hover/tooltip + status bar);
        // if there is no label, show the URL itself. The clickable span is
        // the visible label.
        L := Trim(Copy(L, 3));
        if L = '' then Continue;
        P := 1;
        while (P <= Length(L)) and (L[P] <> ' ') do Inc(P);
        Target := Trim(Copy(L, 1, P - 1));
        LabelTxt := Trim(Copy(L, P + 1));
        if LabelTxt = '' then LabelTxt := Target;
        LineNo := GmiView.Lines.Count;
        GmiView.Lines.Add(LabelTxt);
        if LineNo >= Length(FDocLinks) then
        begin
          SetLength(FDocLinks, LineNo + 1);
          SetLength(FDocLinkEnd, LineNo + 1);
        end;
        FDocLinks[LineNo] := ResolveLink(Target);
        FDocLinkEnd[LineNo] := Length(LabelTxt);
        Continue;
      end;
      if L = '' then Continue;
      if L[1] = '#' then
        GmiView.Lines.Add(TrimLeft(Copy(L, 2)))
      else
        GmiView.Lines.Add(L);
    end;
  finally
    SL.Free;
  end;
end;

procedure TMainForm.Fetch(const AURL: string; APush: Boolean = True);
var
  R: TGeminiResponse;
  Input: string;
begin
  if AURL = '' then Exit;
  StatusBar.SimpleText := 'Connecting to ' + AURL + ' ...';
  try
    if IdentityBox.ItemIndex > 0 then
    begin
      FGemini.SSLIOHandler.SSLOptions.CertFile := FIdents[IdentityBox.ItemIndex - 1].Crt;
      FGemini.SSLIOHandler.SSLOptions.KeyFile := FIdents[IdentityBox.ItemIndex - 1].Key;
    end
    else
    begin
      FGemini.SSLIOHandler.SSLOptions.CertFile := '';
      FGemini.SSLIOHandler.SSLOptions.KeyFile := '';
    end;

    R := FGemini.Request(AURL);
    try
      if (R.Status = IdGemini.gsInput) or (R.Status = IdGemini.gsSensitiveInput) then
      begin
        Input := '';
        if InputQuery('Input required', R.Meta, Input) then
        begin
          R.Free;
          R := FGemini.Request(AURL, Input);
        end;
      end;

      FCurrentURL := AURL;
      UrlEdit.Text := AURL;
      GmiView.Lines.BeginUpdate;
      try
        GmiView.Lines.Text := '';
        Render(StreamToUtf8(R.Content));
        if R.Status = IdGemini.gsCertRequired then
          AddCreateIdentityHint;
      finally
        GmiView.Lines.EndUpdate;
      end;
      FPageStatus := '';
      StatusBar.SimpleText := '';
      if APush then PushHistory(AURL);
    finally
      R.Free;
    end;
  except
    on E: Exception do
    begin
      GmiView.Lines.Text := 'Error: ' + E.Message;
      FPageStatus := 'Error: ' + E.Message;
      StatusBar.SimpleText := FPageStatus;
    end;
  end;
end;

function TMainForm.RunCli(const AArgs: TStringList; ANeedOutput: Boolean; out AOutput: string): Boolean;
var
  P: TProcess;
  I, N: Integer;
  Buf: array[0..8191] of AnsiChar;
  Tmp: AnsiString;
begin
  Result := False;
  AOutput := '';
  if not FileExists(kOpenSSL) then
    raise Exception.Create('openssl not found at ' + kOpenSSL);
  P := TProcess.Create(nil);
  try
    P.Executable := kOpenSSL;
    for I := 0 to AArgs.Count - 1 do
      P.Parameters.Add(AArgs[I]);
    P.Options := [poWaitOnExit];
    if ANeedOutput then P.Options := P.Options + [poUsePipes];
    P.Execute;
    if ANeedOutput then
    begin
      repeat
        N := P.Output.Read(Buf, SizeOf(Buf));
        if N > 0 then
        begin
          SetLength(Tmp, N);
          Move(Buf[0], Tmp[1], N);
          AOutput := AOutput + string(Tmp);
        end;
      until N <= 0;
    end;
    Result := P.ExitStatus = 0;
  finally
    P.Free;
  end;
end;

procedure TMainForm.CreateNewIdentity(out ACreated: Boolean; out ANewKey: string);
var
  Name, Email, Dir, TmpKey, TmpCrt, ArgSubj, Output, FP: string;
  Args: TStringList;
  I, P: Integer;
begin
  ACreated := False;
  ANewKey := '';
  if not AskIdentityParams(Name, Email) then
  begin
    // cancelled: step back to "no identity"
    SelectIdentity(0);
    Exit;
  end;

  Dir := IdentsDir;
  TmpKey := Dir + 'new.key';
  TmpCrt := Dir + 'new.crt';
  DeleteFile(TmpKey);
  DeleteFile(TmpCrt);

  ArgSubj := '/CN=' + Name;
  if Email <> '' then ArgSubj := ArgSubj + '/emailAddress=' + Email;

  Args := TStringList.Create;
  try
    Args.Add('req'); Args.Add('-x509'); Args.Add('-newkey'); Args.Add('rsa:2048');
    Args.Add('-nodes'); Args.Add('-days'); Args.Add('36500');
    Args.Add('-keyout'); Args.Add(TmpKey);
    Args.Add('-out'); Args.Add(TmpCrt);
    Args.Add('-subj'); Args.Add(ArgSubj);
    if not RunCli(Args, False, Output) then
      raise Exception.Create('openssl req failed: ' + Output);

    Args.Clear;
    Args.Add('x509'); Args.Add('-in'); Args.Add(TmpCrt);
    Args.Add('-noout'); Args.Add('-fingerprint'); Args.Add('-sha256');
    if not RunCli(Args, True, Output) then
      raise Exception.Create('openssl fingerprint failed');
  finally
    Args.Free;
  end;

  // e.g. "SHA256 Fingerprint=82:CC:64:EB:..." -> lowercase hex without colons
  FP := '';
  P := LastDelimiter('=', Output);
  if P > 0 then
  begin
    FP := LowerCase(Output);
    System.Delete(FP, 1, P);
    while Pos(':', FP) > 0 do System.Delete(FP, Pos(':', FP), 1);
    FP := Trim(FP);
  end;
  if Length(FP) <> 64 then
    raise Exception.Create('unexpected fingerprint output: ' + Output);

  if not RenameFile(TmpCrt, Dir + FP + '.crt') then
    raise Exception.Create('cannot save cert file to ' + Dir);
  if not RenameFile(TmpKey, Dir + FP + '.key') then
    raise Exception.Create('cannot save key file to ' + Dir);

  ACreated := True;
  ANewKey := Dir + FP + '.key';

  // refresh the list and select the freshly created identity
  LoadIdents;
  for I := 0 to High(FIdents) do
    if FIdents[I].Key = ANewKey then
    begin
      SelectIdentity(I + 1);
      Break;
    end;
end;

procedure TMainForm.GmiMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Pt: TPoint;
  Line: Integer;
begin
  Pt := GmiView.PixelsToRowColumn(Point(X, Y));
  Line := Pt.Y - 1;
  if (Line >= 0) and (Line < Length(FDocLinks)) and (FDocLinks[Line] <> '') then
  begin
    GmiView.Cursor := crHandPoint;
    if (Line <> FLinkLine) and (FDocLinks[Line] <> kNewIdentityCmd) and (FPageStatus <> '') then
      StatusBar.SimpleText := '→ ' + FDocLinks[Line];
  end
  else
  begin
    GmiView.Cursor := crDefault;
    if FPageStatus <> '' then
      StatusBar.SimpleText := FPageStatus;
  end;
  if Line <> FLinkLine then
  begin
    FLinkLine := Line;
    GmiView.Invalidate;
  end;
end;

procedure TMainForm.GmiMouseLeave(Sender: TObject);
begin
  GmiView.Cursor := crDefault;
  if FPageStatus <> '' then
    StatusBar.SimpleText := FPageStatus;
  if FLinkLine >= 0 then
  begin
    FLinkLine := -1;
    GmiView.Invalidate;
  end;
end;

procedure TMainForm.GmiPaint(Sender: TObject; ACanvas: TCanvas);
var
  GutterWidth, StartX, EndX, LineY: Integer;
begin
  // heliko-style underline under the hovered rocketlink label
  if (FLinkLine < 0) or (FLinkLine >= Length(FDocLinks)) or (FDocLinks[FLinkLine] = '') then
    Exit;
  if (FLinkLine < GmiView.TopLine - 1) or
     (FLinkLine >= GmiView.TopLine + GmiView.LinesInWindow) then
    Exit;

  GutterWidth := 0;
  if GmiView.Gutter.Visible then
    GutterWidth := GmiView.Gutter.Width;

  LineY := (FLinkLine - GmiView.TopLine + 1) * GmiView.LineHeight;
  StartX := GutterWidth + (1 - GmiView.LeftChar) * GmiView.CharWidth;
  EndX := GutterWidth + (FDocLinkEnd[FLinkLine] + 1 - GmiView.LeftChar) * GmiView.CharWidth;

  if StartX < GutterWidth then StartX := GutterWidth;
  if EndX > GmiView.ClientWidth then EndX := GmiView.ClientWidth;

  if StartX < EndX then
  begin
    ACanvas.Pen.Color := clBlue;
    ACanvas.Pen.Width := 1;
    ACanvas.MoveTo(StartX, LineY + GmiView.LineHeight - 2);
    ACanvas.LineTo(EndX, LineY + GmiView.LineHeight - 2);
  end;
end;

procedure TMainForm.GmiMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Pt: TPoint;
  Line: Integer;
  Target: string;
  Created: Boolean;
  NewKey: string;
begin
  if Button <> mbLeft then Exit;
  Pt := GmiView.PixelsToRowColumn(Point(X, Y));
  Line := Pt.Y - 1;
  if (Line >= 0) and (Line < Length(FDocLinks)) then
  begin
    Target := FDocLinks[Line];
    if Target = kNewIdentityCmd then
    begin
      CreateNewIdentity(Created, NewKey);
      if Created then
        Fetch(FCurrentURL, False);
    end
    else if Target <> '' then
      Fetch(Target);
  end;
end;

procedure TMainForm.FormMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
var
  NewSize: Integer;
begin
  if (Sender = GmiView) and (ssCtrl in Shift) then
  begin
    NewSize := GmiView.Font.Size;
    if WheelDelta > 0 then
      NewSize := NewSize + 2
    else if NewSize > 8 then
      NewSize := NewSize - 2;
    GmiView.Font.Size := NewSize;
    Handled := True;
  end;
end;

procedure TMainForm.PushHistory(const AURL: string);
begin
  if AURL = '' then Exit;
  if (FHistoryPos >= 0) and (FHistoryPos < Length(FHistory)) and
     (FHistory[FHistoryPos] = AURL) then Exit;
  SetLength(FHistory, FHistoryPos + 2);
  Inc(FHistoryPos);
  FHistory[FHistoryPos] := AURL;
  UpdateNavButtons;
end;

procedure TMainForm.UpdateNavButtons;
begin
  BackBtn.Enabled := FHistoryPos > 0;
  FwdBtn.Enabled := (FHistoryPos >= 0) and (FHistoryPos + 1 < Length(FHistory));
end;

procedure TMainForm.BackClick(Sender: TObject);
begin
  if FHistoryPos > 0 then
  begin
    Dec(FHistoryPos);
    UpdateNavButtons;
    Fetch(FHistory[FHistoryPos], False);
  end;
end;

procedure TMainForm.FwdClick(Sender: TObject);
begin
  if (FHistoryPos >= 0) and (FHistoryPos + 1 < Length(FHistory)) then
  begin
    Inc(FHistoryPos);
    UpdateNavButtons;
    Fetch(FHistory[FHistoryPos], False);
  end;
end;

procedure TMainForm.GoBtnClick(Sender: TObject);
begin
  Fetch(Trim(UrlEdit.Text));
end;

procedure TMainForm.UrlEditKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    GoBtnClick(Sender);
  end;
end;

procedure TMainForm.IdentityBoxChange(Sender: TObject);
var
  Created: Boolean;
  NewKey: string;
begin
  if FRefreshing then Exit;
  if IdentityBox.Items.Count = 0 then Exit;
  if IdentityBox.ItemIndex = IdentityBox.Items.Count - 1 then
    CreateNewIdentity(Created, NewKey);
end;

end.