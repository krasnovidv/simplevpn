package com.simplevpn.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import vpnlib.Vpnlib

/**
 * Home-screen widget: a single tap toggles the VPN on/off and shows the live
 * status. Taps are routed to [WidgetToggleActivity] (a transparent trampoline)
 * rather than handled here as a broadcast — that guarantees the VPN service is
 * started from a foreground Activity context (no Android 12+ background
 * foreground-service-start restriction) and lets us request VPN consent inline
 * when needed.
 *
 * The connect params come from SharedPreferences, mirrored there both by the
 * service on every start ([saveConnectParams]) and proactively by the Flutter
 * app whenever a config is loaded — so the widget works even before the first
 * in-app connect of this version.
 */
class VpnWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val TAG = "SimpleVPN"

        const val PREFS = "simplevpn_widget"
        const val KEY_CONFIG = "config"
        const val KEY_AUTO_RECONNECT = "auto_reconnect"
        const val KEY_KILL_SWITCH = "kill_switch"
        const val KEY_MAX_RETRIES = "max_retries"
        const val KEY_MAX_BACKOFF = "max_backoff_seconds"
        const val KEY_SPLIT_MODE = "split_tunnel_mode"
        const val KEY_SPLIT_APPS = "split_tunnel_apps" // newline-joined

        /**
         * Persist the last connect params so the widget can reconnect without the
         * app being open. Called from the service on start AND from Flutter via
         * the `cacheWidgetParams` method channel when a config is loaded.
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
            refresh(ctx)
        }

        @JvmStatic
        fun hasCachedConfig(ctx: Context): Boolean =
            !ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_CONFIG, null).isNullOrEmpty()

        /**
         * Build a [SimpleVpnService] start Intent from the cached params, or null
         * if no config has been cached yet.
         */
        @JvmStatic
        fun cachedConnectIntent(ctx: Context): Intent? {
            val prefs = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val config = prefs.getString(KEY_CONFIG, null)
            if (config.isNullOrEmpty()) return null
            val splitApps = (prefs.getString(KEY_SPLIT_APPS, "") ?: "")
                .split("\n").filter { it.isNotEmpty() }
            return Intent(ctx, SimpleVpnService::class.java).apply {
                putExtra("config", config)
                putExtra("auto_reconnect", prefs.getBoolean(KEY_AUTO_RECONNECT, false))
                putExtra("kill_switch", prefs.getBoolean(KEY_KILL_SWITCH, false))
                putExtra("max_retries", prefs.getInt(KEY_MAX_RETRIES, SimpleVpnService.DEFAULT_MAX_RETRIES))
                putExtra("max_backoff_seconds", prefs.getInt(KEY_MAX_BACKOFF, SimpleVpnService.DEFAULT_MAX_BACKOFF_SECONDS))
                putExtra("split_tunnel_mode", prefs.getString(KEY_SPLIT_MODE, "off"))
                putStringArrayListExtra("split_tunnel_apps", ArrayList(splitApps))
            }
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
        @JvmStatic
        fun currentState(): String {
            val go = try { Vpnlib.status() } catch (_: Throwable) { null }
            return go ?: SimpleVpnService.currentStatus
        }

        @JvmStatic
        fun isActive(state: String): Boolean =
            state == "connected" || state == "reconnecting" || state.startsWith("connecting")
    }

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) updateWidget(context, mgr, id)
    }

    private fun updateWidget(context: Context, mgr: AppWidgetManager, id: Int) {
        val state = currentState()
        val views = RemoteViews(context.packageName, R.layout.vpn_widget)

        // Compact 1x1 labels.
        val statusText: String
        val statusColor: Int
        when {
            state == "connected" -> {
                statusText = "ВКЛ"; statusColor = 0xFF00F0FF.toInt()
            }
            state == "reconnecting" || state.startsWith("connecting") -> {
                statusText = "…"; statusColor = 0xFFFF2BD6.toInt()
            }
            state.startsWith("error") -> {
                statusText = "ERR"; statusColor = 0xFFFF5555.toInt()
            }
            else -> {
                statusText = "ВЫКЛ"; statusColor = 0xFF5A4A7A.toInt()
            }
        }
        views.setTextViewText(R.id.widget_status, statusText)
        views.setTextColor(R.id.widget_status, statusColor)

        // Route the tap to the transparent toggle Activity (foreground context →
        // can start the FGS and request VPN consent without restriction).
        val toggle = Intent(context, WidgetToggleActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getActivity(context, 0, toggle, flags)
        views.setOnClickPendingIntent(R.id.widget_root, pi)

        mgr.updateAppWidget(id, views)
    }
}
