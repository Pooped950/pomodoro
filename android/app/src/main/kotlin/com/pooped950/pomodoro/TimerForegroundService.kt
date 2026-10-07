package com.pooped950.pomodoro

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * 计时前台服务 —— 方案文档 6.5② 第一层保障。
 *
 * 设计要点：**服务在原生层自持计时状态**（与 Dart 侧同一套绝对时间戳算法，
 * 方案 6.5①），因此即使 Flutter 引擎被杀，通知栏倒计时与「暂停/继续/跳过」
 * 按钮依旧工作；到点后由本服务直接发出提醒通知，不依赖任何 UI 层。
 *
 * Dart 侧通过 MethodChannel("pomodoro/service") 发 startOrUpdate / stop；
 * 本服务每次状态变化都把最新状态写进 [lastState]，供 Dart 回前台时拉取对齐。
 *
 * ## M3 阶段三（精确闹钟兜底）改了什么
 *
 * 到点判定**不再依赖下面的 1 秒 ticker**。原因：澎湃OS / Android 在息屏进入
 * Doze 后会节流甚至冻结后台 Handler 轮询（HyperOS 比原生更激进），ticker 可能
 * 几分钟才跑一次 —— 表现为「到点不响」。
 *
 * 现在：
 *   - 每次状态变化都用 [scheduleAlarm] 向 AlarmManager 排一个精确闹钟
 *     （`setExactAndAllowWhileIdle` + RTC_WAKEUP），触发目标是
 *     [TimerAlarmReceiver]，**不依赖本服务存活**；
 *   - ticker 降级为「只负责刷新通知栏倒计时文字」；
 *   - 暂停 / 停止时 [cancelAlarm]，继续 / 流转时重排；
 *   - [onExpired] 加了幂等保护：ticker 与闹钟几乎同时到达也只处理一次。
 */
class TimerForegroundService : Service() {

    companion object {
        const val CHANNEL_TIMER = "pomodoro_timer"

        /** 到点提醒：铃声 + 震动（默认） */
        const val CHANNEL_ALARM = "pomodoro_alarm"

        /** 到点提醒：只响铃、不震动 */
        const val CHANNEL_ALARM_SOUND = "pomodoro_alarm_sound"

        /** 到点提醒：完全静默，只出通知 */
        const val CHANNEL_ALARM_SILENT = "pomodoro_alarm_silent"

        const val NOTIF_TIMER_ID = 1
        const val NOTIF_ALARM_ID = 2

        const val ACTION_START_OR_UPDATE = "com.pooped950.pomodoro.START_OR_UPDATE"
        const val ACTION_PAUSE = "com.pooped950.pomodoro.PAUSE"
        const val ACTION_RESUME = "com.pooped950.pomodoro.RESUME"
        const val ACTION_SKIP = "com.pooped950.pomodoro.SKIP"
        const val ACTION_STOP = "com.pooped950.pomodoro.STOP"

        /** M3 阶段三：精确闹钟触发后，由 [TimerAlarmReceiver] 唤起本服务推进阶段 */
        const val ACTION_EXPIRED = "com.pooped950.pomodoro.EXPIRED"

        // 与 Dart 侧 TimerServiceProtocol 的 key 一一对应
        const val KEY_PHASE = "phase"
        const val KEY_STARTED_AT = "startedAt"
        const val KEY_PLANNED = "plannedSeconds"
        const val KEY_PAUSED_AT = "pausedAt"
        const val KEY_PAUSED_TOTAL = "pausedTotalSeconds"
        const val KEY_COMPLETED = "completed"
        const val KEY_AUTO_START = "autoStart"
        const val KEY_FOCUS_MIN = "focusMin"
        const val KEY_SHORT_MIN = "shortMin"
        const val KEY_LONG_MIN = "longMin"
        const val KEY_INTERVAL = "interval"

        /** M4 提醒开关：到点是否响铃（false = 静默，只出通知）。不影响闹钟排程。 */
        const val KEY_REMIND_SOUND = "remindSound"

        /** M4 提醒开关：响铃时是否震动 */
        const val KEY_REMIND_VIBRATE = "remindVibrate"

        /** 最新状态快照：MainActivity 的 getState 通道读它对齐 Dart 侧 */
        @Volatile
        var lastState: Map<String, Any>? = null
            private set

        /**
         * 确保两个通知渠道存在。
         *
         * 放在 companion 里是因为 [TimerAlarmReceiver] 也要用 —— 闹钟可能把
         * 冷进程唤醒，那时服务还没走过 onCreate。
         */
        fun ensureChannels(ctx: Context) {
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val timer = NotificationChannel(
                CHANNEL_TIMER, "计时进行中", NotificationManager.IMPORTANCE_LOW
            ).apply { setShowBadge(false) }
            nm.createNotificationChannel(timer)

            // 到点提醒分三个渠道。Android 8+ 的渠道**声音/震动创建后不可修改**，
            // 所以「响铃+震动 / 只响铃 / 静默」这三种组合只能靠预建多个渠道来切换
            // —— M4 的提醒开关就是靠这个实现的。
            // 已有渠道重复 create 是幂等的，老用户原来的 pomodoro_alarm 设置不会被改掉。
            val alarm = NotificationChannel(
                CHANNEL_ALARM, "到点提醒", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(alarmSound(), alarmAudioAttributes())
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 200, 300)
            }
            nm.createNotificationChannel(alarm)

            val soundOnly = NotificationChannel(
                CHANNEL_ALARM_SOUND, "到点提醒（不震动）", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(alarmSound(), alarmAudioAttributes())
                enableVibration(false)
            }
            nm.createNotificationChannel(soundOnly)

            val silent = NotificationChannel(
                CHANNEL_ALARM_SILENT, "到点提醒（静默）", NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(silent)
        }

        private fun alarmSound(): Uri =
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        private fun alarmAudioAttributes(): AudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        /** 点通知回到 App（单实例） */
        fun contentIntent(ctx: Context): PendingIntent = PendingIntent.getActivity(
            ctx, 0,
            Intent(ctx, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        /**
         * 到点提醒通知（铃声 + 震动走 IMPORTANCE_HIGH 通道）。
         *
         * 只依赖 phase 字符串，不读服务状态 —— 这样 [TimerAlarmReceiver] 在
         * App 进程已被回收的情况下也能直接发出来。
         */
        fun buildAlarmNotification(
            ctx: Context,
            phase: String,
            silent: Boolean,
            vibrate: Boolean,
        ): Notification {
            val message = if (phase == "focus") {
                "🍅 专注完成！起来活动一下吧"
            } else {
                "⏰ 休息结束，准备开始下一个专注"
            }
            // 渠道决定响不响：静默 / 只响铃 / 响铃 + 震动
            val channel = when {
                silent -> CHANNEL_ALARM_SILENT
                !vibrate -> CHANNEL_ALARM_SOUND
                else -> CHANNEL_ALARM
            }
            return Notification.Builder(ctx, channel)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle("番茄钟")
                .setContentText(message)
                .setContentIntent(contentIntent(ctx))
                .setAutoCancel(true)
                .build()
        }
    }

    // ---- 原生自持的计时状态（绝对时间戳，方案 6.5①）----
    private var phase: String = "focus"
    private var startedAtMs: Long = 0
    private var plannedSeconds: Int = 1500
    private var pausedAtMs: Long? = null
    private var pausedTotalSeconds: Long = 0
    private var completed: Int = 0
    private var autoStart: Boolean = false
    private var focusMin: Int = 25
    private var shortMin: Int = 5
    private var longMin: Int = 15
    private var interval: Int = 4

    /** M4：到点是否响铃；false = 静默（只出通知，不响不震）。不影响闹钟排程。 */
    private var remindSound: Boolean = true

    /** M4：响铃时是否震动 */
    private var remindVibrate: Boolean = true

    private val handler = Handler(Looper.getMainLooper())
    private var running = false

    /**
     * 已经为哪个 startedAt 处理过「到点」。
     *
     * ticker 与精确闹钟可能几乎同时到达（ticker 恰好在 Doze 边缘跑了一次），
     * 用 startedAt 做幂等键，避免重复提醒、甚至一次跳两个阶段。
     */
    private var expiredForStartedAt: Long = -1

    private val ticker = object : Runnable {
        override fun run() {
            if (!running) return
            val remaining = remainingSeconds()
            if (remaining <= 0) {
                onExpired()
                return
            }
            // ticker 只负责刷新倒计时文字；到点判定交给精确闹钟（见类注释）
            notifyTimer(remaining)
            handler.postDelayed(this, 1_000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE -> {
                if (pausedAtMs == null) {
                    pausedAtMs = System.currentTimeMillis()
                    publishState()
                }
                running = false
                cancelAlarm()
                notifyTimer(remainingSeconds())
                notifyDart("pause")
            }
            ACTION_RESUME -> {
                val paused = pausedAtMs
                if (paused != null) {
                    pausedTotalSeconds += (System.currentTimeMillis() - paused) / 1000
                    pausedAtMs = null
                    publishState()
                }
                startTicking()
                notifyDart("resume")
            }
            ACTION_SKIP -> {
                advancePhase(countFocus = false)
                notifyDart("skip")
            }
            ACTION_EXPIRED -> {
                // 由精确闹钟的接收器唤起。
                // 若进程此前被系统回收，这里没有计时状态 —— 提醒本身已由接收器发出，
                // 此时只需满足「startForegroundService 必须尽快 startForeground」的
                // 硬性要求，然后收摊，阶段流转等 App 回前台用快照对齐。
                ensureForeground()
                if (startedAtMs <= 0) {
                    stopCompat()
                } else if (remainingSeconds() <= 0) {
                    onExpired()
                }
                // 否则说明这条闹钟已过期（阶段已被 ticker 推进），什么都不做
            }
            ACTION_STOP -> stopCompat()
            null, ACTION_START_OR_UPDATE -> {
                applyExtras(intent)
                startTicking()
            }
        }
        // START_REDELIVER_INTENT：服务被系统回收后重建时，带上最后一次的计时状态
        return Service.START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    // ---- 状态流转 ----

    private fun applyExtras(intent: Intent?) {
        if (intent == null) return
        phase = intent.getStringExtra(KEY_PHASE) ?: phase
        startedAtMs = intent.getLongExtra(KEY_STARTED_AT, startedAtMs)
        plannedSeconds = intent.getIntExtra(KEY_PLANNED, plannedSeconds)
        val paused = if (intent.hasExtra(KEY_PAUSED_AT)) intent.getLongExtra(KEY_PAUSED_AT, 0) else null
        pausedAtMs = paused?.takeIf { it > 0 }
        // 通道把 Dart int 传成 Integer，读 Long 会拿不到值 → 用 getIntExtra 再转 Long
        pausedTotalSeconds =
            intent.getIntExtra(KEY_PAUSED_TOTAL, pausedTotalSeconds.toInt()).toLong()
        completed = intent.getIntExtra(KEY_COMPLETED, completed)
        autoStart = intent.getBooleanExtra(KEY_AUTO_START, autoStart)
        focusMin = intent.getIntExtra(KEY_FOCUS_MIN, focusMin)
        shortMin = intent.getIntExtra(KEY_SHORT_MIN, shortMin)
        longMin = intent.getIntExtra(KEY_LONG_MIN, longMin)
        interval = intent.getIntExtra(KEY_INTERVAL, interval)
        remindSound = intent.getBooleanExtra(KEY_REMIND_SOUND, remindSound)
        remindVibrate = intent.getBooleanExtra(KEY_REMIND_VIBRATE, remindVibrate)
        publishState()
    }

    /** 暂停冻结在 pausedAt；继续后从暂停点接着走——与 Dart 侧语义一致（方案 6.5①） */
    private fun remainingSeconds(): Int {
        val end = pausedAtMs ?: System.currentTimeMillis()
        val elapsed = (end - startedAtMs) / 1000 - pausedTotalSeconds
        return (plannedSeconds - elapsed.toInt()).coerceAtLeast(0)
    }

    /** 阶段流转：与 Dart 侧 TimerEngine.nextPhase 完全同构 */
    private fun nextPhaseFor(completedAfter: Int): String {
        if (phase != "focus") return "focus"
        val safeInterval = if (interval <= 0) 1 else interval
        return if (completedAfter > 0 && completedAfter % safeInterval == 0) "longBreak" else "shortBreak"
    }

    private fun minutesFor(p: String): Int = when (p) {
        "shortBreak" -> shortMin
        "longBreak" -> longMin
        else -> focusMin
    }

    /**
     * 阶段流转：与 Dart 侧 TimerEngine.nextPhase 同构。
     *
     * ⚠️ 2026-10-05（M3 阶段三）修正：**不自动开始时必须把 startedAtMs 清零**。
     * 原实现无条件把 startedAtMs 设成"现在"，然后才 `stopCompat()`，导致
     * 状态谎称"正在计时"（App 回前台对齐后显示「暂停」按钮），而实际上服务已停、
     * 闹钟已撤 —— 休息到点不会响，M3 阶段三的兜底形同虚设。
     * Dart 侧 `TimerState.toPhase()` 的语义是 `startedAt = null`（待开始），
     * 这里对齐它：清零后 `TimerServiceProtocol.fromMap` 会返回 null，
     * App 保留自己那份"待开始"状态，两边一致。
     */
    private fun advancePhase(countFocus: Boolean) {
        if (phase == "focus" && countFocus) completed += 1
        phase = nextPhaseFor(completed)
        plannedSeconds = minutesFor(phase) * 60
        pausedTotalSeconds = 0
        pausedAtMs = null

        if (autoStart) {
            // 自动开始下一阶段：从现在起算，继续前台服务 + 排精确闹钟
            startedAtMs = System.currentTimeMillis()
            publishState()
            startTicking()
        } else {
            // 不自动开始：下一阶段处于「待开始」，startedAt 清零后再收摊
            startedAtMs = 0
            publishState()
            stopCompat()
        }
    }

    /**
     * 到点：发提醒通知（铃声 + 震动走高优先级通道），再按配置流转。
     *
     * 幂等：ticker 与精确闹钟可能几乎同时到达，同一次 startedAt 只处理一遍。
     */
    private fun onExpired() {
        if (startedAtMs == expiredForStartedAt) return
        expiredForStartedAt = startedAtMs

        running = false
        handler.removeCallbacksAndMessages(null)
        cancelAlarm()
        notifyAlarm()
        advancePhase(countFocus = phase == "focus")
    }

    /** 服务 → Dart 反向通知：通知栏按钮把动作同步给 App 界面 */
    private fun notifyDart(action: String) {
        val ch = MainActivity.serviceChannel ?: return
        try {
            ch.invokeMethod("onServiceAction", action)
        } catch (_: Exception) {
            // 引擎不在时静默（用户会通过回前台 getState 对齐）
        }
    }

    private fun startTicking() {
        running = phase != "" && startedAtMs > 0 && pausedAtMs == null
        if (!running) {
            cancelAlarm()
            if (startedAtMs <= 0) {
                // 从未开始：服务不该存在（Dart 侧对 idle 状态发的是 stop）
                stopCompat()
                return
            }
            // ⚠️ 暂停中**必须**仍然 startForeground。
            //
            // MainActivity 用 startForegroundService 拉起本服务，系统要求 5 秒内
            // 调用 startForeground()，否则抛 ForegroundServiceDidNotStartInTimeException
            // **直接崩掉整个 App**（2026-10-05 模拟器实测崩溃，日志里就是这个异常）。
            // 而且暂停的计时本来也该留着通知栏（带「继续」按钮），行为上也是对的。
            ensureForeground()
            notifyTimer(remainingSeconds())
            return
        }
        ensureForeground()
        scheduleAlarm()
        notifyTimer(remainingSeconds())
        handler.removeCallbacks(ticker)
        handler.postDelayed(ticker, 1_000)
    }

    // ---- M3 阶段三：精确闹钟兜底 ----

    /** 阶段结束的绝对时刻（epoch ms）：startedAt + 累计暂停 + 计划时长 */
    private fun phaseEndMillis(): Long =
        startedAtMs + (plannedSeconds + pausedTotalSeconds) * 1000L

    private fun alarmIntent(): PendingIntent {
        val i = Intent(this, TimerAlarmReceiver::class.java)
            .setAction(TimerAlarmReceiver.ACTION_ALARM_FIRED)
            .putExtra(TimerAlarmReceiver.EXTRA_PHASE, phase)
            // 接收器是自包含的（App 进程可能已被回收），响铃/震动设置必须随闹钟带过去
            .putExtra(TimerAlarmReceiver.EXTRA_SILENT, !remindSound)
            .putExtra(TimerAlarmReceiver.EXTRA_VIBRATE, remindVibrate)
        // FLAG_UPDATE_CURRENT：每次排程都把最新的 phase 写进 extras
        return PendingIntent.getBroadcast(
            this,
            TimerAlarmReceiver.REQUEST_CODE,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /**
     * 排一个精确闹钟在阶段结束时刻唤醒。
     *
     * - RTC_WAKEUP + setExactAndAllowWhileIdle：Doze 下也能准时触发（澎湃OS 同样认这条）
     * - 权限缺失时降级为 setAndAllowWhileIdle（不精确但不会抛异常）
     * - 暂停中 / 未开始 / 时刻已过：不排
     */
    private fun scheduleAlarm() {
        val am = getSystemService(ALARM_SERVICE) as AlarmManager
        val pi = alarmIntent()
        am.cancel(pi)

        if (pausedAtMs != null || startedAtMs <= 0) return
        val triggerAt = phaseEndMillis()
        if (triggerAt <= System.currentTimeMillis()) return

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
        } catch (_: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
        }
    }

    private fun cancelAlarm() {
        val am = getSystemService(ALARM_SERVICE) as AlarmManager
        am.cancel(alarmIntent())
    }

    // ---- 通知 ----

    private fun ensureForeground() {
        val n = buildTimerNotification(remainingSeconds())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_TIMER_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_TIMER_ID, n)
        }
    }

    private fun actionIntent(action: String, requestCode: Int): PendingIntent = PendingIntent.getService(
        this, requestCode,
        Intent(this, TimerForegroundService::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun phaseLabel(): String = when {
        pausedAtMs != null -> "已暂停"
        phase == "shortBreak" -> "短休息中"
        phase == "longBreak" -> "长休息中"
        else -> "专注中"
    }

    private fun buildTimerNotification(remaining: Int): Notification {
        val mm = remaining / 60
        val ss = remaining % 60
        val text = String.format("剩余 %02d:%02d", mm, ss)

        val b = Notification.Builder(this, CHANNEL_TIMER)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(phaseLabel())
            .setContentText(text)
            .setContentIntent(contentIntent(this))
            .setOngoing(true)
            .setOnlyAlertOnce(true)

        if (pausedAtMs != null) {
            b.addAction(
                Notification.Action.Builder(
                    null, "继续", actionIntent(ACTION_RESUME, 11)
                ).build()
            )
        } else {
            b.addAction(
                Notification.Action.Builder(
                    null, "暂停", actionIntent(ACTION_PAUSE, 10)
                ).build()
            )
        }
        b.addAction(
            Notification.Action.Builder(
                null, "跳过", actionIntent(ACTION_SKIP, 12)
            ).build()
        )
        return b.build()
    }

    private fun notifyTimer(remaining: Int) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_TIMER_ID, buildTimerNotification(remaining))
    }

    /** 到点提醒：铃声 + 震动走 IMPORTANCE_HIGH 通道 */
    private fun notifyAlarm() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(
            NOTIF_ALARM_ID,
            buildAlarmNotification(
                this,
                phase,
                silent = !remindSound,
                vibrate = remindVibrate,
            ),
        )
    }

    /** 把当前状态写进静态快照，供 Dart 回前台时 getState 对齐 */
    private fun publishState() {
        lastState = mapOf(
            KEY_PHASE to phase,
            KEY_STARTED_AT to startedAtMs,
            KEY_PLANNED to plannedSeconds,
            KEY_PAUSED_AT to (pausedAtMs ?: 0L),
            KEY_PAUSED_TOTAL to pausedTotalSeconds,
            KEY_COMPLETED to completed,
            KEY_AUTO_START to autoStart,
            KEY_FOCUS_MIN to focusMin,
            KEY_SHORT_MIN to shortMin,
            KEY_LONG_MIN to longMin,
            KEY_INTERVAL to interval,
        )
    }

    private fun stopCompat() {
        running = false
        handler.removeCallbacksAndMessages(null)
        cancelAlarm()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }
}
