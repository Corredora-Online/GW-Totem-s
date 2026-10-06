param(
  [Parameter(Mandatory=$true)][string]$KioskAccount
)

$ErrorActionPreference = 'Stop'
$admin = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Ejecuta PowerShell como administrador.'
}
$account = New-Object System.Security.Principal.NTAccount($KioskAccount)
$sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
$shell = [wmiclass]'\\localhost\root\standardcimv2\embedded:WESL_UserSetting'
$result = $shell.RemoveCustomShell($sid)
if ($result.ReturnValue -ne 0) { throw 'No se pudo eliminar la asociación del kiosco.' }
Write-Host 'Asociación eliminada. Reinicia para recuperar Explorer en esa cuenta.'
