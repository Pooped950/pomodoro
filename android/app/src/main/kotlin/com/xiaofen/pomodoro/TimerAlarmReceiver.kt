package com.xiaofen.pomodoro

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 到点提醒接收器 —— M3 阶段三「精确闹钟兜底」的落点。
 *
 * ## 为什么不能只靠服务里的 1 秒 ticker
 *
 * [TimerForegroundService] 原本用 `handler.postDelayed(ticker, 1_000)` 每秒轮询，
 * 到点判定也发生在那个 ticker 里。但**澎湃OS / Android 在息屏进入 Doze 后会节流
 * 甚至冻结后台的 Handler 轮询**（HyperOS 比原生更激进），ticker 可能几分钟才跑
 * 一次，用户看到的就是「到点不响」。
 *
 * 精确闹钟（`AlarmManager.setExactAndAllowWhileIdle`，RTC_WAKEUP）由系统闹钟服务
 * 直接唤醒，**不受应用进程死活影响**，所以到点判定交给它，ticker 降级为
 * 「只负责刷新通知栏文字」。
 *
 * ## 本接收器是自包含的
 *
 * 只依赖 Intent 里带的阶段名就能发出提醒，不读取服务的任何内存状态 ——
 * 因此 **App 进程被系统回收后依然能响**。推进阶段（进入下一个番茄/休息）是
 * 「尽力而为」：服务还活着就顺手推进，服务已死则等 App 回前台时用快照对齐
 * （见 M3 阶段一的 `timer_snapshot`）。
 */
class TimerAlarmReceiver : BroadcastReceiver() {

    companion object {
        /** 与 AlarmManager 排程时用的 action 一致 */
        const val ACTION_ALARM_FIRED = "com.xiaofen.pomodoro.ALARM_FIRED"

        /** 阶段名，用于决定提醒文案（专注完成 / 休息结束） */
        const val EXTRA_PHASE = "alarmPhase"

        /** M4 提醒开关：true = 静默（只出通知，不响不震） */
        const val EXTRA_SILENT = "alarmSilent"

        /** M4 提醒开关：是否震动 */
        const val EXTRA_VIBRATE = "alarmVibrate"

        /** PendingIntent 请求码：同一时刻只保留一个待触发闹钟 */
        const val REQUEST_CODE = 21
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_ALARM_FIRED) return

        val phase = intent.getStringExtra(EXTRA_PHASE) ?: "focus"
        // 响铃 / 震动设置随闹钟一起带过来 —— 接收器不读服务的任何内存状态
        val silent = intent.getBooleanExtra(EXTRA_SILENT, false)
        val vibrate = intent.getBooleanExtra(EXTRA_VIBRATE, true)

        // 进程可能是被这条闹钟刚唤醒的，通知渠道需要在这里确保存在
        TimerForegroundService.ensureChannels(context)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(
            TimerForegroundService.NOTIF_ALARM_ID,
            TimerForegroundService.buildAlarmNotification(
                context, phase, silent, vibrate,
            )
        )

        // 尽力唤起前台服务推进阶段。失败不影响「提醒已经响了」这件事。
        try {
            val i = Intent(context, TimerForegroundService::class.java)
                .setAction(TimerForegroundService.ACTION_EXPIRED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(i)
            } else {
                context.startService(i)
            }
        } catch (_: Exception) {
            // 后台启动前台服务可能被系统拒绝（HyperOS 省电策略下更常见）：
            // 提醒已发出，阶段流转等 App 回前台时用快照对齐
        }
    }
}
