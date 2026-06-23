package com.simplevpn.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Invisible trampoline launched by the home-screen widget tap. Toggles the VPN
 * and finishes immediately (no UI). Running as an Activity means:
 *   - starting the foreground VPN service is exempt from the Android 12+
 *     background-FGS-start restriction, and
 *   - the system VPN consent dialog can be shown when needed (it requires an
 *     Activity), without opening the full app.
 *
 * Falls back to launching the full app only when no config has been cached yet.
 */
class WidgetToggleActivity : Activity() {

    companion object {
        private const val TAG = "SimpleVPN"
        private const val REQ_VPN_CONSENT = 7001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (VpnWidgetProvider.isActive(VpnWidgetProvider.currentState())) {
            // Already up → disconnect.
            try {
                startService(Intent(this, SimpleVpnService::class.java).apply { action = "DISCONNECT" })
            } catch (e: Exception) {
                Log.w(TAG, "widget disconnect failed: ${e.message}")
            }
            finish()
            return
        }

        if (!VpnWidgetProvider.hasCachedConfig(this)) {
            // Nothing to connect with yet → open the app so the user can set up.
            Log.i(TAG, "widget toggle: no cached config — opening app")
            packageManager.getLaunchIntentForPackage(packageName)?.let { startActivity(it) }
            finish()
            return
        }

        val consent = VpnService.prepare(this)
        if (consent != null) {
            // Consent not granted yet → ask now (we're an Activity, so we can).
            startActivityForResult(consent, REQ_VPN_CONSENT)
        } else {
            startVpnFromCache()
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN_CONSENT && resultCode == Activity.RESULT_OK) {
            startVpnFromCache()
        } else {
            Log.i(TAG, "widget toggle: VPN consent denied")
        }
        finish()
    }

    private fun startVpnFromCache() {
        val intent = VpnWidgetProvider.cachedConnectIntent(this) ?: run {
            Log.w(TAG, "widget toggle: cached intent missing at connect time")
            return
        }
        try {
            ContextCompat.startForegroundService(this, intent)
            VpnWidgetProvider.refresh(this)
        } catch (e: Exception) {
            Log.w(TAG, "widget toggle: startForegroundService failed: ${e.message}")
        }
    }
}
