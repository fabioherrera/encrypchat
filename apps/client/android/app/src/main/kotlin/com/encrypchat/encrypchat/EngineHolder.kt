package com.encrypchat.encrypchat

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * One Dart runtime for the whole process.
 *
 * The node, the encrypted database and the relay socket all live in Dart. The
 * activity and the background service share this engine, so closing the screen
 * does not stop any of them and nothing has to be duplicated in Kotlin.
 */
object EngineHolder {
    private const val ENGINE_ID = "main"
    private const val CHANNEL = "encrypchat/background"

    fun get(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        bindChannel(app, engine)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        cache.put(ENGINE_ID, engine)
        return engine
    }

    private fun bindChannel(app: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        BackgroundPrefs.setEnabled(app, true)
                        startService(app, RelayListenerService.ACTION_START)
                        result.success(null)
                    }
                    "stop" -> {
                        BackgroundPrefs.setEnabled(app, false)
                        app.stopService(Intent(app, RelayListenerService::class.java))
                        result.success(null)
                    }
                    "setInCall" -> {
                        val active = call.argument<Boolean>("active") == true
                        if (BackgroundPrefs.isEnabled(app)) {
                            startService(
                                app,
                                if (active) {
                                    RelayListenerService.ACTION_CALL_ON
                                } else {
                                    RelayListenerService.ACTION_CALL_OFF
                                },
                            )
                        }
                        result.success(null)
                    }
                    "notifyMessage" -> {
                        Notifications.message(app, call.argument<String>("name") ?: "")
                        result.success(null)
                    }
                    "notifyCall" -> {
                        Notifications.call(app, call.argument<String>("name") ?: "")
                        result.success(null)
                    }
                    "cancelCall" -> {
                        Notifications.cancelCall(app)
                        result.success(null)
                    }
                    "clearMessages" -> {
                        Notifications.clearMessages(app)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startService(context: Context, action: String) {
        val intent = Intent(context, RelayListenerService::class.java).setAction(action)
        try {
            ContextCompat.startForegroundService(context, intent)
        } catch (e: RuntimeException) {
            // Android refuses a start from the background in some states. The next
            // time the app opens it asks again.
            android.util.Log.w("Encrypchat", "background start refused: ${e.javaClass.simpleName}")
        }
    }
}

object BackgroundPrefs {
    private const val FILE = "encrypchat_background"
    private const val KEY = "enabled"

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY, enabled)
            .apply()
    }
}
