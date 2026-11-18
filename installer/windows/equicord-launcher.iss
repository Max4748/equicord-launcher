; Installeur Equicord Launcher (Windows) — Inno Setup 6.
; Compilation : ISCC.exe equicord-launcher.iss (ou installer\windows\build.ps1).
; Prérequis : les binaires doivent exister dans ..\..\target\release\ (cargo build --release).

#define AppName "Equicord Launcher"
#define AppVersion "0.2.0"
#define RelDir "..\..\target\release"

[Setup]
AppId={{7F3C1B94-6D2E-4A51-9C8B-EQUICORDLNCH}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=equicord-launcher
DefaultDirName={autopf}\Equicord Launcher
DefaultGroupName=Equicord Launcher
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=output
OutputBaseFilename=equicord-launcher-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\equicord-stable.exe

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "{#RelDir}\equicord-stable.exe";    DestDir: "{app}"; Flags: ignoreversion
Source: "{#RelDir}\equicord-ptb.exe";       DestDir: "{app}"; Flags: ignoreversion
Source: "{#RelDir}\equicord-canary.exe";    DestDir: "{app}"; Flags: ignoreversion
Source: "{#RelDir}\equicord_launcher.dll";  DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\README.md";                  DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\config.example.toml";        DestDir: "{app}"; Flags: ignoreversion

; Une case par Discord installé (Stable/PTB/Canary). Si aucun n'est détecté, les
; trois sont proposées (non cochées).
[Tasks]
Name: "stable"; Description: "Discord Stable"; GroupDescription: "Discord à équiper d'Equicord :"; Check: ShowBranch('Discord')
Name: "ptb";    Description: "Discord PTB";    GroupDescription: "Discord à équiper d'Equicord :"; Check: ShowBranch('DiscordPTB')
Name: "canary"; Description: "Discord Canary"; GroupDescription: "Discord à équiper d'Equicord :"; Check: ShowBranch('DiscordCanary')
Name: "desktopicon"; Description: "Ajouter aussi les raccourcis sur le Bureau"; GroupDescription: "Raccourcis :"

[Icons]
Name: "{group}\Equicord (Discord)";        Filename: "{app}\equicord-stable.exe"; WorkingDir: "{app}"; IconFilename: "{code:BranchIcon|Discord}";       Tasks: stable
Name: "{group}\Equicord (Discord PTB)";    Filename: "{app}\equicord-ptb.exe";    WorkingDir: "{app}"; IconFilename: "{code:BranchIcon|DiscordPTB}";    Tasks: ptb
Name: "{group}\Equicord (Discord Canary)"; Filename: "{app}\equicord-canary.exe"; WorkingDir: "{app}"; IconFilename: "{code:BranchIcon|DiscordCanary}"; Tasks: canary
Name: "{group}\Désinstaller Equicord Launcher"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Equicord (Discord)";        Filename: "{app}\equicord-stable.exe"; WorkingDir: "{app}"; IconFilename: "{code:BranchIcon|Discord}";       Tasks: stable and desktopicon
Name: "{autodesktop}\Equicord (Discord PTB)";    Filename: "{app}\equicord-ptb.exe";    WorkingDir: "{app}"; IconFilename: "{code:BranchIcon|DiscordPTB}";    Tasks: ptb and desktopicon
Name: "{autodesktop}\Equicord (Discord Canary)"; Filename: "{app}\equicord-canary.exe"; WorkingDir: "{app}"; IconFilename: "{code:BranchIcon|DiscordCanary}"; Tasks: canary and desktopicon

; Build officielle téléchargée par le launcher (la config utilisateur est conservée).
[UninstallDelete]
Type: files; Name: "{userappdata}\equicord-launcher\equicord.asar"
Type: files; Name: "{userappdata}\equicord-launcher\equicord.asar.version"
Type: files; Name: "{userappdata}\equicord-launcher\equicord.asar.tmp"

[Code]
var
  EquicordPage: TInputDirWizardPage;
  TasksInitialized: Boolean;

{ Discord installé = %LOCALAPPDATA%\<Dir>\Update.exe présent (comme src/discord.rs). }
function BranchInstalled(Dir: string): Boolean;
begin
  Result := FileExists(ExpandConstant('{localappdata}\') + Dir + '\Update.exe');
end;

function AnyBranchInstalled(): Boolean;
begin
  Result := BranchInstalled('Discord') or BranchInstalled('DiscordPTB') or BranchInstalled('DiscordCanary');
end;

function ShowBranch(Dir: string): Boolean;
begin
  Result := BranchInstalled(Dir) or not AnyBranchInstalled();
end;

{ Icône de la branche si Discord est là ; sinon '' = icône de l'exécutable. }
function BranchIcon(Dir: string): string;
begin
  Result := ExpandConstant('{localappdata}\') + Dir + '\app.ico';
  if not FileExists(Result) then
    Result := '';
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  { Aucun Discord détecté : les trois branches sont proposées, mais décochées. }
  if (CurPageID = wpSelectTasks) and not TasksInitialized then
  begin
    TasksInitialized := True;
    if not AnyBranchInstalled() then
      WizardSelectTasks('!stable,!ptb,!canary');
  end;
end;

procedure InitializeWizard;
begin
  EquicordPage := CreateInputDirPage(wpSelectTasks,
    'Build Equicord (optionnel)', 'Utiliser un build local d''Equicord ?',
    'Laisse vide (recommandé) : la build officielle d''Equicord est téléchargée au premier' + #13#10 +
    'lancement et mise à jour automatiquement.' + #13#10 +
    'Sinon, indique le dossier dist/desktop de ton build (« pnpm build »).' + #13#10 +
    'Un config.toml existant ne sera pas écrasé.',
    False, '');
  EquicordPage.Add('');
end;

function EquicordDist(): string;
begin
  Result := Trim(EquicordPage.Values[0]);
end;

procedure WriteConfig();
var
  Dir, Path, Content, Escaped: string;
begin
  if EquicordDist() = '' then
    exit;
  Dir := ExpandConstant('{userappdata}\equicord-launcher');
  Path := Dir + '\config.toml';
  if FileExists(Path) then
    exit;  { on ne clobbe pas une config existante }
  ForceDirectories(Dir);
  Escaped := EquicordDist();
  StringChangeEx(Escaped, '\', '\\', True);  { échappement TOML }
  Content :=
    '# Généré par l''installeur Equicord Launcher.' + #13#10 +
    'equicord_dist = "' + Escaped + '"' + #13#10 +
    'branch = "stable"' + #13#10;
  SaveStringToFile(Path, Content, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    WriteConfig();
end;
