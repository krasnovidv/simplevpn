package com.simplevpn.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home-screen widgets (design: «Рабочий стол: виджеты»):
 *  - [VpnWidgetProvider]      — 2×2 power button (compact at 1×1); tap toggles.
 *  - [VpnWidgetWideProvider]  — 4×2 orb + status + timer + on/off pill; tap toggles.
 *  - [VpnWidgetStatsProvider] — 2×2 "today" traffic; tap opens the app.
 *
 * Toggle taps go through [WidgetToggleActivity] (a transparent trampoline):
 * starting the VPN service from an Activity avoids the Android 12+ background
 * foreground-service restriction and lets us ask for VPN consent inline.
 *
 * The connect params come from SharedPreferences, mirrored there both by the
 * service on every start ([saveConnectParams]) and by the Flutter app whenever
 * a config is loaded — so the widgets work without opening the app.
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
         * Redraw every widget instance of every kind. Call on each VPN status
         * change. [stateOverride] is the state being emitted right now; when
         * null, falls back to [currentState].
         */
        @JvmStatic
        @JvmOverloads
        fun refresh(ctx: Context, stateOverride: String? = null) {
            val mgr = AppWidgetManager.getInstance(ctx) ?: return
            val state = stateOverride ?: currentState()
            for (kind in WidgetKind.values()) {
                val ids = mgr.getAppWidgetIds(ComponentName(ctx, kind.provider))
                for (id in ids) {
                    try {
                        mgr.updateAppWidget(id, kind.render(ctx, mgr, id, state))
                    } catch (e: Exception) {
                        Log.w(TAG, "widget ${kind.name} update failed: ${e.message}")
                    }
                }
            }
        }

        /** The service's last emitted state (see [SimpleVpnService.lastStatus]). */
        @JvmStatic
        fun currentState(): String = SimpleVpnService.state

        @JvmStatic
        fun isActive(state: String): Boolean =
            state == "connected" || state == "reconnecting" || state.startsWith("connecting")
    }

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) = refresh(context)

    override fun onAppWidgetOptionsChanged(context: Context, mgr: AppWidgetManager, id: Int, options: Bundle) =
        refresh(context)
}

class VpnWidgetWideProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) =
        VpnWidgetProvider.refresh(context)
}

class VpnWidgetStatsProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) =
        VpnWidgetProvider.refresh(context)
}

private enum class WidgetKind(val provider: Class<out AppWidgetProvider>) {
    BUTTON(VpnWidgetProvider::class.java) {
        override fun render(ctx: Context, mgr: AppWidgetManager, id: Int, state: String): RemoteViews {
            val minW = mgr.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 110)
            val compact = minW < 100
            val on = state == "connected"
            val busy = !on && VpnWidgetProvider.isActive(state)
            val v = RemoteViews(ctx.packageName, if (compact) R.layout.widget_button_small else R.layout.widget_button)
            v.setImageViewResource(R.id.power_bg, if (on) R.drawable.widget_power_on else R.drawable.widget_power_off)
            v.setInt(R.id.power_icon, "setColorFilter", color(ctx, if (on) R.color.w_on_accent else R.color.w_sub))
            if (!compact) {
                v.setTextViewText(R.id.label, when {
                    on -> "спрятан"
                    busy -> "прячемся…"
                    else -> "на виду"
                })
            }
            v.setOnClickPendingIntent(R.id.widget_root, toggleIntent(ctx))
            return v
        }
    },

    WIDE(VpnWidgetWideProvider::class.java) {
        override fun render(ctx: Context, mgr: AppWidgetManager, id: Int, state: String): RemoteViews {
            val on = state == "connected"
            val busy = !on && VpnWidgetProvider.isActive(state)
            val v = RemoteViews(ctx.packageName, R.layout.widget_wide)
            v.setImageViewResource(R.id.orb, when {
                on -> R.drawable.orb_connected
                busy -> R.drawable.orb_connecting
                else -> R.drawable.orb_idle
            })
            v.setTextViewText(R.id.title, when {
                on -> "ТЕБЯ НЕТ"
                busy -> "ПРЯЧЕМ…"
                else -> "ТЕБЯ ВИДНО"
            })
            val since = SimpleVpnService.connectedAtElapsed
            if (on && since > 0) {
                v.setTextViewText(R.id.sub, "Амстердам · ")
                v.setViewVisibility(R.id.chrono, View.VISIBLE)
                v.setChronometer(R.id.chrono, since, null, true)
            } else {
                v.setTextViewText(R.id.sub, if (busy) "заметаем следы…" else "тапни по виджету")
                v.setViewVisibility(R.id.chrono, View.GONE)
                v.setChronometer(R.id.chrono, 0, null, false)
            }
            v.setInt(R.id.pill, "setBackgroundResource", if (on) R.drawable.widget_pill_on else R.drawable.widget_pill_off)
            v.setTextViewText(R.id.pill_text, if (on) "Вкл" else "Выкл")
            val fg = color(ctx, if (on) R.color.w_on_accent else R.color.w_text)
            v.setTextColor(R.id.pill_text, fg)
            v.setInt(R.id.pill_icon, "setColorFilter", fg)
            v.setOnClickPendingIntent(R.id.widget_root, toggleIntent(ctx))
            return v
        }
    },

    STATS(VpnWidgetStatsProvider::class.java) {
        override fun render(ctx: Context, mgr: AppWidgetManager, id: Int, state: String): RemoteViews {
            val v = RemoteViews(ctx.packageName, R.layout.widget_stats)
            val (amount, unit) = TrafficToday.format(TrafficToday.get(ctx))
            v.setTextViewText(R.id.amount, amount)
            v.setTextViewText(R.id.unit, " $unit")
            ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
                v.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(ctx, 2, it, piFlags()))
            }
            return v
        }
    };

    abstract fun render(ctx: Context, mgr: AppWidgetManager, id: Int, state: String): RemoteViews

    companion object {
        fun color(ctx: Context, res: Int): Int = ContextCompat.getColor(ctx, res)

        fun piFlags(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        // Routed through the transparent Activity: foreground context → may
        // start the FGS and ask for VPN consent without restriction.
        fun toggleIntent(ctx: Context): PendingIntent {
            val toggle = Intent(ctx, WidgetToggleActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            return PendingIntent.getActivity(ctx, 0, toggle, piFlags())
        }
    }
}

/**
 * Traffic carried through the tunnel today (local date), for the stats
 * widget. The service feeds it deltas of vpnlib's session counters.
 */
object TrafficToday {
    private const val PREFS = "simplevpn_traffic"
    private const val KEY_DAY = "day"
    private const val KEY_BYTES = "bytes"

    private fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    @JvmStatic
    fun add(ctx: Context, bytes: Long) {
        if (bytes <= 0) return
        val p = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val day = today()
        val base = if (p.getString(KEY_DAY, null) == day) p.getLong(KEY_BYTES, 0) else 0
        p.edit().putString(KEY_DAY, day).putLong(KEY_BYTES, base + bytes).apply()
    }

    @JvmStatic
    fun get(ctx: Context): Long {
        val p = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return if (p.getString(KEY_DAY, null) == today()) p.getLong(KEY_BYTES, 0) else 0
    }

    /** "1,2" + "ГБ", or "342" + "МБ". */
    @JvmStatic
    fun format(bytes: Long): Pair<String, String> {
        val mb = bytes / (1024.0 * 1024.0)
        return if (mb >= 1024) {
            String.format(Locale("ru"), "%.1f", mb / 1024) to "ГБ"
        } else {
            mb.toLong().toString() to "МБ"
        }
    }
}
