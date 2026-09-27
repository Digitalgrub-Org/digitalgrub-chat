package com.digitalgrub.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the microphone alive while a call is running and the app is not.
 *
 * Android stops delivering microphone input to a backgrounded app -- it does
 * not fail, it hands over silence -- unless a foreground service with the
 * `microphone` type is running. Without this, switching to another app mid-call
 * left the person able to hear everyone and audible to no one, which is the
 * worst possible failure for a call because neither side can tell whose fault
 * it is.
 *
 * Deliberately microphone-only. Adding the `camera` type would keep video
 * publishing from a phone whose owner has walked away to another app, and a
 * camera that keeps transmitting when you leave the call screen is not a
 * feature. Audio continuing is what a phone call means; video stopping is what
 * people already expect.
 */
class CallForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        // The service is told to stop when the call ends. Restarting it after
        // the system kills the process would resurrect a notification for a
        // call that is long over.
        return START_NOT_STICKY
    }

    private fun startForegroundCompat() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            // The typed form only exists from API 30, and the background
            // microphone restriction it satisfies arrived with it. Below that,
            // any foreground service is enough.
            @Suppress("DEPRECATION")
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ongoing call",
                // Low: this is a status row, not an alert. The call itself has
                // already announced whatever it needed to.
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while a Digitalgrub Chat call is running."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        // Tapping it returns to the call rather than opening a fresh copy of
        // the app: MainActivity is singleTop, so this lands on the running one.
        val open = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Digitalgrub Chat")
            .setContentText("Call in progress")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentIntent(pending)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "in.digitalgrub.chat.ongoing_call"
        private const val NOTIFICATION_ID = 8801

        fun start(context: Context) {
            val intent = Intent(context, CallForegroundService::class.java)
            // startForegroundService requires the service to call
            // startForeground within a few seconds or the system kills the app
            // with a ForegroundServiceDidNotStartInTimeException; onStartCommand
            // does it first thing.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallForegroundService::class.java))
        }
    }
}
