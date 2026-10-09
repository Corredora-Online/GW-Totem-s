# Gour-net Kiosk en Windows

## Instalar en el PC del local (sin programar)

1. Usa un PC con Windows 10/11 **x64**. No necesita Flutter ni Visual Studio para ejecutar la app.
2. Instala el [Microsoft Visual C++ Redistributable x64 oficial](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist). Es una dependencia del programa, distinta de Visual Studio; debe estar presente antes de abrir la app.
3. Abre [Releases de GW-Totem-s](https://github.com/Corredora-Online/GW-Totem-s/releases) y descarga **gournet-kiosk-windows-x64-setup.exe**, no los enlaces automáticos Source code.
4. Ejecuta el Setup desde la cuenta Windows que usará el kiosko. Se instala en `%LOCALAPPDATA%\Programs\GournetKiosk` y crea accesos directos. No requiere copiar DLL a mano.
5. Abre Gour-net Kiosk, comparte el código con soporte, selecciona la sucursal y configura POS/impresora según la sección siguiente.

Las siguientes versiones se reciben mediante Releases, conservando los datos del perfil. Consulta [actualizaciones y firma](updates.md). El instalador Windows aún no lleva firma Authenticode; no desactives protecciones si una política corporativa bloquea su ejecución: solicita a soporte su validación.

Si la versión 1.0.1 muestra `CERTIFICATE_VERIFY_FAILED` al buscar una
actualización, descarga el Setup de la versión siguiente desde Edge e instálalo
manualmente en la misma cuenta Windows, con la app cerrada. Esa versión consulta
las Releases mediante WinHTTP, que usa los certificados y el proxy de Windows.
Si Windows también rechaza el certificado, comprueba fecha y hora, actualiza los
certificados raíz mediante Windows Update y pide al administrador de la red que
revise el proxy o antivirus HTTPS. No desactives la validación de certificados.

## Estado y requisitos

El mismo proyecto Flutter ya incluye runner Windows, activación por código,
catálogo/cache local, checkout/API y auditoría. Esta adaptación agrega transporte
Getnet IM30 por puerto COM, impresión térmica ESC/POS por la cola RAW de Windows,
video de espera y pantalla completa. La compilación nativa Windows y el Setup
se verifican en GitHub Actions. El POS, la impresión y el reemplazo automático
**aún deben probarse en un PC Windows real**; macOS no compila el `.exe` localmente.

Para desarrollar/compilar manualmente se necesita Windows 10/11 de 64 bits, Flutter con soporte desktop Windows y
Visual Studio con la carga **Desktop development with C++**. Comprueba
`flutter doctor -v` en Windows. Para reproducción del MP4, Windows debe contar
con el códec requerido por Media Foundation. Para pagos, Getnet/PAX debe instalar
el controlador que haga visible el IM30 como un puerto COM. Una impresora térmica
compatible con ESC/POS debe estar instalada con un nombre estable.

## Compilar y distribuir

En PowerShell, desde la raíz del proyecto:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\build-release.ps1
```

El script resuelve dependencias, analiza el código, ejecuta pruebas, compila y
genera `build\windows\distribution\gournet-kiosk-windows-x64.zip`. Hay que
copiar **todo** el contenido del ZIP a un directorio fijo del equipo (por
ejemplo `C:\GournetKiosk`), no sólo el `.exe`. Ejecuta
`C:\GournetKiosk\gournet_kiosk.exe` con el usuario final. No copies el perfil
de datos de una instalación a otro tótem: cada instalación Windows genera IDs
propios y protege la API Key con el almacenamiento seguro del usuario.

Para desarrollo rápido, `flutter run -d windows` desde el PC Windows.

## Activar y conectar hardware

1. Crea primero una cuenta Windows **estándar** para el kiosco e inicia sesión
   con ella. En esa cuenta, abre la app nueva, comparte el código temporal de
   activación con soporte y selecciona la sucursal. La activación y su API Key
   pertenecen a ese perfil, no a la cuenta administradora. Antes de activar,
   la app no activa pantalla completa.
2. Conecta el IM30 por USB al PC. En **Administrador de dispositivos → Puertos
   (COM y LPT)** confirma que aparece como COM. Si no aparece, instala el driver
   entregado por Getnet/PAX y verifica que el terminal esté en modo **POS
   integrado activo**. La app intenta detectar automáticamente el USB PAX
   `VID_2FB8&PID_225E`; si no lo encuentra, ingresa `COM5` (o el puerto real)
   en **Configuración → Operación → Puerto COM del Getnet IM30**.
3. Instala la impresora térmica en **Impresoras y escáneres**. En
   **Configuración → Operación**, elígela de **Impresoras instaladas en Windows**,
   pulsa **Imprimir prueba** y luego **Guardar**. Si no aparece, usa el botón de
   actualizar o escribe su nombre exacto. La app no envía comprobantes a la impresora predeterminada para
   evitar imprimirlos accidentalmente en una impresora de oficina. El driver
   debe aceptar trabajos **RAW ESC/POS**; la app usa codepage 850 y corte.
4. Haz una venta de prueba. Comprueba en el POS el mismo número/monto que en el
   kiosco, verifica el comprobante físico, el pedido enviado a Gour-net y el
   registro local de conciliación. Si el POS recibió la venta pero se perdió
   la respuesta, **no repitas el cobro**: la app conserva el estado incierto.

Puedes listar los puertos y nombres de impresora sin iniciar una venta con
`powershell -ExecutionPolicy Bypass -File .\scripts\windows\check-hardware.ps1`.

El puerto serial se configura a 115200, 8N1, DTR/RTS. Venta y cancelación usan
los comandos Getnet `100`/`116` firmados con SHA-256. La cancelación va por la
misma sesión COM mientras la venta sigue activa. Es necesario certificar esta
implementación Windows y el conjunto PC/driver/IM30 con Getnet antes de uso
productivo; la prueba anterior en SUNMI/Android no equivale a esa certificación.

## Bloqueo de Windows

Si aparece una pantalla negra que dice «No hay imágenes en Descargas», es el
protector de pantalla **Fotos de Windows**, no la pantalla de reposo de Gour-net.
En la cuenta del kiosco selecciona **Protector de pantalla → Ninguno**. La app
también bloquea la activación de ese protector mientras el kiosco está activo
y mantiene encendida la pantalla para mostrar su video de espera.

La app se pone a pantalla completa después de la activación, pero **una ventana
fullscreen no bloquea Windows**. Para un tótem público se recomienda una cuenta
local estándar separada y **Shell Launcher** en Windows Enterprise, Education o
IoT Enterprise. Windows Pro no lo ofrece. Sólo después de activar y probar la
app con hardware, desde otra cuenta administradora:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\enable-shell-launcher.ps1 `
  -KioskAccount '.\Kiosco' `
  -ExecutablePath 'C:\GournetKiosk\gournet_kiosk.exe'
```

Reinicia e inicia sesión como `Kiosco`. Shell Launcher inicia la app en vez de
Explorer y la relanza ante cierre normal; la salida desde Configuración + PIN
usa el código de salida `42` para permitir mantenimiento sin relanzarla.
Otras cuentas conservan Explorer. Para retirar esta configuración, desde la
cuenta administradora ejecuta `disable-shell-launcher.ps1 -KioskAccount
'.\Kiosco'` y reinicia.

Shell Launcher no elimina la pantalla segura Ctrl+Alt+Supr ni sustituye
políticas de seguridad de Windows. Aplica restricciones de cuenta, bloqueo de
ajustes, actualizaciones y acceso físico según tu despliegue. No ejecutes la
cuenta pública con privilegios de administrador.

## Datos y actualizaciones

Para instalaciones mediante Setup usa el actualizador de [GitHub Releases](updates.md). Las instrucciones de reemplazo manual siguientes sólo corresponden al paquete portátil.

La API Key y PIN se guardan con `flutter_secure_storage`; catálogo, imágenes,
pedidos pendientes y auditoría se guardan en el directorio de soporte de la
aplicación del perfil Windows. Al actualizar, reemplaza el **paquete completo**
en el directorio de programa con la app cerrada, sin borrar el perfil de datos.
El restablecimiento de fábrica desde Configuración borra esos datos y vuelve a
la activación. No se debe publicar un ZIP con la API Key dentro.

Referencias: [Flutter para Windows](https://docs.flutter.dev/platform-integration/windows/building),
[canales de plataforma](https://docs.flutter.dev/platform-integration/platform-channels),
[Shell Launcher de Microsoft](https://learn.microsoft.com/en-us/windows/configuration/shell-launcher/configure),
[video Windows](https://pub.dev/packages/video_player_win).
