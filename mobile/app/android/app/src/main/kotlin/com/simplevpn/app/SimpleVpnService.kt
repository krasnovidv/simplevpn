package com.simplevpn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import vpnlib.Vpnlib

class SimpleVpnService : VpnService(), vpnlib.SocketProtector {

    // Implement Go's SocketProtector interface.
    // This protects the VPN socket from being routed through the TUN.
    override fun protectSocket(fd: Int): Boolean {
        val ok = protect(fd) // calls VpnService.protect(int)
        Log.d(TAG, "protectSocket(fd=$fd) = $ok")
        return ok
    }

    companion object {
        const val TAG = "SimpleVPN"
        const val NOTIFICATION_ID = 1
        const val CHANNEL_ID = "simplevpn_channel"

        const val DEFAULT_MAX_RETRIES = 5
        const val DEFAULT_MAX_BACKOFF_SECONDS = 60

        var currentStatus: String = "disconnected"
        private var vpnInterface: ParcelFileDescriptor? = null
        private var configJson: String? = null
        private var autoReconnect: Boolean = false
        private var killSwitch: Boolean = false
        private var connectThread: Thread? = null
        private var maxRetries: Int = DEFAULT_MAX_RETRIES
        private var maxBackoffSeconds: Int = DEFAULT_MAX_BACKOFF_SECONDS
        private var splitTunnelMode: String = "off"
        private var splitTunnelApps: List<String> = emptyList()

        /**
         * Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, then capped at maxBackoffSeconds.
         * Pure function — exposed at companion scope so unit tests can call it directly.
         */
        @JvmStatic
        fun calculateBackoff(attempt: Int, maxBackoffSeconds: Int = DEFAULT_MAX_BACKOFF_SECONDS): Long {
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
         * and the current retry-state. Side-effect-free — caller applies the decision
         * (set status, increment counter, postDelayed, etc.).
         *
         * Contract — this is the auth-short-circuit and max-retries logic that Phase 4
         * Task 3 requires. Patches `2026-03-09-15.10` and `2026-03-09-18.30` are not
         * regressed because no establish() / TUN handling lives here.
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

    private fun emitStructuredStatus(
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
        VpnPlugin.emitStatus(map)
    }

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // Atomic so the connect-thread (writes), main-looper retry runnables (reads),
    // and network callbacks (reads) can race without locks.
    private val reconnectAttempt = AtomicInteger(0)

    // Set to true after auth/fatal classification or maxRetries exhaustion.
    // Latches off the retry loop until the next user-initiated Connect.
    private val retryStopped = AtomicBoolean(false)

    // [FIX] Prevent concurrent connect() calls and debounce network callbacks
    private val isConnecting = AtomicBoolean(false)
    private val reconnectHandler = Handler(Looper.getMainLooper())
    private var pendingReconnect: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")

        when (intent?.action) {
            "DISCONNECT" -> {
                disconnect()
                return START_NOT_STICKY
            }
            "ENABLE_KILL_SWITCH" -> {
                return START_STICKY
            }
        }

        configJson = intent?.getStringExtra("config") ?: run {
            Log.w(TAG, "No config in intent, stopping")
            return START_NOT_STICKY
        }
        autoReconnect = intent.getBooleanExtra("auto_reconnect", false)
        killSwitch = intent.getBooleanExtra("kill_switch", false)
        maxRetries = intent.getIntExtra("max_retries", DEFAULT_MAX_RETRIES)
        maxBackoffSeconds = intent.getIntExtra("max_backoff_seconds", DEFAULT_MAX_BACKOFF_SECONDS)
        splitTunnelMode = intent.getStringExtra("split_tunnel_mode") ?: "off"
        splitTunnelApps = intent.getStringArrayListExtra("split_tunnel_apps") ?: emptyList()
        Log.d(TAG, "Config received, length=${configJson!!.length}, autoReconnect=$autoReconnect, " +
                "killSwitch=$killSwitch, maxRetries=$maxRetries, maxBackoffSeconds=$maxBackoffSeconds, " +
                "splitMode=$splitTunnelMode, splitApps=${splitTunnelApps.size}")

        // User-initiated start — clear any stop-latch from previous session.
        retryStopped.set(false)
        reconnectAttempt.set(0)

        connect(configJson!!)
        return START_STICKY
    }

    private fun connect(config: String) {
        // [FIX] Prevent concurrent connect() calls using AtomicBoolean
        if (!isConnecting.compareAndSet(false, true)) {
            Log.i(TAG, "[FIX] connect() called but another connect is in progress — skipping")
            return
        }

        // Guard: don't re-establish if Go side is already connected.
        // Re-calling builder.establish() invalidates the old TUN fd and kills the tunnel.
        val goStatus = try { Vpnlib.status() } catch (_: Exception) { null }
        if (goStatus == "connected" || goStatus == "connecting") {
            Log.i(TAG, "connect() called but Go is already $goStatus — skipping")
            currentStatus = goStatus
            isConnecting.set(false)
            return
        }

        // Disconnect any stale Go-side connection before starting a new one
        try { Vpnlib.disconnect() } catch (_: Exception) {}

        currentStatus = "connecting"
        emitStructuredStatus("connecting")
        val configPreview = if (config.length > 100) config.take(100) + "..." else config
        Log.i(TAG, "Starting VPN connection, config length=${config.length}")
        Log.d(TAG, "Config preview (may contain masked data): $configPreview")

        try {
            // Start as foreground service (required for Android 8+)
            startForeground(NOTIFICATION_ID, buildNotification("Connecting..."))
            Log.d(TAG, "Foreground service started")

            // Set socket protector so Go can protect the VPN socket from TUN routing
            Vpnlib.setProtector(this)

            // Preflight + RunTunnel run on a background thread.
            // Preflight authenticates and returns the server-assigned IP prefix.
            // RunTunnel builds the TUN interface with that IP and starts the relay.
            connectThread = Thread({
                try {
                    Log.d(TAG, "Calling Vpnlib.preflight() on background thread")
                    val prefix = Vpnlib.preflight(config)
                    if (prefix.startsWith("error:")) {
                        throw Exception(prefix.removePrefix("error:").trim())
                    }

                    // Parse "10.0.0.2/24" → ip="10.0.0.2", prefixLen=24
                    val slashIdx = prefix.lastIndexOf('/')
                    if (slashIdx < 0) throw Exception("Invalid assigned prefix: $prefix")
                    val ip = prefix.substring(0, slashIdx)
                    val prefixLen = prefix.substring(slashIdx + 1).toIntOrNull()
                        ?: throw Exception("Invalid prefix length in: $prefix")

                    Log.i(TAG, "Preflight OK, assigned=$prefix")

                    // [Patch 2026-03-09-18.30] When kill switch is active and we already have
                    // a valid TUN, reuse its fd rather than calling builder.establish() again.
                    // A second establish() would invalidate the live fd while Go is reading/writing
                    // it, causing a native crash. The existing TUN continues to block all traffic
                    // during the retry window — preserving the kill-switch guarantee.
                    val fd: Int
                    val existingIface = vpnInterface
                    if (killSwitch && existingIface != null) {
                        fd = existingIface.fd
                        Log.d(TAG, "Kill-switch retry: reusing existing TUN fd=$fd (skipping establish)")
                    } else {
                        val builder = Builder()
                            .setSession("SimpleVPN")
                            .addAddress(ip, prefixLen)
                            .addRoute("0.0.0.0", 0)
                            .addDnsServer("1.1.1.1")
                            .addDnsServer("8.8.8.8")
                            .setMtu(1380)
                            .setBlocking(true)

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            builder.setMetered(false)
                        }

                        // Apply split-tunnel rules via pure companion helper (testable without Android framework).
                        val ownPkg = applicationContext.packageName
                        Log.d(TAG, "Split-tunnel apply: mode=$splitTunnelMode apps=${splitTunnelApps.size} ownPkg=$ownPkg")
                        applySplitTunnelRules(
                            mode = splitTunnelMode,
                            apps = splitTunnelApps,
                            ownPackage = ownPkg,
                            addAllowed = { pkg ->
                                try { builder.addAllowedApplication(pkg); Log.d(TAG, "ST allowlist: +$pkg") }
                                catch (e: Exception) { Log.w(TAG, "ST allowlist: skip $pkg — ${e.message}") }
                            },
                            addDisallowed = { pkg ->
                                try { builder.addDisallowedApplication(pkg); Log.d(TAG, "ST blocklist: -$pkg") }
                                catch (e: Exception) { Log.w(TAG, "ST blocklist: skip $pkg — ${e.message}") }
                            },
                        )

                        Log.d(TAG, "TUN builder: address=$prefix, routes=0.0.0.0/0, dns=1.1.1.1+8.8.8.8, mtu=1380, splitMode=$splitTunnelMode")
                        val iface = builder.establish()
                            ?: throw Exception("Failed to create TUN interface (establish returned null)")
                        vpnInterface = iface
                        fd = iface.fd
                        Log.i(TAG, "New TUN interface created, fd=$fd assigned=$prefix killSwitch=$killSwitch")
                    }

                    // Reaching here means Preflight + establish succeeded; the connection
                    // is effectively up. Reset retry state so a subsequent transient drop
                    // starts the backoff at attempt 1.
                    reconnectAttempt.set(0)
                    emitStructuredStatus("connected")
                    Log.d(TAG, "Connection established — reset retry counter")

                    // RunTunnel blocks until the tunnel closes.
                    Log.d(TAG, "Calling Vpnlib.runTunnel(fd=$fd)")
                    Vpnlib.runTunnel(fd.toLong())
                    Log.i(TAG, "Vpnlib.runTunnel() returned normally")

                } catch (e: Exception) {
                    Log.e(TAG, "VPN connect failed: ${e.message}", e)
                    currentStatus = "error: ${e.message}"
                } finally {
                    // [FIX] Release connect lock so future connects can proceed
                    isConnecting.set(false)
                    Log.d(TAG, "[FIX] isConnecting released")

                    val retryScheduled = scheduleRetryIfNeeded()
                    Log.d(TAG, "Connect thread finished: retryScheduled=$retryScheduled killSwitch=$killSwitch")

                    if (retryScheduled) {
                        // Keep service alive; status was set to "connecting (retry N/M)".
                        // [FIX/Patch 2026-03-09-18.30] Close the existing TUN before next
                        // connect() establishes a new one. Task 9 will switch to TUN reuse
                        // when killSwitch=true; for now, killSwitch keeps TUN open and the
                        // next connect() will see Go-status=disconnected and proceed.
                        if (!killSwitch) {
                            vpnInterface?.close()
                            vpnInterface = null
                        }
                        updateNotification("Reconnecting...")
                    } else if (killSwitch) {
                        val fd = vpnInterface?.fd ?: -1
                        Log.i(TAG, "Kill switch active — keeping TUN fd=$fd to block all traffic (final failure)")
                        updateNotification("VPN disconnected — traffic blocked (kill switch)")
                        currentStatus = "error: blocked (kill switch)"
                        emitStructuredStatus("error", errorKind = "fatal", errorMessage = "blocked (kill switch)")
                    } else {
                        vpnInterface?.close()
                        vpnInterface = null
                        if (!currentStatus.startsWith("error:")) {
                            currentStatus = "disconnected"
                        }
                        updateNotification("Disconnected")
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        stopSelf()
                    }
                }
            }, "vpnlib-connect")
            connectThread!!.start()

            // Status stays "connecting" until Go-side confirms via Vpnlib.status()
            Log.i(TAG, "VPN tunnel thread started, status remains 'connecting' until Go confirms")
            updateNotification("Connecting...")
            // (retry counter is reset on user-initiated start in onStartCommand and on
            // successful establish() inside the connect-thread; do not reset here or
            // retry-initiated reconnects would clobber the attempt count.)

            if (autoReconnect && networkCallback == null) {
                setupNetworkMonitoring()
            }
        } catch (e: Exception) {
            Log.e(TAG, "VPN connect failed: ${e.message}", e)
            currentStatus = "error: ${e.message}"
            isConnecting.set(false)
            disconnect()
        }
    }

    private fun disconnect() {
        Log.i(TAG, "Disconnecting VPN")

        // Latch the retry loop off — any in-flight RunTunnel that returns after
        // this point will see retryStopped=true and not schedule another attempt.
        retryStopped.set(true)

        removeNetworkMonitoring()

        try {
            Log.d(TAG, "Calling Vpnlib.disconnect()")
            Vpnlib.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Vpnlib.disconnect() error: ${e.message}", e)
        }

        vpnInterface?.close()
        vpnInterface = null
        connectThread = null
        currentStatus = "disconnected"
        emitStructuredStatus("disconnected")
        Log.d(TAG, "VPN disconnected, status=disconnected")

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun isGoConnected(): Boolean {
        val goStatus = try { Vpnlib.status() } catch (_: Exception) { null }
        return goStatus == "connected" || goStatus == "connecting"
    }

    private fun setupNetworkMonitoring() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.i(TAG, "[FIX] Network available, debouncing reconnect check")
                // [FIX/Patch 2026-03-09-18.30] Debounce 500ms so rapid WiFi↔cellular
                // flapping doesn't spawn a flood of reconnects.
                if (retryStopped.get()) {
                    Log.i(TAG, "Retry loop stopped (auth/fatal/exhausted) — ignoring onAvailable")
                    return
                }
                pendingReconnect?.let { reconnectHandler.removeCallbacks(it) }
                pendingReconnect = Runnable {
                    Log.i(TAG, "[FIX] Debounced onAvailable executing")
                    // [FIX/Patch 2026-03-09-15.10] Use Go-side status as source of truth.
                    // onAvailable fires during VPN establishment too — never reconnect
                    // if Go reports we're already up.
                    if (!isGoConnected() && configJson != null && !retryStopped.get()) {
                        // Network came back during a backoff window — fire the retry now
                        // instead of waiting out the backoff.
                        Log.i(TAG, "Network available — firing pending retry early")
                        scheduleRetryIfNeeded(immediate = true)
                    } else {
                        Log.d(TAG, "onAvailable: Go connected or stop-latched — no action")
                    }
                }
                reconnectHandler.postDelayed(pendingReconnect!!, 500)
            }

            override fun onLost(network: Network) {
                Log.i(TAG, "Network lost, checking Go-side VPN status")
                // [FIX/Patch 2026-03-09-15.10] VPN establishment itself triggers
                // onLost for the physical network. Don't flip status to disconnected
                // unless Go agrees the tunnel is down.
                if (!isGoConnected()) {
                    if (!currentStatus.startsWith("error:") && !currentStatus.startsWith("connecting")) {
                        currentStatus = "disconnected"
                    }
                    updateNotification("Waiting for network...")
                } else {
                    Log.i(TAG, "Network lost but Go tunnel still active — ignoring")
                }
            }
        }

        cm.registerDefaultNetworkCallback(networkCallback!!)
        Log.i(TAG, "Network monitoring enabled for auto-reconnect")
    }

    /**
     * Decide whether to schedule another connect attempt after the current one
     * exited (success-disconnect, transient error, auth rejection, or fatal).
     *
     * Consults [Vpnlib.lastErrorKind] to drive the decision:
     *   - "auth"      → latch [retryStopped], no further attempts (status=auth rejected)
     *   - "fatal"     → latch [retryStopped], no further attempts
     *   - "transient" → schedule next attempt with exponential backoff if attempt < maxRetries
     *   - "none"      → clean disconnect, no retry
     *
     * Returns true if a retry was scheduled (caller should keep service alive),
     * false otherwise (caller should stop or hold per kill-switch policy).
     *
     * @param immediate If true, fire the retry on the next loop tick instead of
     *   waiting for the full backoff. Used by [setupNetworkMonitoring]'s
     *   onAvailable to short-circuit the wait when network comes back.
     */
    private fun scheduleRetryIfNeeded(immediate: Boolean = false): Boolean {
        val kind = try {
            Vpnlib.lastErrorKind()
        } catch (e: Exception) {
            Log.w(TAG, "Vpnlib.lastErrorKind() failed: ${e.message} — defaulting to transient")
            "transient"
        }

        val decision = decideRetry(
            autoReconnect = autoReconnect,
            retryStopped = retryStopped.get(),
            kind = kind,
            currentAttempt = reconnectAttempt.get(),
            maxRetries = maxRetries,
            maxBackoffSeconds = maxBackoffSeconds,
            immediate = immediate,
        )
        Log.i(TAG, "scheduleRetry decision: $decision (kind=$kind)")

        if (decision.latchStopped) retryStopped.set(true)
        decision.statusOverride?.let {
            // Don't trample an existing fatal-error status with a generic one.
            if (decision.reason == "fatal" && currentStatus.startsWith("error:")) {
                // Keep currentStatus as the more-specific Go-side error message.
            } else {
                currentStatus = it
            }
        }

        if (!decision.shouldRetry) {
            when (decision.reason) {
                "auth-rejected" -> {
                    updateNotification("VPN error: authentication rejected")
                    emitStructuredStatus("error", errorKind = "auth", errorMessage = "auth rejected")
                }
                "fatal" -> {
                    updateNotification("VPN error: fatal")
                    emitStructuredStatus("error", errorKind = "fatal")
                }
                "max-retries-exceeded" -> {
                    updateNotification("VPN error: max retries exceeded")
                    emitStructuredStatus("error", errorKind = "transient", errorMessage = "max retries exceeded")
                }
                else -> { /* clean-disconnect / autoreconnect-off / already-stopped: caller updates */ }
            }
            return false
        }

        // Persist the new attempt counter for follow-up callbacks (onAvailable etc.).
        reconnectAttempt.set(decision.nextAttempt)
        emitStructuredStatus("reconnecting", attempt = decision.nextAttempt, max = maxRetries)

        updateNotification(
            if (immediate) "Reconnecting (attempt ${decision.nextAttempt}/$maxRetries)..."
            else "Reconnecting in ${decision.delayMs / 1000}s (attempt ${decision.nextAttempt}/$maxRetries)"
        )
        Log.i(TAG, "Scheduling retry ${decision.nextAttempt}/$maxRetries in ${decision.delayMs}ms (kind=$kind, immediate=$immediate)")

        // Cancel any outstanding pending reconnect to avoid double-fire.
        pendingReconnect?.let { reconnectHandler.removeCallbacks(it) }
        pendingReconnect = Runnable {
            // [FIX/Patch 2026-03-09-18.30] Re-check Go status before establish().
            // If Go came back to "connected" via some other path, never call establish() again.
            if (retryStopped.get()) {
                Log.i(TAG, "Retry runnable: stop-latched, aborting")
                return@Runnable
            }
            if (configJson == null) {
                Log.w(TAG, "Retry runnable: configJson is null, aborting")
                return@Runnable
            }
            if (isGoConnected()) {
                Log.i(TAG, "Retry runnable: Go already connected, skipping connect()")
                return@Runnable
            }
            connect(configJson!!)
        }
        reconnectHandler.postDelayed(pendingReconnect!!, decision.delayMs)
        return true
    }

    private fun removeNetworkMonitoring() {
        // [FIX] Cancel any pending debounced reconnect
        pendingReconnect?.let { reconnectHandler.removeCallbacks(it) }
        reconnectHandler.removeCallbacksAndMessages(null)
        pendingReconnect = null

        networkCallback?.let {
            networkCallback = null
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.unregisterNetworkCallback(it)
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "NetworkCallback was not registered, ignoring")
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SimpleVPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN connection status"
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("SimpleVPN")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("SimpleVPN")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setOngoing(true)
                .build()
        }
    }

    private fun updateNotification(text: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, buildNotification(text))
    }

    override fun onDestroy() {
        super.onDestroy()
        disconnect()
    }

    override fun onRevoke() {
        // Called when VPN permission is revoked
        Log.i(TAG, "VPN permission revoked")
        disconnect()
    }
}
