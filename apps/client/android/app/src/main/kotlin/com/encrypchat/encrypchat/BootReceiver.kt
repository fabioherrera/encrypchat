package com.encrypchat.encrypchat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/** Comes back after a reboot and after a silent update, if the person left it on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> Unit
            else -> return
        }
        if (!BackgroundPrefs.isEnabled(context)) return
        val start = Intent(context, RelayListenerService::class.java)
            .setAction(RelayListenerService.ACTION_START)
        try {
            ContextCompat.startForegroundService(context, start)
        } catch (e: RuntimeException) {
            android.util.Log.w("Encrypchat", "boot start refused: ${e.javaClass.simpleName}")
        }
    }
}
