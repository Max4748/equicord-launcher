; Installeur Equicord Launcher (Windows) — Inno Setup 6.
; Compilation : ISCC.exe equicord-launcher.iss (ou installer\windows\build.ps1).
; Prérequis : les binaires doivent exister dans ..\..\target\release\ (cargo build --release).

#define AppName "Equicord Launcher"
#define AppVersion "0.1.0"
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

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau (Discord Stable)"; GroupDescription: "Raccourcis :"
Name: "ptb";    Description: "Raccourci menu Démarrer pour Discord PTB";    GroupDescription: "Raccourcis :"; Flags: unchecked
Name: "canary"; Description: "Raccourci menu Démarrer pour Discord Canary"; GroupDescription: "Raccourcis :"; Flags: unchecked

[Icons]
Name: "{group}\Equicord (Discord)";        Filename: "{app}\equicord-stable.exe"; WorkingDir: "{app}"; IconFilename: "{localappdata}\Discord\app.ico"
Name: "{group}\Equicord (Discord PTB)";    Filename: "{app}\equicord-ptb.exe";    WorkingDir: "{app}"; Tasks: ptb
Name: "{group}\Equicord (Discord Canary)"; Filename: "{app}\equicord-canary.exe"; WorkingDir: "{app}"; Tasks: canary
Name: "{group}\Désinstaller Equicord Launcher"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Equicord (Discord)";  Filename: "{app}\equicord-stable.exe"; WorkingDir: "{app}"; IconFilename: "{localappdata}\Discord\app.ico"; Tasks: desktopicon

[Code]
var
  EquicordPage: TInputDirWizardPage;

procedure InitializeWizard;
begin
  EquicordPage := CreateInputDirPage(wpSelectTasks,
    'Build Equicord', 'Où se trouve ton build local d''Equicord ?',
    'Indique le dossier dist/desktop produit par « pnpm build » (ou la racine du repo Equicord).' + #13#10 +
    'Laisse vide pour configurer plus tard via --equicord ou le fichier config.toml.' + #13#10 +
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
