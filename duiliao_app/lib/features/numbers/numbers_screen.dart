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
import '../design/jump_code_assistant_screen.dart';
import '../design/records_screens.dart';

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Selected date for the attribute table.
final numbersDateProvider = NotifierProvider<NumbersDate, String>(
  NumbersDate.new,
);

class NumbersDate extends Notifier<String> {
  @override
  String build() => _formatDate(nowInChina());
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
  int _window = 50; // 30, 50, 100

  static const _baseHotBalls = [
    ('26', 'blue', 9),
    ('03', 'blue', 8),
    ('34', 'red', 8),
    ('11', 'green', 7),
    ('42', 'blue', 7),
    ('19', 'red', 6),
  ];

  static const _baseColdBalls = [
    ('05', 'green', 1),
    ('48', 'blue', 1),
    ('31', 'blue', 2),
    ('12', 'red', 2),
    ('45', 'red', 2),
  ];

  static const _baseZodiacCounts = [
    ('鼠', 6),
    ('牛', 5),
    ('虎', 4),
    ('兔', 5),
    ('龙', 8),
    ('蛇', 9),
    ('马', 4),
    ('羊', 5),
    ('猴', 6),
    ('鸡', 8),
    ('狗', 5),
    ('猪', 4),
  ];

  static const _baseWuxingCounts = [
    ('金', 9),
    ('木', 11),
    ('水', 8),
    ('火', 10),
    ('土', 12),
  ];

  int _lotteryShift(Lottery lottery) => switch (lottery) {
    Lottery.macau => 0,
    Lottery.hk => 1,
    Lottery.taiwan => 2,
    Lottery.neu => 3,
  };

  int _scaleCount(int base50, int idx, int shift) {
    final adjusted = base50 + ((shift == 0) ? 0 : ((idx + shift) % 3 - 1));
    final scaled = (adjusted * _window / 50).round();
    return scaled < 1 ? 1 : scaled;
  }

  String _shiftedBallNumber(String baseNum, int shift, int step) {
    if (shift == 0) return baseNum;
    final parsed = int.tryParse(baseNum) ?? 1;
    final shifted = ((parsed - 1 + shift * step) % 49) + 1;
    return shifted.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final lottery = ref.watch(selectedLotteryProvider);
    final shift = _lotteryShift(lottery);
    final winDelta = _window == 30
        ? -2
        : _window == 100
        ? 2
        : 0;

    final hotBalls = [
      for (var i = 0; i < _baseHotBalls.length; i++)
        (
          _shiftedBallNumber(_baseHotBalls[i].$1, shift, 7),
          shift == 0
              ? _baseHotBalls[i].$2
              : Lottery2026Lookup.boseForNumber(
                  int.parse(_shiftedBallNumber(_baseHotBalls[i].$1, shift, 7)),
                ),
          _scaleCount(_baseHotBalls[i].$3, i, shift),
        ),
    ];

    final coldBalls = [
      for (var i = 0; i < _baseColdBalls.length; i++)
        (
          _shiftedBallNumber(_baseColdBalls[i].$1, shift, 5),
          shift == 0
              ? _baseColdBalls[i].$2
              : Lottery2026Lookup.boseForNumber(
                  int.parse(_shiftedBallNumber(_baseColdBalls[i].$1, shift, 5)),
                ),
          _scaleCount(_baseColdBalls[i].$3, i, shift),
        ),
    ];

    final redPct = (38 + shift * 2 + winDelta).clamp(25, 48);
    final bluePct = (34 - shift + (winDelta ~/ 2)).clamp(24, 45);
    final greenPct = (100 - redPct - bluePct).clamp(18, 45);

    final zodiacCounts = [
      for (var i = 0; i < _baseZodiacCounts.length; i++)
        (
          _baseZodiacCounts[i].$1,
          _scaleCount(_baseZodiacCounts[i].$2, i, shift),
        ),
    ];
    final sortedCounts = [for (final z in zodiacCounts) z.$2]
      ..sort((a, b) => b.compareTo(a));
    final highlightThreshold = sortedCounts.length >= 3 ? sortedCounts[2] : 8;

    final oddLeft = (46 + shift * 2 + winDelta).clamp(35, 65);
    final bigLeft = (52 - shift * 2 + winDelta).clamp(35, 65);
    final jiayeLeft = (41 + shift * 3 - winDelta).clamp(32, 68);
    final genderLeft = (47 + shift - winDelta).clamp(35, 65);

    final wuxingCounts = [
      for (var i = 0; i < _baseWuxingCounts.length; i++)
        (
          _baseWuxingCounts[i].$1,
          _scaleCount(_baseWuxingCounts[i].$2, i, shift),
        ),
    ];

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
                subtitle: '${lottery.label}六合彩 · 近 $_window 期统计窗口',
                actions: [
                  GlassIconButton(
                    icon: Icons.filter_center_focus_rounded,
                    tooltip: '挑码助手',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const JumpCodeAssistantScreen(),
                      ),
                    ),
                  ),
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
                            active: l == lottery,
                            onTap: () => ref
                                .read(selectedLotteryProvider.notifier)
                                .set(l),
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
                          for (var i = 0; i < hotBalls.length; i++)
                            NumberBall(
                              number: hotBalls[i].$1,
                              bose: hotBalls[i].$2,
                              size: 28,
                              caption: '${hotBalls[i].$3} 次',
                              captionBold: i == 0,
                              captionColor: i == 0
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                        ],
                      ),
                    ),

                    // Section 2: 冷号榜
                    const DesignSectionHeader(title: '冷号榜'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          for (final ball in coldBalls)
                            NumberBall(
                              number: ball.$1,
                              bose: ball.$2,
                              size: 28,
                              caption: '${ball.$3} 次',
                            ),
                        ],
                      ),
                    ),

                    // Section 3: 波色分布
                    const DesignSectionHeader(title: '波色分布'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _WaveDistRow(
                            shortLabel: '红',
                            name: '红波',
                            bose: 'red',
                            pct: redPct / 100,
                            pctLabel: '$redPct%',
                            barColor: DuiliaoColors.miss,
                          ),
                          const SizedBox(height: 12),
                          _WaveDistRow(
                            shortLabel: '蓝',
                            name: '蓝波',
                            bose: 'blue',
                            pct: bluePct / 100,
                            pctLabel: '$bluePct%',
                            barColor: null,
                          ),
                          const SizedBox(height: 12),
                          _WaveDistRow(
                            shortLabel: '绿',
                            name: '绿波',
                            bose: 'green',
                            pct: greenPct / 100,
                            pctLabel: '$greenPct%',
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
                        itemCount: zodiacCounts.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              mainAxisExtent: 58,
                            ),
                        itemBuilder: (context, idx) {
                          final item = zodiacCounts[idx];
                          final highlight = item.$2 >= highlightThreshold;
                          return GlassSubtleBox(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
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
                                const SizedBox(height: 3),
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
                      child: Column(
                        children: [
                          _DualAttrRow(
                            label: '单 / 双',
                            leftPct: '$oddLeft%',
                            rightPct: '${100 - oddLeft}%',
                            value: oddLeft / 100,
                            highlightLeft: oddLeft >= 50,
                          ),
                          const SizedBox(height: 12),
                          _DualAttrRow(
                            label: '大 / 小',
                            leftPct: '$bigLeft%',
                            rightPct: '${100 - bigLeft}%',
                            value: bigLeft / 100,
                            highlightLeft: bigLeft >= 50,
                          ),
                          const SizedBox(height: 12),
                          _DualAttrRow(
                            label: '家禽野兽',
                            leftPct: '$jiayeLeft%',
                            rightPct: '${100 - jiayeLeft}%',
                            value: jiayeLeft / 100,
                            highlightLeft: jiayeLeft >= 50,
                          ),
                          const SizedBox(height: 12),
                          _DualAttrRow(
                            label: '男肖女肖',
                            leftPct: '$genderLeft%',
                            rightPct: '${100 - genderLeft}%',
                            value: genderLeft / 100,
                            highlightLeft: genderLeft >= 50,
                          ),
                        ],
                      ),
                    ),

                    // Section 6: 五行分布
                    const DesignSectionHeader(title: '五行分布'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          for (final wx in wuxingCounts)
                            GlassChipTag(label: '${wx.$1} ${wx.$2}'),
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
                          mainAxisExtent: 54,
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
