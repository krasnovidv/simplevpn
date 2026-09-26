package com.simplevpn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicInteger
import vpnlib.Vpnlib

/**
 * What the service needs to (re)connect. Mirrored into SharedPreferences so the
 * home-screen widget and a system restart (START_STICKY / always-on VPN) can
 * reconnect without Flutter, which is the only other place the config lives.
 */
data class ConnectParams(
    val config: String,
    val killSwitch: Boolean,
    val splitMode: String,
    val splitApps: List<String>,
) {
    fun toIntent(ctx: Context): Intent = Intent(ctx, SimpleVpnService::class.java).apply {
        putExtra("config", config)
        putExtra("kill_switch", killSwitch)
        putExtra("split_tunnel_mode", splitMode)
        putStringArrayListExtra("split_tunnel_apps", ArrayList(splitApps))
    }

    companion object {
        fun fromIntent(intent: Intent?): ConnectParams? {
            val config = intent?.getStringExtra("config")
            if (config.isNullOrEmpty()) return null
            return ConnectParams(
                config = config,
                killSwitch = intent.getBooleanExtra("kill_switch", false),
                splitMode = intent.getStringExtra("split_tunnel_mode") ?: "off",
                splitApps = intent.getStringArrayListExtra("split_tunnel_apps") ?: emptyList(),
            )
        }
    }
}

/**
 * The VPN service. Owns the TUN interface and the retry policy; vpnlib owns the
 * wire protocol and classifies errors.
 *
 * Threading: every state transition runs on the main looper. The blocking
 * vpnlib calls (preflight/runTunnel) run on a per-attempt thread that only
 * reports back by posting to the main looper.
 *
 * Sessions: [sessionGen] is bumped on every user connect and every user
 * disconnect. An attempt thread carries the generation it was started for and
 * whatever it reports under an older generation is dropped — that is what
 * keeps a deliberate disconnect (app, widget, notification) from being
 * reported as a connection error or triggering a retry.
 */
class SimpleVpnService : VpnService(), vpnlib.SocketProtector {

    // Go calls this for every socket it dials so the tunnel's own traffic is
    // not routed back into the tunnel.
    override fun protectSocket(fd: Int): Boolean = protect(fd)

    companion object {
        const val TAG = "SimpleVPN"
        const val NOTIFICATION_ID = 1
        const val CHANNEL_ID = "simplevpn_channel"
        const val ACTION_DISCONNECT = "DISCONNECT"

        /** Retry budget per session: ~3 min of backoff (1,2,4…60 s) before giving up. */
        const val MAX_RETRIES = 8
        const val MAX_BACKOFF_SECONDS = 60

        private const val MTU = 1380

        private val sessionGen = AtomicInteger(0)

        /**
         * The last status pushed to Flutter and the widget — the single source
         * of truth for "what is the VPN doing". Survives the service stopping,
         * so a final error stays visible until the next action.
         */
        @Volatile
        var lastStatus: Map<String, Any?> = mapOf("state" to "disconnected")
            private set

        val state: String get() = lastStatus["state"] as? String ?: "disconnected"

        /**
         * Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, then capped at maxBackoffSeconds.
         * Pure function — exposed at companion scope so unit tests can call it directly.
         */
        @JvmStatic
        fun calculateBackoff(attempt: Int, maxBackoffSeconds: Int = MAX_BACKOFF_SECONDS): Long {
            if (attempt <= 0) return 1000L
            // Cap shift count to avoid overflow on absurd inputs.
            val capped = attempt.coerceAtMost(30)
            val base = (1L shl capped) * 1000L
            return base.coerceAtMost(maxBackoffSeconds * 1000L)
        }

        /**
         * Pure split-tunnel rule applicator. Side-effect-free — callers pass lambdas
         * that perform the actual Builder calls (with exception handling).
         *
         * Contract:
         *   mode="allowlist"  → addAllowed called for each app in [apps]; [ownPackage] is
         *                       added if not already listed (ensures VPN control traffic routes
         *                       through the tunnel).
         *   mode="blocklist"  → addDisallowed called for [ownPackage] first, then each app.
         *   mode="off" / any  → neither lambda is called.
         */
        @JvmStatic
        fun applySplitTunnelRules(
            mode: String,
            apps: List<String>,
            ownPackage: String,
            addAllowed: (String) -> Unit,
            addDisallowed: (String) -> Unit,
        ) {
            when (mode) {
                "allowlist" -> {
                    for (pkg in apps) addAllowed(pkg)
                    if (!apps.contains(ownPackage)) addAllowed(ownPackage)
                }
                "blocklist" -> {
                    addDisallowed(ownPackage)
                    for (pkg in apps) addDisallowed(pkg)
                }
                // off: no rules applied
            }
        }

        /**
         * Outcome of the retry-policy decision. Pure data — no side effects.
         */
        data class RetryDecision(
            /** Schedule another connect attempt? */
            val shouldRetry: Boolean,
            /** Delay before firing the retry (ms). Only meaningful when shouldRetry. */
            val delayMs: Long,
            /** Attempt counter to record (1-based). Only meaningful when shouldRetry. */
            val nextAttempt: Int,
            /** Latch retryStopped=true after this decision? Auth/fatal/exhausted set this. */
            val latchStopped: Boolean,
            /** Status string to surface (e.g. "connecting (retry 2/5)" or "error: auth rejected"). */
            val statusOverride: String?,
            /** Reason tag for logs/metrics. */
            val reason: String,
        )

        /**
         * Pure retry-policy decision based on the most recent error kind from vpnlib
         * and the current retry-state. Side-effect-free — caller applies the decision.
         *
         *   - autoReconnect=false → never retry.
         *   - retryStopped=true   → never retry (latched off by prior auth/fatal/exhausted).
         *   - kind="auth"         → no retry, latch stopped, status="error: auth rejected".
         *   - kind="fatal"        → no retry, latch stopped, status preserved.
         *   - kind="none"         → no retry (clean disconnect from user).
         *   - kind="transient"    → retry if currentAttempt+1 ≤ maxRetries; else latch stopped.
         *   - any unknown kind treated as transient.
         */
        @JvmStatic
        fun decideRetry(
            autoReconnect: Boolean,
            retryStopped: Boolean,
            kind: String,
            currentAttempt: Int,
            maxRetries: Int,
            maxBackoffSeconds: Int,
            immediate: Boolean = false,
        ): RetryDecision {
            if (!autoReconnect) {
                return RetryDecision(false, 0L, currentAttempt, false, null, "auto-reconnect-disabled")
            }
            if (retryStopped) {
                return RetryDecision(false, 0L, currentAttempt, true, null, "already-stopped")
            }
            when (kind) {
                "auth" -> return RetryDecision(
                    shouldRetry = false, delayMs = 0L, nextAttempt = currentAttempt,
                    latchStopped = true,
                    statusOverride = "error: auth rejected",
                    reason = "auth-rejected",
                )
                "fatal" -> return RetryDecision(
                    shouldRetry = false, delayMs = 0L, nextAttempt = currentAttempt,
                    latchStopped = true,
                    statusOverride = null,
                    reason = "fatal",
                )
                "none" -> return RetryDecision(
                    shouldRetry = false, delayMs = 0L, nextAttempt = currentAttempt,
                    latchStopped = false,
                    statusOverride = null,
                    reason = "clean-disconnect",
                )
                // "transient" or unknown → fall through to the retry path
            }
            val nextAttempt = currentAttempt + 1
            if (nextAttempt > maxRetries) {
                return RetryDecision(
                    shouldRetry = false, delayMs = 0L, nextAttempt = currentAttempt,
                    latchStopped = true,
                    statusOverride = "error: max retries exceeded",
                    reason = "max-retries-exceeded",
                )
            }
            val delay = if (immediate) 0L else calculateBackoff(nextAttempt, maxBackoffSeconds)
            return RetryDecision(
                shouldRetry = true, delayMs = delay, nextAttempt = nextAttempt,
                latchStopped = false,
                statusOverride = "connecting (retry $nextAttempt/$maxRetries)",
                reason = "retry-transient",
            )
        }
    }

    private val main = Handler(Looper.getMainLooper())

    // --- Main-looper state ---------------------------------------------------
    private var params: ConnectParams? = null
    private var attempt = 0
    private var retryStopped = false
    private var pendingRetry: Runnable? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var foreground = false
    private var stopped = false

    // --- TUN interface, shared with attempt threads --------------------------
    private val ifaceLock = Object()
    private var vpnInterface: ParcelFileDescriptor? = null
    private var ifacePrefix: String? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")
        if (intent?.action == ACTION_DISCONNECT) {
            userDisconnect()
            return START_NOT_STICKY
        }

        // No extras = restarted by the system (sticky restart, always-on VPN):
        // reconnect with the last params the app or widget used.
        val p = ConnectParams.fromIntent(intent) ?: VpnWidgetProvider.loadConnectParams(this)
        if (p == null) {
            Log.w(TAG, "No config to connect with — stopping")
            stopSelf()
            return START_NOT_STICKY
        }
        VpnWidgetProvider.saveConnectParams(this, p)

        // Already up (or coming up) with the same settings — nothing to do.
        if (p == params && state in setOf("connected", "connecting", "reconnecting")) {
            Log.i(TAG, "Start request for the running session — ignoring")
            ensureForeground()
            return START_STICKY
        }
        startSession(p)
        return START_STICKY
    }

    private fun startSession(p: ConnectParams) {
        val gen = sessionGen.incrementAndGet()
        cancelPendingRetry()
        // Abort whatever a previous session was still doing; its thread sees
        // the bumped generation and exits quietly.
        try { Vpnlib.disconnect() } catch (_: Exception) {}

        params = p
        attempt = 0
        retryStopped = false
        stopped = false
        Log.i(TAG, "Session $gen: killSwitch=${p.killSwitch} split=${p.splitMode}/${p.splitApps.size}")

        Vpnlib.setProtector(this)
        emit("connecting")
        ensureForeground()
        registerNetworkCallback()
        launchAttempt(gen, p)
    }

    /** One Preflight → TUN → RunTunnel cycle on its own thread. */
    private fun launchAttempt(gen: Int, p: ConnectParams) {
        Thread({
            var error: String? = null
            try {
                runAttempt(gen, p)
            } catch (e: Exception) {
                error = e.message ?: e.toString()
                Log.w(TAG, "Session $gen attempt ended: $error")
            }
            main.post { onAttemptEnded(gen, error) }
        }, "vpn-session-$gen").start()
    }

    private fun runAttempt(gen: Int, p: ConnectParams) {
        // Whoever bumps the generation also calls Vpnlib.disconnect(), which
        // cancels this preflight or drops its pending session — a stale thread
        // must not call it itself, or it would hit the newer session.
        val prefix = Vpnlib.preflight(p.config)
        if (gen != sessionGen.get()) return
        if (prefix.startsWith("error:")) throw Exception(prefix.removePrefix("error:").trim())

        val slash = prefix.lastIndexOf('/')
        val ip = if (slash > 0) prefix.substring(0, slash) else throw Exception("bad assigned prefix: $prefix")
        val bits = prefix.substring(slash + 1).toIntOrNull() ?: throw Exception("bad assigned prefix: $prefix")

        val goFd: Int = synchronized(ifaceLock) {
            // Re-checked under the lock: userDisconnect bumps the generation and
            // then closes the interface under this same lock, so an interface
            // created here is never orphaned.
            if (gen != sessionGen.get()) return
            val existing = vpnInterface
            if (p.killSwitch && existing != null && ifacePrefix == prefix) {
                // Kill-switch retry: the old TUN kept blocking traffic during the
                // outage; keep it rather than opening a leak window.
                Log.d(TAG, "Reusing TUN for $prefix")
            } else {
                val iface = buildInterface(p, ip, bits)
                    ?: throw Exception("VPN interface could not be created")
                vpnInterface = iface
                ifacePrefix = prefix
                // A new interface replaces the old one atomically; only now is
                // it safe to release the previous fd.
                try { existing?.close() } catch (_: Exception) {}
            }
            ParcelFileDescriptor.dup(vpnInterface!!.fileDescriptor).detachFd()
        }

        main.post {
            if (gen == sessionGen.get()) {
                attempt = 0
                emit("connected")
            }
        }
        Vpnlib.runTunnel(goFd.toLong()) // returns only when the tunnel ends
    }

    private fun buildInterface(p: ConnectParams, ip: String, bits: Int): ParcelFileDescriptor? {
        val builder = Builder()
            .setSession(getString(R.string.app_name))
            .addAddress(ip, bits)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
            .setMtu(MTU)

        // The server only carries IPv4. Capture IPv6 as well so it cannot leak
        // around the tunnel on dual-stack networks; vpnlib drops it. A ULA
        // address is not "global", so Android stops handing out AAAA answers
        // and apps don't even try IPv6.
        try {
            builder.addAddress("fd00:7a:7a::2", 128)
            builder.addRoute("::", 0)
        } catch (e: Exception) {
            Log.w(TAG, "IPv6 capture unavailable: ${e.message}")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        // Keep the VPN server's own address out of the tunnel so management/OTA
        // traffic to it (in-app update check on :8443) still reaches it.
        // excludeRoute needs Android 13+.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val host = serverHost(Vpnlib.activeServer().ifEmpty { configServer(p.config) })
            if (host != null) {
                try {
                    val addr = InetAddress.getByName(host)
                    builder.excludeRoute(IpPrefix(addr, if (addr.address.size == 4) 32 else 128))
                } catch (e: Exception) {
                    Log.w(TAG, "Could not exclude server $host from routes: ${e.message}")
                }
            }
        }

        applySplitTunnelRules(
            mode = p.splitMode,
            apps = p.splitApps,
            ownPackage = packageName,
            addAllowed = { pkg ->
                try { builder.addAllowedApplication(pkg) }
                catch (e: Exception) { Log.w(TAG, "split allowlist: skip $pkg — ${e.message}") }
            },
            addDisallowed = { pkg ->
                try { builder.addDisallowedApplication(pkg) }
                catch (e: Exception) { Log.w(TAG, "split blocklist: skip $pkg — ${e.message}") }
            },
        )
        return builder.establish()
    }

    private fun configServer(config: String): String =
        try { org.json.JSONObject(config).optString("server", "") } catch (_: Exception) { "" }

    private fun serverHost(server: String): String? {
        if (server.isEmpty()) return null
        val idx = server.lastIndexOf(':')
        return (if (idx > 0) server.substring(0, idx) else server).ifEmpty { null }
    }

    /** Main looper. Decides what follows an attempt that ended on its own. */
    private fun onAttemptEnded(gen: Int, error: String?) {
        if (gen != sessionGen.get() || stopped) return // user disconnected / newer session
        val p = params ?: return
        val kind = try { Vpnlib.lastErrorKind() } catch (_: Exception) { "transient" }
        Log.i(TAG, "Session $gen attempt ended: kind=$kind error=$error")

        val decision = decideRetry(
            autoReconnect = true,
            retryStopped = retryStopped,
            kind = if (kind == "none" && error != null) "transient" else kind,
            currentAttempt = attempt,
            maxRetries = MAX_RETRIES,
            maxBackoffSeconds = MAX_BACKOFF_SECONDS,
        )
        if (decision.latchStopped) retryStopped = true

        if (decision.shouldRetry) {
            attempt = decision.nextAttempt
            if (!p.killSwitch) closeInterface()
            emit("reconnecting", attempt = attempt, max = MAX_RETRIES)
            scheduleRetry(gen, decision.delayMs)
            return
        }
        if (decision.reason == "clean-disconnect") {
            stopSession("disconnected")
            return
        }

        val errorKind = if (decision.reason == "auth-rejected") "auth" else kind
        val message = if (decision.reason == "auth-rejected") "auth rejected" else error ?: "connection failed"
        if (p.killSwitch) {
            // Hold the dead TUN so nothing leaks; the user unblocks by
            // disconnecting. A returning network gets one more round of retries.
            Log.i(TAG, "Kill switch: holding TUN after final failure ($message)")
            emit("error", errorKind = errorKind, errorMessage = "blocked (kill switch)")
            return
        }
        stopSession("error", errorKind = errorKind, errorMessage = message)
    }

    private fun scheduleRetry(gen: Int, delayMs: Long) {
        cancelPendingRetry()
        val r = Runnable {
            pendingRetry = null
            val p = params
            if (gen == sessionGen.get() && !stopped && p != null) {
                emit("reconnecting", attempt = attempt, max = MAX_RETRIES)
                launchAttempt(gen, p)
            }
        }
        pendingRetry = r
        main.postDelayed(r, delayMs)
        Log.i(TAG, "Retry $attempt/$MAX_RETRIES in ${delayMs}ms")
    }

    private fun cancelPendingRetry() {
        pendingRetry?.let { main.removeCallbacks(it) }
        pendingRetry = null
    }

    /** A deliberate stop: app button, widget, notification action, revoke. */
    private fun userDisconnect() {
        Log.i(TAG, "User disconnect")
        sessionGen.incrementAndGet()
        try { Vpnlib.disconnect() } catch (e: Exception) { Log.w(TAG, "Vpnlib.disconnect: ${e.message}") }
        stopSession("disconnected")
    }

    /** Tears the service down and publishes the final state. */
    private fun stopSession(finalState: String, errorKind: String? = null, errorMessage: String? = null) {
        if (stopped) return
        stopped = true
        cancelPendingRetry()
        unregisterNetworkCallback()
        closeInterface()
        params = null
        if (foreground) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            foreground = false
        }
        emit(finalState, errorKind = errorKind, errorMessage = errorMessage)
        stopSelf()
    }

    private fun closeInterface() {
        synchronized(ifaceLock) {
            try { vpnInterface?.close() } catch (e: Exception) { Log.w(TAG, "close TUN: ${e.message}") }
            vpnInterface = null
            ifacePrefix = null
        }
    }

    // --- Network changes -------------------------------------------------------

    /**
     * Watches the underlying (non-VPN) networks. When one comes up while we are
     * waiting out a backoff, retry now instead of at the end of the delay; when
     * the kill switch is holding traffic after giving up, try again once.
     */
    private fun registerNetworkCallback() {
        if (networkCallback != null) return
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                main.post { onUnderlyingNetworkAvailable() }
            }
        }
        try {
            cm.registerNetworkCallback(request, cb)
            networkCallback = cb
        } catch (e: Exception) {
            Log.w(TAG, "registerNetworkCallback failed: ${e.message}")
        }
    }

    private fun onUnderlyingNetworkAvailable() {
        if (stopped) return
        val p = params ?: return
        val gen = sessionGen.get()
        when {
            state == "reconnecting" && pendingRetry != null -> {
                Log.i(TAG, "Network available — retrying now")
                scheduleRetry(gen, 500)
            }
            state == "error" && p.killSwitch && lastStatus["errorKind"] == "transient" -> {
                Log.i(TAG, "Network available — kill switch holding, trying again")
                attempt = 1
                retryStopped = false
                emit("reconnecting", attempt = attempt, max = MAX_RETRIES)
                scheduleRetry(gen, 500)
            }
        }
    }

    private fun unregisterNetworkCallback() {
        val cb = networkCallback ?: return
        networkCallback = null
        try {
            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(cb)
        } catch (_: Exception) {}
    }

    // --- Status + notification -------------------------------------------------

    private fun emit(
        state: String,
        attempt: Int? = null,
        max: Int? = null,
        errorKind: String? = null,
        errorMessage: String? = null,
    ) {
        val map = mutableMapOf<String, Any?>("state" to state)
        attempt?.let { map["attempt"] = it }
        max?.let { map["max"] = it }
        errorKind?.let { map["errorKind"] = it }
        errorMessage?.let { map["errorMessage"] = it }
        lastStatus = map
        Log.d(TAG, "status → $map")
        VpnPlugin.emitStatus(map)
        try { VpnWidgetProvider.refresh(applicationContext, state) } catch (e: Exception) {
            Log.w(TAG, "widget refresh failed: ${e.message}")
        }
        if (foreground) notify(notificationText(map))
    }

    private fun notificationText(s: Map<String, Any?>): String = when (s["state"]) {
        "connected" -> "Подключено"
        "reconnecting" -> "Переподключение… (попытка ${s["attempt"]}/${s["max"]})"
        "error" -> if (params?.killSwitch == true) "Нет связи с сервером — трафик заблокирован"
                   else "Ошибка подключения"
        else -> "Подключение…"
    }

    private fun ensureForeground() {
        if (foreground) return
        startForeground(NOTIFICATION_ID, buildNotification(notificationText(lastStatus)))
        foreground = true
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Статус VPN", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, immutable or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val stop = PendingIntent.getService(
            this, 1,
            Intent(this, SimpleVpnService::class.java).setAction(ACTION_DISCONNECT),
            immutable or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        @Suppress("DEPRECATION")
        return builder
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(0, "Отключить", stop)
            .build()
    }

    private fun notify(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(text))
    }

    override fun onRevoke() {
        // Another VPN app took over, or the user revoked us in system settings.
        Log.i(TAG, "VPN permission revoked")
        userDisconnect()
    }

    override fun onDestroy() {
        if (!stopped) {
            sessionGen.incrementAndGet()
            try { Vpnlib.disconnect() } catch (_: Exception) {}
            stopSession("disconnected")
        }
        super.onDestroy()
    }
}
