package com.framenova.app.engine

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.media3.common.util.UnstableApi
import com.framenova.app.MainActivity
import com.framenova.app.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/** Keeps the app alive and shows progress while an export runs, even if the editor is in the background. */
@UnstableApi
class ExportService : Service() {
    override fun attachBaseContext(newBase: android.content.Context) = super.attachBaseContext(com.framenova.app.AppLanguage.wrap(newBase))

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val manager by lazy { getSystemService(NotificationManager::class.java) }
    private var collector: kotlinx.coroutines.Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        manager.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.notif_channel_exports), NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val first = notification(getString(R.string.editor_exporting), 0, ongoing = true)
        // Called directly: the compat helper masks out types newer than it knows (media processing), and Android then
        // rejects a foreground service with no type.
        if (Build.VERSION.SDK_INT >= 35) startForeground(ID, first, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING)
        else startForeground(ID, first, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        collector?.cancel()
        collector = scope.launch {
            ExportManager.state.collectLatest { state ->
                when (state) {
                    is ExportState.Running -> manager.notify(ID, notification(getString(R.string.notif_exporting, state.label), state.progress, ongoing = true))
                    is ExportState.Done -> { done(getString(R.string.notif_saved, state.displayName)); }
                    is ExportState.Failed -> { done(getString(R.string.notif_failed, state.message)) }
                    ExportState.Idle -> { ServiceCompat.stopForeground(this@ExportService, ServiceCompat.STOP_FOREGROUND_REMOVE); stopSelf() }
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun done(text: String) {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
        manager.notify(ID, notification(text, -1, ongoing = false))
        stopSelf()
    }

    private fun notification(text: String, progress: Int, ongoing: Boolean): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("FrameNova")
            .setContentText(text)
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .apply { if (progress >= 0) setProgress(100, progress, false) }
            .build()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "export"
        const val ID = 41
    }
}
