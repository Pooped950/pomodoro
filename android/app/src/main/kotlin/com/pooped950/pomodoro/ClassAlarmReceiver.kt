package com.pooped950.pomodoro

import android.app.Notification
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 上课提醒的落点 —— 闹钟到点，发通知（震动走渠道），然后**立刻排下一周的同一次**。
 *
 * ## 自包含
 *
 * 只读 [ClassReminderScheduler] 存在 SharedPreferences 里的规则，不依赖
 * App 进程 / Flutter 引擎是否活着 —— 因此**App 被系统回收后照样提醒**。
 *
 * ## 响完就重排，是整个设计的闭环
 *
 * 排程器每次只排「下一次」，响完由这里再排下一个 —— 这样一条规则只需要一个
 * 待触发闹钟（省电、也不会因为排太多被系统丢弃），而且**只要课程表没变，
 * 用户一直不打开 App 也能一直提醒下去**。
 */
class ClassAlarmReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_CLASS_ALARM = "com.pooped950.pomodoro.CLASS_ALARM"

        /** 第几条规则（对应 [ClassReminderScheduler] 的下标） */
        const val EXTRA_INDEX = "classReminderIndex"

        /** 通知 id 基址（避开计时通知的 1 / 2） */
        const val NOTIF_CLASS_BASE = 3000
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CLASS_ALARM) return

        val index = intent.getIntExtra(EXTRA_INDEX, -1)
        if (index < 0) return

        val reminder = ClassReminderScheduler.load(context).getOrNull(index) ?: return

        // 冷进程被闹钟唤醒时渠道可能还没建过
        ClassReminderScheduler.ensureChannel(context)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_CLASS_BASE + index, buildNotification(context, reminder))

        // 排下一周的同一次 —— 闭环的关键一步
        ClassReminderScheduler.scheduleOne(context, index, reminder)
    }

    private fun buildNotification(
        ctx: Context,
        r: ClassReminderScheduler.Reminder,
    ): Notification {
        val builder = Notification.Builder(ctx, ClassReminderScheduler.channel(ctx))
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(r.title)
            .setContentText(r.body)
            .setContentIntent(TimerForegroundService.contentIntent(ctx))
            .setAutoCancel(true)

        // Android 8 以下没有渠道，声音/震动只能在通知上挂
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) {
            builder.setDefaults(Notification.DEFAULT_ALL)
        }
        return builder.build()
    }
}
