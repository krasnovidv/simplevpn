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

class SimpleVpnService : VpnService() {

    companion object {
        const val TAG = "SimpleVPN"
        const val NOTIFICATION_ID = 1
        const val CHANNEL_ID = "simplevpn_channel"

        var currentStatus: String = "disconnected"
        private var vpnInterface: ParcelFileDescriptor? = null
        private var configJson: String? = null
        private var autoReconnect: Boolean = false
        private var connectThread: Thread? = null
    }

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

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
        Log.d(TAG, "Config received, length=${configJson!!.length}, autoReconnect=$autoReconnect")

        connect(configJson!!)
        return START_STICKY
    }

    private fun connect(config: String) {
        currentStatus = "connecting"
        Log.i(TAG, "Starting VPN connection")

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

            vpnInterface = builder.establish()
            val fd = vpnInterface?.fd ?: throw Exception("Failed to create TUN interface")

            Log.i(TAG, "TUN interface created, fd=$fd")

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
                    Log.d(TAG, "Connect thread finished, cleaning up")
                    vpnInterface?.close()
                    vpnInterface = null
                    if (currentStatus != "disconnected") {
                        currentStatus = "disconnected"
                    }
                    updateNotification("Disconnected")
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }, "vpnlib-connect")
            connectThread!!.start()

            currentStatus = "connected"
            Log.i(TAG, "VPN tunnel thread started")
            updateNotification("Connected")

            if (autoReconnect) {
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
