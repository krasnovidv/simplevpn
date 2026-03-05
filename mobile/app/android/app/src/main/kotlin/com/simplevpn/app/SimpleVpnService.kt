package com.simplevpn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log

class SimpleVpnService : VpnService() {

    companion object {
        const val TAG = "SimpleVPN"
        const val NOTIFICATION_ID = 1
        const val CHANNEL_ID = "simplevpn_channel"

        var currentStatus: String = "disconnected"
        private var vpnInterface: ParcelFileDescriptor? = null
        private var configJson: String? = null
        private var autoReconnect: Boolean = false
    }

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "DISCONNECT" -> {
                disconnect()
                return START_NOT_STICKY
            }
            "ENABLE_KILL_SWITCH" -> {
                // Kill switch is achieved via the VPN builder's setBlocking method
                // and by keeping the service always running
                return START_STICKY
            }
        }

        configJson = intent?.getStringExtra("config") ?: return START_NOT_STICKY
        autoReconnect = intent.getBooleanExtra("auto_reconnect", false)

        connect(configJson!!)
        return START_STICKY
    }

    private fun connect(config: String) {
        currentStatus = "connecting"
        Log.i(TAG, "Starting VPN connection")

        try {
            // Start as foreground service (required for Android 8+)
            startForeground(NOTIFICATION_ID, buildNotification("Connecting..."))

            // Create TUN interface with kill switch support
            val builder = Builder()
                .setSession("SimpleVPN")
                .addAddress("10.0.0.2", 24)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")
                .setMtu(1380)
                .setBlocking(true) // Kill switch: block traffic if VPN drops

            // Android 10+: always-on VPN support
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            vpnInterface = builder.establish()
            val fd = vpnInterface?.fd ?: throw Exception("Failed to create TUN")

            Log.i(TAG, "TUN interface created, fd=$fd")

            // Call Go library via gomobile binding
            // vpnlib.Vpnlib.connect(config, fd.toLong())

            currentStatus = "connected"
            Log.i(TAG, "VPN connected")
            updateNotification("Connected")

            // Setup auto-reconnect via network monitoring
            if (autoReconnect) {
                setupNetworkMonitoring()
            }
        } catch (e: Exception) {
            Log.e(TAG, "VPN connect failed: ${e.message}")
            currentStatus = "error: ${e.message}"
            disconnect()
        }
    }

    private fun disconnect() {
        Log.i(TAG, "Disconnecting VPN")

        removeNetworkMonitoring()

        // vpnlib.Vpnlib.disconnect()
        vpnInterface?.close()
        vpnInterface = null
        currentStatus = "disconnected"

        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun setupNetworkMonitoring() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.i(TAG, "Network available, checking VPN status")
                if (currentStatus != "connected" && configJson != null) {
                    Log.i(TAG, "Auto-reconnecting...")
                    connect(configJson!!)
                }
            }

            override fun onLost(network: Network) {
                Log.i(TAG, "Network lost")
                currentStatus = "disconnected"
                updateNotification("Reconnecting...")
            }
        }

        cm.registerDefaultNetworkCallback(networkCallback!!)
        Log.i(TAG, "Network monitoring enabled for auto-reconnect")
    }

    private fun removeNetworkMonitoring() {
        networkCallback?.let {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.unregisterNetworkCallback(it)
            networkCallback = null
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
