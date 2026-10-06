$ErrorActionPreference = 'Stop'

Write-Host 'Puertos COM detectados:'
Get-CimInstance Win32_PnPEntity |
  Where-Object { $_.Name -match '\(COM[0-9]+\)' } |
  Select-Object Name, PNPDeviceID |
  Format-Table -AutoSize

Write-Host 'Dispositivos PAX IM30 conocidos (VID_2FB8 / PID_225E):'
Get-CimInstance Win32_PnPEntity |
  Where-Object { $_.PNPDeviceID -match 'VID_2FB8&PID_225E' } |
  Select-Object Name, PNPDeviceID |
  Format-Table -AutoSize

Write-Host 'Impresoras instaladas (usa el valor exacto de Name en Configuración):'
Get-Printer | Select-Object Name, DriverName, PrinterStatus |
  Format-Table -AutoSize
