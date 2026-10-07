import 'package:meta/meta.dart';

/// 课表文字的**词表与修正** —— 「拿识别对的去救识别错的」。
///
/// ## 为什么能有词表（用户 2026-10-07 的思路）
///
/// 一张课表里，同一门课一周上多次、同一栋楼出现在一堆教室里：
/// 只要有一部分格子识别得干净，它们的课名和楼名就是**现成的词典**，
/// 可以拿去救那些被 OCR 糟蹋的兄弟格子：
///
///   - `307敦室` → `307教室`（「敦室」从不在词表里，「教室」到处都是）
///   - `洲云杉後` → `洲云杉楼`（和词表里的楼名差一个字）
///   - `材料力学A()` → `材料力学A (一)`（别处有一份识别全的）
///   - 跨列粘连行拆分时，切在词表词的边界上才可信
///     （`结构力学|量子光学|材料力学|工程制图`，四刀全落在词上）
///
/// ## 为什么是两轮
///
/// 词表从「拆好的格子」里来，而拆格子又想用词表 —— 先用**强规则**
/// （教室/楼/场/馆 这些字眼）拆一遍求个粗版词表，再用词表回头精修，
/// 详见解析器里的两轮流程。
@immutable
class TimetableVocab {
  const TimetableVocab({
    this.courseNames = const <String>[],
    this.roomLines = const <String>[],
    this.roomCounts = const <String, int>{},
  });

  /// 课名（已去空格、去行首竖线；保留原始的大小写/括号形态）
  final List<String> courseNames;

  /// 教室行（一个格子里的教室文本是按行换行的，**整行**进词表 ——
  /// `云杉楼云杉` 这种被换行截断的楼名，按整行记才能在粘连行里对上）
  final List<String> roomLines;

  /// 每条教室行在整张课表里出现了几次（"多数投票"用，见 [voteFixRoom]）
  final Map<String, int> roomCounts;

  bool get isEmpty => courseNames.isEmpty && roomLines.isEmpty;

  /// 词表里有没有（或差不多有）这个词。CJK 短串按编辑距离 ≤1 归为「差不多」。
  bool hasCourse(String name) => _hasFuzzy(courseNames, name);

  bool hasRoom(String line) => _hasFuzzy(roomLines, line);

  /// 词表里和 [s] 最接近的一个；差太远返回 null
  String? nearestCourse(String s) => _nearest(courseNames, s);

  String? nearestRoom(String s) => _nearest(roomLines, s);

  /// 用"多数投票"修一条教室行里认错的字。
  ///
  /// ## 为什么不能只看"词表里有没有"
  ///
  /// 病句**自己也在词表里**：体育格把认错字的 `云杉洲四敦` 当自己的教室行
  /// 存了进去，精确命中返回自己，修正永远轮空（2026-10-07 实测踩到）。
  /// 所以看**票数**：在自己（编辑距离 0）和所有差一个字的词表形态里，
  /// 谁在全表出现的次数多谁是对的 —— `云杉洲四敦` 只出现 1 次，
  /// `云杉洲四教` 出现 2 次，修过去；票数打平就保持原样（可能本来就是对的，
  /// 比如 `云杉洲三教敦` 这种只有一处、无从对证的写法）。
  ///
  /// ## 为什么只有"含已知误认字"的行才修
  ///
  /// 光看票数会把**正确但少见的**行也改掉：`桂杉园六教` 只出现 1 次，
  /// 差一个字的 `桂杉园五教` 出现 3 次 —— 但六教是另一栋楼，不是错字！
  /// （2026-10-07 实测踩到。）所以只有含**已知误认字**（`敦`=教 之误、
  /// `後`=楼 之误，都是本轮真图里实际出现过的）的行才参与投票，
  /// 干净行保持原样。
  ///
  /// ## 房间号绝对不许碰
  ///
  /// 含数字的行差一个字符就是**另一间教室**（`506教室` 的模糊近邻里有
  /// `406教室`），数字行只认精确命中，其余原样保留。
  String? voteFixRoom(String line) {
    final bool hasDigit = line.contains(RegExp(r'[0-9０-９]'));
    final bool inVocab = roomCounts.containsKey(line);
    if (inVocab) {
      if (hasDigit) return null;
      // 没有病句证据就不动 —— 高票近邻可能是另一栋楼而不是"正确形态"
      if (!line.contains(RegExp(r'[敦後]'))) return null;
      final int myVotes = roomCounts[line] ?? 0;
      String? best;
      int bestVotes = myVotes;
      for (final String v in roomCounts.keys) {
        if (v == line) continue;
        if ((v.length - line.length).abs() > 1) continue;
        if (!_editDistanceAtMost1(v, line)) continue;
        final int votes = roomCounts[v] ?? 0;
        if (votes > bestVotes) {
          bestVotes = votes;
          best = v;
        }
      }
      return best;
    }
    // 不在词表里：无数字时找最近的词表形态（`桂杉园五教!` → `桂杉园五教`）
    if (hasDigit) return null;
    return _nearest(roomLines, line);
  }

  /// 编辑距离是否 ≤1（课表里的行都是短串，够用）
  static bool _editDistanceAtMost1(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 1) return false;
    int i = 0;
    while (i < a.length && i < b.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    if (i == a.length) return b.length - a.length <= 1;
    if (i == b.length) return a.length - b.length <= 1;
    if (a.length == b.length) {
      return a.substring(i + 1) == b.substring(i + 1);
    }
    final String longer = a.length > b.length ? a : b;
    final String shorter = a.length > b.length ? b : a;
    return longer.substring(i + 1) == shorter.substring(i);
  }

  static bool _hasFuzzy(List<String> vocab, String s) {
    if (s.isEmpty) return false;
    for (final String v in vocab) {
      if (v == s) return true;
    }
    return _nearest(vocab, s) != null;
  }

  static String? _nearest(List<String> vocab, String s) {
    if (s.isEmpty || vocab.isEmpty) return null;
    // 太短的不做模糊 —— 一两个字差一个字就完全是另一个词了
    final int tol = s.length >= 4 ? 1 : 0;
    if (tol == 0) {
      for (final String v in vocab) {
        if (v == s) return v;
      }
      return null;
    }
    String? best;
    int bestDist = tol + 1;
    for (final String v in vocab) {
      if ((v.length - s.length).abs() > tol) continue;
      final int d = _editDistance(v, s);
      if (d < bestDist) {
        bestDist = d;
        best = v;
      }
    }
    return bestDist <= tol ? best : null;
  }

  static int _editDistance(String a, String b) {
    final List<List<int>> dp = List<List<int>>.generate(
      a.length + 1,
      (int i) => List<int>.filled(b.length + 1, i),
    );
    for (int j = 0; j <= b.length; j++) {
      dp[0][j] = j;
    }
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final int sub = dp[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        dp[i][j] = <int>[
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          sub,
        ].reduce((int x, int y) => x < y ? x : y);
      }
    }
    return dp[a.length][b.length];
  }
}

/// 「这一行像不像教室/场地」的强规则。
///
/// ## 为什么敢用单字触发
///
/// 校园课表的**课程名几乎不含** 楼/室/场/馆/房/敦/教 这些字（实测一整张
/// 课表一条都没有），而教室行几乎总含其中一个 —— 连被换行截断的
/// `云杉楼云杉`（楼在行首）、被认错字的 `云杉洲四敦`（教→敦）和
/// 「四教」（=第四教学楼，单一个教字收尾）都能兜住。
/// 课名里真出现这些字的情况（「室内设计」之类）交给词表前缀匹配优先处理。
final RegExp kRoomLinePattern = RegExp(r'[楼室场馆房敦教]');

/// 教室行里最常见的认错：`教室` → `敦室`（形近）。整串替换。
String fixRoomTypos(String raw) => raw.replaceAll('敦室', '教室');

/// 行首/行尾的表格竖线是 OCR 把网格线认进来了；行尾的单独 `|` 还可能是
/// 被读残的「一」。先剥行首，行尾的竖线剥掉（课名里不该有竖线）。
String cleanOcrLine(String raw) {
  String s = raw.trim().replaceFirst(RegExp(r'^[|丨│｜\s]+'), '');
  s = s.replaceFirst(RegExp(r'[|丨│｜\s]+$'), '');
  return s.trim();
}

/// 去掉所有空白（教室/课名拼行时用；OCR 的空格是列间隙噪声）
String squeeze(String raw) => raw.replaceAll(RegExp(r'\s+'), '');
