; ============================================================
;  DTR Automator - Inno Setup Script
;  CS Form 48 Generator by DEVLOURENCE
; ============================================================

#define AppName      "DTR Automator"
#define AppVersion   "1.0.0"
#define AppPublisher "DEVLOURENCE"
#define AppExeName   "dtr_form48.exe"
#define AppURL       ""
#define BuildDir     "..\build\windows\x64\runner\Release"
#define AppIcon      "..\windows\runner\resources\app_icon.ico"

[Setup]
AppId={{F3A1C2D4-8E5B-4F7A-9C3D-1B2E6F4A8D90}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
AppMutex={#AppName}
SetupIconFile={#AppIcon}
DefaultDirName={userappdata}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
; Output installer file settings
OutputDir=..\installer\output
OutputBaseFilename=DTR_Automator_Setup_v{#AppVersion}
; Compression
Compression=lzma2/ultra64
SolidCompression=yes
; Visual
WizardStyle=modern
; Automatically close the app if it's running
CloseApplications=yes
CloseApplicationsFilter=*.exe
; Allow installation without admin rights (installs to User AppData)
PrivilegesRequired=lowest
; Minimum Windows version (Windows 10)
MinVersion=10.0
; Architecture
ArchitecturesInstallIn64BitMode=x64
; Uninstall
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";    Description: "{cm:CreateDesktopIcon}";    GroupDescription: "{cm:AdditionalIcons}"
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1

[Files]
; Main executable
Source: "{#BuildDir}\{#AppExeName}";                DestDir: "{app}"; Flags: ignoreversion

; Flutter runtime DLLs
Source: "{#BuildDir}\flutter_windows.dll";          DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\dartjni.dll";                  DestDir: "{app}"; Flags: ignoreversion

; SQLite
Source: "{#BuildDir}\sqlite3.dll";                  DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\sqlite3_flutter_libs_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion

; PDF / Printing
Source: "{#BuildDir}\pdfium.dll";                   DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\printing_plugin.dll";          DestDir: "{app}"; Flags: ignoreversion

; App data directory (fonts, assets, etc.)
Source: "{#BuildDir}\data\*";                       DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start Menu
Name: "{group}\{#AppName}";              Filename: "{app}\{#AppExeName}"; Comment: "CS Form 48 DTR Generator"
Name: "{group}\Uninstall {#AppName}";    Filename: "{uninstallexe}"

; Desktop shortcut (optional, based on task selection)
Name: "{autodesktop}\{#AppName}";        Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

; Quick Launch (Windows XP/Vista)
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: quicklaunchicon

[Run]
; Launch the app after installation (optional)
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clean up the user data directory on uninstall (optional - comment out to preserve data)
; Type: filesandordirs; Name: "{localappdata}\{#AppPublisher}\{#AppName}"

[Code]
// Optional: Check for existing installation and warn user
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
