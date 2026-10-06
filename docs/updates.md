# Actualizaciones remotas por GitHub Releases

Repositorio autorizado: **Corredora-Online/GW-Totem-s**. Ningún workflow toca otros repositorios.

## Uso diario

1. Edita el proyecto desde GitHub (o tu computador) y guarda los cambios en `main`.
2. Espera a que **Actions → Verify Android and Windows** termine en verde.
3. En **Releases → Draft a new release**, crea un tag nuevo, por ejemplo `v1.0.1`, apuntando al commit revisado. Publica una release normal, no prerelease.
4. **Build and publish release** compila Android y Windows. Después de que ambos pasan pruebas sube los instaladores y finalmente `update-manifest.json`.
5. Los equipos activados consultan cada 15 minutos mientras muestran la bienvenida. Descargan y verifican SHA-256. La instalación espera a no tener carrito, venta ni pago pendiente de conciliación.

Editar código NO despliega por sí solo. Publicar una Release autoriza distribuirla a los equipos con esta función instalada. Primero prueba en hardware real. No habilites release immutability antes de terminar la subida de assets.

Tags aceptados: `vM.m.p`, números 0..999. El código interno es `M*1000000+m*1000+p`. Nunca reutilices tags ni reemplaces archivos publicados. Para corregir publica otra versión superior. No existe downgrade ni rollback automático.

## Firma Android: configuración inicial obligatoria

La actualización debe conservar **exactamente la misma clave privada** que firmó la instalación existente. Las compilaciones locales históricas usan el debug keystore de la Mac; no generes otro para actualizar esos dispositivos. Para una flota nueva conviene una firma de producción y migración controlada.

En **Settings → Secrets and variables → Actions → Repository secrets** configura:

| Secret | Contenido |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Archivo de firma existente convertido a Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Contraseña del almacén |
| `ANDROID_KEY_ALIAS` | Alias de la clave |
| `ANDROID_KEY_PASSWORD` | Contraseña de la clave |

No subas keystores, `key.properties`, API keys ni contraseñas al código o Releases. GitHub guarda estos secretos por separado y sólo el job Android los usa. Publicar falla explícitamente si faltan, en lugar de producir APK incompatibles. Los PR no reciben secretos de firma.

## Primera instalación

- **SUNMI/Android:** instalar por ADB la primera versión con actualizador, conservando firma/datos mediante `adb install -r`. La instalación silenciosa requiere **Device Owner**. Se comprueban paquete, versión y firma. Sin Device Owner, soporte instala manualmente. No se cambia de firma ni se restablece de fábrica automáticamente.
- **Windows x64:** descarga y ejecuta `gournet-kiosk-windows-x64-setup.exe` bajo la cuenta Windows que ejecutará el kiosko. Se instala por usuario sin elevar privilegios. No basta copiar el `.exe` Flutter. Las versiones portátiles requieren esta instalación inicial. Drivers y configuración: [windows.md](windows.md).
- WDAC/AppLocker/antivirus corporativo pueden bloquear el Setup. Todavía no tiene firma Authenticode: antes de una flota de producción conviene agregarla. No desactives las protecciones para saltar un bloqueo.

Configuración, API key, correlativo, catálogo, pedidos pendientes y auditoría quedan en el almacenamiento de la app y no se borran al actualizar. Esta implementación no cambia schemas de datos. Los pagos inciertos bloquean la instalación hasta que soporte los concilie.

## Seguridad y límites

- Descargas sólo de este repositorio público y hosts oficiales de assets GitHub, por HTTPS. **No se envían credenciales Gour-net a GitHub**.
- Manifiesto/hash confían en los permisos de publicación del repositorio y TLS. SHA-256 detecta corrupción, no sustituye la firma del publicador. Android verifica además la firma instalada; Windows necesita Authenticode y/o manifiestos firmados para endurecimiento adicional.
- Protege GitHub con 2FA y restringe quién publica/edita workflows: quien publica puede distribuir código a la flota.
- Volver el repo privado interrumpe descargas anónimas. Antes hay que desplegar un gateway; nunca meter un token GitHub en la app.
- No incluye inventario remoto, confirmación central, rollout gradual, rollback automático ni reinicio forzado durante ventas.
- Descargas fallidas reintentan; nunca se ejecuta un archivo parcial. Estado y búsqueda manual: Configuración → Integración.
- Android levanta temporalmente sólo la restricción de instalación puesta por esta app y la restaura en el resultado/reinicio. No modifica otras restricciones.

## Antes de masificar

Instala en un equipo de pruebas y publica otra versión superior. Verifica actualización en reposo, conservación de TUS/API key/correlativo, venta/comprobante, pago incierto, descarga corrupta/interrumpida, reinicio y firma incorrecta. Pruebas unitarias/CI no sustituyen la validación física Android/Windows.
