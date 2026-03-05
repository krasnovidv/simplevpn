package com.simplevpn.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class VpnPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null

    companion object {
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
        when (call.method) {
            "connect" -> {
                val config = call.argument<String>("config") ?: ""
                startVpn(config, result)
            }
            "disconnect" -> {
                stopVpn(result)
            }
            "status" -> {
                result.success(SimpleVpnService.currentStatus)
            }
            else -> result.notImplemented()
        }
    }

    private fun startVpn(config: String, result: Result) {
        val act = activity ?: run {
            result.error("NO_ACTIVITY", "No activity available", null)
            return
        }

        // Check if VPN permission is granted
        val intent = VpnService.prepare(act)
        if (intent != null) {
            act.startActivityForResult(intent, VPN_REQUEST_CODE)
            result.error("VPN_PERMISSION", "VPN permission required", null)
            return
        }

        // Start VPN service
        val serviceIntent = Intent(act, SimpleVpnService::class.java).apply {
            putExtra("config", config)
        }
        act.startService(serviceIntent)
        result.success(null)
    }

    private fun stopVpn(result: Result) {
        val act = activity ?: run {
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
