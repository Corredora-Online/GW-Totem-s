package cl.gournet.kiosk

import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserManager
import io.flutter.plugin.common.MethodChannel
import java.io.File

object UpdateInstaller {
    private var pending: MethodChannel.Result? = null
    private var sessionId: Int? = null
    val active: Boolean get() = pending != null

    fun restoreRestriction(context: Context) {
        val prefs = context.getSharedPreferences("gournet_updates", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("restore_install_restriction", false)) return
        val policy = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (policy.isDeviceOwnerApp(context.packageName)) {
            policy.addUserRestriction(ComponentName(context, KioskDeviceAdminReceiver::class.java), UserManager.DISALLOW_INSTALL_APPS)
        }
        prefs.edit().remove("restore_install_restriction").commit()
    }

    @Suppress("DEPRECATION")
    fun install(context: Context, path: String?, result: MethodChannel.Result) {
        if (active) { result.error("UPDATE_BUSY", "Ya hay una actualización activa", null); return }
        try {
            val file = File(path ?: "").canonicalFile
            require(file.isFile && file.extension == "apk") { "APK inválido" }
            require(file.path.startsWith(context.filesDir.canonicalPath + File.separator)) { "Ubicación de APK no permitida" }
            val pm = context.packageManager
            val incoming = pm.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNATURES) ?: error("APK ilegible")
            val current = pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
            require(incoming.packageName == context.packageName) { "El APK pertenece a otra aplicación" }
            require(incoming.versionCode > current.versionCode) { "Versión no superior a la instalada" }
            require(!incoming.signatures.isNullOrEmpty() && incoming.signatures!!.toSet() == current.signatures!!.toSet()) { "La firma no coincide con la app instalada" }
            val policy = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            require(policy.isDeviceOwnerApp(context.packageName)) { "La actualización automática requiere Device Owner. Instala esta versión por ADB." }
            val admin = ComponentName(context, KioskDeviceAdminReceiver::class.java)
            val restricted = policy.getUserRestrictions(admin).getBoolean(UserManager.DISALLOW_INSTALL_APPS)
            context.getSharedPreferences("gournet_updates", Context.MODE_PRIVATE).edit().putBoolean("restore_install_restriction", restricted).commit()
            policy.clearUserRestriction(admin, UserManager.DISALLOW_INSTALL_APPS)
            pending = result
            val installer = pm.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(context.packageName)
                setSize(file.length())
                if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
            val id = installer.createSession(params)
            sessionId = id
            installer.openSession(id).use { session ->
                session.openWrite("base.apk", 0, file.length()).use { output ->
                    file.inputStream().use { it.copyTo(output) }
                    session.fsync(output)
                }
                val intent = Intent(context, UpdateResultReceiver::class.java)
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                session.commit(PendingIntent.getBroadcast(context, id, intent, flags).intentSender)
            }
            Handler(Looper.getMainLooper()).postDelayed({
                if (sessionId == id) finish(context, false, "Tiempo de instalación agotado")
            }, 150000)
        } catch (error: Exception) {
            if (pending != null) finish(context, false, error.message ?: "Error de instalación")
            else {
                restoreRestriction(context)
                result.error("UPDATE_FAILED", error.message, null)
            }
        }
    }

    fun finish(context: Context, success: Boolean, message: String) {
        if (!success) sessionId?.let { runCatching { context.packageManager.packageInstaller.abandonSession(it) } }
        sessionId = null
        restoreRestriction(context)
        val result = pending
        pending = null
        if (success) result?.success(true) else result?.error("UPDATE_FAILED", message, null)
    }
}

class UpdateResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        // Never show an installation dialog to a customer.
        UpdateInstaller.finish(context, status == PackageInstaller.STATUS_SUCCESS,
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) "El equipo exige instalación manual por soporte" else "Instalación rechazada ($status)")
    }
}

class UpdateReplacedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        UpdateInstaller.restoreRestriction(context)
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
