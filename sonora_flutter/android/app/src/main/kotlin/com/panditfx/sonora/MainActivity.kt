package com.panditfx.sonora

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
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

    /**
     * Kept so a notification's Cancel action can be turned back into a call.
     *
     * It is null until the engine is attached, which is the one case where
     * there is no running download to stop anyway.
     */
    private var downloadChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ACTION_CANCEL_DOWNLOAD) forwardCancelAction(intent)
    }

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

        val downloads = MethodChannel(messenger, DOWNLOAD_METHOD_CHANNEL)
        downloads.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                // "cancelled" is a settled state like "complete" and "failed", so
                // the notification must drop its progress bar and its Cancel
                // action along with them.
                "start", "update", "complete", "failed", "cancelled" -> {
                    val inFlight = call.method == "start" || call.method == "update"
                    showDownloadNotification(call, inFlight)
                    result.success(null)
                }
                "clear" -> {
                    notificationManager().cancel(DOWNLOAD_NOTIFICATION_ID)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        downloadChannel = downloads

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

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
        }
    }

    private fun showDownloadNotification(call: MethodCall, ongoing: Boolean) {
        val manager = notificationManager()
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                DOWNLOAD_NOTIFICATION_CHANNEL,
                "Downloads",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Shows what Sonora is downloading"
            manager.createNotificationChannel(channel)
        }

        val title = call.argument<String>("title") ?: "Downloading"
        val text = call.argument<String>("text") ?: ""
        val progress = call.argument<Int>("progress") ?: 0
        val indeterminate = call.argument<Boolean>("indeterminate") ?: false
        val cancellable = call.argument<Boolean>("cancellable") ?: false
        val downloadId = call.argument<String>("id")
        val activeCount = call.argument<Int>("activeCount") ?: 0
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, DOWNLOAD_NOTIFICATION_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_sonora)
            .setLargeIcon(BitmapFactory.decodeResource(resources, R.drawable.sonora_notification_icon))
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setProgress(100, progress, indeterminate)
        // The transfer lives in Dart, so the action is a launch of this activity
        // that is turned back into a method call in onNewIntent. With more than
        // one download running, stopping the one shown would leave the rest
        // going, so the single action stops them all.
        if (cancellable) {
            val stopEverything = activeCount > 1
            builder.addAction(
                R.drawable.ic_stat_cancel,
                if (stopEverything) "Cancel all" else "Cancel",
                cancelActionPendingIntent(downloadId, stopEverything),
            )
        }
        manager.notify(DOWNLOAD_NOTIFICATION_ID, builder.build())
    }

    /**
     * The intent behind the notification's Cancel action.
     *
     * The request code differs per target so that a second notification can
     * carry its own pending intent instead of replacing the first one's.
     */
    private fun cancelActionPendingIntent(id: String?, stopEverything: Boolean): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_CANCEL_DOWNLOAD
            putExtra(EXTRA_DOWNLOAD_ID, id)
            putExtra(EXTRA_CANCEL_ALL, stopEverything)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            if (stopEverything) CANCEL_ALL_REQUEST_CODE else CANCEL_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Turns a launched Cancel action into the call Dart is waiting for.
     *
     * Dart owns the transfer, so stopping it has to be asked for over the
     * channel; the notification is only the place the user pressed.
     */
    private fun forwardCancelAction(intent: Intent) {
        val stopEverything = intent.getBooleanExtra(EXTRA_CANCEL_ALL, false)
        val id = intent.getStringExtra(EXTRA_DOWNLOAD_ID)
        val channel = downloadChannel ?: return
        channel.invokeMethod(
            if (stopEverything) "cancelAllDownloads" else "cancelDownload",
            if (stopEverything) null else id,
        )
        notificationManager().cancel(DOWNLOAD_NOTIFICATION_ID)
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        private const val METHOD_CHANNEL = "com.panditfx.sonora/volume"
        private const val EVENT_CHANNEL = "com.panditfx.sonora/volume_events"
        private const val DOWNLOAD_METHOD_CHANNEL = "com.panditfx.sonora/downloads"
        private const val DOWNLOAD_NOTIFICATION_CHANNEL = "com.panditfx.sonora.downloads"
        private const val DOWNLOAD_NOTIFICATION_ID = 0x534F
        private const val NOTIFICATION_PERMISSION_REQUEST = 0x534F
        private const val POLL_INTERVAL_MS = 300L
        private const val ACTION_CANCEL_DOWNLOAD = "com.panditfx.sonora.CANCEL_DOWNLOAD"
        private const val EXTRA_DOWNLOAD_ID = "downloadId"
        private const val EXTRA_CANCEL_ALL = "cancelAll"
        private const val CANCEL_REQUEST_CODE = 0x5341
        private const val CANCEL_ALL_REQUEST_CODE = 0x5342
    }
}
