; Inno Setup script for the Windows installer (spec D8).
;
;   iscc /DSrcDir=<dist folder> /DAppVersion=<version> /O<out dir> chesswiz.iss
;
; RootDir is the source tree (COPYING, icons/). SrcDir is the folder made by scripts/make-windows-dist.sh. Installs per
; user without admin rights by default; the user may choose all users.

#ifndef SrcDir
  #define SrcDir "..\build\dist\Chesswiz"
#endif
#ifndef RootDir
  #define RootDir ".."
#endif
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6B0C5E3A-4F1D-4C8E-9B57-2C1A7E0D9F42}
AppName=Chesswiz
AppVersion={#AppVersion}
AppPublisher=Chesswiz
DefaultDirName={autopf}\Chesswiz
DefaultGroupName=Chesswiz
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile={#RootDir}\COPYING
SetupIconFile={#RootDir}\icons\chesswiz.ico
UninstallDisplayIcon={app}\tkchesswiz.exe
OutputBaseFilename=Chesswiz-{#AppVersion}-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: desktopicon; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

; Remove previously bundled executables on upgrade so startup can migrate commands.
[InstallDelete]
Type: files; Name: "{app}\engines\stockfish-scidb.exe"
Type: files; Name: "{app}\engines\reckless-scidb.exe"
Type: files; Name: "{app}\engines\sjeng-scidb.exe"

[Icons]
Name: "{autoprograms}\Chesswiz"; Filename: "{app}\tkchesswiz.exe"
Name: "{autodesktop}\Chesswiz"; Filename: "{app}\tkchesswiz.exe"; Tasks: desktopicon

[Registry]
; Open PGN files with Chesswiz; per user, or for all users when installed so.
Root: HKA; Subkey: "Software\Classes\.pgn\OpenWithProgids"; ValueType: string; ValueName: "Chesswiz.pgn"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Chesswiz.pgn"; ValueType: string; ValueData: "PGN chess database"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Chesswiz.pgn\DefaultIcon"; ValueType: string; ValueData: "{app}\tkchesswiz.exe,0"
Root: HKA; Subkey: "Software\Classes\Chesswiz.pgn\shell\open\command"; ValueType: string; ValueData: """{app}\tkchesswiz.exe"" ""%1"""

[Run]
Filename: "{app}\tkchesswiz.exe"; Description: "{cm:LaunchProgram,Chesswiz}"; Flags: nowait postinstall skipifsilent
