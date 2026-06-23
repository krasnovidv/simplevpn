package com.simplevpn.app

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import vpnlib.Vpnlib
import java.io.ByteArrayOutputStream

class VpnPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    companion object {
        private const val TAG = "SimpleVPN"
        const val CHANNEL_NAME = "com.simplevpn/vpn"
        const val VPN_REQUEST_CODE = 1001

        // Static channel reference so SimpleVpnService can push structured status to Dart.
        private var _channel: MethodChannel? = null

        // Activity-lifetime cache: populated on first listInstalledApps call.
        private var cachedAppList: List<Map<String, String>>? = null

        @JvmStatic
        fun emitStatus(statusMap: Map<String, Any?>) {
            Handler(Looper.getMainLooper()).post {
                _channel?.invokeMethod("onStatusChanged", statusMap)
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        _channel = channel
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        _channel = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "connect" -> {
                val config = call.argument<String>("config") ?: ""
                val autoReconnect = call.argument<Boolean>("auto_reconnect") ?: false
                val killSwitch = call.argument<Boolean>("kill_switch") ?: false
                val reconnectMaxAttempts = call.argument<Int>("reconnect_max_attempts") ?: SimpleVpnService.DEFAULT_MAX_RETRIES
                val reconnectMaxBackoffS = call.argument<Int>("reconnect_max_backoff_s") ?: SimpleVpnService.DEFAULT_MAX_BACKOFF_SECONDS
                val splitMode = call.argument<String>("split_tunnel_mode") ?: "off"
                val splitApps = call.argument<List<String>>("split_tunnel_apps") ?: emptyList()
                startVpn(config, autoReconnect, killSwitch, reconnectMaxAttempts, reconnectMaxBackoffS,
                    splitMode, splitApps, result)
            }
            "disconnect" -> {
                stopVpn(result)
            }
            "cacheWidgetParams" -> {
                // Proactively mirror the current config into the widget's prefs so
                // the home-screen widget can connect without the app being open,
                // even before the first in-app connect of this version.
                val config = call.argument<String>("config") ?: ""
                if (config.isEmpty()) {
                    result.success(false)
                } else {
                    val act = activity
                    if (act == null) {
                        result.error("NO_ACTIVITY", "No activity available", null)
                    } else {
                        VpnWidgetProvider.saveConnectParams(
                            act,
                            config,
                            call.argument<Boolean>("auto_reconnect") ?: false,
                            call.argument<Boolean>("kill_switch") ?: false,
                            call.argument<Int>("reconnect_max_attempts") ?: SimpleVpnService.DEFAULT_MAX_RETRIES,
                            call.argument<Int>("reconnect_max_backoff_s") ?: SimpleVpnService.DEFAULT_MAX_BACKOFF_SECONDS,
                            call.argument<String>("split_tunnel_mode") ?: "off",
                            call.argument<List<String>>("split_tunnel_apps") ?: emptyList(),
                        )
                        result.success(true)
                    }
                }
            }
            "status" -> {
                // Prefer Go-side status (authoritative), fall back to Kotlin-side
                val goStatus = try { Vpnlib.status() } catch (e: Exception) {
                    Log.w(TAG, "Vpnlib.status() failed: ${e.message}")
                    null
                }
                val status = goStatus ?: SimpleVpnService.currentStatus
                Log.d(TAG, "status: go=$goStatus, kotlin=${SimpleVpnService.currentStatus}, returning=$status")
                result.success(status)
            }
            "getLogs" -> {
                val logs = try {
                    Vpnlib.logs()
                } catch (e: Exception) {
                    Log.w(TAG, "Vpnlib.logs() failed: ${e.message}")
                    ""
                }
                if (logs.isNotEmpty()) {
                    Log.d(TAG, "getLogs: returning ${logs.length} chars of Go logs")
                }
                result.success(logs)
            }
            "listInstalledApps" -> listInstalledApps(result)
            "installApk" -> {
                val path = call.argument<String>("path") ?: ""
                installApk(path, result)
            }
            "getStats" -> {
                val stats = try { Vpnlib.getStats() } catch (e: Exception) {
                    Log.w(TAG, "Vpnlib.getStats() failed: ${e.message}")
                    """{"bytes_in":0,"bytes_out":0,"since_ms":0}"""
                }
                Log.d(TAG, "getStats: ${stats.length} bytes")
                result.success(stats)
            }
            else -> result.notImplemented()
        }
    }

    private fun startVpn(
        config: String,
        autoReconnect: Boolean,
        killSwitch: Boolean,
        maxRetries: Int,
        maxBackoffSeconds: Int,
        splitMode: String,
        splitApps: List<String>,
        result: Result,
    ) {
        Log.d(TAG, "startVpn called, config length=${config.length}, autoReconnect=$autoReconnect, " +
                "killSwitch=$killSwitch, maxRetries=$maxRetries, maxBackoffSeconds=$maxBackoffSeconds, " +
                "splitMode=$splitMode, splitApps=${splitApps.size}")
        val act = activity ?: run {
            Log.e(TAG, "startVpn: no activity available")
            result.error("NO_ACTIVITY", "No activity available", null)
            return
        }

        val intent = VpnService.prepare(act)
        if (intent != null) {
            Log.i(TAG, "VPN permission not granted, requesting")
            act.startActivityForResult(intent, VPN_REQUEST_CODE)
            result.error("VPN_PERMISSION", "VPN permission required", null)
            return
        }

        Log.d(TAG, "VPN permission granted, starting service")
        val serviceIntent = Intent(act, SimpleVpnService::class.java).apply {
            putExtra("config", config)
            putExtra("auto_reconnect", autoReconnect)
            putExtra("kill_switch", killSwitch)
            putExtra("max_retries", maxRetries)
            putExtra("max_backoff_seconds", maxBackoffSeconds)
            putExtra("split_tunnel_mode", splitMode)
            putStringArrayListExtra("split_tunnel_apps", ArrayList(splitApps))
        }
        act.startService(serviceIntent)
        result.success(null)
    }

    private fun listInstalledApps(result: Result) {
        val cached = cachedAppList
        if (cached != null) {
            Log.d(TAG, "listInstalledApps: returning cached ${cached.size} apps")
            result.success(cached)
            return
        }

        val act = activity ?: run {
            Log.e(TAG, "listInstalledApps: no activity")
            result.error("NO_ACTIVITY", "No activity available", null)
            return
        }

        // Run on background thread — PackageManager can be slow.
        Thread {
            val pm = act.packageManager
            val ownPackage = act.packageName
            val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                .filter { app ->
                    app.packageName != ownPackage &&
                    ((app.flags and ApplicationInfo.FLAG_SYSTEM) == 0 ||
                     (app.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0)
                }
                .map { app ->
                    val label = try {
                        pm.getApplicationLabel(app).toString()
                    } catch (_: Exception) { app.packageName }

                    val iconBase64 = try {
                        val drawable = pm.getApplicationIcon(app.packageName)
                        val bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                        val canvas = Canvas(bmp)
                        drawable.setBounds(0, 0, 96, 96)
                        drawable.draw(canvas)
                        val out = ByteArrayOutputStream()
                        bmp.compress(Bitmap.CompressFormat.PNG, 80, out)
                        Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
                    } catch (_: Exception) { "" }

                    mapOf("packageName" to app.packageName, "label" to label, "iconBase64" to iconBase64)
                }
                .sortedBy { it["label"] }

            Log.d(TAG, "listInstalledApps: found ${apps.size} user apps")
            cachedAppList = apps
            Handler(Looper.getMainLooper()).post { result.success(apps) }
        }.start()
    }

    private fun installApk(path: String, result: Result) {
        Log.d(TAG, "installApk: path=$path")
        val act = activity ?: run {
            Log.e(TAG, "installApk: no activity")
            result.error("NO_ACTIVITY", "No activity available", null)
            return
        }

        try {
            val file = java.io.File(path)
            if (!file.exists()) {
                Log.e(TAG, "installApk: file not found at $path")
                result.error("FILE_NOT_FOUND", "APK file not found", null)
                return
            }

            val uri = FileProvider.getUriForFile(act, "${act.packageName}.fileprovider", file)
            Log.d(TAG, "installApk: uri=$uri")

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            act.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "installApk failed: ${e.message}", e)
            result.error("INSTALL_FAILED", e.message, null)
        }
    }

    private fun stopVpn(result: Result) {
        Log.d(TAG, "stopVpn called")
        val act = activity ?: run {
            Log.e(TAG, "stopVpn: no activity available")
            result.error("NO_ACTIVITY", "No activity available", null)
            return
        }
        val intent = Intent(act, SimpleVpnService::class.java).apply {
            action = "DISCONNECT"
        }
        act.startService(intent)
        result.success(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
        cachedAppList = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
}
