# SUNMI K2 — perfil del equipo

Fecha de consulta: 2026-08-30 (America/Santiago).

## Estado de detección

ADB está instalado en:

```text
/Users/joaquin/Library/Android/sdk/platform-tools/adb
Android Debug Bridge 1.0.41 / 37.0.0-14910828
```

El equipo fue conectado, autorizado e identificado correctamente por ADB. Gour-net Kiosk fue instalado y abierto satisfactoriamente.

Salida observada:

```text
List of devices attached
K217P14300025 device usb:2-1.2 product:K2 model:K2 device:K2
```

## Consulta reproducible

Con el SUNMI encendido, el cable USB de datos conectado y la depuración USB autorizada en pantalla, ejecutar:

```bash
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
"$ADB" devices -l
"$ADB" shell getprop ro.product.model
"$ADB" shell getprop ro.build.version.release
"$ADB" shell getprop ro.build.version.sdk
"$ADB" shell wm size
"$ADB" shell wm density
```

## Datos reales

| Campo | Valor real |
| --- | --- |
| Serial ADB | K217P14300025 |
| Modelo | K2 |
| Android | 7.1.2 |
| API level | 25 |
| Resolución física | 1080 × 1920 |
| Densidad | 192 dpi |

## Aplicación instalada

```text
Package: cl.gournet.kiosk
Activity: cl.gournet.kiosk/.MainActivity
Resultado ADB: Success
Proceso verificado: activo
```

## Solución rápida si no aparece

1. Usar un cable USB que transporte datos, no sólo carga.
2. Activar Opciones de desarrollador y Depuración USB en el SUNMI.
3. Aceptar la huella RSA del Mac en la pantalla del kiosco.
4. Ejecutar `adb kill-server` y luego `adb start-server`.
5. Confirmar que `adb devices -l` muestre estado `device`, no `unauthorized`.
