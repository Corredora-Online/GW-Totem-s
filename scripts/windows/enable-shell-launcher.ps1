param(
  [Parameter(Mandatory=$true)][string]$KioskAccount,
  [Parameter(Mandatory=$true)][string]$ExecutablePath
)

$ErrorActionPreference = 'Stop'
$admin = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Ejecuta PowerShell como administrador.'
}
if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
  throw 'No se encontró el ejecutable del kiosco.'
}
if ([System.IO.Path]::GetFileName($ExecutablePath) -ne 'gournet_kiosk.exe') {
  throw 'Selecciona gournet_kiosk.exe del paquete Windows.'
}

$edition = (Get-CimInstance Win32_OperatingSystem).Caption
if ($edition -notmatch 'Enterprise|Education|IoT') {
  throw "Shell Launcher no está disponible en esta edición: $edition"
}

$feature = Get-WindowsOptionalFeature -Online -FeatureName Client-EmbeddedShellLauncher
if ($feature.State -ne 'Enabled') {
  Enable-WindowsOptionalFeature -Online -FeatureName Client-DeviceLockdown,Client-EmbeddedShellLauncher -NoRestart | Out-Null
  throw 'Se habilitó Shell Launcher. Reinicia Windows y vuelve a ejecutar este script.'
}

$account = New-Object System.Security.Principal.NTAccount($KioskAccount)
$sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
if ($sid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
  throw 'No configures la cuenta administradora actual como cuenta pública del kiosco.'
}
$shell = [wmiclass]'\\localhost\root\standardcimv2\embedded:WESL_UserSetting'
$fullPath = (Resolve-Path -LiteralPath $ExecutablePath).Path
$quotedPath = '"' + $fullPath + '"'

# Las demás cuentas conservan Explorer. Fallos/salidas normales reinician
# el kiosco; la salida administrativa de la app usa el código 42 y no reinicia.
$defaultResult = $shell.SetDefaultShell('explorer.exe', 3)
if ($defaultResult.ReturnValue -ne 0) { throw 'No se pudo conservar Explorer para otras cuentas.' }
$customResult = $shell.SetCustomShell($sid, $quotedPath, [int[]]@(42), [int[]]@(3), 0)
if ($customResult.ReturnValue -ne 0) { throw 'No se pudo configurar la cuenta del kiosco.' }
$enabledResult = $shell.SetEnabled($true)
if ($enabledResult.ReturnValue -ne 0) { throw 'No se pudo activar Shell Launcher.' }

Write-Host "Shell Launcher configurado para $KioskAccount. Reinicia e inicia sesión con esa cuenta."
Write-Host 'No uses una cuenta administradora como cuenta pública del kiosco.'
