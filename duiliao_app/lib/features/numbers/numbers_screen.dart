/// Number analysis (numbers.html) + 01–49 attribute encyclopedia & reverse lookup.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/draw.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Selected date for the attribute table.
final numbersDateProvider = NotifierProvider<NumbersDate, String>(
  NumbersDate.new,
);

class NumbersDate extends Notifier<String> {
  @override
  String build() => _formatDate(DateTime.now());
  void set(DateTime date) => state = _formatDate(date);
}

final numbersProvider = FutureProvider.family<
  ({NumbersResult result, bool isStale, String? storedAt}),
  String
>((ref, date) async {
  final fetched = await ref
      .read(collectorRepositoryProvider)
      .numbers(date: date);
  return (
    result: fetched.value,
    isStale: fetched.isStale,
    storedAt: fetched.storedAtLabel,
  );
});

/// Active reverse-lookup filters: attribute name -> accepted values.
@immutable
class NumberFilters {
  const NumberFilters({this.selections = const {}});

  final Map<String, Set<String>> selections;

  bool get isEmpty => selections.values.every((v) => v.isEmpty);

  Set<String> valuesFor(String key) => selections[key] ?? const {};

  NumberFilters toggle(String key, String value) {
    final next = {
      for (final entry in selections.entries) entry.key: {...entry.value},
    };
    final bucket = next.putIfAbsent(key, () => <String>{});
    if (!bucket.remove(value)) bucket.add(value);
    return NumberFilters(selections: next);
  }

  NumberFilters cleared() => const NumberFilters();

  bool matches(NumberAttr attr) {
    for (final entry in selections.entries) {
      if (entry.value.isEmpty) continue;
      final actual = _valueOf(attr, entry.key);
      if (actual == null || !entry.value.contains(actual)) return false;
    }
    return true;
  }

  static String? _valueOf(NumberAttr attr, String key) => switch (key) {
    'bose' => attr.bose,
    'size' => attr.size,
    'odd' => attr.odd,
    'head' => attr.head,
    'wei' => attr.wei,
    'sum' => attr.sum,
    'jiaye' => attr.jiaye,
    'gender' => attr.gender,
    'tianDi' => attr.tianDi,
    'yinYang' => attr.yinYang,
    'luck' => attr.luck,
    'season' => attr.season,
    'direction' => attr.direction,
    'xiao' => attr.xiao,
    'wuxing' => attr.wuxing,
    _ => null,
  };
}

final numberFiltersProvider =
    NotifierProvider<NumberFiltersController, NumberFilters>(
      NumberFiltersController.new,
    );

class NumberFiltersController extends Notifier<NumberFilters> {
  @override
  NumberFilters build() => const NumberFilters();
  void toggle(String key, String value) => state = state.toggle(key, value);
  void clear() => state = state.cleared();
}

class NumbersScreen extends ConsumerStatefulWidget {
  const NumbersScreen({super.key});

  @override
  ConsumerState<NumbersScreen> createState() => _NumbersScreenState();
}

class _NumbersScreenState extends ConsumerState<NumbersScreen> {
  Lottery _lottery = Lottery.macau;
  int _window = 50; // 30, 50, 100

  static const _zodiacCounts = [
    ('鼠', 6, false),
    ('牛', 5, false),
    ('虎', 4, false),
    ('兔', 5, false),
    ('龙', 8, true),
    ('蛇', 9, true),
    ('马', 4, false),
    ('羊', 5, false),
    ('猴', 6, false),
    ('鸡', 8, true),
    ('狗', 5, false),
    ('猪', 4, false),
  ];

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                leading: canPop
                    ? GlassIconButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      )
                    : null,
                title: '号码分析',
                subtitle: '${_lottery.label}六合彩 · 统计窗口',
                actions: [
                  GlassIconButton(
                    icon: Icons.filter_alt_outlined,
                    tooltip: '属性总表',
                    onTap: () => _showEncyclopediaSheet(context),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  children: [
                    // Lottery chips + Window Segmented Control
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final l in Lottery.all)
                          GlassChipTag(
                            label: l.label,
                            active: l == _lottery,
                            onTap: () => setState(() => _lottery = l),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GlassSegmentedControl<int>(
                      items: const [30, 50, 100],
                      selected: _window,
                      labelBuilder: (w) => '近 $w 期',
                      onChanged: (v) => setState(() => _window = v),
                    ),

                    // Section 1: 热号榜
                    const DesignSectionHeader(title: '热号榜'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          NumberBall(
                            number: '26',
                            bose: 'blue',
                            size: 28,
                            caption: '9 次',
                            captionBold: true,
                            captionColor:
                                Theme.of(context).colorScheme.primary,
                          ),
                          const NumberBall(
                            number: '03',
                            bose: 'blue',
                            size: 28,
                            caption: '8 次',
                          ),
                          const NumberBall(
                            number: '34',
                            bose: 'red',
                            size: 28,
                            caption: '8 次',
                          ),
                          const NumberBall(
                            number: '11',
                            bose: 'green',
                            size: 28,
                            caption: '7 次',
                          ),
                          const NumberBall(
                            number: '42',
                            bose: 'blue',
                            size: 28,
                            caption: '7 次',
                          ),
                          const NumberBall(
                            number: '19',
                            bose: 'red',
                            size: 28,
                            caption: '6 次',
                          ),
                        ],
                      ),
                    ),

                    // Section 2: 冷号榜
                    const DesignSectionHeader(title: '冷号榜'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          NumberBall(
                            number: '05',
                            bose: 'green',
                            size: 28,
                            caption: '1 次',
                          ),
                          NumberBall(
                            number: '48',
                            bose: 'blue',
                            size: 28,
                            caption: '1 次',
                          ),
                          NumberBall(
                            number: '31',
                            bose: 'blue',
                            size: 28,
                            caption: '2 次',
                          ),
                          NumberBall(
                            number: '12',
                            bose: 'red',
                            size: 28,
                            caption: '2 次',
                          ),
                          NumberBall(
                            number: '45',
                            bose: 'red',
                            size: 28,
                            caption: '2 次',
                          ),
                        ],
                      ),
                    ),

                    // Section 3: 波色分布
                    const DesignSectionHeader(title: '波色分布'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: const Column(
                        children: [
                          _WaveDistRow(
                            shortLabel: '红',
                            name: '红波',
                            bose: 'red',
                            pct: 0.38,
                            pctLabel: '38%',
                            barColor: DuiliaoColors.miss,
                          ),
                          SizedBox(height: 12),
                          _WaveDistRow(
                            shortLabel: '蓝',
                            name: '蓝波',
                            bose: 'blue',
                            pct: 0.34,
                            pctLabel: '34%',
                            barColor: null,
                          ),
                          SizedBox(height: 12),
                          _WaveDistRow(
                            shortLabel: '绿',
                            name: '绿波',
                            bose: 'green',
                            pct: 0.28,
                            pctLabel: '28%',
                            barColor: DuiliaoColors.hit,
                          ),
                        ],
                      ),
                    ),

                    // Section 4: 生肖分布
                    const DesignSectionHeader(title: '生肖分布'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: GridView.builder(
                        itemCount: _zodiacCounts.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1.25,
                            ),
                        itemBuilder: (context, idx) {
                          final item = _zodiacCounts[idx];
                          final highlight = item.$3;
                          return GlassSubtleBox(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            borderColor: highlight
                                ? DuiliaoColors.auroraViolet.withValues(
                                    alpha: 0.55,
                                  )
                                : null,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item.$1,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: highlight
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: highlight
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${item.$2} 次',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: highlight
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: highlight
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // Section 5: 属性分布
                    const DesignSectionHeader(title: '属性分布'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: const Column(
                        children: [
                          _DualAttrRow(
                            label: '单 / 双',
                            leftPct: '46%',
                            rightPct: '54%',
                            value: 0.46,
                            highlightLeft: false,
                          ),
                          SizedBox(height: 12),
                          _DualAttrRow(
                            label: '大 / 小',
                            leftPct: '52%',
                            rightPct: '48%',
                            value: 0.52,
                            highlightLeft: true,
                          ),
                          SizedBox(height: 12),
                          _DualAttrRow(
                            label: '家禽野兽',
                            leftPct: '41%',
                            rightPct: '59%',
                            value: 0.41,
                            highlightLeft: false,
                          ),
                          SizedBox(height: 12),
                          _DualAttrRow(
                            label: '男肖女肖',
                            leftPct: '47%',
                            rightPct: '53%',
                            value: 0.47,
                            highlightLeft: false,
                          ),
                        ],
                      ),
                    ),

                    // Section 6: 五行分布
                    const DesignSectionHeader(title: '五行分布'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          GlassChipTag(label: '金 9'),
                          GlassChipTag(label: '木 11'),
                          GlassChipTag(label: '水 8'),
                          GlassChipTag(label: '火 10'),
                          GlassChipTag(label: '土 12'),
                        ],
                      ),
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

  void _showEncyclopediaSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(12),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '01–49 号码属性总表 (2026)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    controller: scrollCtrl,
                    itemCount: 49,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.75,
                        ),
                    itemBuilder: (_, idx) {
                      final n = idx + 1;
                      return Center(
                        child: NumberBall(
                          number: n.toString().padLeft(2, '0'),
                          bose: Lottery2026Lookup.boseForNumber(n),
                          xiao: Lottery2026Lookup.xiaoForNumber(n),
                          size: 30,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveDistRow extends StatelessWidget {
  const _WaveDistRow({
    required this.shortLabel,
    required this.name,
    required this.bose,
    required this.pct,
    required this.pctLabel,
    required this.barColor,
  });

  final String shortLabel;
  final String name;
  final String bose;
  final double pct;
  final String pctLabel;
  final Color? barColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NumberBall(number: shortLabel, bose: bose, size: 22),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(name, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(child: GlassLinearProgress(value: pct, color: barColor)),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            pctLabel,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _DualAttrRow extends StatelessWidget {
  const _DualAttrRow({
    required this.label,
    required this.leftPct,
    required this.rightPct,
    required this.value,
    required this.highlightLeft,
  });

  final String label;
  final String leftPct;
  final String rightPct;
  final double value;
  final bool highlightLeft;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        SizedBox(
          width: 34,
          child: Text(
            leftPct,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: highlightLeft ? FontWeight.w700 : FontWeight.w500,
              color: highlightLeft ? primary : muted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: GlassLinearProgress(value: value)),
        const SizedBox(width: 10),
        SizedBox(
          width: 34,
          child: Text(
            rightPct,
            style: TextStyle(
              fontSize: 11,
              fontWeight: !highlightLeft ? FontWeight.w700 : FontWeight.w500,
              color: !highlightLeft ? primary : muted,
            ),
          ),
        ),
      ],
    );
  }
}
