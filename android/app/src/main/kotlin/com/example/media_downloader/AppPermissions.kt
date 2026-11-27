package com.example.media_downloader

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodChannel

/**
 * Permisos que usa la app, para la sección de ajustes y antes de cada descarga:
 * - `storage`: solo Android 7–9; desde Android 10 se guarda con MediaStore y SAF, sin permisos.
 * - `notifications`: progreso en la barra (permiso en Android 13+, o desactivadas a mano).
 * - `battery`: sin optimización de batería, para que el sistema no corte descargas largas.
 */
class AppPermissions(private val activity: Activity) {

    companion object {
        const val STORAGE = "storage"
        const val NOTIFICATIONS = "notifications"
        const val BATTERY = "battery"

        private const val GRANTED = "granted"
        private const val DENIED = "denied"
        private const val NOT_REQUIRED = "notRequired"

        private val REQUEST_CODES = mapOf(
            Manifest.permission.WRITE_EXTERNAL_STORAGE to 8845,
            Manifest.permission.POST_NOTIFICATIONS to 8846,
        )
    }

    private val pending = mutableMapOf<Int, MethodChannel.Result>()

    /** Permisos ya pedidos alguna vez (para distinguir "nunca pedido" de "denegado para siempre"). */
    private val asked = activity.getSharedPreferences("permissions_asked", Context.MODE_PRIVATE)

    fun status(): Map<String, String> = mapOf(
        STORAGE to when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> NOT_REQUIRED
            isGranted(Manifest.permission.WRITE_EXTERNAL_STORAGE) -> GRANTED
            else -> DENIED
        },
        NOTIFICATIONS to if (NotificationManagerCompat.from(activity).areNotificationsEnabled()) GRANTED else DENIED,
        BATTERY to if (isIgnoringBatteryOptimizations()) GRANTED else DENIED,
    )

    /**
     * Pide el permiso [name] y responde si quedó concedido. Si Android ya no muestra el diálogo
     * (denegado para siempre, desactivado a mano o batería) y [openSettings] es true, abre la
     * pantalla de ajustes del sistema que corresponde.
     */
    fun request(name: String, openSettings: Boolean, result: MethodChannel.Result) {
        if (status()[name] != DENIED) return result.success(true)
        val runtime = when (name) {
            STORAGE -> Manifest.permission.WRITE_EXTERNAL_STORAGE
            NOTIFICATIONS -> Manifest.permission.POST_NOTIFICATIONS.takeIf {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !isGranted(it)
            }
            else -> null
        }
        if (runtime != null && canAsk(runtime)) return ask(runtime, result)
        if (openSettings) openSettingsFor(name)
        result.success(false)
    }

    /** Devuelve true si el resultado era de un permiso pedido aquí. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        val result = pending.remove(requestCode) ?: return false
        result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        return true
    }

    private fun isGranted(permission: String) =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun isIgnoringBatteryOptimizations() =
        activity.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(activity.packageName)

    /** Nunca pedido, o Android todavía permite mostrar el diálogo. */
    private fun canAsk(permission: String) =
        !asked.getBoolean(permission, false) || activity.shouldShowRequestPermissionRationale(permission)

    private fun ask(permission: String, result: MethodChannel.Result) {
        val code = REQUEST_CODES.getValue(permission)
        if (pending.containsKey(code)) return result.success(false)
        pending[code] = result
        asked.edit().putBoolean(permission, true).apply()
        activity.requestPermissions(arrayOf(permission), code)
    }

    @SuppressLint("BatteryLife") // Se distribuye fuera de Google Play.
    private fun openSettingsFor(name: String) {
        val pkg = activity.packageName
        val appDetails = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", pkg, null))
        val intents = when (name) {
            NOTIFICATIONS -> listOf(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg),
                appDetails,
            )
            BATTERY -> listOf(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$pkg")),
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
            )
            else -> listOf(appDetails)
        }
        for (intent in intents) {
            try {
                activity.startActivity(intent)
                return
            } catch (_: ActivityNotFoundException) {
            }
        }
    }
}
