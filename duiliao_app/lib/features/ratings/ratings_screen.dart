/// Source ratings: hit rates across windows, plus the integrity signals that
/// decide whether those hit rates can be believed at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/json.dart';
import '../../domain/lottery.dart';
import '../../domain/models/ratings.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import 'source_detail_screen.dart';

const List<int> kRatingWindows = [30, 50, 100];

final ratingsProvider = FutureProvider.family<
    ({RatingsResult result, bool isStale, String? storedAt}),
    ({Lottery lottery, String playType})>((ref, key) async {
  final fetched = await ref.read(collectorRepositoryProvider).ratings(
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

/// Which window drives the sort and the headline column.
final ratingWindowProvider = NotifierProvider<RatingWindow, int>(RatingWindow.new);

class RatingWindow extends Notifier<int> {
  @override
  int build() => 30;
  void set(int window) => state = window;
}

class RatingsScreen extends ConsumerWidget {
  const RatingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lottery = ref.watch(selectedLotteryProvider);
    final playType = ref.watch(selectedPlayTypeProvider);
    final window = ref.watch(ratingWindowProvider);
    final key = (lottery: lottery, playType: playType);
    final async = ref.watch(ratingsProvider(key));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.refresh(ratingsProvider(key).future);
          },
          child: AsyncView<({RatingsResult result, bool isStale, String? storedAt})>(
            value: async,
            loading: const SkeletonList(itemHeight: 180),
            onRetry: () => ref.invalidate(ratingsProvider(key)),
            emptyCheck: (data) => data.result.sources.isEmpty,
            emptyMessage: '该玩法暂无评级数据',
            builder: (data) {
              final rows = data.result.sortedBy(window);
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: GlassContainer(
                          height: 54,
                          borderRadius: BorderRadius.circular(999),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Text(
                                  '源评级分析',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  SliverToBoxAdapter(
                    child: _Selectors(lottery: lottery, playType: playType, window: window),
                  ),

                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (data.isStale && index == 0) {
                          return OfflineBanner(
                            storedAtLabel: data.storedAt,
                            onRetry: () => ref.invalidate(ratingsProvider(key)),
                          );
                        }
                        final offset = data.isStale ? 1 : 0;
                        if (index == rows.length + offset) {
                          return _CoverageFootnote(result: data.result);
                        }
                        
                        // Add some bottom padding to the very last item footprint
                        final isLast = index == rows.length + offset - 1;
                        return Padding(
                          padding: EdgeInsets.only(bottom: isLast ? 96.0 : 0.0),
                          child: _RatingCard(
                            row: rows[index - offset],
                            rank: index - offset + 1,
                            window: window,
                            lottery: lottery,
                          ),
                        );
                      },
                      childCount: rows.length + (data.isStale ? 2 : 1),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Selectors extends ConsumerWidget {
  const _Selectors({
    required this.lottery,
    required this.playType,
    required this.window,
  });

  final Lottery lottery;
  final String playType;
  final int window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassContainer(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Lottery>(
                  initialValue: lottery,
                  isDense: true,
                  decoration: const InputDecoration(labelText: '彩种', border: InputBorder.none),
                  items: [
                    for (final l in Lottery.all)
                      DropdownMenuItem(value: l, child: Text(l.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) ref.read(selectedLotteryProvider.notifier).set(value);
                  },
                ),
              ),
              Container(width: 1, height: 30, color: Colors.grey.withValues(alpha: 0.3)),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: playType,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '玩法', border: InputBorder.none),
                  items: [
                    for (final play in kPlayTypes)
                      DropdownMenuItem(
                        value: play.key,
                        child: Text(play.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) ref.read(selectedPlayTypeProvider.notifier).set(value);
                  },
                ),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '统计窗口',
                style: context.texts.labelMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlassSegmentedControl<int>(
                  items: kRatingWindows,
                  selected: window,
                  labelBuilder: (w) => '$w 期',
                  onChanged: (w) =>
                      ref.read(ratingWindowProvider.notifier).set(w),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({
    required this.row,
    required this.rank,
    required this.window,
    required this.lottery,
  });

  final RatingRow row;
  final int rank;
  final int window;
  final Lottery lottery;

  Widget _buildRankBadge(BuildContext context) {
    Gradient gradient;
    Color textColor = Colors.white;
    List<BoxShadow> shadows = [];
    if (rank == 1) {
      gradient = const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF9100)]);
      shadows = [BoxShadow(color: const Color(0xFFFF9100).withValues(alpha: 0.4), blurRadius: 10)];
    } else if (rank == 2) {
      gradient = const LinearGradient(colors: [Color(0xFFE2E8F0), Color(0xFF94A3B8)]);
      shadows = [BoxShadow(color: const Color(0xFF94A3B8).withValues(alpha: 0.3), blurRadius: 10)];
    } else if (rank == 3) {
      gradient = const LinearGradient(colors: [Color(0xFFCD7F32), Color(0xFFA0522D)]);
      shadows = [BoxShadow(color: const Color(0xFFCD7F32).withValues(alpha: 0.3), blurRadius: 10)];
    } else {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      gradient = LinearGradient(colors: [
        isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
        isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
      ]);
      textColor = isDark ? Colors.white70 : const Color(0xFF475569);
    }

    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: gradient,
        shape: BoxShape.circle,
        boxShadow: shadows,
      ),
      child: Text(
        '$rank',
        style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SourceDetailScreen(
            sourceId: row.sourceId,
            sourceName: row.sourceName,
            lottery: lottery,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildRankBadge(context),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  row.sourceName,
                  style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: row.currentStreak >= 0
                      ? DuiliaoColors.hit.withValues(alpha: 0.15)
                      : DuiliaoColors.miss.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      row.currentStreak >= 0 ? Icons.trending_up : Icons.trending_down,
                      size: 14,
                      color: row.currentStreak >= 0 ? DuiliaoColors.hit : DuiliaoColors.miss,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      row.streakLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: row.currentStreak >= 0 ? DuiliaoColors.hit : DuiliaoColors.miss,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Windows Display
          Row(
            children: [
              for (final w in kRatingWindows)
                Expanded(
                  child: _WindowCell(
                    window: w,
                    rate: row.hitRate(w),
                    sample: row.sampleSize(w),
                    highlighted: w == window,
                    smallSample: row.isSmallSample(w),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('盘前命中', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(formatRate(row.beforeRate), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text('盘后命中', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(
                        formatRate(row.afterRate),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: row.suspectedPostDrawEditing ? DuiliaoColors.conflict : null,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text('极值 (中/挂)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text('${row.longestHit} / ${row.longestMiss}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (row.hasIntegrityWarning || row.isSmallSample(window)) ...[
            const SizedBox(height: 12),
            ..._warnings(context),
          ],
        ],
      ),
    );
  }

  List<Widget> _warnings(BuildContext context) {
    final widgets = <Widget>[];

    if (row.suspectedPostDrawEditing) {
      widgets.add(WarningNote(
        message: '疑似改料：开奖后命中率 ${formatRate(row.afterRate)} 显著高于开奖前，不可信',
        icon: Icons.block,
        color: DuiliaoColors.conflict,
      ));
    }
    if (row.hasPostDrawEdits) {
      widgets.add(WarningNote(
        message: '盘后修改预测 ${row.afterEdits} 次',
        icon: Icons.edit_note,
      ));
    }
    if (row.hasDirtyFlags) {
      widgets.add(WarningNote(
        message: '脏源标记 ${row.dirtyFlags} 次（自称命中与判定不符）',
        icon: Icons.report_problem_outlined,
        color: DuiliaoColors.conflict,
      ));
    }
    if (row.isSmallSample(window)) {
      widgets.add(WarningNote(
        message: '样本不足：$window 期仅 ${row.sampleSize(window)} 个样本',
        icon: Icons.warning_amber_rounded,
      ));
    }

    return [
      for (final widget in widgets)
        Padding(padding: const EdgeInsets.only(bottom: 6), child: widget),
    ];
  }
}

class _WindowCell extends StatelessWidget {
  const _WindowCell({
    required this.window,
    required this.rate,
    required this.sample,
    required this.highlighted,
    required this.smallSample,
  });

  final int window;
  final double? rate;
  final int? sample;
  final bool highlighted;
  final bool smallSample;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? primary.withValues(alpha: isDark ? 0.2 : 0.1)
            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? primary.withValues(alpha: 0.5)
              : Colors.transparent,
          width: highlighted ? 1.5 : 0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$window 期',
            style: TextStyle(
              fontSize: 12,
              color: highlighted ? primary : context.colors.onSurfaceVariant,
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                formatRate(rate),
                style: context.texts.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: highlighted ? primary : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (smallSample) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: DuiliaoColors.warning,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            sample == null ? '无样本' : 'n=$sample',
            style: TextStyle(
              fontSize: 10,
              color: highlighted ? primary.withValues(alpha: 0.8) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverageFootnote extends StatelessWidget {
  const _CoverageFootnote({required this.result});

  final RatingsResult result;

  @override
  Widget build(BuildContext context) {
    final totalMissing = result.sources.fold<int>(0, (sum, r) => sum + r.missing);
    final totalPending = result.sources.fold<int>(0, (sum, r) => sum + r.pending);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text('覆盖质量', style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '统计区间 ${result.periodFrom ?? '—'} ~ ${result.periodTo ?? '—'}，'
              '共 ${result.periods.length} 期；'
              '缺期合计 $totalMissing，待判合计 $totalPending。',
              style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
