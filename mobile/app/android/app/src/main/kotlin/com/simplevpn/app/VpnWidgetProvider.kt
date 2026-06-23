package com.simplevpn.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import vpnlib.Vpnlib

/**
 * Home-screen widget: a single tap toggles the VPN on/off and shows the live
 * status. The widget can reconnect WITHOUT opening the app, because the service
 * mirrors the last-used connect params into SharedPreferences on every start
 * (see [SimpleVpnService.onStartCommand] → [saveConnectParams]). If no params
 * are cached yet, or the system VPN consent hasn't been granted, the tap falls
 * back to opening the app (consent can only be requested from an Activity).
 */
class VpnWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "SimpleVPN"
        const val ACTION_TOGGLE = "com.simplevpn.app.WIDGET_TOGGLE"

        private const val PREFS = "simplevpn_widget"
        private const val KEY_CONFIG = "config"
        private const val KEY_AUTO_RECONNECT = "auto_reconnect"
        private const val KEY_KILL_SWITCH = "kill_switch"
        private const val KEY_MAX_RETRIES = "max_retries"
        private const val KEY_MAX_BACKOFF = "max_backoff_seconds"
        private const val KEY_SPLIT_MODE = "split_tunnel_mode"
        private const val KEY_SPLIT_APPS = "split_tunnel_apps" // newline-joined

        /**
         * Persist the last successful connect params so the widget can reconnect
         * without the app being open. Called from the service on every start.
         */
        @JvmStatic
        fun saveConnectParams(
            ctx: Context,
            config: String,
            autoReconnect: Boolean,
            killSwitch: Boolean,
            maxRetries: Int,
            maxBackoff: Int,
            splitMode: String,
            splitApps: List<String>,
        ) {
            ctx.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_CONFIG, config)
                .putBoolean(KEY_AUTO_RECONNECT, autoReconnect)
                .putBoolean(KEY_KILL_SWITCH, killSwitch)
                .putInt(KEY_MAX_RETRIES, maxRetries)
                .putInt(KEY_MAX_BACKOFF, maxBackoff)
                .putString(KEY_SPLIT_MODE, splitMode)
                .putString(KEY_SPLIT_APPS, splitApps.joinToString("\n"))
                .apply()
        }

        /** Redraw every widget instance. Call on each VPN status change. */
        @JvmStatic
        fun refresh(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx) ?: return
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, VpnWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val provider = VpnWidgetProvider()
            for (id in ids) provider.updateWidget(ctx, mgr, id)
        }

        /** Go-side status is authoritative; fall back to the Kotlin mirror. */
        private fun currentState(): String {
            val go = try { Vpnlib.status() } catch (_: Throwable) { null }
            return go ?: SimpleVpnService.currentStatus
        }

        private fun isActive(state: String): Boolean =
            state == "connected" || state == "reconnecting" || state.startsWith("connecting")
    }

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) updateWidget(context, mgr, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TOGGLE) {
            handleToggle(context)
        }
    }

    private fun handleToggle(context: Context) {
        if (isActive(currentState())) {
            // Service is already foreground — plain startService is allowed and
            // must NOT be startForegroundService (the DISCONNECT path never calls
            // startForeground, which would crash the FGS contract).
            val i = Intent(context, SimpleVpnService::class.java).apply { action = "DISCONNECT" }
            try {
                context.startService(i)
            } catch (e: Exception) {
                Log.w(TAG, "widget disconnect failed: ${e.message}")
            }
        } else {
            connectFromWidget(context)
        }
        // Optimistic redraw; the service emits authoritative status shortly after.
        refresh(context)
    }

    private fun connectFromWidget(context: Context) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val config = prefs.getString(KEY_CONFIG, null)
        // No cached config, or VPN consent not granted yet → must use the app UI
        // (VpnService.prepare's consent dialog can only be shown from an Activity).
        if (config.isNullOrEmpty() || VpnService.prepare(context) != null) {
            Log.i(TAG, "widget connect: no cached config or consent needed — opening app")
            openApp(context)
            return
        }

        val splitApps = (prefs.getString(KEY_SPLIT_APPS, "") ?: "")
            .split("\n").filter { it.isNotEmpty() }
        val i = Intent(context, SimpleVpnService::class.java).apply {
            putExtra("config", config)
            putExtra("auto_reconnect", prefs.getBoolean(KEY_AUTO_RECONNECT, false))
            putExtra("kill_switch", prefs.getBoolean(KEY_KILL_SWITCH, false))
            putExtra("max_retries", prefs.getInt(KEY_MAX_RETRIES, SimpleVpnService.DEFAULT_MAX_RETRIES))
            putExtra("max_backoff_seconds", prefs.getInt(KEY_MAX_BACKOFF, SimpleVpnService.DEFAULT_MAX_BACKOFF_SECONDS))
            putExtra("split_tunnel_mode", prefs.getString(KEY_SPLIT_MODE, "off"))
            putStringArrayListExtra("split_tunnel_apps", ArrayList(splitApps))
        }
        try {
            // Widget interaction is an Android 12+ exemption to the background
            // foreground-service-start restriction, so this is allowed here.
            ContextCompat.startForegroundService(context, i)
        } catch (e: Exception) {
            Log.w(TAG, "widget connect failed, opening app instead: ${e.message}")
            openApp(context)
        }
    }

    private fun openApp(context: Context) {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (launch != null) context.startActivity(launch)
    }

    private fun updateWidget(context: Context, mgr: AppWidgetManager, id: Int) {
        val state = currentState()
        val views = RemoteViews(context.packageName, R.layout.vpn_widget)

        val statusText: String
        val actionText: String
        val statusColor: Int
        when {
            state == "connected" -> {
                statusText = "ПОДКЛЮЧЕНО"; actionText = "НАЖМИ, ЧТОБЫ ОТКЛЮЧИТЬ"
                statusColor = 0xFF00F0FF.toInt()
            }
            state == "reconnecting" || state.startsWith("connecting") -> {
                statusText = "ПОДКЛЮЧЕНИЕ…"; actionText = "ОЖИДАНИЕ"
                statusColor = 0xFFFF2BD6.toInt()
            }
            state.startsWith("error") -> {
                statusText = "ОШИБКА"; actionText = "НАЖМИ, ЧТОБЫ ПОВТОРИТЬ"
                statusColor = 0xFFFF5555.toInt()
            }
            else -> {
                statusText = "ОТКЛЮЧЕНО"; actionText = "НАЖМИ, ЧТОБЫ ПОДКЛЮЧИТЬ"
                statusColor = 0xFF5A4A7A.toInt()
            }
        }
        views.setTextViewText(R.id.widget_status, statusText)
        views.setTextColor(R.id.widget_status, statusColor)
        views.setTextViewText(R.id.widget_action, actionText)

        val toggle = Intent(context, VpnWidgetProvider::class.java).apply { action = ACTION_TOGGLE }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getBroadcast(context, 0, toggle, flags)
        views.setOnClickPendingIntent(R.id.widget_root, pi)

        mgr.updateAppWidget(id, views)
    }
}
