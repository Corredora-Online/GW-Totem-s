param(
  [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $project

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Instala Flutter en Windows y agrega flutter\bin al PATH.'
}

flutter doctor -v
if ($LASTEXITCODE -ne 0) { throw 'flutter doctor informó un error.' }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron resolver las dependencias.' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'El análisis de Dart falló.' }
if (-not $SkipTests) {
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Las pruebas de Flutter fallaron.' }
}
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar para Windows.' }

$bundle = Join-Path $project 'build\windows\x64\runner\Release'
$executable = Join-Path $bundle 'gournet_kiosk.exe'
if (-not (Test-Path $executable)) { throw "No se encontró $executable" }
$distribution = Join-Path $project 'build\windows\distribution'
New-Item -ItemType Directory -Path $distribution -Force | Out-Null
$zip = Join-Path $distribution 'gournet-kiosk-windows-x64.zip'
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip -Force
Write-Host "Versión Windows lista: $zip"
Write-Host 'Distribuye el ZIP completo, no sólo el archivo .exe.'
