package cc.binmt.mt_forum

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "cc.binmt.mt_forum/native"

    /** 通知权限是异步回调，先把 Result 存下来等系统回话。 */
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "shareText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    startActivity(Intent.createChooser(intent, "分享"))
                    result.success(true)
                }
                "saveImage" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("name") ?: "mt_forum.jpg"
                    if (bytes == null) {
                        result.error("no-bytes", "缺少图片数据", null)
                    } else {
                        Executors.newSingleThreadExecutor().execute {
                            val ok = runCatching { saveToGallery(bytes, name) }.getOrDefault(false)
                            runOnUiThread { result.success(ok) }
                        }
                    }
                }
                "openDownloadedFile" -> {
                    val path = call.argument<String>("path")
                    val name = call.argument<String>("name") ?: path?.let { File(it).name }
                    if (path.isNullOrBlank() || name.isNullOrBlank()) {
                        result.error("invalid-file", "文件路径无效", null)
                    } else {
                        runCatching { openDownloadedFile(path, name) }
                            .onSuccess { result.success(true) }
                            .onFailure { error ->
                                result.error("open-file-failed", error.message ?: "没有找到可打开此文件的应用", null)
                            }
                    }
                }
                // ---- MCP 后台保活 ----
                "mcpKeepAliveStart" -> {
                    val port = call.argument<Int>("port") ?: 8642
                    val accepted = runCatching { McpKeepAliveService.start(this, port) }.isSuccess
                    if (!accepted) {
                        result.success(false)
                    } else {
                        // startForegroundService 只是把 Intent 递过去，服务有没有
                        // 真的挂上前台要等 onStartCommand 跑完才知道。这里等一小会
                        // 再回话，Dart 侧的「保活已生效」才是真的，而不是「已发出」。
                        Handler(Looper.getMainLooper()).postDelayed({
                            runCatching { result.success(McpKeepAliveService.running) }
                        }, 400)
                    }
                }
                "mcpKeepAliveStop" -> {
                    runCatching { McpKeepAliveService.stop(this) }
                    result.success(true)
                }
                "mcpKeepAliveRunning" -> result.success(McpKeepAliveService.running)
                "notificationPermission" -> result.success(hasNotificationPermission())
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ---------------------------------------------------------- MCP 保活

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission() || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        // 上一次还没回话就先按拒绝收尾，避免 Result 泄漏。
        notificationPermissionResult?.success(false)
        notificationPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1201)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 1201) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || isIgnoringBatteryOptimizations()) return
        // 有的 ROM 不认直接弹窗的 action，那就退到电池优化列表让用户自己勾。
        val direct = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName")
        )
        runCatching { startActivity(direct) }.onFailure {
            runCatching { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }
        }
    }

    private fun openDownloadedFile(path: String, name: String) {        val source = File(path)
        if (!source.isFile) throw IllegalArgumentException("文件不存在")
        // FileProvider only exposes a temporary copy under cache/opened_downloads.
        val openDir = File(cacheDir, "opened_downloads").apply { mkdirs() }
        val safeName = name.substringAfterLast('/')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .ifBlank { "download" }
        val sharedFile = File(openDir, safeName)
        source.copyTo(sharedFile, overwrite = true)
        val contentUri: Uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            sharedFile
        )
        val extension = safeName.substringAfterLast('.', "").lowercase()
        val mimeType = when (extension) {
            "apk" -> "application/vnd.android.package-archive"
            "zip" -> "application/zip"
            "rar" -> "application/vnd.rar"
            "7z" -> "application/x-7z-compressed"
            "tar" -> "application/x-tar"
            "gz" -> "application/gzip"
            "pdf" -> "application/pdf"
            "txt", "log" -> "text/plain"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "mp4" -> "video/mp4"
            "mp3" -> "audio/mpeg"
            "doc" -> "application/msword"
            "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            else -> "*/*"
        }
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = android.content.ClipData.newUri(contentResolver, safeName, contentUri)
        }
        if (extension == "apk") {
            // Hand APKs directly to Android's package installer, not a browser or chooser.
            startActivity(viewIntent)
        } else {
            // Archives and other files ask Android which installed app should handle them.
            startActivity(Intent.createChooser(viewIntent, "选择打开方式"))
        }
    }

    private fun saveToGallery(bytes: ByteArray, name: String): Boolean {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/MT论坛")
            }
        }
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val uri = contentResolver.insert(collection, values) ?: return false
        return runCatching {
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) } != null
        }.getOrDefault(false)
    }
}
