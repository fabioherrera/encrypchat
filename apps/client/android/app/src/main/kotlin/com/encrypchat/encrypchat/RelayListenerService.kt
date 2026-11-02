package com.encrypchat.encrypchat

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat

/**
 * Keeps the process, and so the relay socket in Dart, alive with the app closed.
 *
 * This replaces push on purpose: no Google service learns that a message arrived.
 * The price is the permanent low-priority notification Android requires.
 */
class RelayListenerService : Service() {
    companion object {
        const val ACTION_START = "com.encrypchat.action.START"
        const val ACTION_CALL_ON = "com.encrypchat.action.CALL_ON"
        const val ACTION_CALL_OFF = "com.encrypchat.action.CALL_OFF"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must happen first: Android kills a started service that takes too long
        // to go to the foreground, and booting the engine is the slow part.
        promote(intent?.action == ACTION_CALL_ON)
        EngineHolder.get(this)
        return START_STICKY
    }

    private fun promote(inCall: Boolean) {
        val type = when {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> 0
            // The microphone type is what lets a call keep its audio when the
            // user leaves the app. Android only grants it from the foreground,
            // which is where a call starts or is answered.
            inCall -> ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            else -> ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        }
        try {
            ServiceCompat.startForeground(
                this,
                Notifications.ID_SERVICE,
                Notifications.service(this),
                type,
            )
        } catch (e: RuntimeException) {
            android.util.Log.w("Encrypchat", "foreground refused: ${e.javaClass.simpleName}")
            if (!inCall) stopSelf()
        }
    }
}
