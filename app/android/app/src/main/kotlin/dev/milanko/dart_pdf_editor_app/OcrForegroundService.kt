package dev.milanko.dart_pdf_editor_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Keeps the existing OCR engine alive when the activity is backgrounded or
 * removed from Recents. Force-stop/reboot is recovered from Dart checkpoints.
 * dataSync explicitly covers local file processing; its OS time limit is not
 * bypassed. The service is never restarted without a foreground user session.
 */
class OcrForegroundService : Service() {
    companion object {
        var engine: FlutterEngine? = null
        var active = false
        var channel: MethodChannel? = null
        private const val notificationId = 7301
        private const val channelId = "ocr_jobs"
    }

    private var title = "DartPDF"
    private var completed = 0
    private var total = 0


    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "cancel") {
            channel?.invokeMethod("cancel", null)
            stopSelf()
            return START_NOT_STICKY
        }
        title = intent?.getStringExtra("title") ?: title
        total = intent?.getIntExtra("count", total) ?: total
        completed = intent?.getIntExtra("completed", completed) ?: completed

        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channelId, "OCR", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val cancel = PendingIntent.getService(this, 1,
            Intent(this, OcrForegroundService::class.java).setAction("cancel"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId)
                      else Notification.Builder(this)
        val notification = builder.setContentTitle("OCR — $title")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentText("$completed / $total")
            .setContentIntent(open).setOngoing(true)
            .setProgress(total, completed, total == 0)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, getString(android.R.string.cancel), cancel).build())
            .build()
        active = true
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else { startForeground(notificationId, notification) }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        channel?.invokeMethod("expired", null)
        stopSelf()
    }

    override fun onDestroy() {
        active = false
        // Drop the retained engine reference, but do not destroy the engine
        // currently used by a reattached activity.
        engine = null
        super.onDestroy()
    }
}
