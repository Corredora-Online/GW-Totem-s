# Inicio automático

La opción **Configuración → Operación → Inicio automático → Iniciar el tótem
automáticamente** viene activada por defecto. Pulsa **Guardar** después de
cambiarla. Las configuraciones de versiones anteriores también se migran a
activado. La elección se conserva al actualizar la app.

## Windows

La app registra su ejecutable, entre comillas, en
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run\GournetKiosk`.
Se aplica a la cuenta Windows que ejecuta Gour-net, sin permisos de administrador.
Al desactivar la opción se elimina ese valor; al desinstalar también se limpia.
El Setup abre la app después de instalar o actualizar para aplicar la preferencia
guardada, sin reactivar una opción que estaba deshabilitada.

Windows debe iniciar sesión en esa cuenta para abrir la app. Si el equipo pide
contraseña al encender, el arranque de Gour-net espera ese inicio de sesión.
La app no configura el inicio de sesión automático de Windows. Si soporte ha
configurado Shell Launcher por separado, ese mecanismo también debe retirarse
desde su configuración para que deje de iniciar la app como shell.

## Android

El receptor de `BOOT_COMPLETED` consulta la preferencia nativa antes de abrir
Flutter. En un equipo administrado como **Device Owner**, la app también queda
como pantalla de inicio persistente para que Android la abra al arrancar. La
opción controla un alias HOME separado: desactivarla retira esa selección y
deshabilita el alias, conservando el icono normal para abrir la app a mano.

El sistema debe permitir el arranque de la aplicación. En Android sin Device
Owner, versiones modernas y algunos fabricantes restringen abrir actividades
desde segundo plano o exigen habilitar autoarranque en los ajustes del fabricante.
Para un tótem sin intervención se requiere el aprovisionamiento administrado.
El receptor de arranque actúa después del desbloqueo del usuario si existe una
pantalla de bloqueo. La opción no elimina credenciales de bloqueo del sistema.

La salida administrativa pausa la selección como pantalla de inicio para permitir
mantenimiento. La preferencia guardada vuelve a aplicarse al abrir la app o
reiniciar el dispositivo.

## Verificación en equipos físicos

1. Instalar o actualizar, abrir una vez y comprobar que la opción está activada.
2. Reiniciar: Android administrado debe abrir Gour-net; Windows debe abrirlo al
   iniciar sesión con la misma cuenta.
3. Desactivar, guardar y reiniciar: el sistema debe quedarse en su entorno habitual.
4. Abrir manualmente y confirmar que la opción continúa desactivada.
5. Actualizar con la opción desactivada y repetir el reinicio para verificar que se
   respeta la elección.
6. Volver a activar, guardar y reiniciar para verificar el arranque nuevamente.

Las pruebas de Flutter verifican migración, persistencia y reversión ante fallos
de aplicación o guardado; CI compila Android y Windows. El reinicio real requiere
validación en los dispositivos del local.
