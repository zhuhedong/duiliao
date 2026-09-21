/// Consensus board: what the sources collectively predict for a period.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/consensus.dart';
import '../../domain/models/prediction.dart';
import '../../domain/play_type.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../../ui/widgets/number_ball.dart';
import '../comparison/comparison_screen.dart';

final consensusProvider = FutureProvider.family<
    ({ConsensusResult result, bool isStale, String? storedAt}),
    ({Lottery lottery, String period})>((ref, key) async {
  final fetched = await ref
      .read(collectorRepositoryProvider)
      .consensus(lottery: key.lottery.code, period: key.period);
  return (
    result: fetched.value,
    isStale: fetched.isStale,
    storedAt: fetched.storedAtLabel,
  );
});

class ConsensusScreen extends ConsumerStatefulWidget {
  const ConsensusScreen({super.key, this.lottery, this.initialPeriod});

  final Lottery? lottery;
  final String? initialPeriod;

  @override
  ConsumerState<ConsensusScreen> createState() => _ConsensusScreenState();
}

class _ConsensusScreenState extends ConsumerState<ConsensusScreen> {
  String? _period;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
  }

  @override
  Widget build(BuildContext context) {
    final Lottery lottery = widget.lottery ?? ref.watch(selectedLotteryProvider);

    if (_period == null) {
      // Default to the newest period so the screen is useful without any input.
      final latest = ref.watch(latestPeriodProvider(lottery));
      return Scaffold(
        appBar: AppBar(title: const Text('共识榜')),
        body: latest.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(latestPeriodProvider(lottery)),
          ),
          data: (period) {
            if (period == null) return const EmptyState(message: '暂无开奖期号');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _period = period);
            });
            return const SkeletonList();
          },
        ),
      );
    }

    final key = (lottery: lottery, period: _period!);
    final async = ref.watch(consensusProvider(key));

    return Scaffold(
      appBar: AppBar(
        title: Text('共识榜 ${Period.compact(_period)}'),
        actions: [
          IconButton(
            tooltip: '选择期号',
            icon: const Icon(Icons.event),
            onPressed: _pickPeriod,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(consensusProvider(key)),
        child: AsyncView<({ConsensusResult result, bool isStale, String? storedAt})>(
          value: async,
          loading: const SkeletonList(itemHeight: 120),
          onRetry: () => ref.invalidate(consensusProvider(key)),
          builder: (data) {
            final result = data.result;
            if (result.groups.isEmpty && !result.hasAtomTallies) {
              return const EmptyState(
                message: '本期暂无共识数据',
                detail: '可能还没有采集到任何源预测',
              );
            }
            return ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 96),
              children: [
                if (data.isStale)
                  OfflineBanner(
                    storedAtLabel: data.storedAt,
                    onRetry: () => ref.invalidate(consensusProvider(key)),
                  ),
                if (result.draw != null) _DrawStrip(result: result),
                if (result.temaTallies.isNotEmpty)
                  _HeatSection(
                    title: '特码热度',
                    subtitle: '按得票占比排序',
                    items: result.temaTallies,
                    renderAsBall: true,
                    isDrawn: result.isDrawn,
                  ),
                if (result.texiaoTallies.isNotEmpty)
                  _HeatSection(
                    title: '特肖热度',
                    subtitle: '12 生肖得票分布',
                    items: result.texiaoTallies,
                    renderAsBall: false,
                    isDrawn: result.isDrawn,
                  ),
                if (result.groups.isNotEmpty)
                  const SectionHeader(
                    title: '按玩法分组',
                    subtitle: '领先方案置顶',
                  ),
                for (final group in result.sortedGroups)
                  _GroupCard(group: group, isDrawn: result.isDrawn),
                const _VotingFootnote(),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickPeriod() async {
    final controller = TextEditingController(text: Period.short(_period));
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('输入期号'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(helperText: '可填 248 或 2026248'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    if (!Period.looksValid(value)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('期号格式不正确')));
      return;
    }
    setState(() => _period = value);
  }
}

class _DrawStrip extends StatelessWidget {
  const _DrawStrip({required this.result});

  final ConsensusResult result;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Text('已开奖', style: context.texts.labelMedium),
              const SizedBox(width: 10),
              Expanded(
                child: DrawBallRow(
                  draw: result.draw!,
                  ballSize: 28,
                  showColorNames: false,
                ),
              ),
            ],
          ),
        ),
      );
}

/// Horizontal bar chart of single-atom votes.
class _HeatSection extends StatelessWidget {
  const _HeatSection({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.renderAsBall,
    required this.isDrawn,
  });

  final String title;
  final String subtitle;
  final List<AtomTallyItem> items;
  final bool renderAsBall;
  final bool isDrawn;

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]..sort((a, b) => b.votes.compareTo(a.votes));
    final top = sorted.take(12).toList();
    return Column(
      children: [
        SectionHeader(title: title, subtitle: subtitle),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                for (final item in top)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 42,
                          child: renderAsBall
                              ? NumberBall(
                                  number: item.value,
                                  size: 28,
                                  showColorName: false,
                                )
                              : Text(
                                  item.value,
                                  style: context.texts.titleSmall,
                                ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: item.barFraction,
                              minHeight: 14,
                              backgroundColor:
                                  context.colors.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 70,
                          child: Text(
                            '${item.votes} 票 '
                            '${item.percentage.toStringAsFixed(0)}%',
                            style: context.texts.labelSmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                        // Only meaningful once the draw is published; a null hit
                        // before that is not a miss.
                        if (isDrawn && item.hit != null) ...[
                          const SizedBox(width: 6),
                          _HitMark(hit: item.hit!),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.isDrawn});

  final ConsensusGroup group;
  final bool isDrawn;

  @override
  Widget build(BuildContext context) {
    final share = group.leaderShare;
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Expanded(
              child: Text(
                PlayTypes.labelFor(group.playType),
                style: context.texts.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${group.nSources} 源 / ${group.nVotes} 票',
              style: context.texts.labelSmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              if (group.leader != null && group.leader!.isNotEmpty) ...[
                // The leading scheme is the headline of the group.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    formatAtoms(group.leader!),
                    style: context.texts.labelLarge?.copyWith(
                      color: context.colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${group.leaderVotes} 票'
                  '${share == null ? '' : ' · ${(share * 100).toStringAsFixed(0)}%'}',
                  style: context.texts.labelSmall,
                ),
              ] else
                Text('无领先方案', style: context.texts.labelSmall),
              const Spacer(),
              if (isDrawn && group.leaderHit != null) _HitMark(hit: group.leaderHit!),
            ],
          ),
        ),
        children: [
          for (final item in group.sortedTally)
            _TallyRow(item: item, isDrawn: isDrawn, isLeader: item.votes == group.leaderVotes),
        ],
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  const _TallyRow({
    required this.item,
    required this.isDrawn,
    required this.isLeader,
  });

  final ConsensusTallyItem item;
  final bool isDrawn;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isLeader ? context.colors.primaryContainer.withValues(alpha: 0.25) : null,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatAtoms(item.preds),
                  style: context.texts.bodyLarge?.copyWith(
                    fontWeight: isLeader ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
              Text('${item.votes} 票', style: context.texts.labelMedium),
              if (isDrawn && item.hit != null) ...[
                const SizedBox(width: 8),
                _HitMark(hit: item.hit!),
              ],
            ],
          ),
          if (item.sources.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '投票源：${item.sources.join('、')}',
              style: context.texts.labelSmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hit indicator using both an icon and a word, never colour alone.
class _HitMark extends StatelessWidget {
  const _HitMark({required this.hit});

  final bool hit;

  @override
  Widget build(BuildContext context) => StatusChip(
        label: hit ? '中' : '挂',
        color: hit ? DuiliaoColors.hit : DuiliaoColors.miss,
        icon: hit ? Icons.check_circle : Icons.cancel,
        compact: true,
      );
}

/// Explains the vote-counting rule, because a naive reading of the numbers
/// overstates how much independent agreement there is.
class _VotingFootnote extends StatelessWidget {
  const _VotingFootnote();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          '计票规则：同一站族的多个源、以及文案高度近似的重复内容，只计 1 票，'
          '因此票数反映的是独立意见数量，而非记录条数。',
          style: context.texts.bodySmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      );
}
