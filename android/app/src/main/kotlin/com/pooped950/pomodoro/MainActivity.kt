package com.pooped950.pomodoro

import android.Manifest
import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 承载两条 MethodChannel：
 *
 * - `pomodoro/service` —— M3 阶段二的前台服务控制与状态对齐
 * - `pomodoro/keepalive` —— M3 阶段四的后台保活引导（状态查询 + 跳系统设置页）
 *
 * ## 为什么保活要单独做一页
 *
 * 澎湃OS / MIUI 的后台管理比原生激进得多：应用不只要通知权限，还要用户手动开
 * 「自启动」、把「省电策略」设为无限制，否则息屏后前台服务会被系统直接杀掉 ——
 * 那样精确闹钟排得再准也没用（进程都没了）。这些开关**没有公开 API 可改**，
 * 只能引导用户去系统页面手动开，所以这里提供「状态查询 + 一键跳转」。
 */
class MainActivity : FlutterActivity() {

    companion object {
        /** 服务反向通知 Dart 用的通道引用（onServiceAction） */
        @Volatile
        var serviceChannel: MethodChannel? = null

        /** 通知权限申请的请求码 */
        private const val REQ_NOTIFICATIONS = 1001

        /**
         * MIUI / HyperOS 的「自启动管理」页面。不同版本包名/类名不一样，
         * 按顺序试，全失败再退回应用详情页。
         */
        private val AUTO_START_CANDIDATES = listOf(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.powercenter.PowerSettings"
            ),
        )

        /** MIUI / HyperOS 的「省电策略」页面候选 */
        private val BATTERY_CANDIDATES = listOf(
            ComponentName("com.miui.powercenter", "com.miui.powercenter.PowerSettings"),
            ComponentName("com.miui.securitycenter", "com.miui.powercenter.PowerSettings"),
        )
    }

    private var keepAliveChannel: MethodChannel? = null
    private var installerChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestTopRefreshRate()
    }

    /**
     * 申请面板支持的**最高刷新率**（同分辨率模式里挑）。
     *
     * ## 为什么必须显式申请（2026-10-07，用户报"动画掉帧不够丝滑"）
     *
     * HyperOS 对普通应用默认给 60Hz：Flutter 的 vsync 跟着 surface 走，
     * 不申请的话整套动画都压在 60 帧上限里 —— 渲染再快也白搭。
     * `preferredDisplayModeId` 是窗口级申请，系统在能力范围内会尽量满足；
     * 用户的机型是 1-120Hz LTPO，申请后动画上限即到 120。
     *
     * ## 为什么按"同分辨率"过滤
     *
     * LTPO 的 mode 列表里有各种分辨率×刷新率的组合，直接挑 refreshRate
     * 最高可能选中一个不同分辨率的 mode，切过去会黑屏或重建 surface。
     */
    private fun requestTopRefreshRate() {
        try {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                window.windowManager.defaultDisplay
            } ?: return
            val current = display.mode
            val best = display.supportedModes
                .filter {
                    it.physicalWidth == current.physicalWidth &&
                        it.physicalHeight == current.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return
            if (best.modeId != current.modeId) {
                window.attributes = window.attributes.also {
                    it.preferredDisplayModeId = best.modeId
                }
            }
        } catch (_: Exception) {
            // 拿不到显示模式就维持系统默认，不影响任何功能
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // ---- M3 阶段二：前台服务通道 ----
        val channel = MethodChannel(messenger, "pomodoro/service")
        serviceChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "startOrUpdate" -> {
                        val args = call.arguments as? Map<*, *>
                        val i = Intent(this, TimerForegroundService::class.java)
                            .setAction(TimerForegroundService.ACTION_START_OR_UPDATE)
                        fun extra(key: String, v: Any?) {
                            when (v) {
                                is Int -> i.putExtra(key, v)
                                is Long -> i.putExtra(key, v)
                                is Boolean -> i.putExtra(key, v)
                                is String -> i.putExtra(key, v)
                            }
                        }
                        if (args != null) {
                            extra(TimerForegroundService.KEY_PHASE, args[TimerForegroundService.KEY_PHASE])
                            extra(TimerForegroundService.KEY_STARTED_AT, args[TimerForegroundService.KEY_STARTED_AT])
                            extra(TimerForegroundService.KEY_PLANNED, args[TimerForegroundService.KEY_PLANNED])
                            extra(TimerForegroundService.KEY_PAUSED_AT, args[TimerForegroundService.KEY_PAUSED_AT])
                            extra(TimerForegroundService.KEY_PAUSED_TOTAL, args[TimerForegroundService.KEY_PAUSED_TOTAL])
                            extra(TimerForegroundService.KEY_COMPLETED, args[TimerForegroundService.KEY_COMPLETED])
                            extra(TimerForegroundService.KEY_AUTO_START, args[TimerForegroundService.KEY_AUTO_START])
                            extra(TimerForegroundService.KEY_FOCUS_MIN, args[TimerForegroundService.KEY_FOCUS_MIN])
                            extra(TimerForegroundService.KEY_SHORT_MIN, args[TimerForegroundService.KEY_SHORT_MIN])
                            extra(TimerForegroundService.KEY_LONG_MIN, args[TimerForegroundService.KEY_LONG_MIN])
                            extra(TimerForegroundService.KEY_INTERVAL, args[TimerForegroundService.KEY_INTERVAL])
                            // M4 提醒开关（只影响响铃/震动，不影响闹钟排程）
                            extra(TimerForegroundService.KEY_REMIND_SOUND, args[TimerForegroundService.KEY_REMIND_SOUND])
                            extra(TimerForegroundService.KEY_REMIND_VIBRATE, args[TimerForegroundService.KEY_REMIND_VIBRATE])
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(i)
                        } else {
                            startService(i)
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        startService(
                            Intent(this, TimerForegroundService::class.java)
                                .setAction(TimerForegroundService.ACTION_STOP)
                        )
                        result.success(null)
                    }
                    "getState" -> result.success(TimerForegroundService.lastState)
                    else -> result.notImplemented()
                }
            }

        // ---- M3 阶段四：后台保活引导通道 ----
        val ka = MethodChannel(messenger, "pomodoro/keepalive")
        keepAliveChannel = ka
        ka.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(keepAliveStatus())
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                "openNotificationSettings" -> result.success(openNotificationSettings())
                "openAutoStartSettings" -> result.success(openAutoStartSettings())
                "openBatterySettings" -> result.success(openBatterySettings())
                "openAppDetails" -> result.success(openAppDetails())
                else -> result.notImplemented()
            }
        }

        // ---- 检查更新：调起系统安装器 ----
        // 第三方 App 不能静默装包，这里只做三件事：查权限 / 跳授权页 / 拉起安装器
        val installer = MethodChannel(messenger, "pomodoro/installer")
        installerChannel = installer
        installer.setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(canRequestInstall())
                "openSettings" -> result.success(openInstallPermissionSettings())
                "install" -> {
                    val path = (call.arguments as? Map<*, *>)?.get("path") as? String
                    result.success(installApk(path))
                }
                else -> result.notImplemented()
            }
        }
    }

    /** API 26 起才有「安装未知应用」开关，更低版本一律放行 */
    private fun canRequestInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** 跳到本应用的「安装未知应用」授权页 */
    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 拉起系统安装器。
     *
     * 返回给 Dart 侧的三种结论：
     *   "started"        —— 安装界面已经起来（用户还要在那边点「安装」）
     *   "needPermission" —— 还没授权"安装未知应用"
     *   "unsupported"    —— 文件不在 / 系统或 ROM 走不通
     */
    private fun installApk(path: String?): String {
        if (path.isNullOrBlank()) return "unsupported"
        val file = File(path)
        if (!file.exists()) return "unsupported"
        if (!canRequestInstall()) return "needPermission"
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "started"
        } catch (e: Exception) {
            "unsupported"
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        serviceChannel = null
        keepAliveChannel = null
        installerChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // ------------------------------------------------------------------
    // 状态查询
    // ------------------------------------------------------------------

    /**
     * 四项保活开关的当前状态。**能可靠查到的三项如实返回，
     * 自启动没有公开 API 只能尽力而为**（返回 null 表示"查不到，请用户自己确认"）。
     */
    private fun keepAliveStatus(): Map<String, Any?> {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager

        return mapOf(
            "notificationsEnabled" to nm.areNotificationsEnabled(),
            "exactAlarmAllowed" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                am.canScheduleExactAlarms()
            } else {
                true
            },
            "batteryUnrestricted" to pm.isIgnoringBatteryOptimizations(packageName),
            "autoStartAllowed" to autoStartAllowed(),
            "isMiuiLike" to isMiuiLike(),
        )
    }

    /**
     * 自启动状态：MIUI / HyperOS 把「自启动」实现成一个私有 AppOps（op 号 10008），
     * 没有公开 API。这里读这个 op，**读不到就返回 null（未知）**，不要瞎猜成 false。
     */
    private fun autoStartAllowed(): Boolean? = try {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                "10008", android.os.Process.myUid(), packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow("10008", android.os.Process.myUid(), packageName)
        }
        when (mode) {
            AppOpsManager.MODE_ALLOWED -> true
            AppOpsManager.MODE_IGNORED, AppOpsManager.MODE_DEFAULT -> false
            else -> null // MODE_ERRORED 等：该 ROM 没有这个 op
        }
    } catch (_: Exception) {
        null
    }

    /** 是否小米系 ROM（决定保活页要不要强调「自启动」这一步） */
    private fun isMiuiLike(): Boolean {
        val m = Build.MANUFACTURER.lowercase()
        val b = Build.BRAND.lowercase()
        return m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") ||
            b.contains("xiaomi") || b.contains("redmi") || b.contains("poco")
    }

    // ------------------------------------------------------------------
    // 通知权限
    // ------------------------------------------------------------------

    /** 弹系统通知权限对话框（Android 13+ 才有这个运行时权限） */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
    }

    // ------------------------------------------------------------------
    // 跳系统设置页
    // ------------------------------------------------------------------

    private fun openNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            appDetailsIntent()
        }
        return startSafely(intent)
    }

    /**
     * 省电策略：先用标准对话框申请「电池无限制」（跨 ROM 通用），
     * 不行再跳 MIUI 的省电策略页，最后退回应用详情页。
     */
    private fun openBatterySettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.fromParts("package", packageName, null))
                if (startSafely(i)) return true
            }
        }
        for (c in BATTERY_CANDIDATES) {
            if (startSafely(Intent().setComponent(c))) return true
        }
        return openAppDetails()
    }

    private fun openAutoStartSettings(): Boolean {
        for (c in AUTO_START_CANDIDATES) {
            if (startSafely(Intent().setComponent(c))) return true
        }
        return openAppDetails()
    }

    private fun openAppDetails(): Boolean = startSafely(appDetailsIntent())

    private fun appDetailsIntent(): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.fromParts("package", packageName, null))

    /** 跳转失败（该 ROM 没这个页面）返回 false，让 Dart 侧提示用户手动找 */
    private fun startSafely(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) {
        false
    }
}
