package com.simplevpn.app

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "SimpleVPN"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "Registering VpnPlugin")
        flutterEngine.plugins.add(VpnPlugin())
        Log.d(TAG, "VpnPlugin registered")
    }
}
