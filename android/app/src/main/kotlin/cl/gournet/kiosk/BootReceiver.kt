package cl.gournet.kiosk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        runCatching { AutoStartManager.synchronize(context) }
            .onFailure { Log.e("GournetKiosk", "No se pudo sincronizar el inicio automático", it) }
        if (!AutoStartManager.isEnabled(context)) return
        runCatching {
            context.startActivity(
                Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                },
            )
        }.onFailure { Log.e("GournetKiosk", "Android no permitió abrir el tótem al arrancar", it) }
    }
}
