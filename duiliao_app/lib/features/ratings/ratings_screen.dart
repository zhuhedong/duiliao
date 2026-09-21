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
      appBar: AppBar(title: const Text('源评级')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(ratingsProvider(key)),
        child: Column(
          children: [
            _Selectors(lottery: lottery, playType: playType, window: window),
            Expanded(
              child: AsyncView<({RatingsResult result, bool isStale, String? storedAt})>(
                value: async,
                loading: const SkeletonList(itemHeight: 130),
                onRetry: () => ref.invalidate(ratingsProvider(key)),
                emptyCheck: (data) => data.result.sources.isEmpty,
                emptyMessage: '该玩法暂无评级数据',
                builder: (data) {
                  final rows = data.result.sortedBy(window);
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: rows.length + (data.isStale ? 2 : 1),
                    itemBuilder: (context, index) {
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
                      return _RatingCard(
                        row: rows[index - offset],
                        rank: index - offset + 1,
                        window: window,
                        lottery: lottery,
                      );
                    },
                  );
                },
              ),
            ),
          ],
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
    return Material(
      color: context.colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Lottery>(
                    initialValue: lottery,
                    isDense: true,
                    decoration: const InputDecoration(labelText: '彩种'),
                    items: [
                      for (final l in Lottery.all)
                        DropdownMenuItem(value: l, child: Text(l.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(selectedLotteryProvider.notifier).set(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: playType,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '玩法'),
                    items: [
                      for (final play in kPlayTypes)
                        DropdownMenuItem(
                          value: play.key,
                          child: Text(play.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(selectedPlayTypeProvider.notifier).set(value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('窗口', style: context.texts.labelMedium),
                const SizedBox(width: 10),
                SegmentedButton<int>(
                  segments: [
                    for (final w in kRatingWindows)
                      ButtonSegment(value: w, label: Text('$w 期')),
                  ],
                  selected: {window},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      ref.read(ratingWindowProvider.notifier).set(selection.first),
                ),
              ],
            ),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SourceDetailScreen(
              sourceId: row.sourceId,
              sourceName: row.sourceName,
              lottery: lottery,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    alignment: Alignment.center,
                    child: Text(
                      '$rank',
                      style: context.texts.labelLarge?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      row.sourceName,
                      style: context.texts.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusChip(
                    label: row.streakLabel,
                    color: row.currentStreak >= 0
                        ? DuiliaoColors.hit
                        : DuiliaoColors.miss,
                    icon: row.currentStreak >= 0
                        ? Icons.trending_up
                        : Icons.trending_down,
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Three windows side by side, so a rate that looks good at 30 but
              // poor at 100 is immediately visible.
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

              const Divider(height: 18),

              // Integrity block. These signals decide whether the rates above
              // mean anything.
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: '开奖前命中',
                      value: formatRate(row.beforeRate),
                      hint: '${row.beforeN} 样本',
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: '开奖后命中',
                      value: formatRate(row.afterRate),
                      hint: '${row.afterN} 样本',
                      valueColor: row.suspectedPostDrawEditing
                          ? DuiliaoColors.conflict
                          : null,
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: '连中 / 连挂',
                      value: '${row.longestHit} / ${row.longestMiss}',
                    ),
                  ),
                ],
              ),

              if (row.hasIntegrityWarning || row.isSmallSample(window)) ...[
                const SizedBox(height: 10),
                ..._warnings(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _warnings(BuildContext context) {
    final widgets = <Widget>[];

    if (row.suspectedPostDrawEditing) {
      widgets.add(WarningNote(
        // The headline number is untrustworthy, so say so plainly rather than
        // leaving the operator to spot the gap.
        message: '疑似开奖后改料：开奖后命中率 ${formatRate(row.afterRate)} '
            '显著高于开奖前 ${formatRate(row.beforeRate)}，命中率不可信',
        icon: Icons.block,
        color: DuiliaoColors.conflict,
      ));
    }
    if (row.hasPostDrawEdits) {
      widgets.add(WarningNote(
        message: '开奖后修改预测 ${row.afterEdits} 次',
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
        message: '样本不足：$window 期窗口仅 ${row.sampleSize(window)} 个样本，'
            '命中率参考价值有限',
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
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? context.colors.primaryContainer.withValues(alpha: 0.4)
            : context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$window 期', style: context.texts.labelSmall),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                // formatRate renders a dash for null: "no data" must not read as 0%.
                formatRate(rate),
                style: context.texts.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (smallSample) ...[
                const SizedBox(width: 3),
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 13,
                  color: DuiliaoColors.warning,
                ),
              ],
            ],
          ),
          Text(
            sample == null ? '无样本' : 'n=$sample',
            style: context.texts.labelSmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '覆盖质量',
            style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '统计区间 ${result.periodFrom ?? '—'} ~ ${result.periodTo ?? '—'}，'
            '共 ${result.periods.length} 期；'
            '缺期合计 $totalMissing，待判合计 $totalPending。',
            style: context.texts.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            '命中率显示「—」表示该窗口没有样本，与 0% 含义不同。',
            style: context.texts.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
