import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/task/task.dart';

/// 任务领域模型的单测（M5-①）。全是纯函数，不需要数据库。
void main() {
  final DateTime t0 = DateTime(2026, 10, 5, 9, 0, 0);

  Task task({
    required int id,
    String title = '任务',
    int estimated = 1,
    int completed = 0,
    bool done = false,
    int order = 0,
    DateTime? completedAt,
  }) =>
      Task(
        id: id,
        title: title,
        estimatedPomodoros: estimated,
        completedPomodoros: completed,
        isDone: done,
        sortOrder: order,
        createdAt: t0,
        completedAt: completedAt,
      );

  group('番茄进度', () {
    test('正常比例', () {
      expect(task(id: 1, estimated: 4, completed: 1).progress, 0.25);
      expect(task(id: 1, estimated: 4, completed: 4).progress, 1.0);
    });

    test('★ 超额完成时进度封顶在 1.0，不会画出界', () {
      expect(task(id: 1, estimated: 2, completed: 5).progress, 1.0);
      expect(task(id: 1, estimated: 2, completed: 5).isOverrun, isTrue);
    });

    test('★ 预估为 0 时按已完成算满，避免除零', () {
      final Task t = task(id: 1, estimated: 0, completed: 0);
      expect(t.progress, 1.0);
      expect(t.progress.isNaN, isFalse);
    });

    test('未超额时 isOverrun 为 false', () {
      expect(task(id: 1, estimated: 3, completed: 3).isOverrun, isFalse);
    });
  });

  group('sortedForDisplay 展示顺序', () {
    test('未完成在前，且按 sortOrder 升序', () {
      final List<Task> input = <Task>[
        task(id: 1, title: 'C', order: 3),
        task(id: 2, title: 'A', order: 1),
        task(id: 3, title: 'B', order: 2),
      ];
      expect(
        sortedForDisplay(input).map((Task t) => t.title).toList(),
        <String>['A', 'B', 'C'],
      );
    });

    test('★ 已完成一律沉底，即使 sortOrder 很小', () {
      final List<Task> input = <Task>[
        task(id: 1, title: '做完了', order: 0, done: true, completedAt: t0),
        task(id: 2, title: '还没做', order: 99),
      ];
      expect(
        sortedForDisplay(input).map((Task t) => t.title).toList(),
        <String>['还没做', '做完了'],
      );
    });

    test('★ 已完成的内部按完成时间倒序（最近完成的在最上面）', () {
      final List<Task> input = <Task>[
        task(
          id: 1,
          title: '早完成',
          done: true,
          completedAt: t0,
        ),
        task(
          id: 2,
          title: '晚完成',
          done: true,
          completedAt: t0.add(const Duration(hours: 2)),
        ),
      ];
      expect(
        sortedForDisplay(input).map((Task t) => t.title).toList(),
        <String>['晚完成', '早完成'],
      );
    });

    test('sortOrder 相同时按 id 稳定排序（结果可预期）', () {
      final List<Task> input = <Task>[
        task(id: 5, title: 'B', order: 1),
        task(id: 3, title: 'A', order: 1),
      ];
      expect(
        sortedForDisplay(input).map((Task t) => t.id).toList(),
        <int>[3, 5],
      );
    });

    test('不修改传入的列表（纯函数）', () {
      final List<Task> input = <Task>[
        task(id: 2, order: 2),
        task(id: 1, order: 1),
      ];
      final List<int> before = input.map((Task t) => t.id).toList();
      sortedForDisplay(input);
      expect(input.map((Task t) => t.id).toList(), before);
    });
  });

  group('nextSortOrder', () {
    test('空列表从 0 开始', () => expect(nextSortOrder(<Task>[]), 0));
    test('取最大值 +1', () {
      expect(
        nextSortOrder(<Task>[task(id: 1, order: 3), task(id: 2, order: 7)]),
        8,
      );
    });
  });

  group('TaskMapper 行映射', () {
    test('round-trip 无损（含 completedAt）', () {
      final Task t = task(
        id: 7,
        title: '写方案',
        estimated: 3,
        completed: 2,
        done: false,
        order: 5,
        completedAt: null,
      );
      final Task back = TaskMapper.fromRow(TaskMapper.toRow(t));
      expect(back, t);
    });

    test('布尔存成 0/1，读回来还是布尔', () {
      final Map<String, Object?> row = TaskMapper.toRow(
        task(id: 1, done: true, completedAt: t0),
      );
      expect(row['is_done'], 1);
      expect(TaskMapper.fromRow(row).isDone, isTrue);
    });

    test('★ toInsertRow 不含 id（交给 SQLite 自增）', () {
      final Map<String, Object?> row =
          TaskMapper.toInsertRow(task(id: 999));
      expect(row.containsKey('id'), isFalse);
      expect(row['title'], '任务');
    });

    test('脏数据（缺字段 / 时间格式不对）不抛异常', () {
      final Task t = TaskMapper.fromRow(<String, Object?>{
        'id': 1,
        'title': 'x',
        'created_at': '不是时间',
      });
      expect(t.estimatedPomodoros, 1, reason: '缺字段回退默认');
      expect(t.completedAt, isNull);
    });
  });
}
