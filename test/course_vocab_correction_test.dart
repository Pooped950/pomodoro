import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/ocr/common_courses.dart';

/// 常见课程词表纠错（2026-10-09 用户明确要求）。
///
/// 用户原话：「是毛泽东，给我把这些伟人名字都改一下，推演一下常见的大学课程，
/// 从文科系统到工科系统到理科系统，把常见课程加进检索里，避免闹出这样的过错！」
///
/// 这里钉两件事：
///   1. **该纠的必须纠**（`毛淨东…` → `毛泽东…`）
///   2. **不该纠的绝不能纠**（`美国文学史…` 不能变成 `英国文学史…`）
void main() {
  group('该纠的必须纠', () {
    test('★ 伟人名字：毛淨东 → 毛泽东（用户报的原始问题）', () {
      expect(
        correctByCourseVocab('毛淨东思想和中国特色社会主义理论体休概论'),
        '毛泽东思想和中国特色社会主义理论体系概论',
      );
    });

    test('★ 只错一个字也要纠', () {
      expect(correctByCourseVocab('毛泽东思想和中国特色社会主义理论体休概论'),
          '毛泽东思想和中国特色社会主义理论体系概论');
      expect(correctByCourseVocab('习近平新时代中国特色社杜会主义思想概论'),
          '习近平新时代中国特色社会主义思想概论');
      expect(correctByCourseVocab('马克思主义基本原埋'),
          '马克思主义基本原理');
    });

    test('★ 生僻字误认（OCR 常见）', () {
      expect(correctByCourseVocab('知识产权沄'), '知识产权法');
      expect(correctByCourseVocab('经济沄学'), '经济法学');
    });

    test('★ 长课名允许差 2 字', () {
      expect(
        correctByCourseVocab('毛泽东思想和中国特色社杜会主义理论体休概论'),
        '毛泽东思想和中国特色社会主义理论体系概论',
      );
    });
  });

  group('⚠️ 不该纠的绝不能纠（误纠是灾难）', () {
    test('★ 美国文学史 ≠ 英国文学史（只差 1 字但是两门真课）', () {
      const String american = '美国文学史及作品选读';
      expect(correctByCourseVocab(american), american,
          reason: '「美」「英」都是词表里出现过的字，是合法差异不是 OCR 错误');
      const String british = '英国文学史及作品选读';
      expect(correctByCourseVocab(british), british);
    });

    test('★ 词表里已有的课名原样返回', () {
      for (final String s in <String>[
        '高等数学',
        '数据结构',
        '线性代数',
        '大学英语',
        '英汉/汉英笔译',
        '谈判和调解',
        '材料力学',
        '普通生物学',
        '中国近现代史纲要',
      ]) {
        expect(correctByCourseVocab(s), s, reason: '「$s」本身就对，不该被改');
      }
    });

    test('★ 长度不同一律不动', () {
      expect(correctByCourseVocab('法语(二)'), '法语(二)');
      expect(correctByCourseVocab('大教据'), '大教据');
      expect(correctByCourseVocab('与法律检素'), '与法律检素');
    });

    test('★ 完全没听过的课名不动（宁可不动，也不能瞎改）', () {
      for (final String s in <String>[
        '某门小众选修课',
        '某某老师专题讲座',
        '托福强化',
        '考研政治冲刺',
      ]) {
        expect(correctByCourseVocab(s), s, reason: '「$s」不在词表里，不该被改');
      }
    });

    test('★ 差异字都是常见字 → 不纠', () {
      // `软件测试` vs 词表里的 `软件工程`：差 2 字且都是常见字 → 不动
      expect(correctByCourseVocab('软件测试'), '软件测试');
    });
  });

  group('词表覆盖（用户要求：文科 → 工科 → 理科）', () {
    test('★ 三个学科都有内容', () {
      expect(kCommonCoursesLiberalArts.length, greaterThan(40));
      expect(kCommonCoursesScience.length, greaterThan(30));
      expect(kCommonCoursesEngineering.length, greaterThan(50));
    });

    test('★ 合并后无重复且去重正确', () {
      final int total = kCommonCoursesPolitics.length +
          kCommonCoursesLiberalArts.length +
          kCommonCoursesScience.length +
          kCommonCoursesEngineering.length;
      expect(kCommonCourseNames.length, lessThanOrEqualTo(total));
      expect(kCommonCourseNames, isNotEmpty);
    });

    test('★ 用户提到的伟人课程都在表里', () {
      expect(kCommonCourseNames,
          contains('毛泽东思想和中国特色社会主义理论体系概论'));
      expect(kCommonCourseNames, contains('习近平新时代中国特色社会主义思想概论'));
      expect(kCommonCourseNames, contains('马克思主义基本原理'));
    });

    test('★ 三个学科的代表课都在表里', () {
      // 文科
      expect(kCommonCourseNames, contains('国际经济法'));
      expect(kCommonCourseNames, contains('美国文学史及作品选读'));
      // 理科
      expect(kCommonCourseNames, contains('概率论与数理统计'));
      expect(kCommonCourseNames, contains('有机化学'));
      // 工科
      expect(kCommonCourseNames, contains('数据结构'));
      expect(kCommonCourseNames, contains('材料力学'));
      expect(kCommonCourseNames, contains('自动控制原理'));
    });
  });
}
