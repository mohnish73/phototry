package com.example.phototry

import android.app.*
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.IBinder
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class UploadService : Service() {

    companion object {
        private const val CHANNEL_ID  = "phototry_upload"
        private const val NOTIF_ID    = 9001
        private const val TAG         = "UploadService"

        const val PREFS_NAME          = "upload_prefs"
        const val KEY_UPLOADED        = "uploaded"
        const val KEY_TOTAL           = "total"
        const val KEY_RUNNING         = "running"
        const val KEY_STATUS          = "status"

        // ── Backblaze B2 credentials (saved by MainActivity) ──────────────────
        const val KEY_B2_KEY_ID       = "b2_key_id"
        const val KEY_B2_APP_KEY      = "b2_app_key"
        const val KEY_B2_BUCKET_ID    = "b2_bucket_id"

        // Already-uploaded file keys (prevents re-uploading on next run)
        private const val KEY_UPLOADED_SET = "b2_uploaded_files"

        @Volatile var isRunning = false
    }

    // ── B2 session state ──────────────────────────────────────────────────────
    private var authToken      = ""
    private var apiUrl         = ""
    private var uploadUrl      = ""
    private var uploadAuthToken= ""

    private var uploadThread: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() { super.onCreate(); createChannel() }

    // ─────────────────────────────────────────────────────────────────────────
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (isRunning) return START_NOT_STICKY
        isRunning = true
        startForeground(NOTIF_ID, buildNotif("Starting upload…", 0, 0, false))
        saveProgress(0, 0, true, "Starting…")
        uploadThread = Thread { runUpload() }.also { it.start() }
        return START_NOT_STICKY
    }

    // ─────────────────────────────────────────────────────────────────────────
    private fun runUpload() {
        try {
            @Suppress("DEPRECATION")
            val prefs    = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE or Context.MODE_MULTI_PROCESS)

            val keyId    = B2Config.KEY_ID
            val appKey   = B2Config.APP_KEY
            val bucketId = B2Config.BUCKET_ID

            if (bucketId == "YOUR_BUCKET_ID_HERE") {
                saveProgress(0, 0, false, "Please set your Bucket ID in B2Config.kt and rebuild.")
                return
            }

            // Step 1 – authorise
            saveProgress(0, 0, true, "Authenticating with Backblaze B2…")
            if (!authorizeB2(keyId, appKey)) {
                saveProgress(0, 0, false, "B2 auth failed – check B2Config credentials.")
                return
            }

            // Step 2 – get upload URL
            if (!refreshUploadUrl(bucketId)) {
                saveProgress(0, 0, false, "Could not get B2 upload URL.")
                return
            }

            val uploadedSet = prefs.getStringSet(KEY_UPLOADED_SET, mutableSetOf())!!.toMutableSet()
            val files       = getAllFiles()
            val total       = files.size
            var uploaded    = 0
            var failed      = 0

            saveProgress(0, total, true, "Found $total files – uploading…")
            showNotif("Found $total files – uploading…", 0, total, false)

            for (info in files) {
                if (!isRunning) break
                if (uploadedSet.contains(info.key)) { uploaded++; continue }

                // Open stream
                val stream = try {
                    info.uri?.let { contentResolver.openInputStream(it) }
                        ?: info.file?.inputStream()
                } catch (e: Exception) {
                    Log.e(TAG, "Cannot open ${info.name}", e); failed++; continue
                } ?: run { failed++; continue }

                val success = try {
                    uploadToB2(stream, info.b2Name, info.mime, info.size)
                } catch (e: Exception) {
                    Log.e(TAG, "Upload error ${info.name}: ${e.message}")
                    // Try once more after refreshing the upload URL
                    try { stream.close() } catch (_: Exception) {}
                    retryUpload(info, bucketId)
                } finally {
                    try { stream.close() } catch (_: Exception) {}
                }

                if (success) {
                    uploaded++
                    uploadedSet.add(info.key)
                    if (uploaded % 10 == 0)
                        prefs.edit().putStringSet(KEY_UPLOADED_SET, uploadedSet).apply()
                    Log.d(TAG, "✅ [$uploaded/$total] ${info.name}")
                } else {
                    failed++
                    Log.e(TAG, "❌ Failed: ${info.name}")
                }

                val done = uploaded + failed
                val msg  = "Uploading $done of $total…"
                saveProgress(uploaded, total, true, msg)
                if (done % 5 == 0) showNotif(msg, done, total, false)
            }

            prefs.edit().putStringSet(KEY_UPLOADED_SET, uploadedSet).apply()

            val doneMsg = "Done! $uploaded uploaded" +
                    (if (failed > 0) ", $failed failed" else "") + "."
            saveProgress(uploaded, total, false, doneMsg)
            showNotif(doneMsg, total, total, true)
            Log.d(TAG, "🎉 $doneMsg")

        } catch (e: Exception) {
            Log.e(TAG, "runUpload exception", e)
            saveProgress(0, 0, false, "Error: ${e.message}")
        } finally {
            isRunning = false
            stopForeground(STOP_FOREGROUND_DETACH)
            stopSelf()
        }
    }

    private fun retryUpload(info: FileInfo, bucketId: String): Boolean {
        if (!refreshUploadUrl(bucketId)) return false
        val stream = try {
            info.uri?.let { contentResolver.openInputStream(it) } ?: info.file?.inputStream()
        } catch (e: Exception) { return false } ?: return false
        return try {
            uploadToB2(stream, info.b2Name, info.mime, info.size)
        } catch (e: Exception) {
            Log.e(TAG, "Retry failed ${info.name}: ${e.message}"); false
        } finally {
            try { stream.close() } catch (_: Exception) {}
        }
    }

    // ── Backblaze B2 API ──────────────────────────────────────────────────────

    private fun authorizeB2(keyId: String, appKey: String): Boolean {
        return try {
            val credentials = Base64.encodeToString(
                "$keyId:$appKey".toByteArray(Charsets.UTF_8), Base64.NO_WRAP
            )
            val conn = URL("https://api.backblazeb2.com/b2api/v2/b2_authorize_account")
                .openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("Authorization", "Basic $credentials")
            conn.connectTimeout = 30_000
            conn.readTimeout    = 30_000

            val code = conn.responseCode
            val body = if (code == 200) {
                conn.inputStream.bufferedReader().readText()
            } else {
                val err = conn.errorStream?.bufferedReader()?.readText() ?: "(no body)"
                Log.e(TAG, "B2 auth HTTP $code → $err")
                conn.disconnect()
                return false
            }
            conn.disconnect()

            val json  = JSONObject(body)
            authToken = json.getString("authorizationToken")
            apiUrl    = json.getString("apiUrl")
            Log.d(TAG, "✅ B2 auth OK  apiUrl=$apiUrl")
            true
        } catch (e: Exception) {
            Log.e(TAG, "B2 auth exception: ${e.javaClass.simpleName}: ${e.message}")
            false
        }
    }

    private fun refreshUploadUrl(bucketId: String): Boolean {
        return try {
            val conn = URL("$apiUrl/b2api/v2/b2_get_upload_url")
                .openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Authorization", authToken)
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput       = true
            conn.connectTimeout = 30_000
            conn.readTimeout    = 30_000
            conn.outputStream.use { it.write("{\"bucketId\":\"$bucketId\"}".toByteArray()) }

            val code = conn.responseCode
            val body = if (code == 200) {
                conn.inputStream.bufferedReader().readText()
            } else {
                val err = conn.errorStream?.bufferedReader()?.readText() ?: "(no body)"
                Log.e(TAG, "get_upload_url HTTP $code → $err")
                conn.disconnect()
                return false
            }
            conn.disconnect()

            val json        = JSONObject(body)
            uploadUrl       = json.getString("uploadUrl")
            uploadAuthToken = json.getString("authorizationToken")
            Log.d(TAG, "✅ B2 upload URL ready")
            true
        } catch (e: Exception) {
            Log.e(TAG, "get_upload_url exception: ${e.javaClass.simpleName}: ${e.message}")
            false
        }
    }

    /** Upload one file to B2.  Returns true on HTTP 200. */
    private fun uploadToB2(
        stream   : java.io.InputStream,
        b2Name   : String,
        mime     : String,
        fileSize : Long
    ): Boolean {
        val encodedName = URLEncoder.encode(b2Name, "UTF-8").replace("+", "%20")
        val conn = (URL(uploadUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Authorization",       uploadAuthToken)
            setRequestProperty("X-Bz-File-Name",     encodedName)
            setRequestProperty("Content-Type",        mime.ifBlank { "b2/x-auto" })
            setRequestProperty("X-Bz-Content-Sha1",  "do_not_verify")
            doOutput       = true
            connectTimeout = 60_000
            readTimeout    = 120_000
            if (fileSize > 0) setFixedLengthStreamingMode(fileSize)
            else              setChunkedStreamingMode(512 * 1024)
        }
        conn.outputStream.use { out ->
            val buf = ByteArray(512 * 1024)
            var n: Int
            while (stream.read(buf).also { n = it } != -1) {
                if (!isRunning) { conn.disconnect(); return false }
                out.write(buf, 0, n)
            }
        }
        return try {
            val code = conn.responseCode
            val body = if (code == 200) conn.inputStream.bufferedReader().readText()
                       else conn.errorStream?.bufferedReader()?.readText() ?: ""
            conn.disconnect()
            Log.d(TAG, "B2 [$code] $b2Name — $body")
            code == 200
        } catch (e: Exception) {
            Log.e(TAG, "Response read error: ${e.message}"); conn.disconnect(); false
        }
    }

    // ── File scanning ─────────────────────────────────────────────────────────

    private data class FileInfo(
        val uri    : Uri?,
        val file   : File?,
        val name   : String,   // display name
        val b2Name : String,   // path inside the B2 bucket
        val mime   : String,
        val key    : String,   // dedup key stored in SharedPrefs
        val size   : Long = -1L
    )

    private fun getAllFiles(): List<FileInfo> {
        val list = mutableListOf<FileInfo>()
        list += queryMediaStore(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Images.Media.DISPLAY_NAME, "image/jpeg", "gallery/images")
        list += queryMediaStore(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Video.Media.DISPLAY_NAME, "video/mp4",  "gallery/videos")
        for (mime in listOf(
            "application/pdf",
            "text/plain",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )) list += queryDocFiles(mime)
        list += scanWhatsAppFolder()
        return list.distinctBy { it.key }
    }

    private fun queryMediaStore(
        contentUri  : Uri,
        nameCol     : String,
        fallbackMime: String,
        b2Prefix    : String
    ): List<FileInfo> {
        val result = mutableListOf<FileInfo>()
        contentResolver.query(
            contentUri,
            arrayOf(MediaStore.MediaColumns._ID, nameCol,
                    MediaStore.MediaColumns.MIME_TYPE, MediaStore.MediaColumns.SIZE),
            null, null,
            "${MediaStore.MediaColumns.DATE_ADDED} DESC"
        )?.use { c ->
            val idIdx   = c.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val nameIdx = c.getColumnIndexOrThrow(nameCol)
            val mimeIdx = c.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
            val sizeIdx = c.getColumnIndex(MediaStore.MediaColumns.SIZE)
            while (c.moveToNext()) {
                val name = c.getString(nameIdx) ?: continue
                val mime = if (mimeIdx >= 0) c.getString(mimeIdx) ?: fallbackMime else fallbackMime
                val size = if (sizeIdx >= 0) c.getLong(sizeIdx) else -1L
                val uri  = ContentUris.withAppendedId(contentUri, c.getLong(idIdx))
                result += FileInfo(uri, null, name, "$b2Prefix/$name", mime, "$b2Prefix/$name", size)
            }
        }
        return result
    }

    private fun queryDocFiles(mimeType: String): List<FileInfo> {
        val result     = mutableListOf<FileInfo>()
        val contentUri = MediaStore.Files.getContentUri("external")
        contentResolver.query(
            contentUri,
            arrayOf(MediaStore.Files.FileColumns._ID,
                    MediaStore.Files.FileColumns.DISPLAY_NAME,
                    MediaStore.Files.FileColumns.SIZE),
            "${MediaStore.Files.FileColumns.MIME_TYPE} = ?",
            arrayOf(mimeType),
            "${MediaStore.Files.FileColumns.DATE_ADDED} DESC"
        )?.use { c ->
            val idIdx   = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
            val nameIdx = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DISPLAY_NAME)
            val sizeIdx = c.getColumnIndex(MediaStore.Files.FileColumns.SIZE)
            while (c.moveToNext()) {
                val name = c.getString(nameIdx) ?: continue
                val size = if (sizeIdx >= 0) c.getLong(sizeIdx) else -1L
                val uri  = ContentUris.withAppendedId(contentUri, c.getLong(idIdx))
                result += FileInfo(uri, null, name, "docs/$name", mimeType, "docs/$name", size)
            }
        }
        return result
    }

    /** Scan WhatsApp folder (requires MANAGE_EXTERNAL_STORAGE on Android 11+). */
    private fun scanWhatsAppFolder(): List<FileInfo> {
        val result = mutableListOf<FileInfo>()
        // Try both legacy path and Android/media path (newer WhatsApp)
        val candidates = listOf(
            File(Environment.getExternalStorageDirectory(), "WhatsApp"),
            File(Environment.getExternalStorageDirectory(), "Android/media/com.whatsapp/WhatsApp")
        )
        var found = false
        for (waRoot in candidates) {
            if (waRoot.exists() && waRoot.canRead()) {
                Log.d(TAG, "Scanning WhatsApp at ${waRoot.absolutePath}")
                scanDirRecursive(waRoot, result, "whatsapp")
                found = true
                break
            }
        }
        if (!found) Log.d(TAG, "WhatsApp folder not accessible – grant All Files Access in Settings.")
        Log.d(TAG, "WhatsApp files found: ${result.size}")
        return result
    }

    private fun scanDirRecursive(dir: File, result: MutableList<FileInfo>, b2Prefix: String) {
        dir.listFiles()?.forEach { file ->
            if (!isRunning) return
            when {
                file.isDirectory -> scanDirRecursive(file, result, "$b2Prefix/${file.name}")
                file.isFile && file.length() > 0 -> {
                    val mime   = mimeForName(file.name)
                    val b2Name = "$b2Prefix/${file.name}"
                    result += FileInfo(null, file, file.name, b2Name, mime, b2Name, file.length())
                }
            }
        }
    }

    private fun mimeForName(name: String): String = when {
        name.endsWith(".jpg",  true) || name.endsWith(".jpeg", true) -> "image/jpeg"
        name.endsWith(".png",  true)  -> "image/png"
        name.endsWith(".gif",  true)  -> "image/gif"
        name.endsWith(".webp", true)  -> "image/webp"
        name.endsWith(".mp4",  true)  -> "video/mp4"
        name.endsWith(".mkv",  true)  -> "video/x-matroska"
        name.endsWith(".3gp",  true)  -> "video/3gpp"
        name.endsWith(".mp3",  true)  -> "audio/mpeg"
        name.endsWith(".ogg",  true)  -> "audio/ogg"
        name.endsWith(".opus", true)  -> "audio/opus"
        name.endsWith(".aac",  true)  -> "audio/aac"
        name.endsWith(".pdf",  true)  -> "application/pdf"
        name.endsWith(".doc",  true)  -> "application/msword"
        name.endsWith(".docx", true)  ->
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        else -> "application/octet-stream"
    }

    // ── Progress / notifications ──────────────────────────────────────────────

    private fun saveProgress(up: Int, tot: Int, running: Boolean, status: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putInt(KEY_UPLOADED, up).putInt(KEY_TOTAL, tot)
            .putBoolean(KEY_RUNNING, running).putString(KEY_STATUS, status)
            .apply()
    }

    private fun showNotif(text: String, done: Int, total: Int, finished: Boolean) =
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIF_ID, buildNotif(text, done, total, finished))

    private fun buildNotif(text: String, done: Int, total: Int, finished: Boolean): Notification {
        val pi = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Gallery Backup → Backblaze B2")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setProgress(if (finished) 0 else total, done, total == 0 && !finished)
            .setOngoing(!finished)
            .setContentIntent(pi)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun createChannel() {
        val ch = NotificationChannel(CHANNEL_ID, "Photo Upload", NotificationManager.IMPORTANCE_DEFAULT)
            .apply { description = "Background upload progress" }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "onTaskRemoved — upload continues in background")
    }
    override fun onDestroy() { isRunning = false; uploadThread?.interrupt(); super.onDestroy() }
}
