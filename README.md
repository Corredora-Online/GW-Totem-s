# Gour-net Kiosk

Código de **GW-Totem-s**: Android/SUNMI y Windows. Para editar desde GitHub y distribuir nuevas versiones, sigue [la guía de Releases y actualizaciones remotas](docs/updates.md). Las API keys y claves de firma no deben guardarse en este repositorio.

Versión local-first de la aplicación de autoatención Gour-net. Es Flutter nativo, no usa WebView y comparte dominio y UI entre Android y Windows. Para compilación, hardware y bloqueo Windows, consulta [docs/windows.md](docs/windows.md).

La aplicación sincroniza productos con la API de catálogo Gour-net y conserva localmente la última respuesta válida y sus imágenes. Por eso puede seguir vendiendo temporalmente sin Internet después de una sincronización exitosa; además mantiene un catálogo empacado como respaldo de primera instalación. En el SUNMI K2, el comprobante ficticio se envía directamente por USB ESC/POS a la impresora térmica integrada.

Después de un pago aprobado, el pedido se guarda en una cola local persistente y se envía a la API de Venta Directa. La sucursal configurada se informa mediante `tus`; comer aquí se informa como `mesa`, para llevar como `retiro` y, mientras Getnet siga simulado, el pago se informa como `pagado` mediante `app`. Si la red o la API fallan, el mismo payload se reintenta cada minuto con una clave idempotente estable.

## Flujo implementado

```text
video de espera / tocar pantalla → comer aquí / para llevar → catálogo → producto/modificadores
→ carrito → Getnet (o simulador) → DTE mock / impresión nativa → pedido incremental
→ cuenta regresiva de 15 s → video de espera
```

El catálogo presenta las categorías como tarjetas en una sola columna izquierda con scroll vertical independiente: icono arriba, nombre abajo y fondo rosado para la selección activa. Incluye una pestaña de Promociones y mantiene ocho productos visibles por pantalla (2 × 4 en vertical, 4 × 2 en horizontal), con fotografía arriba e información abajo. El carrito permanece en el encabezado y una franja fija inferior ofrece accesos a Ver carrito y Pagar sin impedir que el usuario siga navegando. También incluye búsqueda, edición de líneas, variantes separadas en el carrito, timeout de inactividad (60 + 15 segundos) y estados simulables de Internet, pago, impresora y DTE.

En reposo, `assets/videos/standby.mp4` se reproduce automáticamente en loop y sin sonido. Toda la pantalla funciona como llamada táctil para comenzar; al cancelar por inactividad o finalizar un pedido, la app vuelve a esta pantalla.

## Arquitectura

```text
features / widgets
        ↓
Riverpod state
        ↓
domain contracts
        ↓
API Gour-net + caché local / proveedores mock
```

- `lib/domain`: modelos y contratos sin imports Android.
- `lib/data/remote`: catálogo Gour-net, validación de respuesta, ETag y caché local.
- `lib/data/mock`: respaldo empacado y proveedores de pago, DTE e impresora para esta etapa.
- `lib/services`: abstracciones de hardware (`PaymentGateway`, `PrinterService`, `ScannerService`, `NfcService`, `SpeakerService`, `DteService`).
- `lib/state`: catálogo, carrito, sesión, checkout y configuración del equipo.
- `lib/features`: pantallas del flujo.
- `lib/core/theme`: colores, radios y espaciado centralizados.
- `assets/data/catalog.json`: catálogo de respaldo para la primera ejecución offline.
- `assets/images/products`: imágenes de respaldo del Restaurant Demo.

Implementaciones actuales:

```text
GournetCatalogRepository → API + ETag → caché JSON → CatalogRepository
PaymentGateway        → Getnet USB Android / COM Windows / simulador
SunmiPrinterService   → canal Flutter hacia USB ESC/POS SUNMI / cola RAW Windows
MockPrinterService    → tests y simulación de falta de papel
MockDteService        → GourLectura Android / Windows
```

## Requisitos

- Flutter estable con Dart compatible con `pubspec.yaml`.
- Android Studio + Android SDK para Android.
- Windows 10/11 con Visual Studio Desktop C++ para compilar el target Windows.

Verificar el entorno:

```bash
flutter doctor -v
flutter devices
```

## Ejecutar

```bash
flutter pub get
flutter run
```

Para seleccionar explícitamente el SUNMI:

```bash
adb devices -l
flutter devices
flutter run -d <device-id>
```

El package Android es `cl.gournet.kiosk` y el mínimo soportado por esta app es API 24.

## Compilar e instalar APK

APK debug para validación:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

APK release (usa firma debug sólo en esta etapa):

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Detectar y documentar el SUNMI

```bash
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
"$ADB" devices -l
"$ADB" shell getprop ro.product.model
"$ADB" shell getprop ro.build.version.release
"$ADB" shell getprop ro.build.version.sdk
"$ADB" shell wm size
"$ADB" shell wm density
```

El resultado real se registra en [docs/hardware/sunmi-k2.md](docs/hardware/sunmi-k2.md). El SUNMI K2 fue detectado con Android 7.1.2/API 25, resolución 1080 × 1920 y densidad 192 dpi; el APK release fue instalado y abierto por ADB.

## Catálogo dinámico Gour-net

La app consulta `GET https://atm.novelty8.com/webhook/api/gournet/v1/catalogo/` con el header `apiKey`. La clave temporal está centralizada en `lib/core/config/gournet_api_config.dart` y no se replica en documentación ni fixtures; debe reemplazarse por almacenamiento seguro cuando se implemente la configuración del equipo.

La sincronización comienza al abrir la app y se repite cada 5 minutos, incluso mientras se reproduce el video de espera. Se usa `ETag / If-None-Match`: una respuesta `304` conserva la copia existente sin reescribirla. Ante errores de red o servidor se usa el último catálogo JSON guardado junto con sus imágenes descargadas. Si el equipo nunca logró sincronizar, se recurre a `assets/data/catalog.json`.

Los precios de la API se convierten a enteros CLP; `8990` se muestra como `$8.990`. Los productos con precio igual o menor que cero no se publican en el kiosco. Categorías, nombres, descripciones, precios, disponibilidad, stock, etiquetas, orden e imágenes provienen dinámicamente de la respuesta.

Dos productos iguales con modificadores distintos se conservan como líneas separadas. Los grupos soportan selección mínima/máxima y ajustes de precio enteros.

## Panel DEV

Mantener presionado durante 5 segundos el isotipo `G` de Gour-net. El panel permite alternar:

- Standalone / Integrated.
- Online / Offline.
- Payment Approved / Declined.
- Printer Ready / No paper.
- DTE Success / Error.
- Reset completo de la app.

En modo `Integrated + Offline` se bloquea el paso al catálogo con el mensaje de indisponibilidad. En `Standalone + Offline` el flujo continúa normalmente.

La opción `Printer Ready` usa la impresora integrada del SUNMI. `No paper` fuerza el error simulado para comprobar la recuperación del flujo sin gastar papel.

## Boleta ficticia SUNMI

Al completar un pago aprobado, Android detecta la impresora `ICOD_Thermal_Printer` del K2 (VID `0483`, PID `7540`) y envía el comprobante directamente a su endpoint USB usando comandos ESC/POS. Esto evita el estado `OFFLINE` incorrecto que devuelve el antiguo servicio SUNMI instalado en este equipo. Para otros modelos, la app conserva el servicio SUNMI como alternativa y sólo lo utiliza cuando reporta estado listo.

El comprobante contiene pedido, tipo de consumo, fecha, productos, total y transacción Getnet simulada. Está marcado expresamente como ficticio y no válido como documento tributario.

La primera instalación puede mostrar una autorización de acceso a la impresora USB. Debe aceptarse una sola vez.

### Prueba física rápida

El build debug incluye una actividad de diagnóstico que imprime una tira corta directamente por USB:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n cl.gournet.kiosk/.PrinterHardwareTestActivity
```

Una transferencia correcta muestra `IMPRESION USB ENVIADA` y la cantidad exacta de bytes enviados. La prueba realizada en el K2 transfirió `107/107` bytes; el flujo completo de la app transfirió `639/639` bytes para la boleta ficticia.

## Inactividad

En catálogo, detalle y carrito, 60 segundos sin interacción muestran “¿Sigues ahí?” con una cuenta regresiva de 15 segundos. El cliente puede continuar o borrar el pedido inmediatamente; si no responde, se vacían carrito, modificadores y sesión y se vuelve automáticamente al video de espera. El timer está desactivado durante pago, procesamiento y éxito.

## Tests

```bash
flutter analyze
flutter test
```

La suite cubre dinero CLP, alta/baja/cantidad/total/modificadores del carrito, reset de sesión, render responsive, mapeo del catálogo Gour-net, almacenamiento local y respuestas `304`.

## Windows

El target `windows/` incluye canales nativos para Getnet COM, impresora térmica y pantalla completa. La compilación debe ejecutarse desde Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\build-release.ps1
```

Consulta [docs/windows.md](docs/windows.md) antes de conectar el IM30 o activar Shell Launcher. Falta validar y certificar el binario con hardware Windows real.

## Fuera de alcance

No se implementan todavía CAF/SII, GourLectura, scanner, NFC, WebSocket, administración remota ni auto-update. El DTE continúa simulado.
