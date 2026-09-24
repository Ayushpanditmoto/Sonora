package com.ayushpandit.sonora_flutter

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * Exposes the device's music stream volume to Dart.
 *
 * just_audio's own `setVolume` is a per player gain multiplier: it scales the
 * audio inside the app and never touches the system volume, so the hardware
 * volume keys and the notification could not possibly stay in step with it.
 * These channels read and write [AudioManager.STREAM_MUSIC] instead, which is
 * the stream the media session is routed to.
 */
class MainActivity : AudioServiceActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var lastVolume = -1
    private var watching = false

    private val audioManager: AudioManager
        get() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val maxVolume: Int
        get() = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

    private fun currentVolume(): Int =
        audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // The system volume is a short ladder rather than a smooth 0..1
                // range, so the step count is reported too: it lets Dart show
                // the level that was actually set instead of the coarser value
                // it rounds to.
                "getVolume" -> result.success(
                    mapOf(
                        "level" to currentVolume().toDouble() / maxVolume,
                        "steps" to maxVolume,
                    )
                )
                "setVolume" -> {
                    val level = call.argument<Double>("level") ?: 0.0
                    val index = (level * maxVolume)
                        .roundToInt()
                        .coerceIn(0, maxVolume)
                    audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
                    emitVolume()
                    // Handing back the level that really applied lets the caller
                    // correct itself instead of drifting from the device.
                    result.success(index.toDouble() / maxVolume)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // Android sends no callback when the stream volume changes, so
                    // it is polled while the player screen is watching.
                    watching = true
                    handler.post(poll)
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    watching = false
                    handler.removeCallbacks(poll)
                }
            }
        )
    }

    private val poll = object : Runnable {
        override fun run() {
            if (!watching) return
            emitVolume()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    /** Sends the level only when it actually changed. */
    private fun emitVolume() {
        val volume = currentVolume()
        if (volume == lastVolume) return
        lastVolume = volume
        eventSink?.success(volume.toDouble() / maxVolume)
    }

    override fun onResume() {
        super.onResume()
        if (eventSink != null) {
            // The level may have moved while the app was away.
            lastVolume = -1
            watching = true
            handler.post(poll)
        }
    }

    override fun onPause() {
        watching = false
        handler.removeCallbacks(poll)
        super.onPause()
    }

    companion object {
        private const val METHOD_CHANNEL = "com.ayushpandit.sonora_flutter/volume"
        private const val EVENT_CHANNEL = "com.ayushpandit.sonora_flutter/volume_events"
        private const val POLL_INTERVAL_MS = 300L
    }
}
