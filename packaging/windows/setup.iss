#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
[Setup]
AppId={{A54B6F9B-8A7A-4888-AF29-D011BB809315}
AppName=Gour-net Kiosk
AppVersion={#AppVersion}
AppPublisher=Gour-net
DefaultDirName={localappdata}\Programs\GournetKiosk
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=gournet-kiosk-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
CloseApplications=no
RestartApplications=no
UninstallDisplayIcon={app}\gournet_kiosk.exe

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "gournet-managed-install.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Gour-net Kiosk"; Filename: "{app}\gournet_kiosk.exe"
Name: "{autodesktop}\Gour-net Kiosk"; Filename: "{app}\gournet_kiosk.exe"

[Run]
Filename: "{app}\gournet_kiosk.exe"; WorkingDir: "{app}"; Flags: nowait

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var Attempt: Integer;
begin
  Result := '';
  { The updater closes the app after starting Setup. Never terminate a sale. }
  for Attempt := 1 to 60 do begin
    if not CheckForMutexes('Local\GournetKiosk') then Exit;
    Sleep(500);
  end;
  Result := 'Cierra Gour-net Kiosk desde Configuración antes de instalar. No se interrumpirá un pago.';
end;
