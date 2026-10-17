/// Trend analysis screen matching djds-129.dhd1k5.com.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/draw.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import 'draws_providers.dart';

enum TrendTab { draw, wei, tou, bose, wuxing, shengxiao }

class CellValue {
  const CellValue({this.value, this.index, this.color, this.allValues = const []});

  final String? value;
  final int? index;
  final String? color; // 'red' | 'blue' | 'green'
  final List<String> allValues;
}

const List<String> kWeiCols = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
const List<String> kTouCols = ['0', '1', '2', '3', '4'];
const List<String> kBoseCols = ['红波', '蓝波', '绿波'];
const List<String> kWuxingCols = ['金', '木', '水', '火', '土'];
const List<String> kShengxiaoCols = [
  '鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪',
];

String _boseColor(String bose) {
  if (bose.contains('红')) return 'red';
  if (bose.contains('蓝')) return 'blue';
  return 'green';
}

Color _colorForBose(String? color) {
  if (color == 'green') return DuiliaoColors.boseGreen;
  if (color == 'blue') return DuiliaoColors.boseBlue;
  return DuiliaoColors.boseRed;
}

class TrendScreen extends ConsumerStatefulWidget {
  const TrendScreen({super.key});

  @override
  ConsumerState<TrendScreen> createState() => _TrendScreenState();
}

class _TrendScreenState extends ConsumerState<TrendScreen> {
  TrendTab _tab = TrendTab.draw;
  int _limit = 50;
  bool _isPingteMode = false; // false = 特码走势 (djds-129 default), true = 平特走势
  bool _forceRefresh = false;

  void _refresh() {
    setState(() => _forceRefresh = true);
  }

  @override
  Widget build(BuildContext context) {
    final lottery = ref.watch(selectedLotteryProvider);
    final trendAsync = ref.watch(
      trendProvider((lottery: lottery, limit: _limit, forceRefresh: _forceRefresh)),
    );

    if (_forceRefresh && !trendAsync.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _forceRefresh = false);
      });
    }

    final items = trendAsync.value?.data ?? const <TrendItem>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '走势图表',
                subtitle: _isPingteMode ? '平特走势 (7码全出)' : '特码走势 (兼容 djds-129)',
                actions: [
                  GlassIconButton(
                    icon: _isPingteMode ? Icons.filter_7_rounded : Icons.star_rounded,
                    tooltip: _isPingteMode ? '切换为特码走势' : '切换为平特走势',
                    onTap: () => setState(() => _isPingteMode = !_isPingteMode),
                  ),
                  GlassIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '刷新走势',
                    onTap: _refresh,
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    // Lottery switcher
                    GlassSegmentedControl<Lottery>(
                      items: Lottery.all,
                      selected: lottery,
                      labelBuilder: (l) => l.label,
                      onChanged: (next) =>
                          ref.read(selectedLotteryProvider.notifier).set(next),
                    ),
                    const SizedBox(height: 10),

                    // Controls row: Limits & Mode
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [30, 50, 100, 200].map((lim) {
                                final isSel = _limit == lim;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text('$lim期', style: const TextStyle(fontSize: 11)),
                                    selected: isSel,
                                    onSelected: (_) => setState(() => _limit = lim),
                                    selectedColor: DuiliaoColors.primary.withValues(alpha: 0.25),
                                    backgroundColor: Colors.black.withValues(alpha: 0.1),
                                    side: BorderSide(
                                      color: isSel ? DuiliaoColors.primary : Colors.white12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            _isPingteMode ? '平特走势' : '特码走势',
                            style: const TextStyle(
                              fontSize: 11,
                              color: DuiliaoColors.primaryDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Sub-tabs row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          (tab: TrendTab.draw, label: '开奖'),
                          (tab: TrendTab.wei, label: '尾号'),
                          (tab: TrendTab.tou, label: '头号'),
                          (tab: TrendTab.bose, label: '波色'),
                          (tab: TrendTab.wuxing, label: '五行'),
                          (tab: TrendTab.shengxiao, label: '生肖'),
                        ].map((item) {
                          final isSel = _tab == item.tab;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => setState(() => _tab = item.tab),
                              borderRadius: BorderRadius.circular(12),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? DuiliaoColors.primaryDark
                                      : Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSel
                                        ? DuiliaoColors.primaryDark
                                        : Colors.white10,
                                  ),
                                ),
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight:
                                        isSel ? FontWeight.bold : FontWeight.normal,
                                    color: isSel ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Content
                    if (trendAsync.isLoading && items.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (items.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            '暂无走势数据',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      switch (_tab) {
                        TrendTab.draw => _buildDrawTab(lottery, items),
                        TrendTab.wei => _buildTableTab(
                            columns: kWeiCols,
                            rows: _computeWeiMatrix(items, _isPingteMode),
                          ),
                        TrendTab.tou => _buildTableTab(
                            columns: kTouCols,
                            rows: _computeTouMatrix(items, _isPingteMode),
                          ),
                        TrendTab.bose => _buildTableTab(
                            columns: kBoseCols,
                            rows: _computeBoseMatrix(items, _isPingteMode),
                          ),
                        TrendTab.wuxing => _buildTableTab(
                            columns: kWuxingCols,
                            rows: _computeWuxingMatrix(items, _isPingteMode),
                          ),
                        TrendTab.shengxiao => _buildTableTab(
                            columns: kShengxiaoCols,
                            rows: _computeShengxiaoMatrix(items, _isPingteMode),
                          ),
                      },
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAB 1: Draws list
  Widget _buildDrawTab(Lottery lottery, List<TrendItem> items) {
    return Column(
      children: items.map((item) {
        final balls = item.code.map((b) => b.padLeft(2, '0')).toList();
        final zBalls = balls.take(6).toList();
        final temaBall = balls.length > 6 ? balls[6] : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: GlassSubtleBox(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${lottery.label}六合彩 · 第${item.period}期',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      item.date,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...zBalls.map((b) {
                        final bs = Lottery2026Lookup.boseForNumber(b);
                        final xiao = Lottery2026Lookup.xiaoForNumber(b);
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: NumberBall(
                            number: b,
                            bose: bs,
                            size: 32,
                            showCaption: true,
                            caption: xiao,
                          ),
                        );
                      }),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '+',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      if (temaBall.isNotEmpty)
                        NumberBall(
                          number: temaBall,
                          bose: Lottery2026Lookup.boseForNumber(temaBall),
                          isSpecial: true,
                          size: 34,
                          showCaption: true,
                          caption: Lottery2026Lookup.xiaoForNumber(temaBall),
                          captionColor: DuiliaoColors.boseGold,
                          captionBold: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // TAB 2-6: Matrix Table
  Widget _buildTableTab({
    required List<String> columns,
    required List<({String period, List<CellValue> cells})> rows,
  }) {
    final colCount = columns.length;
    final hits = List<int>.filled(colCount, 0);
    final maxOmission = List<int>.filled(colCount, 0);
    final curOmission = List<int>.filled(colCount, 0);

    for (var c = 0; c < colCount; c++) {
      var count = 0;
      var maxOm = 0;
      for (final r in rows) {
        if (r.cells[c].value != null) {
          count++;
        } else if (r.cells[c].index != null) {
          if (r.cells[c].index! > maxOm) maxOm = r.cells[c].index!;
        }
      }
      hits[c] = count;
      maxOmission[c] = maxOm;
      curOmission[c] = rows.isNotEmpty ? (rows.first.cells[c].index ?? 0) : 0;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 10,
          horizontalMargin: 8,
          headingRowHeight: 34,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 34,
          headingRowColor: WidgetStateProperty.all(
            Colors.white.withValues(alpha: 0.08),
          ),
          columns: [
            const DataColumn(
              label: Text(
                '期号',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            ...columns.map(
              (c) => DataColumn(
                label: Center(
                  child: Text(
                    c,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
          rows: [
            ...rows.map((row) {
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      row.period,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  ...row.cells.map((cell) {
                    if (cell.value != null) {
                      final bg = _colorForBose(cell.color);
                      return DataCell(
                        Center(
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: bg,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: bg.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              cell.value!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return DataCell(
                      Center(
                        child: Text(
                          '${cell.index ?? 1}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white38,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            }),
            // Summary Footer Rows
            DataRow(
              color: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.04)),
              cells: [
                const DataCell(
                  Text(
                    '出现次数',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: DuiliaoColors.primaryDark,
                    ),
                  ),
                ),
                ...hits.map(
                  (h) => DataCell(
                    Center(
                      child: Text(
                        '$h',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: DuiliaoColors.primaryDark,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            DataRow(
              color: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.04)),
              cells: [
                const DataCell(
                  Text(
                    '当前遗漏',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white60,
                    ),
                  ),
                ),
                ...curOmission.map(
                  (om) => DataCell(
                    Center(
                      child: Text(
                        '$om',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white60,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            DataRow(
              color: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.04)),
              cells: [
                const DataCell(
                  Text(
                    '最大遗漏',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white60,
                    ),
                  ),
                ),
                ...maxOmission.map(
                  (om) => DataCell(
                    Center(
                      child: Text(
                        '$om',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white60,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Calculations for Matrixes ---
  List<({String period, List<CellValue> cells})> _computeWeiMatrix(
    List<TrendItem> items,
    bool isPingte,
  ) {
    final reversed = items.reversed.toList();
    final out = <({String period, List<CellValue> cells})>[];
    var prevOmission = List<int>.filled(kWeiCols.length, 0);

    for (final it in reversed) {
      final balls = it.code.map((b) => b.padLeft(2, '0')).toList();
      final targetBalls =
          isPingte ? balls : (balls.length > 6 ? [balls[6]] : <String>[]);
      final hitMap = <int, List<String>>{};

      for (final b in targetBalls) {
        if (b.isEmpty) continue;
        final tail = int.tryParse(b[b.length - 1]) ?? 0;
        hitMap.putIfAbsent(tail, () => []).add(b);
      }

      final cells = <CellValue>[];
      final curOmission = List<int>.filled(kWeiCols.length, 0);
      for (var c = 0; c < kWeiCols.length; c++) {
        final hit = hitMap[c];
        if (hit != null && hit.isNotEmpty) {
          final first = hit.first;
          cells.add(
            CellValue(
              value: first,
              color: _boseColor(Lottery2026Lookup.boseForNumber(first)),
              allValues: hit,
            ),
          );
          curOmission[c] = 0;
        } else {
          final om = prevOmission[c] + 1;
          cells.add(CellValue(index: om));
          curOmission[c] = om;
        }
      }
      prevOmission = curOmission;
      out.insert(0, (period: it.period, cells: cells));
    }
    return out;
  }

  List<({String period, List<CellValue> cells})> _computeTouMatrix(
    List<TrendItem> items,
    bool isPingte,
  ) {
    final reversed = items.reversed.toList();
    final out = <({String period, List<CellValue> cells})>[];
    var prevOmission = List<int>.filled(kTouCols.length, 0);

    for (final it in reversed) {
      final balls = it.code.map((b) => b.padLeft(2, '0')).toList();
      final targetBalls =
          isPingte ? balls : (balls.length > 6 ? [balls[6]] : <String>[]);
      final hitMap = <int, List<String>>{};

      for (final b in targetBalls) {
        if (b.isEmpty) continue;
        final head = int.tryParse(b[0]) ?? 0;
        if (head >= 0 && head < kTouCols.length) {
          hitMap.putIfAbsent(head, () => []).add(b);
        }
      }

      final cells = <CellValue>[];
      final curOmission = List<int>.filled(kTouCols.length, 0);
      for (var c = 0; c < kTouCols.length; c++) {
        final hit = hitMap[c];
        if (hit != null && hit.isNotEmpty) {
          final first = hit.first;
          cells.add(
            CellValue(
              value: first,
              color: _boseColor(Lottery2026Lookup.boseForNumber(first)),
              allValues: hit,
            ),
          );
          curOmission[c] = 0;
        } else {
          final om = prevOmission[c] + 1;
          cells.add(CellValue(index: om));
          curOmission[c] = om;
        }
      }
      prevOmission = curOmission;
      out.insert(0, (period: it.period, cells: cells));
    }
    return out;
  }

  List<({String period, List<CellValue> cells})> _computeBoseMatrix(
    List<TrendItem> items,
    bool isPingte,
  ) {
    final reversed = items.reversed.toList();
    final out = <({String period, List<CellValue> cells})>[];
    var prevOmission = List<int>.filled(kBoseCols.length, 0);

    for (final it in reversed) {
      final balls = it.code.map((b) => b.padLeft(2, '0')).toList();
      final targetBalls =
          isPingte ? balls : (balls.length > 6 ? [balls[6]] : <String>[]);
      final hitMap = <int, List<String>>{};

      for (final b in targetBalls) {
        if (b.isEmpty) continue;
        final bs = Lottery2026Lookup.boseForNumber(b);
        final colIdx = bs.contains('红') ? 0 : (bs.contains('蓝') ? 1 : 2);
        hitMap.putIfAbsent(colIdx, () => []).add(b);
      }

      final cells = <CellValue>[];
      final curOmission = List<int>.filled(kBoseCols.length, 0);
      for (var c = 0; c < kBoseCols.length; c++) {
        final hit = hitMap[c];
        if (hit != null && hit.isNotEmpty) {
          final first = hit.first;
          cells.add(
            CellValue(
              value: first,
              color: _boseColor(Lottery2026Lookup.boseForNumber(first)),
              allValues: hit,
            ),
          );
          curOmission[c] = 0;
        } else {
          final om = prevOmission[c] + 1;
          cells.add(CellValue(index: om));
          curOmission[c] = om;
        }
      }
      prevOmission = curOmission;
      out.insert(0, (period: it.period, cells: cells));
    }
    return out;
  }

  List<({String period, List<CellValue> cells})> _computeWuxingMatrix(
    List<TrendItem> items,
    bool isPingte,
  ) {
    // 2026 wuxing table
    const wuxingSets = {
      '金': {4, 5, 12, 13, 26, 27, 34, 35, 42, 43},
      '木': {8, 9, 16, 17, 24, 25, 38, 39, 46, 47},
      '水': {1, 14, 15, 22, 23, 30, 31, 44, 45},
      '火': {2, 3, 10, 11, 18, 19, 32, 33, 40, 41, 48, 49},
      '土': {6, 7, 20, 21, 28, 29, 36, 37},
    };

    final reversed = items.reversed.toList();
    final out = <({String period, List<CellValue> cells})>[];
    var prevOmission = List<int>.filled(kWuxingCols.length, 0);

    for (final it in reversed) {
      final balls = it.code.map((b) => b.padLeft(2, '0')).toList();
      final targetBalls =
          isPingte ? balls : (balls.length > 6 ? [balls[6]] : <String>[]);
      final hitMap = <int, List<String>>{};

      for (final b in targetBalls) {
        if (b.isEmpty) continue;
        final n = int.tryParse(b) ?? 0;
        var colIdx = -1;
        for (var i = 0; i < kWuxingCols.length; i++) {
          if (wuxingSets[kWuxingCols[i]]?.contains(n) ?? false) {
            colIdx = i;
            break;
          }
        }
        if (colIdx >= 0) {
          hitMap.putIfAbsent(colIdx, () => []).add(b);
        }
      }

      final cells = <CellValue>[];
      final curOmission = List<int>.filled(kWuxingCols.length, 0);
      for (var c = 0; c < kWuxingCols.length; c++) {
        final hit = hitMap[c];
        if (hit != null && hit.isNotEmpty) {
          final first = hit.first;
          cells.add(
            CellValue(
              value: first,
              color: _boseColor(Lottery2026Lookup.boseForNumber(first)),
              allValues: hit,
            ),
          );
          curOmission[c] = 0;
        } else {
          final om = prevOmission[c] + 1;
          cells.add(CellValue(index: om));
          curOmission[c] = om;
        }
      }
      prevOmission = curOmission;
      out.insert(0, (period: it.period, cells: cells));
    }
    return out;
  }

  List<({String period, List<CellValue> cells})> _computeShengxiaoMatrix(
    List<TrendItem> items,
    bool isPingte,
  ) {
    final reversed = items.reversed.toList();
    final out = <({String period, List<CellValue> cells})>[];
    var prevOmission = List<int>.filled(kShengxiaoCols.length, 0);

    for (final it in reversed) {
      final balls = it.code.map((b) => b.padLeft(2, '0')).toList();
      final targetBalls =
          isPingte ? balls : (balls.length > 6 ? [balls[6]] : <String>[]);
      final hitMap = <int, List<String>>{};

      for (final b in targetBalls) {
        if (b.isEmpty) continue;
        final xiao = Lottery2026Lookup.xiaoForNumber(b);
        final colIdx = kShengxiaoCols.indexOf(xiao);
        if (colIdx >= 0) {
          hitMap.putIfAbsent(colIdx, () => []).add(b);
        }
      }

      final cells = <CellValue>[];
      final curOmission = List<int>.filled(kShengxiaoCols.length, 0);
      for (var c = 0; c < kShengxiaoCols.length; c++) {
        final hit = hitMap[c];
        if (hit != null && hit.isNotEmpty) {
          final first = hit.first;
          cells.add(
            CellValue(
              value: first,
              color: _boseColor(Lottery2026Lookup.boseForNumber(first)),
              allValues: hit,
            ),
          );
          curOmission[c] = 0;
        } else {
          final om = prevOmission[c] + 1;
          cells.add(CellValue(index: om));
          curOmission[c] = om;
        }
      }
      prevOmission = curOmission;
      out.insert(0, (period: it.period, cells: cells));
    }
    return out;
  }
}
