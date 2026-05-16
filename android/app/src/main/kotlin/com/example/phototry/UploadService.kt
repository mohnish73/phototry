package com.example.phototry

import android.app.*
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.IBinder
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.storage.FirebaseStorage
import java.util.concurrent.TimeUnit

class UploadService : Service() {

    companion object {
        private const val CHANNEL_ID = "phototry_upload"
        private const val NOTIF_ID = 9001
        private const val TAG = "UploadService"

        const val PREFS_NAME = "upload_prefs"
        const val KEY_UPLOADED = "uploaded"
        const val KEY_TOTAL = "total"
        const val KEY_RUNNING = "running"
        const val KEY_STATUS = "status"

        @Volatile
        var isRunning = false
    }

    private var uploadThread: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        FirebaseApp.initializeApp(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (isRunning) return START_NOT_STICKY

        isRunning = true
        // Start foreground IMMEDIATELY — Android kills service if not called within 5 seconds
        startForeground(NOTIF_ID, buildNotif("Starting upload...", 0, 0, false))
        saveProgress(0, 0, true, "Starting...")

        uploadThread = Thread { runUpload() }.also { it.start() }

        return START_NOT_STICKY
    }

    private fun runUpload() {
        try {
            val photos = getPhotoUris()
            val total = photos.size
            var uploaded = 0
            var failed = 0

            Log.d(TAG, "📁 Total photos: $total")
            saveProgress(0, total, true, "Uploading 0 of $total...")
            showNotif("Uploading 0 of $total...", 0, total, false)

            val storageRoot = FirebaseStorage.getInstance().reference.child("gallery_backup")

            for ((index, uri) in photos.withIndex()) {
                if (!isRunning) {
                    Log.d(TAG, "Upload stopped by user")
                    break
                }

                val name = getFileName(uri) ?: "photo_${index}_${System.currentTimeMillis()}.jpg"
                Log.d(TAG, "⬆️  [${index + 1}/$total] $name")

                val stream = try {
                    contentResolver.openInputStream(uri)
                } catch (e: Exception) {
                    Log.e(TAG, "Cannot open $name", e)
                    failed++
                    continue
                }

                if (stream == null) { failed++; continue }

                try {
                    // 10-minute timeout per file; Firebase retries network errors internally
                    Tasks.await(storageRoot.child(name).putStream(stream), 10, TimeUnit.MINUTES)
                    uploaded++
                    Log.d(TAG, "✅  [$uploaded/$total] $name")
                } catch (e: Exception) {
                    failed++
                    Log.e(TAG, "❌  Failed: $name — ${e.message}")
                } finally {
                    stream.close()
                }

                val progress = uploaded + failed
                val msg = "Uploading $progress of $total..."
                saveProgress(uploaded, total, true, msg)
                showNotif(msg, progress, total, false)
            }

            val doneMsg = "Done! $uploaded uploaded${if (failed > 0) ", $failed failed" else ""}."
            Log.d(TAG, "🎉 $doneMsg")
            saveProgress(uploaded, total, false, doneMsg)
            showNotif(doneMsg, total, total, true)

        } catch (e: Exception) {
            Log.e(TAG, "Upload error", e)
            saveProgress(0, 0, false, "Error: ${e.message}")
        } finally {
            isRunning = false
            stopForeground(STOP_FOREGROUND_DETACH)
            stopSelf()
        }
    }

    private fun getPhotoUris(): List<Uri> {
        val uris = mutableListOf<Uri>()
        contentResolver.query(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Images.Media._ID),
            null, null,
            "${MediaStore.Images.Media.DATE_ADDED} ASC"
        )?.use { cursor ->
            val col = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            while (cursor.moveToNext()) {
                uris.add(
                    ContentUris.withAppendedId(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        cursor.getLong(col)
                    )
                )
            }
        }
        return uris
    }

    private fun getFileName(uri: Uri): String? =
        contentResolver.query(
            uri, arrayOf(MediaStore.Images.Media.DISPLAY_NAME), null, null, null
        )?.use { if (it.moveToFirst()) it.getString(0) else null }

    private fun saveProgress(uploaded: Int, total: Int, running: Boolean, status: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putInt(KEY_UPLOADED, uploaded)
            .putInt(KEY_TOTAL, total)
            .putBoolean(KEY_RUNNING, running)
            .putString(KEY_STATUS, status)
            .apply()
    }

    private fun showNotif(text: String, done: Int, total: Int, finished: Boolean) {
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIF_ID, buildNotif(text, done, total, finished))
    }

    private fun buildNotif(text: String, done: Int, total: Int, finished: Boolean): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(this, 0, launchIntent, PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Gallery Backup")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setProgress(if (finished) 0 else total, done, total == 0 && !finished)
            .setOngoing(!finished)
            .setContentIntent(pi)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID, "Photo Upload", NotificationManager.IMPORTANCE_DEFAULT
        ).apply { description = "Background photo upload progress" }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    // KEY: do nothing here — this is what flutter_background_service was doing wrong.
    // With stopWithTask="false" in the manifest AND not calling stopSelf() here,
    // the service survives when the user swipes the app away from recents.
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "onTaskRemoved — upload continues in background")
    }

    override fun onDestroy() {
        isRunning = false
        uploadThread?.interrupt()
        super.onDestroy()
    }
}
