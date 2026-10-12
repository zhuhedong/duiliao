/// Source credibility ratings aligned 1:1 with ratings.html.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/ratings.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import 'source_detail_screen.dart';

const List<int> kRatingWindows = [30, 50, 100];

final ratingsProvider = FutureProvider.family<
  ({RatingsResult result, bool isStale, String? storedAt}),
  ({Lottery lottery, String playType})
>((ref, key) async {
  final fetched = await ref
      .read(collectorRepositoryProvider)
      .ratings(
        lottery: key.lottery.code,
        playType: key.playType,
        windows: kRatingWindows,
      );
  return (
    result: fetched.value,
    isStale: fetched.isStale,
    storedAt: fetched.storedAtLabel,
  );
});

final ratingWindowProvider = NotifierProvider<RatingWindow, int>(
  RatingWindow.new,
);

class RatingWindow extends Notifier<int> {
  @override
  int build() => 50;
  void set(int window) => state = window;
}

class _RatingSample {
  const _RatingSample({
    required this.grade,
    required this.sourceId,
    required this.name,
    required this.sub,
    required this.pillLabel,
    required this.pillColor,
    required this.hitRate,
    required this.hitColor,
    required this.maxWin,
    required this.maxLoss,
    required this.missing,
    this.warningPill,
    this.footnote,
  });

  final String grade;
  final String sourceId;
  final String name;
  final String sub;
  final String pillLabel;
  final Color pillColor;
  final String hitRate;
  final Color? hitColor;
  final String maxWin;
  final String maxLoss;
  final String missing;
  final String? warningPill;
  final String? footnote;
}

const _fallbackRatingSamples = [
  _RatingSample(
    grade: 'S',
    sourceId: 'haige_xiao',
    name: '海哥平特一肖',
    sub: '平特一肖 · 样本 50 期',
    pillLabel: '稳定',
    pillColor: DuiliaoColors.hit,
    hitRate: '62%',
    hitColor: DuiliaoColors.hit,
    maxWin: '6',
    maxLoss: '3',
    missing: '0',
  ),
  _RatingSample(
    grade: 'A',
    sourceId: 'top_master',
    name: '顶尖大师',
    sub: '特肖 · 样本 49 期',
    pillLabel: '良好',
    pillColor: DuiliaoColors.primaryDark,
    hitRate: '55%',
    hitColor: DuiliaoColors.primaryDark,
    maxWin: '4',
    maxLoss: '4',
    missing: '1',
  ),
  _RatingSample(
    grade: 'B',
    sourceId: 'gjp_fax',
    name: '管家婆传真',
    sub: '特肖 · 样本 48 期',
    pillLabel: '波动',
    pillColor: DuiliaoColors.warning,
    hitRate: '48%',
    hitColor: DuiliaoColors.warning,
    maxWin: '3',
    maxLoss: '5',
    missing: '2',
  ),
  _RatingSample(
    grade: 'C',
    sourceId: 'bxz',
    name: '白小组',
    sub: '特肖 · 样本 46 期',
    pillLabel: '偏弱',
    pillColor: DuiliaoColors.miss,
    hitRate: '41%',
    hitColor: DuiliaoColors.miss,
    maxWin: '2',
    maxLoss: '8',
    missing: '4',
    warningPill: '虚假报喜 1 次(不一致)',
  ),
  _RatingSample(
    grade: '—',
    sourceId: 'xzt_laoqian',
    name: '肖中特-老钱',
    sub: '特肖 · 样本 41 期',
    pillLabel: '待对奖',
    pillColor: DuiliaoColors.pending,
    hitRate: '—',
    hitColor: null,
    maxWin: '—',
    maxLoss: '—',
    missing: '9',
    footnote: '数据不足 · 缺期 9 期,补足样本后自动计算评级',
  ),
];

class RatingsScreen extends ConsumerWidget {
  const RatingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lottery = ref.watch(selectedLotteryProvider);
    final window = ref.watch(ratingWindowProvider);
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
                title: '源可信评级',
                subtitle: '对奖口径 · 官方判定为准',
                actions: [
                  GlassIconButton(
                    icon: Icons.info_outline_rounded,
                    tooltip: '评级说明',
                    onTap: () => _showRatingInfo(context),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
                      items: kRatingWindows,
                      selected: window,
                      labelBuilder: (w) => w == 30 ? '窗口 30 期' : '$w 期',
                      onChanged: (w) =>
                          ref.read(ratingWindowProvider.notifier).set(w),
                    ),
                    const SizedBox(height: 12),

                    // Context Strip
                    GlassSubtleBox(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: Text(
                        '当前为 $window 期窗口的静态评级样例 · 数据截至第 2026276 期',
                        style: context.texts.labelSmall,
                      ),
                    ),
                    const SizedBox(height: 12),

                    for (final item in _fallbackRatingSamples)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RatingSampleCard(
                          item: item,
                          lottery: lottery,
                        ),
                      ),
                  ],
                ),
              ),
              // Sticky Bottom Action Bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  children: [
                    GlassGhostButton(
                      label: '导出评级',
                      onTap: () {
                        Clipboard.setData(
                          const ClipboardData(
                            text:
                                '源可信评级 (50期): S 海哥平特一肖 62% | A 顶尖大师 55% | B 管家婆传真 48% | C 白小组 41%',
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已导出评级摘要到剪贴板')),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GlassButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '已重算 ${lottery.label} 近 $window 期源可信评级矩阵',
                              ),
                            ),
                          );
                        },
                        child: const Text('计算评级矩阵'),
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

  void _showRatingInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('源可信评级口径'),
        content: const Text(
          '评级仅以官方开奖对照结果为准：\n'
          '• S 级：命中率 ≥ 60% 且无虚假报喜、缺期 ≤ 1\n'
          '• A 级：命中率 ≥ 52% 且连挂可控\n'
          '• B 级：命中率 45%–52%，近期存在一定波动\n'
          '• C 级：命中率偏弱或存在自称命中与官方不一致',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _RatingSampleCard extends StatelessWidget {
  const _RatingSampleCard({required this.item, required this.lottery});

  final _RatingSample item;
  final Lottery lottery;

  @override
  Widget build(BuildContext context) {
    final isMutedGrade = item.grade == '—';
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SourceDetailScreen(
            lottery: lottery,
            sourceId: item.sourceId,
            sourceName: item.name,
            initialPlayType: 'texiao',
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isMutedGrade)
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  child: Text(
                    '—',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                BrandLogoBox(
                  label: item.grade,
                  size: 34,
                  borderRadius: 10,
                  fontSize: 16,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(item.sub, style: context.texts.labelSmall),
                  ],
                ),
              ),
              GlassStatusPill(
                label: item.pillLabel,
                color: item.pillColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricCell(
                  label: '命中率',
                  value: item.hitRate,
                  valueColor: item.hitColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCell(label: '最大连中', value: item.maxWin),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCell(label: '最大连挂', value: item.maxLoss),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricCell(label: '缺期', value: item.missing),
              ),
            ],
          ),
          if (item.warningPill != null) ...[
            const SizedBox(height: 10),
            GlassStatusPill(
              label: item.warningPill!,
              color: DuiliaoColors.miss,
              showDot: false,
            ),
          ],
          if (item.footnote != null) ...[
            const SizedBox(height: 10),
            Text(item.footnote!, style: context.texts.labelSmall),
          ],
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return GlassSubtleBox(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        children: [
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
