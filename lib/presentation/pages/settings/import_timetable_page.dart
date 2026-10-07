import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../core/theme/motion_tokens.dart';
import '../../../core/theme/timetable_palette.dart';
import '../../../data/repositories/timetable_repository.dart';
import '../../../data/services/image_stitch_service.dart';
import '../../../data/services/ocr_service.dart';
import '../../../domain/ocr/image_stitcher.dart';
import '../../../domain/ocr/ocr_result.dart';
import '../../../domain/ocr/timetable_grid.dart';
import '../../../domain/timetable/course.dart';
import '../../../domain/timetable/period_time.dart';
import '../../widgets/ambient_background.dart';
import '../../widgets/app_card.dart';
import '../../widgets/course_edit_dialog.dart';
import '../../widgets/glass_primary_button.dart';
import '../../widgets/motion_scope.dart';
import '../../widgets/pressable.dart';
import 'schedule_preview.dart';

/// 导入课表 —— 四步走完，最后落库。
///
/// ```
/// ① 选两张图  →  ② 拼图确认  →  ③ 时间设置  →  ④ 逐格核对  →  导入完成
/// ```
///
/// ## 为什么是一页里的四步，而不是四个页面
///
/// 这四步共用同一份中间状态（两张图路径、拼好的图、识别结果、用户填的锚点），
/// 拆成四个页面就得把这份状态传来传去，或者塞进一个全局 provider ——
/// 前者啰嗦，后者会让"导入到一半退出"留下脏状态。
///
/// 一页里的步骤切换用 `AnimatedSwitcher` 淡入淡出 + 轻微上浮，
/// 时长曲线走 `motion_tokens`（和全 App 一套）。
///
/// ## 用户在哪一步能反悔
///
/// - ①②之间：随便重选
/// - ②③之间：拼歪了可以手动调重叠高度，或者退回去重选图
/// - ③④之间：时间填错了随时回来改
/// - ④之后：**还没写库**，点「确认导入」才落库 —— 在此之前退出等于什么都没发生
enum _Step { pick, stitch, setup, review, done }

class ImportTimetablePage extends ConsumerStatefulWidget {
  const ImportTimetablePage({super.key});

  @override
  ConsumerState<ImportTimetablePage> createState() =>
      _ImportTimetablePageState();
}

class _ImportTimetablePageState extends ConsumerState<ImportTimetablePage> {
  static const ImageStitchService _stitchService = ImageStitchService();
  static const OcrService _ocr = OcrService();

  _Step _step = _Step.pick;

  // ---- ① 选图 ----
  String? _topPath;
  String? _bottomPath;

  // ---- ② 拼图 ----
  bool _stitchBusy = false;
  StitchOutcome? _stitched;
  String? _stitchError;
  /// 用户手动指定的重叠高度（null = 用自动算出来的）
  int? _manualOverlap;

  // ---- ③ 识别 ----
  bool _recognizeBusy = false;
  ParsedTimetable? _parsed;
  String? _recognizeError;

  // ---- ③ 时间设置 ----
  final TextEditingController _firstStart = TextEditingController(text: '08:00');
  final TextEditingController _morningEnd =
      TextEditingController(text: '11:40');
  final TextEditingController _afternoonStart =
      TextEditingController(text: '14:00');
  final TextEditingController _lastEnd = TextEditingController(text: '17:30');
  final TextEditingController _periodMinutes =
      TextEditingController(text: '45');
  final TextEditingController _eveningStart =
      TextEditingController(text: '19:00');
  final TextEditingController _eveningEnd =
      TextEditingController(text: '21:30');
  bool _hasEvening = false;
  String? _anchorError;

  /// 用户有没有动过任意一个时间输入 —— 没动过时预览是"预填默认值的
  /// 示意"，整块淡显（2026-10-07 用户要求：没输入时预览不该抢眼）
  bool _timesTouched = false;

  void _markTimesTouched() {
    if (_timesTouched) return;
    setState(() => _timesTouched = true);
  }

  // ---- ③ 官方作息表（粘贴，精确时间） ----
  // 锚点 + 均匀间隔是近似（真实课间不均匀），有官方表就按表来。
  final TextEditingController _periodTable = TextEditingController();
  List<PeriodTime>? _pastedPeriods;

  // ---- ③ 上午节数（识别只能猜，用户改得起） ----
  /// null = 跟随识别的猜测；用户动过步进器后就是明确值
  int? _morningCountOverride;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _firstStart,
      _morningEnd,
      _afternoonStart,
      _lastEnd,
      _periodMinutes,
      _eveningStart,
      _eveningEnd,
      _periodTable,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- ④ 核对 ----
  final List<_DraftCourse> _draft = <_DraftCourse>[];

  bool _saving = false;

  // ==================================================================
  // ① 选图
  // ==================================================================

  Future<void> _pick({required bool isTop}) async {
    final XFile? picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      if (isTop) {
        _topPath = picked.path;
      } else {
        _bottomPath = picked.path;
      }
      // 换了图，之前拼的、识别的全作废
      _stitched = null;
      _stitchError = null;
      _manualOverlap = null;
      _parsed = null;
      _recognizeError = null;
    });
  }

  // ==================================================================
  // ② 拼图
  // ==================================================================

  Future<void> _runStitch() async {
    final String? top = _topPath;
    final String? bottom = _bottomPath;
    if (top == null || bottom == null) return;

    setState(() {
      _stitchBusy = true;
      _stitchError = null;
    });

    try {
      final int? manual = _manualOverlap;
      final StitchOutcome? outcome = manual == null
          ? await _stitchService.stitchAuto(topPath: top, bottomPath: bottom)
          : await _stitchService.stitchWithOverlap(
              topPath: top,
              bottomPath: bottom,
              overlapPixels: manual,
              // 固定装饰要原样带上，否则手动微调会把状态栏 / 导航栏当成内容拼进去
              chrome: _stitched?.chrome ?? ChromeInsets.none,
            );

      if (!mounted) return;
      setState(() {
        _stitchBusy = false;
        if (outcome == null) {
          _stitched = null;
          _stitchError = '这两张图找不到足够像的重叠部分。'
              '可能截的时候两张之间没有重复的内容 —— '
              '重新截一次，让下面那张的顶部和上面那张的底部有大约五分之一屏的重复。';
        } else {
          _stitched = outcome;
          _manualOverlap = outcome.overlapPixels;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stitchBusy = false;
        _stitchError = '拼图出错：$e';
      });
    }
  }

  void _nudgeOverlap(int delta) {
    final StitchOutcome? cur = _stitched;
    if (cur == null) return;
    final int next = (cur.overlapPixels + delta).clamp(0, 4000);
    if (next == cur.overlapPixels) return;
    setState(() => _manualOverlap = next);
    _runStitch();
  }

  // ==================================================================
  // ③ 识别
  // ==================================================================

  Future<void> _runRecognize() async {
    final StitchOutcome? stitched = _stitched;
    if (stitched == null) return;

    setState(() {
      _recognizeBusy = true;
      _recognizeError = null;
    });

    try {
      final OcrResult result = await _ocr.recognizeFile(stitched.path);
      // 拼图原始像素给几何分析用：课程块的第几节到第几节量自色块，
      // 比文字坐标可信（文字挤在块顶，量不出大块的真实跨度）
      final TimetablePixels? pixels = await _ocr.pixelsOf(stitched.path);
      ParsedTimetable? parsed;
      String? error;
      try {
        parsed = parseTimetable(result.blocks, pixels: pixels);
      } on TimetableParseException catch (e) {
        error = e.message;
      } catch (e) {
        error = '解析出现意外错误：$e';
      }

      if (!mounted) return;
      setState(() {
        _recognizeBusy = false;
        _parsed = parsed;
        _recognizeError = error;
        if (parsed != null) {
          _draft
            ..clear()
            ..addAll(parsed.cells.map(_DraftCourse.fromCell));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recognizeBusy = false;
        _recognizeError = '识别失败：$e';
      });
    }
  }

  // ==================================================================
  // ③ 时间锚点 → 节次时间表
  // ==================================================================

  /// 上午有几节 —— 用户改过就用用户的；没改过用识别的猜测
  /// （猜测靠节次栏的纵向间隔找午休，行距不均匀时不可靠，所以允许改）
  int get _morningCount {
    final int? override = _morningCountOverride;
    if (override != null) return override;
    final List<PeriodAnchor> anchors =
        _parsed?.periodAnchors ?? const <PeriodAnchor>[];
    return morningPeriodCountFromAnchors(
      anchors.map((PeriodAnchor a) => a.centerY).toList(),
    );
  }

  /// 一共几节：优先数节次栏；截图里没有节次栏时退回"课程格里最大的节次"
  int get _totalPeriods {
    final List<PeriodAnchor> anchors =
        _parsed?.periodAnchors ?? const <PeriodAnchor>[];
    if (anchors.isNotEmpty) return anchors.length;
    int max = 0;
    for (final ParsedCell c in _parsed?.cells ?? const <ParsedCell>[]) {
      final int p = c.endPeriod ?? 0;
      if (p > max) max = p;
    }
    return max;
  }

  /// 粘贴的作息表解析结果（空文本 = 没粘贴）
  void _onPeriodTableChanged(String text) {
    final List<PeriodTime>? parsed =
        text.trim().isEmpty ? null : parsePeriodTable(text);
    setState(() => _pastedPeriods = parsed);
  }

  /// 最终落库的节次时间表：优先官方作息表（精确），退回锚点估算
  TimetableSchedule? _buildSchedule() {
    final List<PeriodTime>? pasted = _pastedPeriods;
    if (pasted != null) {
      EveningBlock? evening;
      if (_hasEvening) {
        final int? s = labelToMinutes(_eveningStart.text);
        final int? e = labelToMinutes(_eveningEnd.text);
        if (s == null || e == null || e <= s) return null;
        evening = EveningBlock(startMinute: s, endMinute: e);
      }
      return TimetableSchedule(periods: pasted, evening: evening);
    }
    final ScheduleAnchors? anchors = _readAnchors();
    return anchors == null ? null : buildSchedule(anchors);
  }

  ScheduleAnchors? _readAnchors() {
    final int? first = labelToMinutes(_firstStart.text);
    final int? amEnd = labelToMinutes(_morningEnd.text);
    final int? pmStart = labelToMinutes(_afternoonStart.text);
    final int? last = labelToMinutes(_lastEnd.text);
    final int? minutes = int.tryParse(_periodMinutes.text.trim());

    if (first == null ||
        amEnd == null ||
        pmStart == null ||
        last == null ||
        minutes == null ||
        minutes <= 0) {
      return null;
    }

    int? eveStart;
    int? eveEnd;
    if (_hasEvening) {
      eveStart = labelToMinutes(_eveningStart.text);
      eveEnd = labelToMinutes(_eveningEnd.text);
      if (eveStart == null || eveEnd == null || eveEnd <= eveStart) return null;
    }

    final int morning = _morningCount;
    final int total = _totalPeriods;
    return ScheduleAnchors(
      firstStartMinute: first,
      morningEndMinute: amEnd,
      afternoonStartMinute: pmStart,
      lastEndMinute: last,
      periodMinutes: minutes,
      morningPeriodCount: morning,
      afternoonPeriodCount: (total - morning) > 0 ? total - morning : 0,
      eveningStartMinute: eveStart,
      eveningEndMinute: eveEnd,
    );
  }

  // ==================================================================
  // ④ 落库
  // ==================================================================

  Future<void> _confirmImport() async {
    final TimetableSchedule? schedule = _buildSchedule();
    if (schedule == null) {
      setState(() => _anchorError = '时间填得不对：请检查是不是 HH:mm 的格式，'
          '以及晚自习的结束时间是否晚于开始时间。');
      setState(() => _step = _Step.setup);
      return;
    }
    if (_draft.isEmpty) return;

    setState(() => _saving = true);

    final DateTime now = DateTime.now();
    final Map<String, int> colorOf = assignColorIndexes(
      _draft.map((_DraftCourse d) => d.displayName),
      kTimetablePaletteSize,
    );

    final List<Course> courses = <Course>[
      for (final _DraftCourse d in _draft)
        Course(
          id: 0,
          weekday: d.weekday,
          startPeriod: d.startPeriod,
          endPeriod: d.endPeriod,
          name: d.displayName,
          location: d.location.trim(),
          colorIndex: colorOf[d.displayName] ?? 0,
          createdAt: now,
        ),
    ];

    try {
      await ref.read(timetableRepositoryProvider).replaceAll(
            courses: courses,
            schedule: schedule,
          );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _anchorError = '保存失败：$e';
      });
    }
  }

  // ==================================================================
  // 界面
  // ==================================================================

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: Column(
                children: <Widget>[
                  _header(text),
                  Expanded(child: _body()),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(TextTheme text) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Motion motion = MotionScope.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.tight,
        AppSpacing.tight,
        AppSpacing.page,
        AppSpacing.tight,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () {
              if (_step == _Step.pick || _step == _Step.done) {
                Navigator.of(context).maybePop();
              } else {
                setState(() => _step = _Step.values[_step.index - 1]);
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: _step == _Step.pick ? '返回' : '上一步',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('导入课表', style: text.titleMedium),
                // 步骤文字用 AnimatedSwitcher 换，和内容切换同一个节奏
                AnimatedSwitcher(
                  duration: motion.standard,
                  switchInCurve: MotionTokens.emphasized,
                  switchOutCurve: MotionTokens.soft,
                  child: Text(
                    _stepLabel,
                    key: ValueKey<String>(_stepLabel),
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _stepLabel => switch (_step) {
        _Step.pick => '第 1 步 / 共 4 步 · 选两张截图',
        _Step.stitch => '第 2 步 / 共 4 步 · 拼成一张完整的',
        _Step.setup => '第 3 步 / 共 4 步 · 填上课时间',
        _Step.review => '第 4 步 / 共 4 步 · 核对每一节',
        _Step.done => '导入完成',
      };

  Widget _body() {
    final Motion motion = MotionScope.of(context);
    final Widget child = switch (_step) {
      _Step.pick => _buildPick(),
      _Step.stitch => _buildStitch(),
      _Step.setup => _buildSetup(),
      _Step.review => _buildReview(),
      _Step.done => _buildDone(),
    };

    return AnimatedSwitcher(
      duration: motion.pageExit,
      switchInCurve: MotionTokens.emphasized,
      switchOutCurve: MotionTokens.soft,
      transitionBuilder: (Widget child, Animation<double> a) {
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(a),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<_Step>(_step), child: child),
    );
  }

  Widget _footer() {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final ({String label, IconData icon, VoidCallback? onTap})? action =
        switch (_step) {
      _Step.pick => _topPath != null && _bottomPath != null
          ? (
              label: '下一步：拼图',
              icon: Icons.auto_awesome_motion_rounded,
              onTap: () {
                setState(() {
                  _step = _Step.stitch;
                  _manualOverlap = null;
                });
                _runStitch();
              },
            )
          : null,
      _Step.stitch => _stitched == null
          ? null
          : (
              label: '下一步：识别',
              icon: Icons.text_fields_rounded,
              onTap: () {
                setState(() => _step = _Step.setup);
                _runRecognize();
              },
            ),
      _Step.setup => (
          label: '下一步：核对',
          icon: Icons.fact_check_outlined,
          onTap: () {
            setState(() {
              _anchorError = null;
              _step = _Step.review;
            });
          },
        ),
      _Step.review => _draft.isEmpty
          ? null
          : (
              label: _saving ? '正在保存…' : '确认导入（${_draft.length} 节课）',
              icon: Icons.check_rounded,
              onTap: _saving ? null : _confirmImport,
            ),
      _Step.done => (
          label: '返回课表',
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.of(context).maybePop(),
        ),
    };

    if (action == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.tight,
          AppSpacing.page,
          AppSpacing.section,
        ),
        child: Text(
          switch (_step) {
            _Step.pick => '两张都选好了才能继续',
            _Step.stitch => _stitchBusy ? '正在拼…' : '先看看拼得对不对',
            _Step.review => '识别到的课程是空的，退回上一步看看',
            _ => '',
          },
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.tight,
        AppSpacing.page,
        AppSpacing.section,
      ),
      child: GlassPrimaryButton(
        key: ValueKey<String>(action.label),
        label: action.label,
        icon: action.icon,
        accent: scheme.primary,
        onPressed: action.onTap ?? () {},
      ),
    );
  }

  // ------------------------------------------------------------------
  // ① 选图
  // ------------------------------------------------------------------

  Widget _buildPick() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.item,
      ),
      children: <Widget>[
        _HintCard(
          icon: Icons.crop_free_rounded,
          title: '先截两张图',
          body: '在你的课表页面里，先截上半张，往下滚动一屏再截下半张。'
              '两张中间留大约五分之一屏的重复内容 —— '
              'App 靠这段重复把接缝对上。',
        ),
        const SizedBox(height: AppSpacing.item),
        _PickSlot(
          label: '上半张',
          path: _topPath,
          onTap: () => _pick(isTop: true),
        ),
        const SizedBox(height: AppSpacing.tight),
        _PickSlot(
          label: '下半张',
          path: _bottomPath,
          onTap: () => _pick(isTop: false),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // ② 拼图
  // ------------------------------------------------------------------

  Widget _buildStitch() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    if (_stitchBusy) {
      return const Center(child: CircularProgressIndicator());
    }

    final String? error = _stitchError;
    if (error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        children: <Widget>[
          _HintCard(
            icon: Icons.error_outline_rounded,
            title: '拼不上',
            body: error,
            danger: true,
          ),
          const SizedBox(height: AppSpacing.item),
          AppCard(
            child: Pressable(
              onTap: _runStitch,
              borderRadius: BorderRadius.circular(AppRadius.cardMedium),
              highlightColor: scheme.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.refresh_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('再试一次', style: text.bodyMedium),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final StitchOutcome? stitched = _stitched;
    if (stitched == null) {
      return const Center(child: Text('还没有拼图结果'));
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: _ConfidenceBanner(outcome: stitched),
        ),
        const SizedBox(height: AppSpacing.tight),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.cardMedium),
              color: scheme.onSurface.withValues(alpha: 0.05),
            ),
            child: SingleChildScrollView(
              child: Image.file(File(stitched.path), fit: BoxFit.fitWidth),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.tight),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '接缝不对？微调重叠高度',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              _NudgeButton(
                icon: Icons.remove_rounded,
                onTap: () => _nudgeOverlap(-20),
              ),
              SizedBox(
                width: 76,
                child: Text(
                  '${stitched.overlapPixels} px',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    fontFeatures: const <FontFeature>[FontFeature('tnum')],
                  ),
                ),
              ),
              _NudgeButton(
                icon: Icons.add_rounded,
                onTap: () => _nudgeOverlap(20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // ③ 时间设置
  // ------------------------------------------------------------------

  Widget _buildSetup() {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (_recognizeBusy) {
      return const Center(child: CircularProgressIndicator());
    }

    final int morning = _morningCount;
    final int total = _totalPeriods;
    final int afternoon = total - morning;
    final List<PeriodTime>? pasted = _pastedPeriods;

    // 锚点路线的可行性检查：节数 × 时长装不进锚点区间就提前说，
    // 不然排出"11:45~11:40"这种倒挂用户才发现（2026-10-07 实测踩到）
    String? infeasibleHint;
    if (pasted == null) {
      final int? first = labelToMinutes(_firstStart.text);
      final int? amEnd = labelToMinutes(_morningEnd.text);
      final int? minutes = int.tryParse(_periodMinutes.text.trim());
      if (first != null && amEnd != null && minutes != null && minutes > 0) {
        final int need = total > morning ? morning : total;
        final int room = amEnd - first - need * minutes;
        if (room < 0) {
          infeasibleHint = '按"上午 $need 节 × $minutes 分钟"，'
              '8:00 这类起点到"上午最后一节结束"之间还差 ${-room} 分钟排不下 —— '
              '检查一下上午节数是不是多了，或时间填小了。';
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.item,
      ),
      children: <Widget>[
        if (_recognizeError != null) ...<Widget>[
          _HintCard(
            icon: Icons.error_outline_rounded,
            title: '识别/解析没成功',
            body: '$_recognizeError\n\n'
                '可以先按下面的时间把课表建起来（课表内容之后再补），'
                '或者退回上一步重新截两张更清楚的图。',
            danger: true,
          ),
          const SizedBox(height: AppSpacing.item),
        ] else
          _HintCard(
            icon: Icons.check_circle_outline_rounded,
            title: '识别到 $total 节 · 上午 $morning 节 / 下午 $afternoon 节',
            body: '上午/下午的分界是猜的（猜错了下面能改）。'
                '每节课的时间有两种填法：有官方作息表就直接粘贴，'
                '没有就填锚点估算 —— 以后都能在课表页逐节改。',
          ),
        const SizedBox(height: AppSpacing.item),

        // ---- 官方作息表（推荐）：精确到每节课 ----
        AppCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.item,
            AppSpacing.tight,
            AppSpacing.item,
            AppSpacing.tight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.table_chart_rounded,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '官方作息表（推荐，排得最准）',
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.tight),
              Text(
                '每节课几点上下课，学校一般有官方表。'
                '从 Excel 或通知里复制过来粘进下面就行，'
                '格式像「08:00 ~ 08:45」，一行一条或整行带制表符都可以。',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.tight),
              TextField(
                controller: _periodTable,
                onChanged: _onPeriodTableChanged,
                minLines: 3,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: '08:00 ~ 08:45\n08:55 ~ 09:40\n…',
                ),
              ),
              if (pasted != null) ...<Widget>[
                const SizedBox(height: AppSpacing.tight),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '认出 ${pasted.length} 节的精确时间，'
                      '下面的估算不用填了',
                      style: text.bodySmall?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        if (pasted == null) ...<Widget>[
          const SizedBox(height: AppSpacing.item),
          AppCard(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.item,
              AppSpacing.tight,
              AppSpacing.item,
              AppSpacing.tight,
            ),
            child: Column(
              children: <Widget>[
                _TimeRow(
                  label: '最早一节课开始',
                  controller: _firstStart,
                  onEdited: _markTimesTouched,
                ),
                _TimeRow(
                  label: '上午最后一节结束',
                  controller: _morningEnd,
                  onEdited: _markTimesTouched,
                ),
                _TimeRow(
                  label: '下午第一节开始',
                  controller: _afternoonStart,
                  onEdited: _markTimesTouched,
                ),
                _TimeRow(
                  label: '最晚一节课结束',
                  controller: _lastEnd,
                  onEdited: _markTimesTouched,
                ),
                _TimeRow(
                  label: '每节课时长',
                  controller: _periodMinutes,
                  suffix: '分钟',
                  isTime: false,
                  onEdited: _markTimesTouched,
                ),
                _CountRow(
                  label: '上午节数（识别猜的是 $morning 节）',
                  value: morning,
                  min: 0,
                  max: total,
                  onChanged: (int v) =>
                      setState(() => _morningCountOverride = v),
                ),
              ],
            ),
          ),
          if (infeasibleHint != null) ...<Widget>[
            const SizedBox(height: AppSpacing.tight),
            Text(
              infeasibleHint,
              style: text.bodySmall?.copyWith(
                color: scheme.error,
                height: 1.5,
              ),
            ),
          ],
        ],

        const SizedBox(height: AppSpacing.item),
        AppCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.item,
            AppSpacing.tight,
            AppSpacing.item,
            AppSpacing.tight,
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('有晚自习吗', style: text.bodyMedium),
                  ),
                  Switch(
                    value: _hasEvening,
                    onChanged: (bool v) => setState(() => _hasEvening = v),
                  ),
                ],
              ),
              if (_hasEvening) ...<Widget>[
                _TimeRow(label: '晚自习开始', controller: _eveningStart),
                _TimeRow(label: '晚自习结束', controller: _eveningEnd),
              ],
            ],
          ),
        ),

        if (_anchorError != null) ...<Widget>[
          const SizedBox(height: AppSpacing.item),
          Text(
            _anchorError!,
            style: text.bodySmall?.copyWith(color: scheme.error),
          ),
        ],

        const SizedBox(height: AppSpacing.item),
        SchedulePreview(
          schedule: _buildSchedule(),
          dimmed: _pastedPeriods == null && !_timesTouched,
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // ④ 核对
  // ------------------------------------------------------------------

  Widget _buildReview() {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (_draft.isEmpty) {
      return const Center(child: Text('没有识别到任何课程'));
    }

    final List<_DraftCourse> sorted = List<_DraftCourse>.of(_draft)
      ..sort((_DraftCourse a, _DraftCourse b) {
        final int byDay = a.weekday.compareTo(b.weekday);
        if (byDay != 0) return byDay;
        return a.startPeriod.compareTo(b.startPeriod);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.item,
      ),
      children: <Widget>[
        _HintCard(
          icon: Icons.touch_app_outlined,
          title: '点任意一节改它',
          body: '识别难免认错字（课名、教室都可能）。'
              '点一下那一节就能改课名 / 教室 / 星期几 / 第几节。'
              '确认没问题再点下面的「确认导入」—— 在那之前什么都没写进手机。',
        ),
        const SizedBox(height: AppSpacing.item),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              for (int i = 0; i < sorted.length; i++) ...<Widget>[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: AppSpacing.item,
                    endIndent: AppSpacing.item,
                    color: scheme.onSurface.withValues(alpha: 0.06),
                  ),
                _DraftRow(
                  draft: sorted[i],
                  onTap: () => _editDraft(sorted[i]),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.tight),
        Text(
          '共 ${sorted.length} 节',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }

  Future<void> _editDraft(_DraftCourse draft) async {
    final CourseDraft? edited = await showCourseEditDialog(
      context,
      title: '改这一节',
      name: draft.name,
      location: draft.location,
      weekday: draft.weekday,
      startPeriod: draft.startPeriod,
      endPeriod: draft.endPeriod,
    );
    if (edited == null || !mounted) return;
    setState(() {
      final int i = _draft.indexOf(draft);
      if (i >= 0) {
        _draft[i] = _DraftCourse(
          weekday: edited.weekday,
          startPeriod: edited.startPeriod,
          endPeriod: edited.endPeriod,
          name: edited.name,
          location: edited.location,
          spanningSuspicion: draft.spanningSuspicion,
        );
      }
    });
  }

  // ------------------------------------------------------------------
  // 完成
  // ------------------------------------------------------------------

  Widget _buildDone() {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: scheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(height: AppSpacing.item),
              Text('导入完成', style: text.titleMedium),
              const SizedBox(height: AppSpacing.tight),
              Text(
                '${_draft.length} 节课已经存进手机了，'
                '$_totalPeriods 个节次的时间也排好了。\n\n'
                '⚠️ 现在课表页还只显示"已导入多少节"的概要 —— '
                '**周视图网格是下一步要做的**。',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// ④ 里的草稿课程
// ====================================================================

class _DraftCourse {
  _DraftCourse({
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.name,
    required this.location,
    this.spanningSuspicion = false,
  });

  factory _DraftCourse.fromCell(ParsedCell cell) => _DraftCourse(
        weekday: cell.weekday,
        startPeriod: cell.startPeriod ?? 1,
        endPeriod: cell.endPeriod ?? (cell.startPeriod ?? 1),
        name: cell.courseNameGuess,
        location: cell.locationGuess,
        spanningSuspicion: cell.spanningSuspicion,
      );

  int weekday;
  int startPeriod;
  int endPeriod;
  String name;
  String location;

  /// OCR 把两列的文字并成了一行，内容不可信 —— 界面上标出来提醒用户重点看
  final bool spanningSuspicion;

  String get displayName {
    final String n = name.trim();
    return n.isEmpty ? '未命名课程' : n;
  }

  String get weekdayLabel =>
      const <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日']
          [weekday.clamp(1, 7) - 1];

  String get periodLabel => startPeriod == endPeriod
      ? '第 $startPeriod 节'
      : '第 $startPeriod-$endPeriod 节';
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({required this.draft, required this.onTap});

  final _DraftCourse draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Pressable(
      onTap: onTap,
      highlightColor: scheme.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.item,
          12,
          AppSpacing.tight,
          12,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 76,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    draft.weekdayLabel,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    draft.periodLabel,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          draft.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                      ),
                      if (draft.spanningSuspicion)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 15,
                            color: scheme.error.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                  if (draft.location.trim().isNotEmpty)
                    Text(
                      draft.location.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.edit_outlined,
              size: 17,
              color: scheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

// 公用小件
// ====================================================================

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.icon,
    required this.title,
    required this.body,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final Color tint = danger ? scheme.error : scheme.primary;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 20, color: tint),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: AppSpacing.tight),
          Text(
            body,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickSlot extends StatelessWidget {
  const _PickSlot({
    required this.label,
    required this.path,
    required this.onTap,
  });

  final String label;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    final String? p = path;

    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      highlightColor: scheme.primary.withValues(alpha: 0.06),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: p == null
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.section),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: scheme.primary,
                      size: 26,
                    ),
                    const SizedBox(width: AppSpacing.item),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('选$label', style: text.bodyMedium),
                          Text(
                            '从相册里挑',
                            style: text.bodySmall?.copyWith(
                              color:
                                  scheme.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.card),
                    ),
                    child: Image.file(
                      File(p),
                      height: 150,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.item,
                      AppSpacing.tight,
                      AppSpacing.item,
                      AppSpacing.tight,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(label, style: text.bodySmall)),
                        Text(
                          '换一张',
                          style: text.bodySmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ConfidenceBanner extends StatelessWidget {
  const _ConfidenceBanner({required this.outcome});

  final StitchOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    final bool ok = outcome.isConfident;
    final Color tint = ok ? scheme.primary : scheme.error;

    // 上下两张选反了是常见手滑，算法会自动换过来 —— 但得告诉用户一声，
    // 不然他会以为"我明明选对了"
    final String swapNote =
        outcome.swapped ? '（上下两张选反了，已自动换过来）' : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            ok
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 17,
            color: tint,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            ok
                ? '$swapNote拼好了（${outcome.width}×${outcome.height}，'
                    '上下两半对上了 ${outcome.match?.matchedRows ?? 0} 像素）'
                    '—— 看接缝处有没有错位、下面有没有缺内容'
                : '这两张图重叠得不太确定，仔细看一眼接缝；'
                    '不对就用下面的按钮微调',
            style: text.bodySmall?.copyWith(
              color: ok
                  ? scheme.onSurface.withValues(alpha: 0.6)
                  : scheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      highlightColor: scheme.primary.withValues(alpha: 0.10),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(
          icon,
          size: 19,
          color: scheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// 节数步进行 —— 识别猜的节数能错（第 7 节漏读就少一节），
/// 用户直接加减到自己的真实作息
class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          IconButton(
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_rounded),
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '$value',
            style: text.titleMedium?.copyWith(
              color: scheme.primary,
              fontFeatures: const <FontFeature>[FontFeature('tnum')],
            ),
          ),
          IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_rounded),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.controller,
    this.suffix,
    this.isTime = true,
    this.onEdited,
  });

  final String label;
  final TextEditingController controller;
  final String? suffix;
  final bool isTime;

  /// 用户编辑了这一项（用于"预览还是默认值示意"的判断）
  final VoidCallback? onEdited;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          SizedBox(
            width: 96,
            child: TextField(
              controller: controller,
              onChanged: onEdited == null ? null : (_) => onEdited!(),
              textAlign: TextAlign.right,
              keyboardType: isTime
                  ? TextInputType.datetime
                  : TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                hintText: isTime ? '08:00' : '45',
                suffixText: suffix,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

