import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../data/services/ocr_service.dart';
import '../../../domain/ocr/ocr_result.dart';
import '../../widgets/ambient_background.dart';
import '../../widgets/app_card.dart';

/// 「导入课表」页 —— 课表方案 A 阶段一：**把 OCR 管道跑通**。
///
/// 这一版只做「选图 → 离线识别 → 展示结果」，**不解析、不落库**。
///
/// 为什么先只做这一步：课表识别的难点根本不在认字，而在**版面结构** ——
/// 哪一列是星期、哪一行是节次、课程名/老师/教室怎么分、周次信息长什么样。
/// 而"该按什么规则切分"完全取决于 OCR 实际吐出什么。所以先拿真实截图
/// 跑出结果、看清结构，再照着结果写解析器，而不是猜着写。
///
/// 结果页保留每个文本行的**坐标**并支持一键复制 —— 坐标是解析器的输入，
/// 复制出来就能拿去设计切分规则。
class ImportTimetablePage extends StatefulWidget {
  const ImportTimetablePage({super.key});

  @override
  State<ImportTimetablePage> createState() => _ImportTimetablePageState();
}

class _ImportTimetablePageState extends State<ImportTimetablePage> {
  static const OcrService _ocr = OcrService();

  String? _imagePath;
  OcrResult? _result;
  bool _busy = false;
  String? _error;

  Future<void> _pickAndRecognize() async {
    setState(() {
      _error = null;
      _result = null;
    });

    final XFile? picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return; // 用户取消，保持原样

    setState(() {
      _imagePath = picked.path;
      _busy = true;
    });

    try {
      final OcrResult r = await _ocr.recognizeFile(picked.path);
      // 调试构建下把识别结果打进 logcat —— 解析器的输入就是这批带坐标的文本行，
      // 开发阶段需要能直接读到真实输出（release 构建不会打，避免把课表内容留在日志里）
      if (kDebugMode) {
        debugPrint('[OCR] blocks=${r.blocks.length}');
        debugPrint(r.debugDump);
      }
      if (!mounted) return;
      setState(() {
        _result = r;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '识别失败：$e';
        _busy = false;
      });
    }
  }

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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.tight,
                  AppSpacing.page,
                  AppSpacing.section,
                ),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: '返回',
                      ),
                      Expanded(
                        child: Text('导入课表', style: text.titleLarge),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.tight),

                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('第一步：识别', style: text.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          '选一张课表截图，本机离线识别。'
                          '图片不会上传到任何地方。',
                          style: text.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.item),
                        FilledButton.icon(
                          onPressed: _busy ? null : _pickAndRecognize,
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('选择课表截图'),
                        ),
                      ],
                    ),
                  ),

                  if (_busy) ...<Widget>[
                    const SizedBox(height: AppSpacing.section),
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: AppSpacing.tight),
                    Center(
                      child: Text('识别中…', style: text.bodySmall),
                    ),
                  ],

                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.section),
                    AppCard(
                      child: Text(
                        _error!,
                        style: text.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],

                  if (_imagePath != null && _result != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.section),
                    _SectionLabel('截图'),
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.tight),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppRadius.cardMedium),
                        child: Image.file(
                          File(_imagePath!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.section),
                    _SectionLabel('识别到 ${_result!.blocks.length} 个文本行'),
                    AppCard(
                      child: SelectableText(
                        _result!.debugDump,
                        style: text.bodySmall?.copyWith(
                          height: 1.9,
                          fontFeatures: const <FontFeature>[
                            FontFeature('tnum'),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.section),
                    _SectionLabel('整段文本（ML Kit 的版面判断）'),
                    AppCard(
                      child: SelectableText(
                        _result!.rawText,
                        style: text.bodySmall?.copyWith(height: 1.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: AppSpacing.tight),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}
