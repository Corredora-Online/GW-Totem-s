package cl.gournet.kiosk

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager

/** Boot preference is native so the receiver can read it before Flutter starts. */
object AutoStartManager {
    private const val PREFERENCES = "gournet_kiosk_native"
    private const val KEY = "auto_start"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(KEY, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        val previous = isEnabled(context)
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        check(preferences.edit().putBoolean(KEY, enabled).commit()) {
            "No se pudo guardar el inicio automático"
        }
        try {
            synchronize(context)
        } catch (error: Exception) {
            preferences.edit().putBoolean(KEY, previous).commit()
            runCatching { synchronize(context) }
            throw error
        }
    }

    fun synchronize(context: Context) {
        val enabled = isEnabled(context)
        setHomeComponentEnabled(context, enabled)
        val policy = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (!policy.isDeviceOwnerApp(context.packageName)) return
        val admin = ComponentName(context, KioskDeviceAdminReceiver::class.java)
        // Also removes the preference pointing at MainActivity in older releases.
        policy.clearPackagePersistentPreferredActivities(admin, context.packageName)
        if (enabled) {
            val filter = IntentFilter(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addCategory(Intent.CATEGORY_DEFAULT)
            }
            policy.addPersistentPreferredActivity(admin, filter, homeComponent(context))
        }
    }

    fun pauseForMaintenance(context: Context) {
        // Saved preference stays intact: opening the app or rebooting restores it.
        setHomeComponentEnabled(context, false)
        val policy = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (policy.isDeviceOwnerApp(context.packageName)) {
            policy.clearPackagePersistentPreferredActivities(
                ComponentName(context, KioskDeviceAdminReceiver::class.java),
                context.packageName,
            )
        }
    }

    private fun homeComponent(context: Context) =
        ComponentName(context, "${context.packageName}.KioskHome")

    private fun setHomeComponentEnabled(context: Context, enabled: Boolean) {
        val component = homeComponent(context)
        val state = if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        if (context.packageManager.getComponentEnabledSetting(component) != state) {
            context.packageManager.setComponentEnabledSetting(
                component,
                state,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
