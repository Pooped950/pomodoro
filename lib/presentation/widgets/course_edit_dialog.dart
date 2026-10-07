import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import 'app_dialog.dart';

/// 加课 / 改课共用的字段草稿
class CourseDraft {
  const CourseDraft({
    required this.name,
    required this.location,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
  });

  final String name;
  final String location;
  final int weekday;
  final int startPeriod;
  final int endPeriod;
}

/// 编辑一门课的字段：课名 / 教室 / 星期几 / 起止节次。
///
/// 导入流程（逐格核对）和课表页（三点点菜单里的「加课」）共用 ——
/// 字段和校验只有一份，两边的编辑体验才是一致的。
///
/// 居中弹窗（用户的既定偏好，不用底部弹层）。
Future<CourseDraft?> showCourseEditDialog(
  BuildContext context, {
  required String title,
  String name = '',
  String location = '',
  int weekday = 1,
  int startPeriod = 1,
  int endPeriod = 1,
  String confirmLabel = '保存',
}) {
  return showAppDialog<CourseDraft>(
    context: context,
    builder: (BuildContext _) => _CourseEditDialog(
      title: title,
      name: name,
      location: location,
      weekday: weekday,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      confirmLabel: confirmLabel,
    ),
  );
}

class _CourseEditDialog extends StatefulWidget {
  const _CourseEditDialog({
    required this.title,
    required this.name,
    required this.location,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.confirmLabel,
  });

  final String title;
  final String name;
  final String location;
  final int weekday;
  final int startPeriod;
  final int endPeriod;
  final String confirmLabel;

  @override
  State<_CourseEditDialog> createState() => _CourseEditDialogState();
}

class _CourseEditDialogState extends State<_CourseEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  late final TextEditingController _location =
      TextEditingController(text: widget.location);
  late int _weekday = widget.weekday.clamp(1, 7);
  late int _start = widget.startPeriod;
  late int _end = widget.endPeriod;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '课程名',
                hintText: '例如：材料力学',
              ),
            ),
            const SizedBox(height: AppSpacing.tight),
            TextField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: '教室',
                hintText: '例如：教学楼 307',
              ),
            ),
            const SizedBox(height: AppSpacing.item),

            Text('星期几', style: text.bodyMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: <Widget>[
                for (int d = 1; d <= 7; d++)
                  ChoiceChip(
                    label: Text(
                      const <String>['一', '二', '三', '四', '五', '六', '日'][d - 1],
                    ),
                    selected: _weekday == d,
                    onSelected: (_) => setState(() => _weekday = d),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.item),

            Text('第几节', style: text.bodyMedium),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                _Stepper(
                  label: '从',
                  value: _start,
                  min: 1,
                  max: 20,
                  onChanged: (int v) => setState(() {
                    _start = v;
                    if (_end < _start) _end = _start;
                  }),
                ),
                const SizedBox(width: AppSpacing.item),
                _Stepper(
                  label: '到',
                  value: _end,
                  min: _start,
                  max: 20,
                  onChanged: (int v) => setState(() => _end = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(CourseDraft(
            name: _name.text,
            location: _location.text,
            weekday: _weekday,
            startPeriod: _start,
            endPeriod: _end,
          )),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
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

    return Row(
      children: <Widget>[
        Text(label, style: text.bodySmall),
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
    );
  }
}
