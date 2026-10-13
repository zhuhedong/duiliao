/// Pick/Jump Code Assistant (挑码助手 · djds-126.dhd1k5.com /aide + jump-code-assistant.html) & Play Catalog (play-catalog.html).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/lottery.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import 'records_screens.dart';

typedef ParsedPickKill = ({
  Set<String> includedConditions,
  Set<String> excludedConditions,
  Set<int> includedNumbers,
  Set<int> excludedNumbers,
  bool hasKillClause,
});

/// Shared matcher & natural-language parser for Pick (挑码) and Kill (杀码, e.g. "杀1头，2尾").
class JumpCodeMatcher {
  const JumpCodeMatcher._();

  static const Set<int> jin = {4, 5, 12, 13, 26, 27, 34, 35, 42, 43};
  static const Set<int> mu = {8, 9, 16, 17, 24, 25, 38, 39, 46, 47};
  static const Set<int> shui = {1, 14, 15, 22, 23, 30, 31, 44, 45};
  static const Set<int> huo = {2, 3, 10, 11, 18, 19, 32, 33, 40, 41, 48, 49};

  static String wuxingFor(int n) {
    if (jin.contains(n)) return '金';
    if (mu.contains(n)) return '木';
    if (shui.contains(n)) return '水';
    if (huo.contains(n)) return '火';
    return '土';
  }

  /// 2026 wave color numbers matching djds-126.dhd1k5.com `tt.colorNumbers`.
  static const Map<String, List<int>> colorNumbers2026 = {
    '红': [1, 2, 7, 8, 12, 13, 18, 19, 23, 24, 29, 30, 34, 35, 40, 45, 46],
    '蓝': [3, 4, 9, 10, 14, 15, 20, 25, 26, 31, 36, 37, 41, 42, 47, 48],
    '绿': [5, 6, 11, 16, 17, 21, 22, 27, 28, 32, 33, 38, 39, 43, 44, 49],
  };

  /// 2026 zodiac numbers matching djds-126.dhd1k5.com `nt[2026].animalMap`.
  static const Map<String, List<int>> animalMap2026 = {
    '鼠': [7, 19, 31, 43],
    '牛': [6, 18, 30, 42],
    '虎': [5, 17, 29, 41],
    '兔': [4, 16, 28, 40],
    '龙': [3, 15, 27, 39],
    '蛇': [2, 14, 26, 38],
    '马': [1, 13, 25, 37, 49],
    '羊': [12, 24, 36, 48],
    '猴': [11, 23, 35, 47],
    '鸡': [10, 22, 34, 46],
    '狗': [9, 21, 33, 45],
    '猪': [8, 20, 32, 44],
  };

  /// 2026 five elements numbers matching djds-126.dhd1k5.com `nt[2026].fiveMap`.
  static const Map<String, List<int>> fiveMap2026 = {
    '金': [4, 5, 12, 13, 26, 27, 34, 35, 42, 43],
    '木': [8, 9, 16, 17, 24, 25, 38, 39, 46, 47],
    '水': [1, 14, 15, 22, 23, 30, 31, 44, 45],
    '火': [2, 3, 10, 11, 18, 19, 32, 33, 40, 41, 48, 49],
    '土': [6, 7, 20, 21, 28, 29, 36, 37],
  };

  /// 24 zodiac attribute categories matching djds-126.dhd1k5.com `tt.animalCategories`.
  static const Map<String, List<String>> animalCategories = {
    '家禽': ['牛', '马', '羊', '鸡', '狗', '猪'],
    '野兽': ['虎', '兔', '龙', '蛇', '鼠', '猴'],
    '阴性': ['鼠', '龙', '蛇', '马', '狗', '猪'],
    '阳性': ['牛', '虎', '兔', '羊', '猴', '鸡'],
    '天肖': ['兔', '马', '猴', '猪', '牛', '龙'],
    '地肖': ['蛇', '羊', '鸡', '狗', '鼠', '虎'],
    '男肖': ['鼠', '牛', '虎', '龙', '马', '猴', '狗'],
    '女肖': ['兔', '蛇', '羊', '鸡', '猪'],
    '吉美': ['兔', '龙', '蛇', '马', '羊', '鸡'],
    '凶丑': ['鼠', '牛', '虎', '猴', '狗', '猪'],
    '红肖': ['马', '兔', '鼠', '鸡'],
    '蓝肖': ['蛇', '虎', '猪', '猴'],
    '绿肖': ['羊', '龙', '牛', '狗'],
    '白边': ['鼠', '牛', '虎', '鸡', '狗', '猪'],
    '黑中': ['兔', '龙', '蛇', '马', '羊', '猴'],
    '单笔': ['鼠', '龙', '马', '蛇', '鸡', '猪'],
    '双笔': ['虎', '猴', '狗', '兔', '羊', '牛'],
    '五福肖': ['鼠', '虎', '兔', '蛇', '猴'],
    '琴': ['兔', '蛇', '鸡'],
    '棋': ['鼠', '牛', '狗'],
    '书': ['虎', '龙', '马'],
    '画': ['羊', '猴', '猪'],
    '六合': ['鼠牛', '龙鸡', '虎猪', '蛇猴', '兔狗', '马羊'],
    '三合': ['鼠龙猴', '牛蛇鸡', '虎马狗', '兔羊猪'],
  };

  static const Map<String, List<String>> groups = {
    '单双': ['单', '双'],
    '大小': ['大', '小'],
    '大小单双': ['大单', '小单', '大双', '小双'],
    '合数': ['合单', '合双', '合大', '合小'],
    '五行': ['金', '木', '水', '火', '土'],
    '波色': ['红波', '蓝波', '绿波'],
    '家野': ['家禽', '野兽'],
    '波色单双': ['红单', '红双', '蓝单', '蓝双', '绿单', '绿双'],
    '生肖': ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'],
    '尾数': [
      '0尾',
      '1尾',
      '2尾',
      '3尾',
      '4尾',
      '5尾',
      '6尾',
      '7尾',
      '8尾',
      '9尾',
    ],
    '尾数大小': ['大尾', '小尾'],
    '头数': ['0头', '1头', '2头', '3头', '4头'],
    '生肖属性': [
      '天肖',
      '地肖',
      '男肖',
      '女肖',
      '阴性',
      '阳性',
      '吉美',
      '凶丑',
      '红肖',
      '蓝肖',
      '绿肖',
      '白边',
      '黑中',
      '单笔',
      '双笔',
      '五福肖',
      '琴',
      '棋',
      '书',
      '画',
    ],
  };

  static bool matchesCondition(int n, String cond) {
    final isOdd = n % 2 == 1;
    final isBig = n >= 25;
    final bose = Lottery2026Lookup.boseForNumber(n); // red / blue / green
    final xiao = Lottery2026Lookup.xiaoForNumber(n);
    final isJia = Lottery2026Lookup.jiaXiao.contains(xiao);
    final wuxing = wuxingFor(n);
    final tail = n % 10;
    final head = n ~/ 10;
    final sum = head + tail;

    if (animalCategories.containsKey(cond) &&
        cond != '六合' &&
        cond != '三合') {
      return animalCategories[cond]!.contains(xiao);
    }

    return switch (cond) {
      '单' => isOdd,
      '双' => !isOdd,
      '大' => isBig,
      '小' => !isBig,
      '大单' => isBig && isOdd,
      '小单' => !isBig && isOdd,
      '大双' => isBig && !isOdd,
      '小双' => !isBig && !isOdd,
      '合单' => sum % 2 == 1,
      '合双' => sum % 2 == 0,
      '合大' => sum >= 7,
      '合小' => sum <= 6,
      '金' || '木' || '水' || '火' || '土' => wuxing == cond,
      '红波' => bose.contains('红') || bose == 'red',
      '蓝波' => bose.contains('蓝') || bose == 'blue',
      '绿波' => bose.contains('绿') || bose == 'green',
      '家禽' => isJia,
      '野兽' => !isJia,
      '红单' => (bose.contains('红') || bose == 'red') && isOdd,
      '红双' => (bose.contains('红') || bose == 'red') && !isOdd,
      '蓝单' => (bose.contains('蓝') || bose == 'blue') && isOdd,
      '蓝双' => (bose.contains('蓝') || bose == 'blue') && !isOdd,
      '绿单' => (bose.contains('绿') || bose == 'green') && isOdd,
      '绿双' => (bose.contains('绿') || bose == 'green') && !isOdd,
      '鼠' ||
      '牛' ||
      '虎' ||
      '兔' ||
      '龙' ||
      '蛇' ||
      '马' ||
      '羊' ||
      '猴' ||
      '鸡' ||
      '狗' ||
      '猪' => xiao == cond,
      '大尾' => tail >= 5,
      '小尾' => tail < 5,
      _ when cond.endsWith('尾') => '$tail尾' == cond,
      _ when cond.endsWith('头') => '$head头' == cond,
      _ => false,
    };
  }

  static bool keepNumber({
    required int n,
    required Set<String> includedConditions,
    required Set<String> excludedConditions,
    Set<int> includedNumbers = const <int>{},
    Set<int> excludedNumbers = const <int>{},
    bool defaultEmptyKeepAll = false,
    bool crossGroupIntersectionForIncluded = true,
  }) {
    // 1. Reverse kill (杀码) always takes priority: any matched kill condition or number is excluded.
    if (excludedNumbers.contains(n)) return false;
    for (final cond in excludedConditions) {
      if (matchesCondition(n, cond)) return false;
    }

    // 2. If no positive conditions/numbers are specified:
    final hasPositive =
        includedConditions.isNotEmpty || includedNumbers.isNotEmpty;
    final hasNegative =
        excludedConditions.isNotEmpty || excludedNumbers.isNotEmpty;
    if (!hasPositive) {
      if (hasNegative) {
        // Pure kill mode (e.g., "杀1头，2尾"): keep all 01–49 that survived the kill check.
        return true;
      }
      return defaultEmptyKeepAll;
    }

    // 3. Positive match check:
    if (includedNumbers.contains(n)) return true;
    if (includedConditions.isEmpty) return false;

    if (!crossGroupIntersectionForIncluded) {
      return includedConditions.any((c) => matchesCondition(n, c));
    }

    for (final entry in groups.entries) {
      final activeInGroup =
          entry.value.where(includedConditions.contains).toList();
      if (activeInGroup.isEmpty) continue;
      final matchesAny = activeInGroup.any((c) => matchesCondition(n, c));
      if (!matchesAny) return false;
    }
    return true;
  }

  static List<int> evaluate({
    required Set<String> includedConditions,
    required Set<String> excludedConditions,
    Set<int> includedNumbers = const <int>{},
    Set<int> excludedNumbers = const <int>{},
    bool defaultEmptyKeepAll = false,
    bool crossGroupIntersectionForIncluded = true,
  }) {
    return <int>[
      for (var n = 1; n <= 49; n++)
        if (keepNumber(
          n: n,
          includedConditions: includedConditions,
          excludedConditions: excludedConditions,
          includedNumbers: includedNumbers,
          excludedNumbers: excludedNumbers,
          defaultEmptyKeepAll: defaultEmptyKeepAll,
          crossGroupIntersectionForIncluded: crossGroupIntersectionForIncluded,
        ))
          n,
    ];
  }

  static const List<String> _multiCharTokens = [
    '五福肖',
    '大单',
    '小单',
    '大双',
    '小双',
    '合单',
    '合双',
    '合大',
    '合小',
    '红波',
    '蓝波',
    '绿波',
    '红单',
    '红双',
    '蓝单',
    '蓝双',
    '绿单',
    '绿双',
    '家禽',
    '野兽',
    '大尾',
    '小尾',
    '阴性',
    '阳性',
    '天肖',
    '地肖',
    '男肖',
    '女肖',
    '吉美',
    '凶丑',
    '红肖',
    '蓝肖',
    '绿肖',
    '白边',
    '黑中',
    '单笔',
    '双笔',
  ];

  static const List<String> _singleCharTokens = [
    '鼠',
    '牛',
    '虎',
    '兔',
    '龙',
    '蛇',
    '马',
    '羊',
    '猴',
    '鸡',
    '狗',
    '猪',
    '金',
    '木',
    '水',
    '火',
    '土',
    '单',
    '双',
    '大',
    '小',
    '琴',
    '棋',
    '书',
    '画',
  ];

  static String _normalizeCnDigitsBeforeHeadTail(String input) {
    const cnMap = {
      '零': '0',
      '〇': '0',
      '一': '1',
      '二': '2',
      '两': '2',
      '三': '3',
      '四': '4',
      '五': '5',
      '六': '6',
      '七': '7',
      '八': '8',
      '九': '9',
    };
    return input.replaceAllMapped(
      RegExp(r'[零〇一二两三四五六七八九,，、./\-~～与和及\s]+[头尾]'),
      (m) {
        var s = m.group(0)!;
        cnMap.forEach((k, v) {
          s = s.replaceAll(k, v);
        });
        return s;
      },
    );
  }

  /// Parses expressions like `"杀1头，2尾"`, `"红波 杀1头2尾"`, `"杀0,1头 2,5尾"`, `"杀马羊 05"`.
  static ParsedPickKill parseExpression(String rawText) {
    final includedConditions = <String>{};
    final excludedConditions = <String>{};
    final includedNumbers = <int>{};
    final excludedNumbers = <int>{};
    var hasKillClause = false;

    // Strip stake / multiplier / play-mode noise first
    var cleaned = rawText.replaceAll(
      RegExp(
        r'(?:各数|个数|各号|各码|每码|每注|每组|各组|每个|一组|1组|一注|1注|一个|1个|各|×|\*)\s*\d+\s*(?:块|元|米|蚊)?',
      ),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\d+\s*(?:块|元|米|蚊)?\s*(?:/|每|一|1)\s*(?:组|注|个|码)'),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'[·\s]*\d+\s*不中.*$'), ' ');
    cleaned = cleaned.replaceAll(
      RegExp(
        r'(?:复[试式]\s*)?[2-5二三四五](?:\s*[,，、./\-~～\s连]*\s*[2-5二三四五])*\s*连(?:复[试式])?',
      ),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'复[试式]\s*[2-5二三四五,，、./\-~～\s]*'),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'(?:倍\s*\d+|\d+\s*倍)'), ' ');
    cleaned = cleaned.replaceAll(
      RegExp(r'(?:正码|特码|特肖|特尾|特头|特波|两面|半波|合肖|平特肖|平特尾|正肖|连肖|连尾|单注|单式|大小)'),
      ' ',
    );
    cleaned = _normalizeCnDigitsBeforeHeadTail(cleaned);

    final modeRe = RegExp(r'(杀码|排除|不要|不买|杀|除|去|正选|挑码|挑|选|买|主)');
    final matches = modeRe.allMatches(cleaned).toList();

    final clauses = <({bool isKill, String text})>[];
    if (matches.isEmpty) {
      clauses.add((isKill: false, text: cleaned));
    } else {
      if (matches.first.start > 0) {
        clauses.add((
          isKill: false,
          text: cleaned.substring(0, matches.first.start),
        ));
      }
      for (var i = 0; i < matches.length; i++) {
        final kw = matches[i].group(0)!;
        final isKill =
            kw == '杀码' ||
            kw == '排除' ||
            kw == '不要' ||
            kw == '不买' ||
            kw == '杀' ||
            kw == '除' ||
            kw == '去';
        if (isKill) hasKillClause = true;
        final start = matches[i].end;
        final end = (i + 1 < matches.length)
            ? matches[i + 1].start
            : cleaned.length;
        clauses.add((isKill: isKill, text: cleaned.substring(start, end)));
      }
    }

    for (final clause in clauses) {
      var seg = clause.text;
      final targetConds =
          clause.isKill ? excludedConditions : includedConditions;
      final targetNums = clause.isKill ? excludedNumbers : includedNumbers;

      // 1. Big/Small tail first
      for (final bw in const ['大尾', '小尾']) {
        if (seg.contains(bw)) {
          targetConds.add(bw);
          seg = seg.replaceAll(bw, ' ');
        }
      }

      // 2. Head (0头–4头) expressions, e.g. "1头", "0,1头", "1-3头", "12头"
      final headRe = RegExp(
        r'([0-4](?:\s*[,，、./\-~～与和及]\s*[0-4])*|[0-4]{1,5})\s*头',
      );
      for (final m in headRe.allMatches(seg)) {
        final rawGrp = m.group(1) ?? '';
        final rangeMatch = RegExp(r'([0-4])\s*[\-~～]\s*([0-4])').firstMatch(
          rawGrp,
        );
        if (rangeMatch != null) {
          final a = int.parse(rangeMatch.group(1)!);
          final b = int.parse(rangeMatch.group(2)!);
          final lo = a <= b ? a : b;
          final hi = a <= b ? b : a;
          for (var d = lo; d <= hi; d++) {
            targetConds.add('$d头');
          }
        } else {
          for (final ch in rawGrp.characters) {
            final d = int.tryParse(ch);
            if (d != null && d >= 0 && d <= 4) {
              targetConds.add('$d头');
            }
          }
        }
      }
      seg = seg.replaceAll(headRe, ' ');

      // 3. Tail (0尾–9尾) expressions, e.g. "2尾", "2,5尾", "1-3尾", "25尾"
      final tailRe = RegExp(
        r'([0-9](?:\s*[,，、./\-~～与和及]\s*[0-9])*|[0-9]{1,10})\s*尾',
      );
      for (final m in tailRe.allMatches(seg)) {
        final rawGrp = m.group(1) ?? '';
        final rangeMatch = RegExp(r'([0-9])\s*[\-~～]\s*([0-9])').firstMatch(
          rawGrp,
        );
        if (rangeMatch != null) {
          final a = int.parse(rangeMatch.group(1)!);
          final b = int.parse(rangeMatch.group(2)!);
          final lo = a <= b ? a : b;
          final hi = a <= b ? b : a;
          for (var d = lo; d <= hi; d++) {
            targetConds.add('$d尾');
          }
        } else {
          for (final ch in rawGrp.characters) {
            final d = int.tryParse(ch);
            if (d != null && d >= 0 && d <= 9) {
              targetConds.add('$d尾');
            }
          }
        }
      }
      seg = seg.replaceAll(tailRe, ' ');

      // 4. Multi-char attribute tokens
      for (final token in _multiCharTokens) {
        if (seg.contains(token)) {
          targetConds.add(token);
          seg = seg.replaceAll(token, ' ');
        }
      }

      // 5. Shorthand wave tokens (红 / 蓝 / 绿)
      for (final entry in const [
        ('红', '红波'),
        ('蓝', '蓝波'),
        ('绿', '绿波'),
      ]) {
        if (seg.contains(entry.$1)) {
          targetConds.add(entry.$2);
          seg = seg.replaceAll(entry.$1, ' ');
        }
      }

      // 6. Single-char tokens (12 zodiacs, 5 elements, 单/双/大/小, 琴棋书画)
      for (final token in _singleCharTokens) {
        if (seg.contains(token)) {
          targetConds.add(token);
          seg = seg.replaceAll(token, ' ');
        }
      }

      // 7. Standalone numbers 01–49
      final numRe = RegExp(r'(?<!\d)([0-4]?\d)(?!\d)');
      for (final m in numRe.allMatches(seg)) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null && n >= 1 && n <= 49) {
          targetNums.add(n);
        }
      }
    }

    return (
      includedConditions: includedConditions,
      excludedConditions: excludedConditions,
      includedNumbers: includedNumbers,
      excludedNumbers: excludedNumbers,
      hasKillClause: hasKillClause,
    );
  }
}

class JumpCodeAssistantScreen extends StatefulWidget {
  const JumpCodeAssistantScreen({super.key, this.initialTab = '挑码'});

  final String initialTab;

  @override
  State<JumpCodeAssistantScreen> createState() =>
      _JumpCodeAssistantScreenState();
}

class _JumpCodeAssistantScreenState extends State<JumpCodeAssistantScreen> {
  static const List<String> _tabs = ['挑码', '波色', '生肖', '五行', '家禽'];
  late String _activeTab = _tabs.contains(widget.initialTab)
      ? widget.initialTab
      : '挑码';

  Lottery _lottery = Lottery.macau;
  late String _period = currentPeriodForLottery(_lottery);

  /// Click action mode: 'include' (正选号码: click to pick) or 'exclude' (反选号码: click to kill/杀码)
  String _mode = 'include';

  /// Positive conditions (挑码: within-group OR, cross-group AND)
  final Set<String> _included = <String>{};

  /// Negative kill conditions (杀码: e.g. '1头', '2尾', '马' — any match is excluded)
  final Set<String> _excluded = <String>{};

  /// Explicitly included / excluded individual numbers (1–49)
  final Set<int> _includedNumbers = <int>{};
  final Set<int> _excludedNumbers = <int>{};

  final TextEditingController _commandController = TextEditingController();

  static const Map<String, List<int>> _colorNumbers2026 =
      JumpCodeMatcher.colorNumbers2026;
  static const Map<String, List<int>> _animalMap2026 =
      JumpCodeMatcher.animalMap2026;
  static const Map<String, List<int>> _fiveMap2026 =
      JumpCodeMatcher.fiveMap2026;
  static const Map<String, List<String>> _animalCategories =
      JumpCodeMatcher.animalCategories;
  static const Map<String, List<String>> _groups = JumpCodeMatcher.groups;

  /// Single-select mutually exclusive pairs in 正选 mode (matching `ba` in djds-126).
  static const Map<String, String> _exclusivePeer = {
    '单': '双',
    '双': '单',
    '大': '小',
    '小': '大',
  };

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  void _toggleCondition(String val, {bool? forceKill}) {
    final isKillAction = forceKill ?? (_mode == 'exclude');
    setState(() {
      if (isKillAction) {
        _included.remove(val);
        if (!_excluded.remove(val)) {
          _excluded.add(val);
        }
      } else {
        _excluded.remove(val);
        if (_included.contains(val)) {
          _included.remove(val);
        } else {
          final peer = _exclusivePeer[val];
          if (peer != null) {
            _included.remove(peer);
          }
          _included.add(val);
        }
      }
    });
  }

  void _applyCommandText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() {
        _included.clear();
        _excluded.clear();
        _includedNumbers.clear();
        _excludedNumbers.clear();
      });
      return;
    }
    final parsed = JumpCodeMatcher.parseExpression(text);
    setState(() {
      _included
        ..clear()
        ..addAll(parsed.includedConditions);
      _excluded
        ..clear()
        ..addAll(parsed.excludedConditions);
      _includedNumbers
        ..clear()
        ..addAll(parsed.includedNumbers);
      _excludedNumbers
        ..clear()
        ..addAll(parsed.excludedNumbers);
      if (parsed.hasKillClause &&
          parsed.includedConditions.isEmpty &&
          parsed.includedNumbers.isEmpty) {
        _mode = 'exclude';
      }
    });
  }

  void _swapIncludeExclude() {
    setState(() {
      final prevInc = Set<String>.of(_included);
      final prevExc = Set<String>.of(_excluded);
      _included
        ..clear()
        ..addAll(prevExc);
      _excluded
        ..clear()
        ..addAll(prevInc);

      final prevIncNums = Set<int>.of(_includedNumbers);
      final prevExcNums = Set<int>.of(_excludedNumbers);
      _includedNumbers
        ..clear()
        ..addAll(prevExcNums);
      _excludedNumbers
        ..clear()
        ..addAll(prevIncNums);

      _mode = _excluded.isNotEmpty && _included.isEmpty ? 'exclude' : 'include';
    });
  }

  bool _keepNumber(int n) {
    return JumpCodeMatcher.keepNumber(
      n: n,
      includedConditions: _included,
      excludedConditions: _excluded,
      includedNumbers: _includedNumbers,
      excludedNumbers: _excludedNumbers,
      defaultEmptyKeepAll: _mode == 'exclude',
      crossGroupIntersectionForIncluded: true,
    );
  }

  void _copyNumbers(List<int> nums, {String? label}) {
    if (nums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择挑码或杀码条件')),
      );
      return;
    }
    final text = nums.map((n) => n.toString().padLeft(2, '0')).join(',');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          label != null
              ? '已复制「$label」共 ${nums.length} 码：$text'
              : '复制成功（共 ${nums.length} 个号码）',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kept = <int>[
      for (var n = 1; n <= 49; n++)
        if (_keepNumber(n)) n,
    ];
    final droppedCount = 49 - kept.length;
    final codeText = kept
        .map((n) => n.toString().padLeft(2, '0'))
        .join(' ');
    final commaCodeText = kept
        .map((n) => n.toString().padLeft(2, '0'))
        .join(',');
    final keptXiaos =
        kept.map((n) => Lottery2026Lookup.xiaoForNumber(n)).toSet().toList();
    final redCount =
        kept.where((n) => Lottery2026Lookup.boseForNumber(n) == 'red').length;
    final blueCount =
        kept.where((n) => Lottery2026Lookup.boseForNumber(n) == 'blue').length;
    final greenCount =
        kept.where((n) => Lottery2026Lookup.boseForNumber(n) == 'green').length;
    final oddCount = kept.where((n) => n % 2 == 1).length;
    final evenCount = kept.length - oddCount;
    final bigCount = kept.where((n) => n >= 25).length;
    final smallCount = kept.length - bigCount;

    final incLabels = [
      ..._included,
      for (final n in _includedNumbers) n.toString().padLeft(2, '0'),
    ];
    final excLabels = [
      ..._excluded,
      for (final n in _excludedNumbers) n.toString().padLeft(2, '0'),
    ];

    final String formulaText;
    if (incLabels.isEmpty && excLabels.isEmpty) {
      formulaText = _mode == 'exclude'
          ? '当前未选杀码条件，保留全部 01–49（可点选或输入如「杀1头，2尾」）'
          : '请点击属性按钮挑码，或直接点选/输入「杀1头，2尾」反向排除';
    } else if (incLabels.isEmpty && excLabels.isNotEmpty) {
      formulaText =
          '反向杀码 = 01–49 杀 [${excLabels.join('、')}]（排除 $droppedCount 码）→ 保留 ${kept.length} 码';
    } else if (incLabels.isNotEmpty && excLabels.isEmpty) {
      formulaText =
          '正向挑码 = 满足 [${incLabels.join(' · ')}] → 命中 ${kept.length} 码';
    } else {
      formulaText =
          '挑杀组合 = 挑 [${incLabels.join(' · ')}] 且 杀 [${excLabels.join('、')}] → 保留 ${kept.length} 码';
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '挑码助手',
                subtitle: '挑码交集 · 反向杀码 · 2026速查',
                actions: [
                  GlassIconButton(
                    icon: Icons.menu_book_outlined,
                    tooltip: '玩法目录',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PlayCatalogScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              // 5-Tab Bar matching https://djds-126.dhd1k5.com/ (/aide: 挑码 | 波色 | 生肖 | 五行 | 家禽)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: GlassSegmentedControl<String>(
                  items: _tabs,
                  selected: _activeTab,
                  labelBuilder: (t) => t,
                  onChanged: (v) => setState(() => _activeTab = v),
                ),
              ),
              Expanded(
                child: switch (_activeTab) {
                  '波色' => _buildBoseTab(context),
                  '生肖' => _buildZodiacTab(context),
                  '五行' => _buildWuxingTab(context),
                  '家禽' => _buildJiaqinTab(context),
                  _ => _buildPickTab(
                    context: context,
                    kept: kept,
                    droppedCount: droppedCount,
                    codeText: codeText,
                    commaCodeText: commaCodeText,
                    keptXiaos: keptXiaos,
                    redCount: redCount,
                    blueCount: blueCount,
                    greenCount: greenCount,
                    oddCount: oddCount,
                    evenCount: evenCount,
                    bigCount: bigCount,
                    smallCount: smallCount,
                    formulaText: formulaText,
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickTab({
    required BuildContext context,
    required List<int> kept,
    required int droppedCount,
    required String codeText,
    required String commaCodeText,
    required List<String> keptXiaos,
    required int redCount,
    required int blueCount,
    required int greenCount,
    required int oddCount,
    required int evenCount,
    required int bigCount,
    required int smallCount,
    required String formulaText,
  }) {
    final hasAnyFilter =
        _included.isNotEmpty ||
        _excluded.isNotEmpty ||
        _includedNumbers.isNotEmpty ||
        _excludedNumbers.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      children: [
        // Top Selected Balls Box matching djds-126.dhd1k5.com `.selected-code` + Clear / Copy buttons
        GlassCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _excluded.isNotEmpty && _included.isEmpty
                                ? '杀码保留结果'
                                : (_excluded.isNotEmpty && _included.isNotEmpty
                                      ? '挑杀组合结果'
                                      : (_mode == 'include'
                                            ? '挑码结果'
                                            : '反选杀码结果')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassStatusPill(
                          label: '共 ${kept.length} 码',
                          color: kept.isNotEmpty
                              ? DuiliaoColors.hit
                              : DuiliaoColors.pending,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  GlassStatusPill(
                    label: _mode == 'exclude' ? '点选杀码' : '点选挑码',
                    color: _mode == 'exclude'
                        ? DuiliaoColors.miss
                        : DuiliaoColors.primaryDark,
                    showDot: true,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // `.selected-code` container
              GlassSubtleBox(
                padding: const EdgeInsets.all(12),
                borderRadius: 12,
                child: SizedBox(
                  width: double.infinity,
                  child: kept.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            !hasAnyFilter
                                ? '点击下方属性挑码，或直接点选/输入「杀1头，2尾」反向排除'
                                : '没有同时满足所选挑杀条件的号码',
                            textAlign: TextAlign.center,
                            style: context.texts.labelSmall?.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                for (final numVal in kept)
                                  NumberBall(
                                    number: numVal.toString().padLeft(2, '0'),
                                    bose: Lottery2026Lookup.boseForNumber(
                                      numVal,
                                    ),
                                    xiao: Lottery2026Lookup.xiaoForNumber(
                                      numVal,
                                    ),
                                    size: 28,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              commaCodeText,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (hasAnyFilter) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cond in _included)
                      GestureDetector(
                        onTap: () => setState(() => _included.remove(cond)),
                        child: ZTag(
                          label: '挑: $cond ×',
                          variant: ZTagVariant.hit,
                        ),
                      ),
                    for (final n in _includedNumbers)
                      GestureDetector(
                        onTap: () => setState(() => _includedNumbers.remove(n)),
                        child: ZTag(
                          label: '挑: ${n.toString().padLeft(2, '0')} ×',
                          variant: ZTagVariant.hit,
                        ),
                      ),
                    for (final cond in _excluded)
                      GestureDetector(
                        onTap: () => setState(() => _excluded.remove(cond)),
                        child: ZTag(
                          label: '杀: $cond ×',
                          variant: ZTagVariant.primary,
                        ),
                      ),
                    for (final n in _excludedNumbers)
                      GestureDetector(
                        onTap: () => setState(() => _excludedNumbers.remove(n)),
                        child: ZTag(
                          label: '杀: ${n.toString().padLeft(2, '0')} ×',
                          variant: ZTagVariant.primary,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              // Action Buttons Row: 清空 | 正反互换 | 复制结果 | 带入记录
              Row(
                children: [
                  Expanded(
                    child: GlassGhostButton(
                      label: '清空',
                      icon: Icons.delete_outline_rounded,
                      compact: true,
                      onTap: () => setState(() {
                        _included.clear();
                        _excluded.clear();
                        _includedNumbers.clear();
                        _excludedNumbers.clear();
                        _commandController.clear();
                      }),
                    ),
                  ),
                  if (hasAnyFilter) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: GlassGhostButton(
                        label: '正反互换',
                        icon: Icons.swap_horiz_rounded,
                        compact: true,
                        onTap: _swapIncludeExclude,
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Expanded(
                    child: GlassGhostButton(
                      label: '复制结果',
                      icon: Icons.copy_rounded,
                      compact: true,
                      onTap: () => _copyNumbers(kept),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: GlassGhostButton(
                      label: '带入记录',
                      icon: Icons.add_circle_outline_rounded,
                      compact: true,
                      onTap: () {
                        if (kept.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请先挑出至少 1 个号码')),
                          );
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RecordAddScreen(
                              initialText: '特码 $codeText 各 10',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Smart Pick/Kill Command Input (支持输入如 "杀1头，2尾" / "红波 杀1头2尾")
        GlassCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      '智能挑杀口令（支持杀头/杀尾/杀肖/杀波）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_commandController.text.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        _commandController.clear();
                        _applyCommandText('');
                      },
                      child: Text(
                        '清除口令',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _commandController,
                onChanged: _applyCommandText,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.bolt_rounded, size: 18),
                  hintText: '如：杀1头，2尾 / 红波 杀1头2尾 / 杀马羊',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in const [
                    '杀1头，2尾',
                    '杀0头，9尾',
                    '红波 杀1头2尾',
                    '杀马羊',
                    '大单 杀0尾',
                  ])
                    GlassChipTag(
                      label: preset,
                      compact: true,
                      active: _commandController.text.trim() == preset,
                      onTap: () {
                        _commandController.text = preset;
                        _applyCommandText(preset);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),

        // Mode switcher (正选号码 | 反选号码) & Lottery chips
        Row(
          children: [
            Expanded(
              child: GlassSegmentedControl<String>(
                items: const ['include', 'exclude'],
                selected: _mode,
                labelBuilder: (m) => m == 'include' ? '正选号码' : '反选号码',
                onChanged: (v) => setState(() {
                  if (v == 'exclude' &&
                      _excluded.isEmpty &&
                      _included.isNotEmpty) {
                    // Automatically convert existing positive picks to kill conditions when switching to 反选号码
                    _excluded.addAll(_included);
                    _included.clear();
                  } else if (v == 'include' &&
                      _included.isEmpty &&
                      _excluded.isNotEmpty) {
                    _included.addAll(_excluded);
                    _excluded.clear();
                  }
                  _mode = v;
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final item in Lottery.all)
              GlassChipTag(
                label: item.label,
                active: item == _lottery,
                onTap: () => setState(() {
                  _lottery = item;
                  _period = currentPeriodForLottery(item);
                }),
              ),
            Text(
              '第 $_period 期',
              style: context.texts.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),

        // Quick Reverse Kill Panel (一键杀头 / 杀尾 / 杀肖 / 杀波色)
        const DesignSectionHeader(
          title: '反向杀码专区（直接点选排除）',
          trailingText: '可与正选挑码叠加使用',
        ),
        GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildKillGroupHeaderAndGrid(
                title: '杀头数（十位排除）',
                subtitle: '如：杀1头（排除 10–19）',
                options: const ['0头', '1头', '2头', '3头', '4头'],
                crossAxisCount: 5,
                aspectRatio: 1.9,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              _buildKillGroupHeaderAndGrid(
                title: '杀尾数（个位排除）',
                subtitle: '如：杀2尾（排除 02,12,22,32,42）',
                options: const [
                  '0尾',
                  '1尾',
                  '2尾',
                  '3尾',
                  '4尾',
                  '5尾',
                  '6尾',
                  '7尾',
                  '8尾',
                  '9尾',
                  '大尾',
                  '小尾',
                ],
                crossAxisCount: 6,
                aspectRatio: 1.55,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              _buildKillGroupHeaderAndGrid(
                title: '杀生肖',
                subtitle: '点选排除指定生肖号码',
                options: const [
                  '鼠',
                  '牛',
                  '虎',
                  '兔',
                  '龙',
                  '蛇',
                  '马',
                  '羊',
                  '猴',
                  '鸡',
                  '狗',
                  '猪',
                ],
                crossAxisCount: 6,
                aspectRatio: 1.65,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              _buildKillGroupHeaderAndGrid(
                title: '杀波色 · 单双 · 大小 · 家野',
                subtitle: '点选排除对应属性',
                options: const [
                  '红波',
                  '蓝波',
                  '绿波',
                  '单',
                  '双',
                  '大',
                  '小',
                  '家禽',
                  '野兽',
                  '合单',
                  '合双',
                  '合大',
                ],
                crossAxisCount: 6,
                aspectRatio: 1.55,
              ),
            ],
          ),
        ),

        // Interactive Attribute Buttons matching djds-126.dhd1k5.com layout
        const DesignSectionHeader(
          title: '挑码属性条件',
          trailingText: '同组并集 · 跨组交集',
        ),
        GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1 in djds-126: Left [单, 双] (single-select) | Right [大, 小] (single-select)
              Row(
                children: [
                  Expanded(
                    child: _buildGroupHeaderAndGrid(
                      title: '单双',
                      subtitle: '单选切换',
                      options: const ['单', '双'],
                      crossAxisCount: 2,
                      aspectRatio: 2.3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildGroupHeaderAndGrid(
                      title: '大小',
                      subtitle: '25–49 大',
                      options: const ['大', '小'],
                      crossAxisCount: 2,
                      aspectRatio: 2.3,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),

              // Row 2 in djds-126: [大单, 小单, 大双, 小双] & [金, 木, 水, 火, 土]
              _buildGroupHeaderAndGrid(
                title: '大小单双',
                subtitle: '可多选',
                options: const ['大单', '小单', '大双', '小双'],
                crossAxisCount: 4,
                aspectRatio: 2.2,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              _buildGroupHeaderAndGrid(
                title: '五行',
                subtitle: '2026 五行属性',
                options: const ['金', '木', '水', '火', '土'],
                crossAxisCount: 5,
                aspectRatio: 1.9,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),

              // Row 3 in djds-126: [红波, 蓝波, 绿波, 家禽, 野兽]
              _buildGroupHeaderAndGrid(
                title: '波色 · 家野',
                subtitle: '波色与家野跨组取交集',
                options: const ['红波', '蓝波', '绿波', '家禽', '野兽'],
                crossAxisCount: 5,
                aspectRatio: 1.85,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),

              // Row 4 in djds-126: [红单, 红双, 蓝单, 蓝双, 绿单, 绿双]
              _buildGroupHeaderAndGrid(
                title: '波色单双',
                subtitle: '6 项组合属性',
                options: const ['红单', '红双', '蓝单', '蓝双', '绿单', '绿双'],
                crossAxisCount: 6,
                aspectRatio: 1.55,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),

              // Row 5 in djds-126: 12 生肖 (6 per row)
              _buildGroupHeaderAndGrid(
                title: '生肖',
                subtitle: '2026 丙午马年映射',
                options: const [
                  '鼠',
                  '牛',
                  '虎',
                  '兔',
                  '龙',
                  '蛇',
                  '马',
                  '羊',
                  '猴',
                  '鸡',
                  '狗',
                  '猪',
                ],
                crossAxisCount: 6,
                aspectRatio: 1.65,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),

              // Row 6 in djds-126: 0尾–9尾, 大尾, 小尾 (6 per row)
              _buildGroupHeaderAndGrid(
                title: '尾数',
                subtitle: '0–9 尾 · 大尾 / 小尾',
                options: const [
                  '0尾',
                  '1尾',
                  '2尾',
                  '3尾',
                  '4尾',
                  '5尾',
                  '6尾',
                  '7尾',
                  '8尾',
                  '9尾',
                  '大尾',
                  '小尾',
                ],
                crossAxisCount: 6,
                aspectRatio: 1.55,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),

              // Row 7 in djds-126: 0头–4头
              _buildGroupHeaderAndGrid(
                title: '头数',
                subtitle: '十位 0–4 头',
                options: const ['0头', '1头', '2头', '3头', '4头'],
                crossAxisCount: 5,
                aspectRatio: 1.9,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),

              // Row 8: 特色生肖属性 (天肖/地肖/男肖/女肖/阴阳/吉凶/红蓝绿肖/琴棋书画等)
              _buildGroupHeaderAndGrid(
                title: '特色生肖分类',
                subtitle: '天地 · 男女 · 阴阳 · 吉凶 · 琴棋书画',
                options: _groups['生肖属性']!,
                crossAxisCount: 5,
                aspectRatio: 1.85,
              ),
            ],
          ),
        ),

        // 01-49 Matrix & Formula Overview
        const DesignSectionHeader(
          title: '01–49 号码分布全景',
          trailingText: '点击号码可单独杀/留',
        ),
        GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '当前命中 ${kept.length} 个号码',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${_excluded.isNotEmpty || _mode == 'exclude' ? '已杀/排除' : '未选中'} $droppedCount 个 · 占比 ${(kept.length / 49 * 100).toStringAsFixed(1)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: context.texts.labelSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.builder(
                itemCount: 49,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  mainAxisExtent: 52,
                ),
                itemBuilder: (context, idx) {
                  final numVal = idx + 1;
                  final isKept = _keepNumber(numVal);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (isKept) {
                        _includedNumbers.remove(numVal);
                        _excludedNumbers.add(numVal);
                      } else {
                        if (!_excludedNumbers.remove(numVal)) {
                          _includedNumbers.add(numVal);
                        }
                      }
                    }),
                    child: Center(
                      child: NumberBall(
                        number: numVal.toString().padLeft(2, '0'),
                        bose: Lottery2026Lookup.boseForNumber(numVal),
                        xiao: Lottery2026Lookup.xiaoForNumber(numVal),
                        size: 28,
                        dimmed: !isKept,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              GlassSubtleBox(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                borderRadius: 10,
                child: Text(
                  formulaText,
                  style: context.texts.labelSmall?.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),

        // Attribute Summary
        const DesignSectionHeader(title: '属性概览'),
        GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          child: GridView(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              mainAxisExtent: 68,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              GlassSubtleBox(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('保留生肖', style: context.texts.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                      keptXiaos.isEmpty ? '无' : keptXiaos.join(' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              GlassSubtleBox(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('保留波色', style: context.texts.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                      '红$redCount · 蓝$blueCount · 绿$greenCount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              GlassSubtleBox(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('保留单双 / 大小', style: context.texts.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                      '单$oddCount 双$evenCount / 大$bigCount 小$smallCount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              GlassSubtleBox(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('挑 / 杀条件数', style: context.texts.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                      '挑 ${_included.length + _includedNumbers.length} 项 · 杀 ${_excluded.length + _excludedNumbers.length} 项',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassButton(
          onPressed: () {
            final targetNums = kept.isNotEmpty
                ? codeText
                : [for (var i = 1; i <= 49; i++) i.toString().padLeft(2, '0')]
                      .take(6)
                      .join(' ');
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RecordAddScreen(
                  initialText: '正码 $targetNums 各 10',
                ),
              ),
            );
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18),
              SizedBox(width: 6),
              Text('将结果带入新增记录'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKillGroupHeaderAndGrid({
    required String title,
    required String subtitle,
    required List<String> options,
    required int crossAxisCount,
    required double aspectRatio,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: aspectRatio,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final val in options)
              _FilterOptButton(
                label: '杀$val',
                selected: _excluded.contains(val),
                isExclude: true,
                onTap: () => _toggleCondition(val, forceKill: true),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGroupHeaderAndGrid({
    required String title,
    required String subtitle,
    required List<String> options,
    required int crossAxisCount,
    required double aspectRatio,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: aspectRatio,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final val in options)
              _FilterOptButton(
                label: _excluded.contains(val) ? '杀·$val' : val,
                selected: _included.contains(val) || _excluded.contains(val),
                isExclude: _excluded.contains(val) ||
                    (!_included.contains(val) && _mode == 'exclude'),
                onTap: () => _toggleCondition(val),
              ),
          ],
        ),
      ],
    );
  }

  void _jumpWithCondition(String cond, {required bool kill}) {
    setState(() {
      if (kill) {
        _included.remove(cond);
        _excluded.add(cond);
        _mode = 'exclude';
      } else {
        _excluded.remove(cond);
        _included
          ..clear()
          ..add(cond);
        _mode = 'include';
      }
      _activeTab = '挑码';
    });
  }

  /// Tab 2: 波色 (`colorMap` + `numberMap` from djds-126.dhd1k5.com)
  Widget _buildBoseTab(BuildContext context) {
    final oddNums = [for (var i = 1; i <= 49; i += 2) i];
    final evenNums = [for (var i = 2; i <= 49; i += 2) i];
    final rows = <(String, String, List<int>, Color)>[
      ('红波', '红波', _colorNumbers2026['红']!, DuiliaoColors.miss),
      ('蓝波', '蓝波', _colorNumbers2026['蓝']!, DuiliaoColors.waveBlueA),
      ('绿波', '绿波', _colorNumbers2026['绿']!, DuiliaoColors.hit),
      ('单', '单', oddNums, DuiliaoColors.primaryDark),
      ('双', '双', evenNums, DuiliaoColors.auroraViolet),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      children: [
        const DesignSectionHeader(
          title: '波色与单双号码对照表',
          trailingText: '点击可复制 · 支持一键挑/杀',
        ),
        GlassGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final row in rows)
              InkWell(
                onTap: () => _copyNumbers(row.$3, label: row.$1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.$1,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: row.$4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${row.$3.length} 码',
                              style: context.texts.labelSmall?.copyWith(
                                fontSize: 10.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                GestureDetector(
                                  onTap: () =>
                                      _jumpWithCondition(row.$2, kill: false),
                                  child: const ZTag(
                                    label: '挑',
                                    variant: ZTagVariant.hit,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () =>
                                      _jumpWithCondition(row.$2, kill: true),
                                  child: const ZTag(
                                    label: '杀',
                                    variant: ZTagVariant.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final n in row.$3)
                              NumberBall(
                                number: n.toString().padLeft(2, '0'),
                                bose: Lottery2026Lookup.boseForNumber(n),
                                size: 26,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Tab 3: 生肖 (`animalMap` for 2026 from djds-126.dhd1k5.com)
  Widget _buildZodiacTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      children: [
        const DesignSectionHeader(
          title: '2026 丙午马年十二生肖号码表',
          trailingText: '马为本命年 5 码',
        ),
        GlassGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final entry in _animalMap2026.entries)
              InkWell(
                onTap: () => _copyNumbers(entry.value, label: '${entry.key}肖'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Row(
                          children: [
                            Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: entry.key == '马'
                                    ? DuiliaoColors.miss
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              Lottery2026Lookup.jiaXiao.contains(entry.key)
                                  ? '家'
                                  : '野',
                              style: context.texts.labelSmall?.copyWith(
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final n in entry.value)
                              NumberBall(
                                number: n.toString().padLeft(2, '0'),
                                bose: Lottery2026Lookup.boseForNumber(n),
                                size: 27,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () =>
                            _jumpWithCondition(entry.key, kill: false),
                        child: const ZTag(
                          label: '挑',
                          variant: ZTagVariant.hit,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () =>
                            _jumpWithCondition(entry.key, kill: true),
                        child: const ZTag(
                          label: '杀',
                          variant: ZTagVariant.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Tab 4: 五行 (`fiveMap` for 2026 from djds-126.dhd1k5.com)
  Widget _buildWuxingTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      children: [
        const DesignSectionHeader(
          title: '2026 五行号码对照表',
          trailingText: '金 · 木 · 水 · 火 · 土',
        ),
        GlassGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final entry in _fiveMap2026.entries)
              InkWell(
                onTap: () => _copyNumbers(entry.value, label: '五行${entry.key}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${entry.value.length} 码',
                              style: context.texts.labelSmall?.copyWith(
                                fontSize: 10.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                GestureDetector(
                                  onTap: () => _jumpWithCondition(
                                    entry.key,
                                    kill: false,
                                  ),
                                  child: const ZTag(
                                    label: '挑',
                                    variant: ZTagVariant.hit,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _jumpWithCondition(
                                    entry.key,
                                    kill: true,
                                  ),
                                  child: const ZTag(
                                    label: '杀',
                                    variant: ZTagVariant.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final n in entry.value)
                              NumberBall(
                                number: n.toString().padLeft(2, '0'),
                                bose: Lottery2026Lookup.boseForNumber(n),
                                xiao: Lottery2026Lookup.xiaoForNumber(n),
                                size: 27,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Tab 5: 家禽 (`animailFullMap` 24 categories from djds-126.dhd1k5.com)
  Widget _buildJiaqinTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      children: [
        const DesignSectionHeader(
          title: '家禽野兽 · 24 类生肖属性百科',
          trailingText: '支持一键挑码或杀码',
        ),
        GlassGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final entry in _animalCategories.entries)
              InkWell(
                onTap: () {
                  if (entry.key == '六合' || entry.key == '三合') {
                    Clipboard.setData(
                      ClipboardData(
                        text: '${entry.key}：${entry.value.join('、')}',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '已复制「${entry.key}」：${entry.value.join('、')}',
                        ),
                      ),
                    );
                    return;
                  }
                  _jumpWithCondition(entry.key, kill: false);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            fontStyle: FontStyle.italic,
                            color: DuiliaoColors.miss,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final item in entry.value)
                              ZTag(label: item),
                          ],
                        ),
                      ),
                      if (entry.key != '六合' && entry.key != '三合') ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () =>
                              _jumpWithCondition(entry.key, kill: false),
                          child: const ZTag(
                            label: '挑',
                            variant: ZTagVariant.hit,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () =>
                              _jumpWithCondition(entry.key, kill: true),
                          child: const ZTag(
                            label: '杀',
                            variant: ZTagVariant.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FilterOptButton extends StatelessWidget {
  const _FilterOptButton({
    required this.label,
    required this.selected,
    required this.isExclude,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isExclude;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isExclude
        ? DuiliaoColors.auroraFuchsia
        : DuiliaoColors.auroraViolet;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      activeColor.withValues(alpha: 0.38),
                      DuiliaoColors.auroraIndigo.withValues(alpha: 0.28),
                    ],
                  )
                : null,
            color: selected
                ? null
                : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03)),
            border: Border.all(
              color: selected
                  ? activeColor.withValues(alpha: 0.72)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.08)),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Play Catalog Screen (play-catalog.html).
class PlayCatalogScreen extends StatelessWidget {
  const PlayCatalogScreen({super.key});

  static const _lotteries = [
    ('澳', '澳门', 'macau', '每日 21:34 开奖 · 默认主彩种'),
    ('港', '香港', 'hk', '官方六合彩规则口径 · 49 号码体系'),
    ('台', '台湾', 'taiwan', '同步支持采集、开奖、统计与对照'),
    ('新', '新彩', 'new', '与主流程共用 21 种标准玩法定义'),
  ];

  static const _temaPlays = [
    ('特码', 'tema_n', '01–49 号码', '任一命中特码'),
    ('特肖', 'texiao', '12 生肖', '任一等于特码生肖'),
    ('特码波色', 'tema_bose', '红 / 蓝 / 绿', '任一等于特码波色'),
    ('特码单双', 'tema_odd', '单 / 双', '任一等于特码单双'),
    ('特码大小', 'tema_size', '大 / 小', '25–49 为大'),
    ('特码尾数', 'tema_tail', '0尾–9尾', '等于特码个位'),
    ('特码头数', 'tema_head', '0头–4头', '等于特码十位'),
    ('特码合数', 'tema_heshu', '合单/双/大/小', '十位 + 个位'),
  ];

  static const _zhengPlays = [
    ('平特肖', 'pingte_xiao', '12 生肖', '7 码生肖任一命中'),
    ('平特一肖', 'pingte_1xiao', '单一生肖', '出现在 7 码生肖集合'),
    ('平特尾数', 'pingte_tail', '0尾–9尾', '出现在 7 码尾数集合'),
    ('正码', 'zhengma_n', '01–49 号码', '6 个正码任一/全部'),
  ];

  static const _comboPlays = [
    ('一肖中特 · yixiao_tema'),
    ('家禽野兽 · jiaye'),
    ('天地肖 · tiandi_xiao'),
    ('男女肖 · nannv_xiao'),
    ('五行 · wuxing'),
    ('特码两面 · tema_twoface'),
  ];

  static const _missPlays = [
    ('连肖', 'lianxiao', '2–8 连肖', '全部出现在 7 码生肖中'),
    ('N不中', 'nbuzhong', '5–12 不中', '所选号码全部不出现在 7 码中'),
    ('杀肖', 'shaxiao', '排除生肖', '所杀生肖全部不出现在 7 码中'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '彩种与玩法',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  children: [
                    // Summary Card
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '项目支持目录',
                                      style: context.texts.labelSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      '4 个彩种 · 21 个玩法',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const GlassStatusPill(
                                label: '已同步',
                                color: DuiliaoColors.hit,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '源自 constants.py 与 rules.py 的统一规则表，供采集、多源对照、源评级、AI 研判与我的记录共用。',
                            style: context.texts.bodySmall?.copyWith(
                              fontSize: 11.5,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Lotteries
                    const DesignSectionHeader(
                      title: '彩种 · lottery',
                      trailingText: '4 项',
                    ),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        for (final l in _lotteries)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                BrandLogoBox(
                                  label: l.$1,
                                  size: 36,
                                  borderRadius: 10,
                                  fontSize: 13,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.$2,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        l.$4,
                                        style: context.texts.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                GlassChipTag(label: l.$3),
                              ],
                            ),
                          ),
                      ],
                    ),

                    // 特码类 (8)
                    const DesignSectionHeader(
                      title: '特码类 (8)',
                      trailingText: '对照范围：特码',
                    ),
                    _PlayGrid(items: _temaPlays),

                    // 平特与正码 (4)
                    const DesignSectionHeader(
                      title: '平特与正码 (4)',
                      trailingText: '对照范围：6 正码 / 7 码',
                    ),
                    _PlayGrid(items: _zhengPlays),

                    // 组合玩法 (6)
                    const DesignSectionHeader(
                      title: '组合玩法 (6)',
                      trailingText: '属性 / 两面 / 五行',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final c in _comboPlays)
                                GlassChipTag(label: c),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '一肖中特：所选生肖在 6 正码或特码中命中均可结算；特码两面支持大单、大双、小单、小双、合单、合双等复合判定。',
                            style: context.texts.labelSmall?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 不中与杀号 (3)
                    const DesignSectionHeader(
                      title: '不中与杀号 (3)',
                      trailingText: '复试 / 全不中判定',
                    ),
                    _PlayGrid(items: _missPlays),
                    const SizedBox(height: 10),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '录入联动说明',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '新增记录支持号码单式、连肖复试与 N 不中三种专用录入视图。',
                                  style: context.texts.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          GlassStatusPill(
                            label: '规则完备',
                            color: Theme.of(context).colorScheme.primary,
                            showDot: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('返回新增记录'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayGrid extends StatelessWidget {
  const _PlayGrid({required this.items});
  final List<(String, String, String, String)> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 74,
      ),
      itemBuilder: (context, idx) {
        final item = items[idx];
        return GlassSubtleBox(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      item.$1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    item.$2,
                    style: context.texts.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              Text(
                '${item.$3} · ${item.$4}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        );
      },
    );
  }
}
