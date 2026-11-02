package com.encrypchat.encrypchat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Local notifications only: nothing here touches Google or any push service.
 *
 * They name the contact and never carry message text, so a locked screen shows
 * that someone wrote, not what they wrote.
 */
object Notifications {
    const val CHANNEL_SERVICE = "relay_listener"
    private const val CHANNEL_MESSAGES = "messages"
    private const val CHANNEL_CALLS = "calls"

    const val ID_SERVICE = 1
    private const val ID_CALL = 2
    private const val ID_MESSAGES = 3

    private const val CALL_RING_MS = 60_000L

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_SERVICE,
                "Conexión en segundo plano",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "Mantiene el buzón escuchando con la app cerrada."
                setShowBadge(false)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_MESSAGES,
                "Mensajes",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_CALLS,
                "Llamadas",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                enableVibration(true)
            },
        )
    }

    fun openApp(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun service(context: Context): Notification {
        ensureChannels(context)
        return NotificationCompat.Builder(context, CHANNEL_SERVICE)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Encrypchat")
            .setContentText("Lista para recibir mensajes y llamadas")
            .setContentIntent(openApp(context))
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    fun message(context: Context, name: String) {
        ensureChannels(context)
        val text = if (name.isBlank()) "Mensaje nuevo" else "Mensaje de $name"
        val notification = NotificationCompat.Builder(context, CHANNEL_MESSAGES)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Encrypchat")
            .setContentText(text)
            .setContentIntent(openApp(context))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .build()
        post(context, ID_MESSAGES, notification)
    }

    fun call(context: Context, name: String) {
        ensureChannels(context)
        val text = if (name.isBlank()) "Llamada entrante" else "Llamada de $name"
        val notification = NotificationCompat.Builder(context, CHANNEL_CALLS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Encrypchat")
            .setContentText(text)
            .setContentIntent(openApp(context))
            .setFullScreenIntent(openApp(context), true)
            .setOngoing(true)
            .setTimeoutAfter(CALL_RING_MS)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .build()
        post(context, ID_CALL, notification)
    }

    fun cancelCall(context: Context) {
        NotificationManagerCompat.from(context).cancel(ID_CALL)
    }

    fun clearMessages(context: Context) {
        NotificationManagerCompat.from(context).cancel(ID_MESSAGES)
    }

    private fun post(context: Context, id: Int, notification: Notification) {
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (e: SecurityException) {
            // Notifications turned off: the message is still in the chat.
            android.util.Log.w("Encrypchat", "notification refused")
        }
    }
}
