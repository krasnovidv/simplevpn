package com.simplevpn.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import vpnlib.Vpnlib

class VpnPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    companion object {
        private const val TAG = "SimpleVPN"
        const val CHANNEL_NAME = "com.simplevpn/vpn"
        const val VPN_REQUEST_CODE = 1001
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        Log.d(TAG, "onMethodCall: ${call.method}")
        when (call.method) {
            "connect" -> {
                val config = call.argument<String>("config") ?: ""
                startVpn(config, result)
            }
            "disconnect" -> {
                stopVpn(result)
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
            else -> result.notImplemented()
        }
    }

    private fun startVpn(config: String, result: Result) {
        Log.d(TAG, "startVpn called, config length=${config.length}")
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
        }
        act.startService(serviceIntent)
        result.success(null)
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
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
}
