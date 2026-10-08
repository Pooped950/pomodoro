import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/ocr/ocr_rules.dart';
import 'package:pomodoro/domain/ocr/timetable_vocab.dart';
import 'package:pomodoro/domain/remote/remote_config.dart';

/// 远程配置（`remote_config.json`）的解析与生效。
///
/// 这是「免安装更新」的地基：推一份 JSON 上去，App 拉下来立刻改
/// 课表识别规则 / 品牌配色 / 界面文案。所以这里必须钉死两件事：
///
///   1. **局部覆盖**：远程只给一项，其余仍是代码里的默认值
///   2. **脏数据不生效**：解析不出来就当没拉到，绝不半残地应用
void main() {
  tearDown(() {
    // 每个用例后恢复默认，避免相互污染（全局生效值是刻意设计的）
    applyRemoteConfig(null);
  });

  group('解析', () {
    test('完整配置', () {
      final RemoteConfig? c = RemoteConfig.tryParse('''
      {
        "configVersion": 3,
        "ocr": {
          "roomKeywords": "楼室场馆房敦教课",
          "misreadBeforeDigit": "数敦敎",
          "roomSpanMinLen": 2
        },
        "seedColor": "#FF8800",
        "strings": {"导入课表": "导入我的课表"}
      }
      ''');
      expect(c, isNotNull);
      expect(c!.configVersion, 3);
      expect(c.ocr.roomKeywords, '楼室场馆房敦教课');
      expect(c.ocr.misreadBeforeDigit, '数敦敎');
      expect(c.ocr.roomSpanMinLen, 2);
      expect(c.seedColorHex, '#FF8800');
      expect(c.strings['导入课表'], '导入我的课表');
    });

    test('局部覆盖：没给的字段用默认值', () {
      final RemoteConfig c =
          RemoteConfig.tryParse('{"seedColor":"E4572E"}')!;
      const OcrRules d = OcrRules();
      expect(c.ocr.roomKeywords, d.roomKeywords);
      expect(c.ocr.misreadAlways, d.misreadAlways);
      expect(c.ocr.typoFixes, d.typoFixes);
      expect(c.ocr.roomSpanMinHead, d.roomSpanMinHead);
      expect(c.seedColorHex, 'E4572E');
    });

    test('`timetable` 是 `ocr` 的别名', () {
      final RemoteConfig c =
          RemoteConfig.tryParse('{"timetable":{"roomKeywords":"楼"}}')!;
      expect(c.ocr.roomKeywords, '楼');
    });

    test('脏数据一律返回 null', () {
      expect(RemoteConfig.tryParse(null), isNull);
      expect(RemoteConfig.tryParse(''), isNull);
      expect(RemoteConfig.tryParse('   '), isNull);
      expect(RemoteConfig.tryParse('not json'), isNull);
      expect(RemoteConfig.tryParse('[1,2,3]'), isNull);
      expect(RemoteConfig.tryParse('{"strings":"不是对象"}')!.strings, isEmpty);
    });

    test('strings 里非字符串的值被丢掉', () {
      final RemoteConfig c =
          RemoteConfig.tryParse('{"strings":{"A":"B","C":1,"":"D"}}')!;
      expect(c.strings, <String, String>{'A': 'B'});
    });
  });

  group('生效', () {
    test('applyRemoteConfig 改课表规则 + 文案', () {
      applyRemoteConfig(RemoteConfig.tryParse('''
      {
        "ocr": {"roomKeywords": "楼室", "roomPrefix": "", "misreadAlways": "",
                "misreadBeforeDigit": "", "typoFixes": {}},
        "strings": {"导入课表": "导入我的课表"}
      }
      ''')!);

      // 文案：远程给了覆盖
      expect(t('导入课表'), '导入我的课表');
      // 文案：没给覆盖 → 原样
      expect(t('重新导入'), '重新导入');

      // 课表规则：关键词收窄成「楼室」后，`教2-213` 不再算教室行
      expect(looksLikeRoomLine('教2-213'), isFalse);
      expect(looksLikeRoomLine('教学楼'), isTrue);
    });

    test('applyRemoteConfig(null) 回到代码里的默认值', () {
      applyRemoteConfig(RemoteConfig.tryParse(
          '{"ocr":{"roomKeywords":"楼"},"strings":{"A":"B"}}')!);
      // 关键词被收窄成「楼」→ `教` 不再算教室行
      expect(looksLikeRoomLine('教2-213'), isFalse);
      expect(t('A'), 'B');

      applyRemoteConfig(null);
      // 回到默认关键词表 → 又算教室行
      expect(looksLikeRoomLine('教2-213'), isTrue);
      expect(t('A'), 'A');
    });

    test('配色解析', () {
      expect(parseHexColor('#E4572E'), 0xFFE4572E);
      expect(parseHexColor('E4572E'), 0xFFE4572E);
      expect(parseHexColor('#FFE4572E'), 0xFFE4572E);
      expect(parseHexColor('xyz'), isNull);
      expect(parseHexColor(null), isNull);
    });
  });
}
