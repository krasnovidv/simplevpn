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
import android.os.ParcelFileDescriptor
import android.util.Log
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

        var currentStatus: String = "disconnected"
        private var vpnInterface: ParcelFileDescriptor? = null
        private var configJson: String? = null
        private var autoReconnect: Boolean = false
        private var killSwitch: Boolean = false
        private var connectThread: Thread? = null
    }

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var reconnectAttempt: Int = 0
    private val maxReconnectDelay: Long = 60_000 // 60 seconds max

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
        Log.d(TAG, "Config received, length=${configJson!!.length}, autoReconnect=$autoReconnect, killSwitch=$killSwitch")

        connect(configJson!!)
        return START_STICKY
    }

    private fun connect(config: String) {
        // Guard: don't re-establish if Go side is already connected.
        // Re-calling builder.establish() invalidates the old TUN fd and kills the tunnel.
        val goStatus = try { Vpnlib.status() } catch (_: Exception) { null }
        if (goStatus == "connected" || goStatus == "connecting") {
            Log.i(TAG, "connect() called but Go is already $goStatus — skipping")
            currentStatus = goStatus
            return
        }

        // Disconnect any stale Go-side connection before starting a new one
        try { Vpnlib.disconnect() } catch (_: Exception) {}

        currentStatus = "connecting"
        val configPreview = if (config.length > 100) config.take(100) + "..." else config
        Log.i(TAG, "Starting VPN connection, config length=${config.length}")
        Log.d(TAG, "Config preview (may contain masked data): $configPreview")

        try {
            // Start as foreground service (required for Android 8+)
            startForeground(NOTIFICATION_ID, buildNotification("Connecting..."))
            Log.d(TAG, "Foreground service started")

            // Create TUN interface
            val builder = Builder()
                .setSession("SimpleVPN")
                .addAddress("10.0.0.2", 24)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")
                .setMtu(1380)
                .setBlocking(true)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            Log.d(TAG, "TUN builder: address=10.0.0.2/24, routes=0.0.0.0/0, dns=1.1.1.1+8.8.8.8, mtu=1380")
            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                Log.e(TAG, "builder.establish() returned null — VPN permission may not be granted")
                throw Exception("Failed to create TUN interface (establish returned null)")
            }
            val fd = vpnInterface!!.fd

            Log.i(TAG, "TUN interface created, fd=$fd")

            // Set socket protector so Go can protect the VPN socket from TUN routing
            Log.d(TAG, "Setting socket protector on Vpnlib")
            Vpnlib.setProtector(this)

            // Vpnlib.connect() is blocking — run on a background thread
            connectThread = Thread({
                try {
                    Log.d(TAG, "Calling Vpnlib.connect() on background thread")
                    Vpnlib.connect(config, fd.toLong())
                    // connect() returns when tunnel closes normally
                    Log.i(TAG, "Vpnlib.connect() returned normally")
                } catch (e: Exception) {
                    Log.e(TAG, "Vpnlib.connect() error: ${e.message}", e)
                    currentStatus = "error: ${e.message}"
                } finally {
                    Log.d(TAG, "Connect thread finished, cleaning up (killSwitch=$killSwitch)")
                    if (killSwitch) {
                        // Keep TUN open to block all traffic (kill switch)
                        Log.i(TAG, "Kill switch active — keeping TUN interface to block traffic")
                        updateNotification("VPN disconnected — traffic blocked (kill switch)")
                        currentStatus = "disconnected"
                    } else {
                        vpnInterface?.close()
                        vpnInterface = null
                        if (currentStatus != "disconnected") {
                            currentStatus = "disconnected"
                        }
                        updateNotification("Disconnected")
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        stopSelf()
                    }
                }
            }, "vpnlib-connect")
            connectThread!!.start()

            // NOTE: Do NOT set currentStatus = "connected" here!
            // Status stays "connecting" until Go-side confirms via Vpnlib.status()
            Log.i(TAG, "VPN tunnel thread started, status remains 'connecting' until Go confirms")
            updateNotification("Connecting...")
            reconnectAttempt = 0 // Reset backoff on new connection attempt

            if (autoReconnect && networkCallback == null) {
                setupNetworkMonitoring()
            }
        } catch (e: Exception) {
            Log.e(TAG, "VPN connect failed: ${e.message}", e)
            currentStatus = "error: ${e.message}"
            disconnect()
        }
    }

    private fun disconnect() {
        Log.i(TAG, "Disconnecting VPN")

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
                Log.i(TAG, "Network available, checking VPN status")
                // Always check Go-side status — Kotlin currentStatus may be stale
                if (!isGoConnected() && configJson != null) {
                    val delay = calculateBackoff()
                    Log.i(TAG, "Auto-reconnecting in ${delay}ms (attempt $reconnectAttempt)")
                    updateNotification("Reconnecting in ${delay / 1000}s...")
                    Thread {
                        Thread.sleep(delay)
                        if (!isGoConnected() && configJson != null) {
                            reconnectAttempt++
                            connect(configJson!!)
                        }
                    }.start()
                } else {
                    Log.i(TAG, "Network available but VPN still active — no reconnect needed")
                }
            }

            override fun onLost(network: Network) {
                Log.i(TAG, "Network lost, checking Go-side VPN status")
                // Don't blindly set disconnected — the VPN tunnel may still be alive.
                // VPN establishment itself triggers onLost for the physical network.
                if (!isGoConnected()) {
                    currentStatus = "disconnected"
                    updateNotification("Waiting for network...")
                } else {
                    Log.i(TAG, "Network lost but Go tunnel still active — ignoring")
                }
            }
        }

        cm.registerDefaultNetworkCallback(networkCallback!!)
        Log.i(TAG, "Network monitoring enabled for auto-reconnect")
    }

    private fun calculateBackoff(): Long {
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, 60s max
        val delay = (1000L * (1L shl reconnectAttempt.coerceAtMost(5))).coerceAtMost(maxReconnectDelay)
        return delay
    }

    private fun removeNetworkMonitoring() {
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
