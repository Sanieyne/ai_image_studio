; Inno Setup script for the Windows GPU build.
; Built in CI: ISCC /DAppVersion=x.y.z /DSourceDir=<assembled bundle> ai_image_studio.iss
;
; The bundle is ~5 GB (CUDA torch), more than one setup .exe can hold, so the
; installer is split: AI_Image_Studio_Setup.exe + AI_Image_Studio_Setup-N.bin.
; They ship together in one zip and must stay in the same folder.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist\AI_Image_Studio"
#endif

#define AppName "Cosmic-Gen AI Studio"
#define AppExe "ai_image_studio.exe"

[Setup]
; Never change AppId: Windows uses it to find the existing install for upgrades/uninstall.
AppId={{71dc6bb7-9f72-4575-8d99-ffc5d48fb4d5}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Cosmic-Gen AI
AppPublisherURL=https://cosmic-gen.com
DefaultDirName={autopf}\Cosmic-Gen AI Studio
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Per-user install by default (no admin prompt); the user can still pick "all users".
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
SetupIconFile=..\..\flutter_app\windows\runner\resources\app_icon.ico
WizardStyle=modern
OutputDir=..\..\dist\installer
OutputBaseFilename=AI_Image_Studio_Setup
Compression=lzma2/fast
SolidCompression=no
LZMAUseSeparateProcess=yes
DiskSpanning=yes
DiskSliceSize=max
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Upgrades: clear the old engine so files dropped from a newer build don't linger
Type: filesandordirs; Name: "{app}\engine"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\engine"
