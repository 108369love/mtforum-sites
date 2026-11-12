package cc.binmt.mt_forum

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * MCP 服务的前台保活。
 *
 * App 退到后台后，普通进程随时可能被系统回收或冻结，Dart 里的 HttpServer
 * 跟着断掉，电脑上的 AI 客户端就再也连不上。这里挂一个前台服务：通知栏
 * 常驻一条低优先级通知，进程会被系统当作「正在运行」对待，不会因为
 * 内存回收或后台限制被清掉。
 *
 * 光有前台服务还不够：它只保证进程不被回收，屏幕一黑 CPU 照样进休眠，
 * 于是还要自己按住一颗 partial wake lock（CPU）和一把 Wi-Fi 锁（网卡）。
 * 服务本身不跑任何业务，只负责把宿主进程和网络按住；HTTP 监听仍在 Flutter 侧。
 */
class McpKeepAliveService : Service() {
    companion object {
        private const val CHANNEL_ID = "mt_forum_mcp"
        private const val NOTIFICATION_ID = 8642
        private const val ACTION_START = "cc.binmt.mt_forum.MCP_KEEP_ALIVE_START"
        private const val ACTION_STOP = "cc.binmt.mt_forum.MCP_KEEP_ALIVE_STOP"
        private const val EXTRA_PORT = "port"
        private const val LOCK_TAG = "mtforum:mcp"

        /** 给 MethodChannel 查询用：服务是否还在跑。 */
        @Volatile
        var running: Boolean = false
            private set

        fun start(context: Context, port: Int) {
            val intent = Intent(context, McpKeepAliveService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_PORT, port)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, McpKeepAliveService::class.java))
        }
    }

    private var port: Int = 8642
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        port = intent?.getIntExtra(EXTRA_PORT, port) ?: port
        // 必须在 onStartCommand 里立刻挂上前台通知，否则系统会按
        // 「startForegroundService 但没 startForeground」直接 ANR。
        promoteToForeground()
        return START_STICKY
    }

    /**
     * 从最近任务里划掉 App 时，Activity 会把 Flutter 引擎一起销毁，
     * Dart 里的 HttpServer 已经没了。这时再挂着「服务运行中」的通知只是骗人，
     * 直接把服务收掉，用户回 App 重新开还会重新拉起来。
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        running = false
        releaseLocks()
        super.onDestroy()
    }

    private fun promoteToForeground() {
        val notification = buildNotification()
        val ok = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        }.isSuccess
        if (!ok) {
            // 权限被 ROM 拦掉、类型不合法……都在这里。别让 Dart 侧和通知栏
            // 以为服务还活着，直接收摊，界面会如实显示「没起来」。
            running = false
            stopSelf()
            return
        }
        running = true
        acquireLocks()
    }

    /**
     * CPU 与网卡各按一把锁。
     *
     * 前台服务只保证进程不被回收，屏幕一黑 CPU 照样休眠：套接字在手里，
     * 但 Dart 侧读不动，客户端看到的就是「连上了没反应 / 请求超时」。
     * Wi-Fi 锁再压住网卡的省电模式，锁屏后不至于掉到几秒一次的 DTIM 节奏。
     */
    private fun acquireLocks() {
        if (wakeLock == null) {
            wakeLock = runCatching {
                (getSystemService(Context.POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, LOCK_TAG)
                    .apply {
                        setReferenceCounted(false)
                        acquire()
                    }
            }.getOrNull()
        }
        if (wifiLock == null) {
            wifiLock = runCatching {
                val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                manager.createWifiLock(mode, LOCK_TAG).apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }.getOrNull()
        }
    }

    private fun releaseLocks() {
        runCatching { wakeLock?.takeIf { it.isHeld }?.release() }
        wakeLock = null
        runCatching { wifiLock?.takeIf { it.isHeld }?.release() }
        wifiLock = null
    }

    private fun buildNotification(): Notification {
        ensureChannel()
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("open_mcp", true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_mcp)
            .setContentTitle("MCP 服务运行中")
            .setContentText("端口 $port · 局域网 AI 客户端可连接")
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "MCP 服务", NotificationManager.IMPORTANCE_MIN).apply {
            description = "MCP 服务后台保活时显示的常驻通知"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }
}
