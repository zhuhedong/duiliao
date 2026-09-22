/// Consensus board: what the sources collectively predict for a period.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/consensus.dart';
import '../../domain/models/prediction.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../../ui/widgets/number_ball.dart';
import '../comparison/comparison_screen.dart';

final consensusProvider = FutureProvider.family<
    ({ConsensusResult result, bool isStale, String? storedAt}),
    ({Lottery lottery, String period, String playType})>((ref, key) async {
  final fetched = await ref
      .read(collectorRepositoryProvider)
      .consensus(
          lottery: key.lottery.code,
          period: key.period,
          playType: key.playType,
        );
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
        backgroundColor: Colors.transparent,
        body: GlassBackground(
          child: latest.when(
            loading: () => const SkeletonList(),
            error: (e, _) => ErrorState(
              error: e,
              onRetry: () => ref.invalidate(latestPeriodProvider(lottery)),
            ),
            data: (period) {
              if (period == null) return const Center(child: EmptyState(message: '暂无开奖期号'));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _period = period);
              });
              return const SkeletonList();
            },
          ),
        ),
      );
    }

    final playType = ref.watch(selectedPlayTypeProvider);
    final key = (lottery: lottery, period: _period!, playType: playType);
    final async = ref.watch(consensusProvider(key));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(consensusProvider(key));
            await ref.read(consensusProvider(key).future);
          },
          child: AsyncView<({ConsensusResult result, bool isStale, String? storedAt})>(
            value: async,
            loading: const SkeletonList(itemHeight: 120),
            onRetry: () => ref.invalidate(consensusProvider(key)),
            builder: (data) {
              final result = data.result;
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
                              Expanded(
                                child: Text(
                                  '共识热力榜 ${Period.compact(_period)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '选择期号',
                                icon: const Icon(Icons.event, size: 20),
                                onPressed: _pickPeriod,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (data.isStale)
                    SliverToBoxAdapter(
                      child: OfflineBanner(
                        storedAtLabel: data.storedAt,
                        onRetry: () => ref.invalidate(consensusProvider(key)),
                      ),
                    ),
                    
                  if (result.groups.isEmpty && !result.hasAtomTallies)
                    const SliverFillRemaining(
                      child: EmptyState(
                        message: '本期暂无共识数据',
                        detail: '可能还没有采集到任何源预测',
                      ),
                    )
                  else ...[
                    if (result.draw != null) 
                      SliverToBoxAdapter(child: _DrawStrip(result: result)),
                    
                    if (result.temaTallies.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _HeatPoolSection(
                          title: '特码热度池',
                          items: result.temaTallies,
                          renderAsBall: true,
                          isDrawn: result.isDrawn,
                        ),
                      ),
                      
                    if (result.texiaoTallies.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _HeatPoolSection(
                          title: '特肖热力环',
                          items: result.texiaoTallies,
                          renderAsBall: false,
                          isDrawn: result.isDrawn,
                        ),
                      ),
                      
                    if (result.groups.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                          child: Text('玩法流体分组', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _GroupFluidCard(group: result.sortedGroups[index], isDrawn: result.isDrawn),
                            ),
                            childCount: result.sortedGroups.length,
                          ),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: _VotingFootnote()),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
                  ],
                ],
              );
            },
          ),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本期已开奖', style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DrawBallRow(
                draw: result.draw!,
                ballSize: 34,
                showColorNames: false,
              ),
            ],
          ),
        ),
      );
}

/// A "Heat Pool" displaying items as a horizontal scrolling list of glowing pods instead of boring vertical bars.
class _HeatPoolSection extends StatelessWidget {
  const _HeatPoolSection({
    required this.title,
    required this.items,
    required this.renderAsBall,
    required this.isDrawn,
  });

  final String title;
  final List<AtomTallyItem> items;
  final bool renderAsBall;
  final bool isDrawn;

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]..sort((a, b) => b.votes.compareTo(a.votes));
    final top = sorted.take(12).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: top.length,
            itemBuilder: (context, index) {
              final item = top[index];
              return _HeatPod(
                item: item,
                renderAsBall: renderAsBall,
                isDrawn: isDrawn,
                isTop: index == 0,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeatPod extends StatelessWidget {
  const _HeatPod({required this.item, required this.renderAsBall, required this.isDrawn, required this.isTop});
  final AtomTallyItem item;
  final bool renderAsBall;
  final bool isDrawn;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 10),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(24),
        fillColor: isTop ? primary.withValues(alpha: 0.15) : null,
        borderColor: isTop ? primary.withValues(alpha: 0.4) : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background neon aura for the top item
            if (isTop)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: primary.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 10),
                  ],
                ),
              ),
            
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (renderAsBall)
                  NumberBall(number: item.value, size: 36, showColorName: false)
                else
                  Text(
                    item.value,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: isTop ? primary : null),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${item.percentage.toStringAsFixed(0)}% 热度',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87),
                ),
                Text(
                  '${item.votes} 票',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                if (isDrawn && item.hit != null) ...[
                  const SizedBox(height: 4),
                  _HitMark(hit: item.hit!),
                ]
              ],
            ),
            
            // Energy ring (Circular progress) around the edge
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: CustomPaint(
                  painter: _EnergyRingPainter(
                    fraction: item.barFraction,
                    color: isTop ? primary : Colors.grey.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnergyRingPainter extends CustomPainter {
  _EnergyRingPainter({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Path extraction for partial drawing is complex without PathMetrics, so we just draw an arc if it's circular
    // Since it's a rounded rect, we'll draw a simplified representation: a line at the bottom
    
    final p = Path();
    p.moveTo(20, size.height);
    p.lineTo(20 + (size.width - 40) * fraction, size.height);
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _GroupFluidCard extends StatelessWidget {
  const _GroupFluidCard({required this.group, required this.isDrawn});

  final ConsensusGroup group;
  final bool isDrawn;

  @override
  Widget build(BuildContext context) {
    final share = group.leaderShare;
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      borderRadius: BorderRadius.circular(24),
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: primary,
          collapsedIconColor: isDark ? Colors.white54 : Colors.black54,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  PlayTypes.labelFor(group.playType),
                  style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${group.nSources}源',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                if (group.leader != null && group.leader!.isNotEmpty) ...[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatAtoms(group.leader!),
                            style: TextStyle(
                              fontSize: 14,
                              color: primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.how_to_vote, size: 10, color: primary),
                              const SizedBox(width: 4),
                              Text(
                                '${group.leaderVotes} 票${share == null ? '' : ' · ${(share * 100).toStringAsFixed(0)}% 热度'}',
                                style: TextStyle(fontSize: 10, color: primary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  const Expanded(child: Text('无领先方案', style: TextStyle(fontSize: 12, color: Colors.grey))),
                if (isDrawn && group.leaderHit != null) ...[
                  const SizedBox(width: 12),
                  _HitMark(hit: group.leaderHit!),
                ],
              ],
            ),
          ),
          children: [
            const SizedBox(height: 10),
            for (final item in group.sortedTally)
              _TallyFluidRow(item: item, isDrawn: isDrawn, isLeader: item.votes == group.leaderVotes),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _TallyFluidRow extends StatelessWidget {
  const _TallyFluidRow({
    required this.item,
    required this.isDrawn,
    required this.isLeader,
  });

  final ConsensusTallyItem item;
  final bool isDrawn;
  final bool isLeader;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLeader 
            ? primary.withValues(alpha: 0.08) 
            : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatAtoms(item.preds),
                  style: context.texts.bodyMedium?.copyWith(
                    fontWeight: isLeader ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${item.votes} 票',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              if (isDrawn && item.hit != null) ...[
                const SizedBox(width: 8),
                _HitMark(hit: item.hit!),
              ],
            ],
          ),
          if (item.sources.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.sources.join('、'),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hit indicator using both an icon and a word with crystal badge.
class _HitMark extends StatelessWidget {
  const _HitMark({required this.hit});

  final bool hit;

  @override
  Widget build(BuildContext context) => GlassBadge(
        label: hit ? '中' : '挂',
        color: hit ? DuiliaoColors.hit : DuiliaoColors.miss,
        icon: hit ? Icons.check_circle : Icons.cancel,
        small: true,
      );
}

/// Explains the vote-counting rule.
class _VotingFootnote extends StatelessWidget {
  const _VotingFootnote();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '计票规则：同一站族的多个源、以及文案高度近似的重复内容，只计 1 票，因此票数反映的是独立意见数量，而非记录条数。',
            style: context.texts.bodySmall?.copyWith(color: Colors.grey, fontSize: 10),
          ),
        ),
      );
}
