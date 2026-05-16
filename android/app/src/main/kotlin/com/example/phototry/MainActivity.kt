package com.example.phototry

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.phototry/upload")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startUpload" -> {
                        startForegroundService(Intent(this, UploadService::class.java))
                        result.success(null)
                    }
                    "stopUpload" -> {
                        // UploadService runs in a separate process — we cannot touch its
                        // static fields. stopService() triggers onDestroy() in that process,
                        // which sets isRunning = false and stops the upload thread.
                        stopService(Intent(this, UploadService::class.java))
                        // Update our own copy so the UI reflects the stopped state immediately.
                        getSharedPreferences(UploadService.PREFS_NAME, Context.MODE_PRIVATE)
                            .edit()
                            .putBoolean(UploadService.KEY_RUNNING, false)
                            .putString(UploadService.KEY_STATUS, "Upload stopped.")
                            .apply()
                        result.success(null)
                    }
                    "getProgress" -> {
                        // MODE_MULTI_PROCESS forces Android to reload from disk if the
                        // :upload process has modified the file since our last read.
                        @Suppress("DEPRECATION")
                        val prefs = getSharedPreferences(
                            UploadService.PREFS_NAME,
                            Context.MODE_PRIVATE or Context.MODE_MULTI_PROCESS
                        )
                        result.success(mapOf(
                            "uploaded" to prefs.getInt(UploadService.KEY_UPLOADED, 0),
                            "total"    to prefs.getInt(UploadService.KEY_TOTAL, 0),
                            "running"  to prefs.getBoolean(UploadService.KEY_RUNNING, false),
                            "status"   to (prefs.getString(UploadService.KEY_STATUS, "") ?: "")
                        ))
                    }
                    "requestBatteryOptimization" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                    .also { it.data = Uri.parse("package:$packageName") }
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
