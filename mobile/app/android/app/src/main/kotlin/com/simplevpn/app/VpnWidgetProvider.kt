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
        const val KEY_KILL_SWITCH = "kill_switch"
        const val KEY_SPLIT_MODE = "split_tunnel_mode"
        const val KEY_SPLIT_APPS = "split_tunnel_apps" // newline-joined

        /**
         * Persist the last connect params so the widget (and a system restart of
         * the service) can reconnect without the app being open. Called from the
         * service on start AND from Flutter via `cacheWidgetParams`.
         */
        @JvmStatic
        fun saveConnectParams(ctx: Context, p: ConnectParams) {
            ctx.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_CONFIG, p.config)
                .putBoolean(KEY_KILL_SWITCH, p.killSwitch)
                .putString(KEY_SPLIT_MODE, p.splitMode)
                .putString(KEY_SPLIT_APPS, p.splitApps.joinToString("\n"))
                .apply()
            refresh(ctx)
        }

        @JvmStatic
        fun loadConnectParams(ctx: Context): ConnectParams? {
            val prefs = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val config = prefs.getString(KEY_CONFIG, null)
            if (config.isNullOrEmpty()) return null
            return ConnectParams(
                config = config,
                killSwitch = prefs.getBoolean(KEY_KILL_SWITCH, false),
                splitMode = prefs.getString(KEY_SPLIT_MODE, "off") ?: "off",
                splitApps = (prefs.getString(KEY_SPLIT_APPS, "") ?: "")
                    .split("\n").filter { it.isNotEmpty() },
            )
        }

        @JvmStatic
        fun hasCachedConfig(ctx: Context): Boolean = loadConnectParams(ctx) != null

        /**
         * Build a [SimpleVpnService] start Intent from the cached params, or null
         * if no config has been cached yet.
         */
        @JvmStatic
        fun cachedConnectIntent(ctx: Context): Intent? = loadConnectParams(ctx)?.toIntent(ctx)

        /**
         * Redraw every widget instance. Call on each VPN status change.
         *
         * [stateOverride] is the state being emitted right now; when null,
         * falls back to [currentState].
         */
        @JvmStatic
        @JvmOverloads
        fun refresh(ctx: Context, stateOverride: String? = null) {
            val mgr = AppWidgetManager.getInstance(ctx) ?: return
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, VpnWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val provider = VpnWidgetProvider()
            for (id in ids) provider.updateWidget(ctx, mgr, id, stateOverride)
        }

        /** The service's last emitted state (see [SimpleVpnService.lastStatus]). */
        @JvmStatic
        fun currentState(): String = SimpleVpnService.state

        @JvmStatic
        fun isActive(state: String): Boolean =
            state == "connected" || state == "reconnecting" || state.startsWith("connecting")
    }

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) updateWidget(context, mgr, id)
    }

    private fun updateWidget(context: Context, mgr: AppWidgetManager, id: Int, stateOverride: String? = null) {
        val state = stateOverride ?: currentState()
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
