package com.pooped950.pomodoro

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 上课提醒的排程器 —— 把「每周几、几点几分、提醒哪门课」落到 AlarmManager。
 *
 * ## 为什么存「规则」而不是「时间戳」
 *
 * 课表是**每周重复**的。Dart 侧只下发「周一 07:50 提醒 排球初级」这种规则，
 * 由本类算出**下一次**的具体时刻去排精确闹钟；闹钟响完（见 [ClassAlarmReceiver]）
 * 立刻再排下一周的那一次 —— 这样**只要课程表没变，App 一直不打开也照样提醒**。
 *
 * 存绝对时间戳的方案一周就过期了，不可取。
 *
 * ## 为什么用精确闹钟
 *
 * 和计时到点提醒同一个理由：澎湃OS / Android 在 Doze 下会节流普通闹钟和
 * 后台轮询，`setExactAndAllowWhileIdle` 由系统闹钟服务直接唤醒，
 * 不受应用进程死活影响。
 *
 * ## 降级
 *
 * Android 12+ 需要用户在系统设置里授予「闹钟与提醒」权限（`canScheduleExactAlarms`）。
 * 没授权时退化成 `setAndAllowWhileIdle`（可能晚几分钟）——
 * **宁可晚一点响，也不要完全不响**。
 */
object ClassReminderScheduler {

    /** 上课提醒：震动 + 响铃（默认） */
    const val CHANNEL_CLASS = "pomodoro_class"

    /** 上课提醒：只响铃、不震动 */
    const val CHANNEL_CLASS_SOUND = "pomodoro_class_sound"

    /** 上课提醒：只震动、不响铃 */
    const val CHANNEL_CLASS_VIBRATE = "pomodoro_class_vibrate"

    private const val PREFS = "pomodoro_class_reminders"
    private const val KEY_ITEMS = "items"
    private const val KEY_VIBRATE = "vibrate"
    private const val KEY_SOUND = "sound"

    /** 每条提醒一个请求码，从 1000 起（避开 TimerAlarmReceiver 的 21） */
    private const val BASE_REQUEST = 1000

    /** 最多支持这么多条提醒（一张课表一周不会超过 60 节课） */
    const val MAX_ITEMS = 64

    /** 一条提醒规则 */
    data class Reminder(
        val weekday: Int,      // 1 = 周一 … 7 = 周日
        val minuteOfDay: Int,  // 0~1439
        val title: String,
        val body: String,
    )

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Dart 侧下发整个列表 + 提醒方式：存起来 + 全部重排 */
    fun apply(ctx: Context, json: String, vibrate: Boolean, sound: Boolean) {
        prefs(ctx).edit()
            .putString(KEY_ITEMS, json)
            .putBoolean(KEY_VIBRATE, vibrate)
            .putBoolean(KEY_SOUND, sound)
            .apply()
        rescheduleAll(ctx)
    }

    /** 关掉提醒（两个复选框都取消 / 清空课表） */
    fun clear(ctx: Context) {
        prefs(ctx).edit().remove(KEY_ITEMS).apply()
        cancelAll(ctx)
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        for (i in 0 until MAX_ITEMS) nm.cancel(ClassAlarmReceiver.NOTIF_CLASS_BASE + i)
    }

    /**
     * 当前该用哪个渠道发通知。
     *
     * Android 8+ 渠道的声音/震动**创建后不可改**，所以三种组合靠三个预建渠道
     * 切换（和番茄钟到点提醒同一套路）。两个都关时不排闹钟，不会走到这里。
     */
    fun channel(ctx: Context): String {
        val p = prefs(ctx)
        val vibrate = p.getBoolean(KEY_VIBRATE, true)
        val sound = p.getBoolean(KEY_SOUND, true)
        return when {
            sound && vibrate -> CHANNEL_CLASS
            sound -> CHANNEL_CLASS_SOUND
            else -> CHANNEL_CLASS_VIBRATE
        }
    }

    fun load(ctx: Context): List<Reminder> {
        val raw = prefs(ctx).getString(KEY_ITEMS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val o: JSONObject = arr.optJSONObject(i) ?: return@mapNotNull null
                val r = Reminder(
                    weekday = o.optInt("weekday", 0),
                    minuteOfDay = o.optInt("minuteOfDay", -1),
                    title = o.optString("title", ""),
                    body = o.optString("body", ""),
                )
                // 脏数据直接丢：星期/时刻不在合法范围、或没课名的，排了也没意义
                if (r.weekday in 1..7 && r.minuteOfDay in 0..1439 && r.title.isNotEmpty()) r
                else null
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** 全部重排（先取消再排，顺手清掉"已经删掉的课"留下的旧闹钟） */
    fun rescheduleAll(ctx: Context) {
        cancelAll(ctx)
        load(ctx).forEachIndexed { i, r ->
            if (i < MAX_ITEMS) scheduleOne(ctx, i, r)
        }
    }

    fun cancelAll(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (i in 0 until MAX_ITEMS) {
            am.cancel(pendingIntent(ctx, i))
        }
    }

    /** 排「下一次」的那一条 */
    fun scheduleOne(ctx: Context, index: Int, r: Reminder) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val at = nextTriggerMillis(r.weekday, r.minuteOfDay)
        val pi = pendingIntent(ctx, index)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                // 用户没给「闹钟与提醒」权限 → 降级成不精确（可能晚几分钟）
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (_: SecurityException) {
            // 权限被中途撤销 → 再降一级，别让整个流程崩掉
            try {
                am.set(AlarmManager.RTC_WAKEUP, at, pi)
            } catch (_: Exception) {
                // 实在排不上就算了，App 下次启动会重排
            }
        }
    }

    /**
     * 「下一次」该提醒的绝对时刻（毫秒）。
     *
     * ⚠️ 星期换算：`Calendar.DAY_OF_WEEK` 是 **1=周日 … 7=周六**，
     * 而课表的 weekday 是 **1=周一 … 7=周日** —— 两边不能直接比。
     */
    fun nextTriggerMillis(weekday: Int, minuteOfDay: Int): Long {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, minuteOfDay / 60)
            set(Calendar.MINUTE, minuteOfDay % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val target = if (weekday == 7) Calendar.SUNDAY else Calendar.MONDAY + (weekday - 1)
        var delta = (target - cal.get(Calendar.DAY_OF_WEEK) + 7) % 7
        // 就是今天、但那个点已经过了 → 推到下周同一天
        if (delta == 0 && cal.timeInMillis <= System.currentTimeMillis()) delta = 7
        cal.add(Calendar.DAY_OF_YEAR, delta)
        return cal.timeInMillis
    }

    private fun pendingIntent(ctx: Context, index: Int): PendingIntent {
        val i = Intent(ctx, ClassAlarmReceiver::class.java).apply {
            action = ClassAlarmReceiver.ACTION_CLASS_ALARM
            putExtra(ClassAlarmReceiver.EXTRA_INDEX, index)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(ctx, BASE_REQUEST + index, i, flags)
    }

    /**
     * 确保三个渠道存在。放这里是因为 [ClassAlarmReceiver] 可能在**冷进程**里被
     * 闹钟唤醒 —— 那时没有任何服务走过 onCreate。
     *
     * Android 8+ 渠道的震动/声音创建后不可改，所以把三种组合**都预建好**，
     * 运行时按用户的复选框挑一个用。
     */
    fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_CLASS,
                "上课提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "每节课上课前 10 分钟提醒（震动 + 响铃）"
                setSound(sound, attrs)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 200, 300)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_CLASS_SOUND,
                "上课提醒（不震动）",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "每节课上课前 10 分钟提醒（只响铃）"
                setSound(sound, attrs)
                enableVibration(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_CLASS_VIBRATE,
                "上课提醒（只震动）",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "每节课上课前 10 分钟提醒（只震动，不响铃）"
                setSound(null, null)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 200, 300)
            }
        )
    }
}
