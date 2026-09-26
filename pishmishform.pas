unit pishmishform;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls, LCLType, Clipbrd, Menus,
  Process, LCLIntf,
  Math,
  SynEdit, SynEditTypes, SynEditHighlighter,
  IdGlobal, IdSSL, IdSSLOpenSSL, IdSSLOpenSSLHeaders, IdGemini, IdURI;

type
  TIdentEntry = record
    LabelText: string;
    Crt, Key: string;
  end;

  TGemtextHighlighter = class(TSynCustomHighlighter)
  private
    FBoldAttr: TSynHighlighterAttributes;
    FPreAttr: TSynHighlighterAttributes;
    FNormalAttr: TSynHighlighterAttributes;
    FKinds: array of SmallInt;
    FLine: string;
    FLineLen: Integer;
    FTokenPos: Integer;
    FCursor: Integer;
    FEol: Boolean;
    FCurKind: SmallInt;
  protected
    function GetIdentChars: TSynIdentChars; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetLine(const NewValue: String; LineNumber: Integer); override;
    function GetEol: Boolean; override;
    procedure Next; override;
    function GetToken: String; override;
    procedure GetTokenEx(out TokenStart: PChar; out TokenLength: Integer); override;
    function GetTokenAttribute: TSynHighlighterAttributes; override;
    function GetTokenKind: Integer; override;
    function GetTokenPos: Integer; override;
    function GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes; override;
    function GetRange: Pointer; override;
    procedure ResetRange; override;
    procedure SetRange(Value: Pointer); override;
    procedure SetLineKinds(const AKinds: array of SmallInt);
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
    FDocLinkText: array of string;   // line index -> painted label, measured for the underline
    FLinkLine: Integer;              // hovered link line, -1 = none
    FStarted: Boolean;
    FRefreshing: Boolean;
    FHistory: array of string;
    FHistoryPos: Integer;
    FGemtextHL: TGemtextHighlighter;
    FLineKind: array of SmallInt;
    FLastRaw: string;
    FDownX: Integer;
    FDownY: Integer;
    FEditMenu: TPopupMenu;
    FCopyItem: TMenuItem;
    FOpenLinkItem: TMenuItem;
    FRightLink: string;               // link under the right-clicked position
    procedure EditMenuPopup(Sender: TObject);
    procedure EditMenuCopyClick(Sender: TObject);
    procedure OpenLinkInNewWindowClick(Sender: TObject);
    procedure OpenInNewWindow(const AURL: string);
    function CertSubject(const AFileName: string): string;
    procedure LoadIdents;
    procedure SelectIdentity(AIndex: Integer);
    function ResolveLink(const ARelative: string): string;
    procedure Fetch(const AURL: string; APush: Boolean = True);
    function NormalizeURL(const AURL: string): string;
    procedure Render(const ABody: string);
    procedure AddCreateIdentityHint;
    procedure GmiMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GmiMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure GmiMouseLeave(Sender: TObject);
    procedure GmiPaint(Sender: TObject; ACanvas: TCanvas);
    procedure GmiMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DumpDiagnostics(const APath: string);
    procedure GmiCopy(Sender: TObject; var AText: string;
      var AMode: TSynSelectionMode; ALogStartPos: TPoint;
      var AnAction: TSynCopyPasteAction);
    procedure FormMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure GmiResize(Sender: TObject);
    function Utf8Col(const S: string): Integer;
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

procedure WriteStringToFile(const APath, AContent: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(APath, fmCreate);
  try
    if AContent <> '' then
      F.Write(AContent[1], Length(AContent));
  finally
    F.Free;
  end;
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
var
  Itm: TMenuItem;
  I: Integer;
  IdentArg: string;
begin
  // 'pishmish <url> --ident=<n>' opens that page with that identity, used by
  // 'open link in new window'. '--ident' alone opens the default page.
  IdentArg := '';
  for I := 1 to ParamCount do
    if Copy(ParamStr(I), 1, 8) = '--ident=' then
      IdentArg := Copy(ParamStr(I), 9, MaxInt)
    else if (ParamStr(I) <> '') and (ParamStr(I)[1] <> '-') then
      UrlEdit.Text := ParamStr(I);
  FGemini := TIdGemini.Create(Self);
  FGemtextHL := TGemtextHighlighter.Create(Self);
  KeyPreview := True;
  OnKeyDown := FormKeyDown;
  LoadIdents;
  if IdentArg <> '' then
  begin
    SelectIdentity(StrToIntDef(IdentArg, 0));
    IdentityBox.OnChange := IdentityBoxChange;
  end
  else
    IdentityBox.ItemIndex := 0;
  FLinkLine := -1;
  FPageStatus := '';
  FHistoryPos := -1;
  UpdateNavButtons;
  // heliko-style mouse link handling; note: no '@' prefix, see ../etest
  GmiView.OnMouseMove := GmiMouseMove;
  GmiView.OnMouseLeave := GmiMouseLeave;
  GmiView.OnPaint := GmiPaint;
  GmiView.OnCutCopy := GmiCopy;
  GmiView.OnMouseUp := GmiMouseUp;
  GmiView.OnMouseDown := GmiMouseDown;
  FEditMenu := TPopupMenu.Create(Self);
  Itm := TMenuItem.Create(Self);
  Itm.Caption := 'Open &link in new window';
  Itm.OnClick := OpenLinkInNewWindowClick;
  FEditMenu.Items.Add(Itm);
  FOpenLinkItem := Itm;
  FEditMenu.Items.Add(TMenuItem.Create(Self));
  Itm := TMenuItem.Create(Self);
  Itm.Caption := '&Copy';
  Itm.OnClick := EditMenuCopyClick;
  FEditMenu.Items.Add(Itm);
  FCopyItem := Itm;
  FEditMenu.OnPopup := EditMenuPopup;
  GmiView.PopupMenu := FEditMenu;
  // Ctrl + mouse wheel zooms the text (same as heliko)
  GmiView.OnMouseWheel := FormMouseWheel;
  OnMouseWheel := FormMouseWheel;
  // re-wrap the page to the window width when the view is resized
  GmiView.OnResize := GmiResize;
  // same initial font sizing as heliko, so zoom starts from a sane size
  GmiView.Font.Size := Max(12, Min(Round(Screen.Height / 60 * (PixelsPerInch / 96)), 36));
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  if not FStarted then
  begin
    FStarted := True;
    Fetch(Trim(UrlEdit.Text));
  end;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (ssCtrl in Shift) and (Key = VK_N) then
  begin
    Key := 0;
    OpenInNewWindow('');
    Exit;
  end;
  if (ssCtrl in Shift) and (Key = VK_C) then
  begin
    if GmiView.SelAvail then
    begin
      Clipboard.AsText := GmiView.SelText;
      Key := 0;
    end;
    Exit;
  end;
  // debug aid: dump the raw + rendered page so the Dashboar line can be inspected
  if (ssCtrl in Shift) and (ssShift in Shift) and (Key = VK_D) then
  begin
    Key := 0;
    if FLastRaw <> '' then
    begin
      DumpDiagnostics('/tmp/pishmishraw.txt');
      StatusBar.SimpleText := 'raw page saved to /tmp/pishmishraw.txt';
    end;
  end;
end;

function TMainForm.Utf8Col(const S: string): Integer;
var
  Ix: Integer;
  B: Byte;
begin
  Result := 0;
  Ix := 1;
  while Ix <= Length(S) do
  begin
    Inc(Result);
    B := Ord(S[Ix]);
    if B < 128 then Inc(Ix)
    else if (B and $E0) = $C0 then Inc(Ix, 2)
    else if (B and $F0) = $E0 then Inc(Ix, 3)
    else if (B and $F8) = $F0 then Inc(Ix, 4)
    else Inc(Ix);
  end;
end;

procedure TMainForm.GmiResize(Sender: TObject);
begin
  // re-flow the currently displayed page to the new window width
  if FRefreshing or (FLastRaw = '') then Exit;
  FRefreshing := True;
  try
    GmiView.Lines.BeginUpdate;
    try
      GmiView.Lines.Text := '';
      Render(FLastRaw);
    finally
      GmiView.Lines.EndUpdate;
    end;
    GmiView.Invalidate;
    GmiView.Refresh;
  finally
    FRefreshing := False;
  end;
end;

procedure TMainForm.DumpDiagnostics(const APath: string);
var
  SL: TStringList;
  I: Integer;
begin
  SL := TStringList.Create;
  try
    SL.Add('===== raw content from server =====');
    SL.Text := SL.Text + FLastRaw;
    SL.Add('');
    SL.Add('===== rendered SynEdit buffer =====');
    SL.Add(GmiView.Text);
    SL.Add('');
    SL.Add('===== rendered lines with byte lengths =====');
    for I := 0 to GmiView.Lines.Count - 1 do
      SL.Add(IntToStr(I) + ': [' + IntToStr(Length(GmiView.Lines[I])) + '] <' +
        GmiView.Lines[I] + '>');
    SL.SaveToFile(APath);
  finally
    SL.Free;
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  GmiView.Highlighter := nil;
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
    SetLength(FDocLinkText, LineNo + 1);
  end;
  FDocLinks[LineNo] := kNewIdentityCmd;
  FDocLinkText[LineNo] := S;
  FDocLinkEnd[LineNo] := Utf8Col(S);
end;

procedure TMainForm.Render(const ABody: string);
label
  nxtline;
var
  SL: TStringList;
  L, Target, LabelTxt: string;
  I, P, T, NumHashes, LineNo: Integer;
  InPre: Boolean;
  FitChars, GW: Integer;

  function CountChars(const S: string): Integer;
  begin
    Result := Utf8Col(S);
  end;

  function StepAt(const S: string; Ix: Integer): Integer;
  var
    B: Byte;
  begin
    B := Ord(S[Ix]);
    if B < 128 then Result := 1
    else if (B and $E0) = $C0 then Result := 2
    else if (B and $F0) = $E0 then Result := 3
    else if (B and $F8) = $F0 then Result := 4
    else Result := 1;
  end;

  procedure AddLine(const ATxt: string; AKind: SmallInt);
  begin
    GmiView.Lines.Add(ATxt);
    SetLength(FLineKind, GmiView.Lines.Count);
    FLineKind[GmiView.Lines.Count - 1] := AKind;
  end;

  // Emit ATxt, wrapping at word boundaries to the window width. Continuation
  // lines get AContIndent (2 spaces for non-links, '' for links). Only the
  // first physical line of a link carries the clickable span.
  procedure EmitWrapped(ATxt: string; AKind: SmallInt; const AContIndent: string;
    AIsLink: Boolean; const ALinkTarget: string; ALinkEnd: Integer);
  var
    Rest, Piece, Pre, LineTxt: string;
    Limit, Take, N, Ix, LastBreak, L: Integer;
    First: Boolean;
  begin
    Rest := ATxt;
    Pre := '';
    First := True;
    while True do
    begin
      Limit := FitChars - CountChars(Pre);
      if Limit < 1 then Limit := 1;
      if CountChars(Rest) <= Limit then
      begin
        LineTxt := Pre + Rest;
        LineNo := GmiView.Lines.Count;
        AddLine(LineTxt, AKind);
        if First and AIsLink then
        begin
          if LineNo >= Length(FDocLinks) then
          begin
            SetLength(FDocLinks, LineNo + 1);
            SetLength(FDocLinkEnd, LineNo + 1);
            SetLength(FDocLinkText, LineNo + 1);
          end;
          FDocLinks[LineNo] := ALinkTarget;
          FDocLinkText[LineNo] := LineTxt;
          L := CountChars(LineTxt);
          if L > ALinkEnd then L := ALinkEnd;
          FDocLinkEnd[LineNo] := L;
        end;
        Break;
      end;
      // find the last space within the first Limit chars
      LastBreak := 0;
      N := 0;
      Ix := 1;
      while (N < Limit) and (Ix <= Length(Rest)) do
      begin
        if Rest[Ix] = ' ' then LastBreak := Ix;
        Ix := Ix + StepAt(Rest, Ix);
        Inc(N);
      end;
      if LastBreak > 0 then Take := LastBreak
      else Take := Ix - 1;
      if Take < 1 then Take := 1;
      Piece := TrimRight(Copy(Rest, 1, Take));
      LineNo := GmiView.Lines.Count;
      AddLine(Pre + Piece, AKind);
      if First and AIsLink then
      begin
        if LineNo >= Length(FDocLinks) then
        begin
          SetLength(FDocLinks, LineNo + 1);
          SetLength(FDocLinkEnd, LineNo + 1);
          SetLength(FDocLinkText, LineNo + 1);
        end;
        FDocLinks[LineNo] := ALinkTarget;
        FDocLinkText[LineNo] := Pre + Piece;
        L := CountChars(Pre + Piece);
        if L > ALinkEnd then L := ALinkEnd;
        FDocLinkEnd[LineNo] := L;
      end;
      First := False;
      Rest := Copy(Rest, Take + 1, MaxInt);
      Pre := AContIndent;
      if Rest = '' then Break;
    end;
  end;

begin
  SL := TStringList.Create;
  SetLength(FLineKind, 0);
  try
    SetLength(FDocLinks, 0);
    SetLength(FDocLinkEnd, 0);
    SetLength(FDocLinkText, 0);
    // the hovered line index no longer refers to the new page
    FLinkLine := -1;
    GW := 0;
    if GmiView.Gutter.Visible then
      GW := GmiView.Gutter.Width;
    FitChars := Max(8, (GmiView.ClientWidth - GW) div GmiView.CharWidth);
    SL.Text := ABody;
    InPre := False;
    for I := 0 to SL.Count - 1 do
    begin
      L := SL[I];
      // preformatted block fences (```) - content is non-link text so it is
      // indented; the block keeps a light background like Lagrange
      if (Length(L) >= 3) and (Copy(L, 1, 3) = '```') then
      begin
        InPre := not InPre;
        EmitWrapped('', 0, '  ', False, '', 0);
        goto nxtline;
      end;
      if InPre then
      begin
        EmitWrapped('  ' + L, 2, '  ', False, '', 0);
        goto nxtline;
      end;
      if Copy(L, 1, 2) = '=>' then
      begin
        // links are shown bold; display only the label (the URL is the
        // hover/tooltip + status bar); if there is no label, show the URL.
        L := Trim(Copy(L, 3));
        if L = '' then
        begin
          EmitWrapped('', 0, '  ', False, '', 0);
          goto nxtline;
        end;
        P := 1;
        while (P <= Length(L)) and (L[P] <> ' ') do Inc(P);
        Target := Trim(Copy(L, 1, P - 1));
        LabelTxt := Trim(Copy(L, P + 1));
        if LabelTxt = '' then LabelTxt := Target;
        EmitWrapped(LabelTxt, 1, '', True, ResolveLink(Target), CountChars(LabelTxt));
        goto nxtline;
      end;
      // gemtext headings: markers stripped, shown like plain text
      // (2-space indent, no bold)
      if (Length(L) > 0) and (L[1] = '#') then
      begin
        NumHashes := 0;
        T := 1;
        while (T <= Length(L)) and (L[T] = '#') do
        begin
          Inc(NumHashes);
          Inc(T);
        end;
        while (T <= Length(L)) and (L[T] = ' ') do Inc(T);
        if NumHashes in [1..3] then
        begin
          EmitWrapped('  ' + Trim(Copy(L, T, Length(L) - T + 1)), 0, '  ', False, '', 0);
          goto nxtline;
        end;
      end;
      if Trim(L) = '' then
        EmitWrapped('', 0, '  ', False, '', 0)
      else
        EmitWrapped('  ' + L, 0, '  ', False, '', 0);
    nxtline:
    end;
    FGemtextHL.SetLineKinds(FLineKind);
    GmiView.Highlighter := FGemtextHL;
  finally
    SL.Free;
  end;
end;

// a host without a scheme means gemini, like a browser assumes http
function TMainForm.NormalizeURL(const AURL: string): string;
var
  S: string;
begin
  S := Trim(AURL);
  if (S <> '') and (Pos('://', S) = 0) then
    S := 'gemini://' + S;
  Result := S;
end;

procedure TMainForm.Fetch(const AURL: string; APush: Boolean = True);
var
  R: TGeminiResponse;
  Input: string;
  U: string;
begin
  U := NormalizeURL(AURL);
  if U = '' then Exit;
  StatusBar.SimpleText := 'Connecting to ' + U + ' ...';
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

    R := FGemini.Request(U);
    try
      if (R.Status = IdGemini.gsInput) or (R.Status = IdGemini.gsSensitiveInput) then
      begin
        Input := '';
        if InputQuery('Input required', R.Meta, Input) then
        begin
          R.Free;
          R := FGemini.Request(U, Input);
        end;
      end;

      FCurrentURL := U;
      UrlEdit.Text := U;
      FLastRaw := StreamToUtf8(R.Content);
      FRefreshing := True;
      try
        GmiView.Lines.BeginUpdate;
        try
          GmiView.Lines.Text := '';
          Render(FLastRaw);
          if R.Status = IdGemini.gsCertRequired then
            AddCreateIdentityHint;
        finally
          GmiView.Lines.EndUpdate;
        end;
      finally
        FRefreshing := False;
      end;
      GmiView.Invalidate;
      GmiView.Refresh;
      FPageStatus := '';
      StatusBar.SimpleText := '';
      if APush then PushHistory(U);
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

procedure TMainForm.GmiCopy(Sender: TObject; var AText: string;
  var AMode: TSynSelectionMode; ALogStartPos: TPoint;
  var AnAction: TSynCopyPasteAction);
begin
  if GmiView.SelAvail then
  begin
    Clipboard.AsText := GmiView.SelText;
    // SynEdit clears the clipboard right after this handler returns
    AnAction := scaAbort;
  end;
end;

procedure TMainForm.EditMenuCopyClick(Sender: TObject);
begin
  if GmiView.SelAvail then
  begin
    try
      Clipboard.AsText := GmiView.SelText;
    except
    end;
  end;
end;

procedure TMainForm.EditMenuPopup(Sender: TObject);
begin
  FCopyItem.Enabled := GmiView.SelAvail;
  FOpenLinkItem.Enabled := FRightLink <> '';
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
  GutterWidth := 0;
  if GmiView.Gutter.Visible then
    GutterWidth := GmiView.Gutter.Width;

  // heliko-style underline under the hovered rocketlink label
  if (FLinkLine < 0) or (FLinkLine >= Length(FDocLinks)) or (FDocLinks[FLinkLine] = '') then
    Exit;
  if (FLinkLine < GmiView.TopLine - 1) or
     (FLinkLine >= GmiView.TopLine + GmiView.LinesInWindow) then
    Exit;

  LineY := (FLinkLine - GmiView.TopLine + 1) * GmiView.LineHeight;
  StartX := GutterWidth + (1 - GmiView.LeftChar) * GmiView.CharWidth;
  // measure the painted label: cell counting is wrong for double-width glyphs
  if (FLinkLine < Length(FDocLinkText)) and (FDocLinkText[FLinkLine] <> '') then
    EndX := StartX + ACanvas.TextWidth(FDocLinkText[FLinkLine])
  else
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

procedure TMainForm.GmiMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Pt: TPoint;
  Line: Integer;
begin
  if Button = mbLeft then
  begin
    FDownX := X;
    FDownY := Y;
  end;
  // remember the link under the cursor, the context menu is built in OnPopup
  // where the mouse position is not available anymore
  FRightLink := '';
  Pt := GmiView.PixelsToRowColumn(Point(X, Y));
  Line := Pt.Y - 1;
  if (Line >= 0) and (Line < Length(FDocLinks)) and
     (FDocLinks[Line] <> '') and (FDocLinks[Line] <> kNewIdentityCmd) then
    FRightLink := FDocLinks[Line];
end;

procedure TMainForm.OpenInNewWindow(const AURL: string);
var
  Proc: TProcess;
  Exe: string;
  Ident: Integer;
begin
  if Copy(AURL, 1, 7) = 'http://' then
  begin
    // a gemtext client cannot fetch it, let the desktop handle it
    OpenURL(AURL);
    Exit;
  end;
  Exe := ParamStr(0);
  if not FileExists(Exe) then
    Exe := Application.ExeName;
  Ident := IdentityBox.ItemIndex;
  // a second process, so the new window has its own history
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := Exe;
    if AURL <> '' then
      Proc.Parameters.Add(AURL);
    if Ident > 0 then
      Proc.Parameters.Add('--ident=' + IntToStr(Ident));
    Proc.Options := [poNoConsole, poDetached];
    Proc.Execute;
  finally
    Proc.Free;
  end;
end;

procedure TMainForm.OpenLinkInNewWindowClick(Sender: TObject);
begin
  OpenInNewWindow(FRightLink);
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
  // middle click and ctrl+click open a link in a new window, firefox style
  if (Button = mbMiddle) or ((Button = mbLeft) and (ssCtrl in Shift)) then
  begin
    Pt := GmiView.PixelsToRowColumn(Point(X, Y));
    Line := Pt.Y - 1;
    if (Line >= 0) and (Line < Length(FDocLinks)) and
       (FDocLinks[Line] <> '') and (FDocLinks[Line] <> kNewIdentityCmd) then
    begin
      OpenInNewWindow(FDocLinks[Line]);
      Exit;
    end;
    Exit;
  end;
  if Button <> mbLeft then Exit;
  // a drag is a text selection for copying; only a plain click opens a link
  if (Abs(X - FDownX) + Abs(Y - FDownY) > 5) or GmiView.SelAvail then Exit;
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
    else
      NewSize := Max(8, NewSize - 2);
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

{ TGemtextHighlighter }

constructor TGemtextHighlighter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBoldAttr := TSynHighlighterAttributes.Create('gemtext_bold');
  FBoldAttr.Style := [fsBold];
  AddAttribute(FBoldAttr);
  FPreAttr := TSynHighlighterAttributes.Create('gemtext_pre');
  FPreAttr.Background := $ECECEC;
  AddAttribute(FPreAttr);
  FNormalAttr := TSynHighlighterAttributes.Create('gemtext_normal');
  AddAttribute(FNormalAttr);
end;

function TGemtextHighlighter.GetIdentChars: TSynIdentChars;
begin
  Result := ['0'..'9', 'a'..'z', 'A'..'Z', '#', '_', '/', '-', '.', '~'];
end;

procedure TGemtextHighlighter.SetLine(const NewValue: String; LineNumber: Integer);
begin
  inherited SetLine(NewValue, LineNumber);
  FLine := NewValue;
  FLineLen := Length(NewValue);
  FTokenPos := 0;
  FCursor := 0;
  FEol := False;
  if (LineNumber >= 0) and (LineNumber < Length(FKinds)) then
    FCurKind := FKinds[LineNumber]
  else
    FCurKind := 0;
  Next;
end;

function TGemtextHighlighter.GetEol: Boolean;
begin
  Result := FEol;
end;

procedure TGemtextHighlighter.Next;
begin
  if FEol then Exit;
  FTokenPos := FCursor;
  if FCursor >= FLineLen then
    FEol := True
  else
    FCursor := FLineLen;
end;

function TGemtextHighlighter.GetToken: String;
begin
  if FEol then
    Result := ''
  else
    Result := Copy(FLine, FTokenPos + 1, FCursor - FTokenPos);
end;

procedure TGemtextHighlighter.GetTokenEx(out TokenStart: PChar; out TokenLength: Integer);
begin
  if FEol then
  begin
    TokenStart := PChar(FLine);
    TokenLength := 0;
  end
  else
  begin
    TokenStart := PChar(FLine) + FTokenPos;
    TokenLength := FCursor - FTokenPos;
  end;
end;

function TGemtextHighlighter.GetTokenAttribute: TSynHighlighterAttributes;
begin
  if FEol then
    Result := FNormalAttr
  else
    case FCurKind of
      1: Result := FBoldAttr; // links
      2: Result := FPreAttr;  // preformatted, keeps the indent
    else
      Result := FNormalAttr;
    end;
end;

function TGemtextHighlighter.GetTokenKind: Integer;
begin
  Result := FCurKind;
end;

function TGemtextHighlighter.GetTokenPos: Integer;
begin
  Result := FTokenPos;
end;

function TGemtextHighlighter.GetDefaultAttribute(Index: Integer): TSynHighlighterAttributes;
begin
  Result := FNormalAttr;
end;

function TGemtextHighlighter.GetRange: Pointer;
begin
  Result := nil;
end;

procedure TGemtextHighlighter.ResetRange;
begin
end;

procedure TGemtextHighlighter.SetRange(Value: Pointer);
begin
end;

procedure TGemtextHighlighter.SetLineKinds(const AKinds: array of SmallInt);
var
  I, N: Integer;
begin
  N := High(AKinds);
  if N < 0 then N := -1;
  SetLength(FKinds, N + 1);
  for I := 0 to N do
    FKinds[I] := AKinds[I];
end;

end.