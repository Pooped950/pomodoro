import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoro/domain/ocr/image_stitcher.dart';

/// 对缝算法的回归测试。
///
/// ## 为什么用**合成图**而不是真实截图
///
/// 真实课表截图带着用户的课程名 / 教室（隐私红线：不进仓库），而且它只覆盖
/// 一种版式。这里用程序合成的"课表样式"图，好处是：
///   - **几何可控**：每行的纹理由行号决定、行与行不重复 → 正确答案唯一
///   - **有标准答案**：裁切位置是我们自己定的，所以可以断言
///     "算出来的重叠高度**精确等于**真实重叠"，而不是"看起来差不多"
const int kCols = 48;

/// 合成"长图"的总行数。要够长，才容得下"裁上下两半、各自带一段"的取法
/// （上半 120 行 + 下半最多 150 行，起点最靠后时要用到第 262 行）
const int kRows = 300;

/// 便宜的整数哈希 —— 只为了造出"行与行明显不同"的纹理
int _hash(int a, int b) {
  int h = (a * 73856093) ^ (b * 19349663);
  h ^= h >> 13;
  h *= 1274126177;
  return (h ^ (h >> 16)) & 0x7fffffff;
}

/// 合成一张"课表样式"的图：浅底 + 每行一条随行号变化的深色"文字带"。
///
/// 为什么不做成纯噪声：真实截图是"大片浅底 + 少量深色文字"，本函数保留了
/// 这个分布 —— 不同行之间既**明显不同**（深色带位置随机，平均亮度差 ≈ 70，
/// 远高于阈值），又**不是处处都不同**，和真实数据的手感一致。
List<int> synthPage({int rows = kRows, int columns = kCols}) {
  final List<int> v = List<int>.filled(rows * columns, 230);
  for (int r = 0; r < rows; r++) {
    final int start = _hash(r, 1) % (columns - 16);
    final int len = 6 + _hash(r, 2) % 10;
    for (int c = start; c < start + len && c < columns; c++) {
      v[r * columns + c] = 20 + _hash(r, c) % 60;
    }
  }
  return v;
}

/// 从合成图里裁一段出来当"一张截图"
RowSignature slice(List<int> page, int fromRow, int rowCount, {int columns = kCols}) {
  final List<int> out = <int>[];
  for (int r = fromRow; r < fromRow + rowCount; r++) {
    out.addAll(page.sublist(r * columns, (r + 1) * columns));
  }
  return RowSignature.fromLuminance(
    rowCount: rowCount,
    columns: columns,
    luminance: out,
  );
}

void main() {
  final List<int> page = synthPage();

  group('找垂直重叠', () {
    test('★ 上下两半重叠 60 行 —— 必须精确还原', () {
      final RowSignature top = slice(page, 0, 120);
      final RowSignature bottom = slice(page, 60, 140);

      final StitchMatch? m = findVerticalOverlap(top: top, bottom: bottom);

      expect(m, isNotNull);
      expect(
        m!.overlapRows,
        60,
        reason: '重叠高度算错，拼出来的课表会整段错位 —— 这是对缝最不能犯的错',
      );
      expect(m.meanDiff, lessThan(1.0), reason: '同一内容的两段，平均差应该几乎为 0');
      expect(m.confidence, greaterThan(0.9));
    });

    test('★ 多组重叠高度都算得准（含很窄的重叠）', () {
      for (final int overlap in <int>[8, 15, 30, 45, 90]) {
        const int topRows = 120;
        final RowSignature top = slice(page, 0, topRows);
        final RowSignature bottom = slice(page, topRows - overlap, 150);

        final StitchMatch? m = findVerticalOverlap(top: top, bottom: bottom);

        expect(m, isNotNull, reason: '重叠 $overlap 行时不该判成"拼不上"');
        expect(m!.overlapRows, overlap, reason: '重叠 $overlap 行时算错了');
      }
    });

    test('★ 两张完全不重叠 → 返回 null，宁可不拼也不拼错', () {
      // 上半取 0~99，下半取 150~199，中间 50 行谁都没有
      final RowSignature top = slice(page, 0, 100);
      final RowSignature bottom = slice(page, 150, 50);

      expect(findVerticalOverlap(top: top, bottom: bottom), isNull);
    });
    test('同一张图截了两次（内容完全一样）→ 重叠 = 较矮那张的全部行数', () {
      final RowSignature a = slice(page, 40, 100);
      final RowSignature b = slice(page, 40, 100);

      final StitchMatch? m = findVerticalOverlap(top: a, bottom: b);

      expect(m, isNotNull);
      expect(m!.overlapRows, 100);
      expect(m.meanDiff, 0);
      expect(m.confidence, 1.0);
    });

    test('容差里挑最大的重叠 —— 别被"短得很像"的错误答案骗走', () {
      // 制造一个"短重叠也满分"的局面：把 60~69 行的内容复制到 110~119 行。
      // 于是 o=10（拿 110~119 比 60~69）和 o=60（拿 60~119 比 60~119）都是满分，
      // 算法必须挑大的那个 —— 挑小了会把课表拦腰截断。
      final List<int> tricky = List<int>.of(page);
      for (int r = 0; r < 10; r++) {
        for (int c = 0; c < kCols; c++) {
          tricky[(110 + r) * kCols + c] = page[(60 + r) * kCols + c];
        }
      }

      final RowSignature top = slice(tricky, 0, 120);
      final RowSignature bottom = slice(tricky, 60, 140);

      final StitchMatch? m = findVerticalOverlap(top: top, bottom: bottom);

      expect(m, isNotNull);
      expect(m!.overlapRows, 60, reason: '应该挑容差范围内**最大**的那个重叠');
    });

    test('图太矮（连最小重叠都凑不出）→ 返回 null，不崩', () {
      final RowSignature tiny = slice(page, 0, 3);
      final RowSignature tall = slice(page, 0, 100);

      expect(findVerticalOverlap(top: tiny, bottom: tall), isNull);
    });
  });

  group('下半张顶部有一段对不上的内容（手机状态栏 / 应用标题栏）', () {
    // 真实截图长这样：[状态栏][标题栏][课表内容…]
    // 这段在两张图里位置一模一样、**不属于滚动内容**，所以对缝时它天生对不上。
    // 算法必须能把它排除在外，而不是被它拉高整体分数判成"没有重叠"。
    const int cols = 24;
    const int chromeRows = 30;

    /// 内容行由行号决定；[salt] 决定"从哪一行开始"，用来模拟滚动
    RowSignature content(int rows, {required int salt}) =>
        RowSignature.fromLuminance(
          rowCount: rows,
          columns: cols,
          luminance: <int>[
            for (int r = 0; r < rows; r++)
              for (int c = 0; c < cols; c++) _hash(r + salt, c) % 200,
          ],
        );

    /// 给一张图前面接上"状态栏 + 标题栏"
    RowSignature withChrome(RowSignature body) => RowSignature.fromLuminance(
          rowCount: chromeRows + body.rowCount,
          columns: cols,
          luminance: <int>[
            for (int r = 0; r < chromeRows; r++)
              for (int c = 0; c < cols; c++) 80,
            ...body.values,
          ],
        );

    test('★ 顶部有 30 行对不上的内容，也能找到真正的重叠', () {
      // 上半 = 状态栏 + 内容[0..99]
      // 下半 = 状态栏 + 内容[40..139]  → 内容真正重叠 60 行
      final RowSignature top = withChrome(content(100, salt: 0));
      final RowSignature bottom = withChrome(content(100, salt: 40));

      final StitchMatch? m = findVerticalOverlap(top: top, bottom: bottom);

      expect(m, isNotNull, reason: '顶部有重复的状态栏不该导致"拼不上"');
      expect(m!.matchedRows, 60, reason: '真正对上的内容应该是 60 行');
      expect(
        m.skippedTopRows,
        chromeRows,
        reason: '下半张顶部那 30 行状态栏应该被排除在外',
      );
      expect(m.meanDiff, lessThan(1.0));
    });

    test('顶部那段对不上的内容不该把置信度拉低', () {
      final RowSignature top = withChrome(content(100, salt: 0));
      final RowSignature bottom = withChrome(content(100, salt: 40));

      final StitchMatch m = findVerticalOverlap(top: top, bottom: bottom)!;

      expect(m.confidence, greaterThan(0.9),
          reason: '内容明明对得很准，不该因为状态栏而显得"不确定"');
    });
  });
}
