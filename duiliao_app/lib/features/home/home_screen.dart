/// Home: everything an operator wants at a glance, in one request.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/json.dart';
import '../../domain/lottery.dart';
import '../../domain/models/app_event.dart';
import '../../domain/models/collect_job.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../../ui/widgets/number_ball.dart';
import '../ai/ai_screen.dart';
import '../auth/auth_providers.dart';
import '../comparison/comparison_screen.dart';
import '../consensus/consensus_screen.dart';
import '../draws/draw_detail_screen.dart';
import '../notifications/messages_screen.dart';
import '../notifications/notification_service.dart';
import '../numbers/numbers_screen.dart';
import '../profile/profile_screen.dart';
import '../ratings/ratings_screen.dart';
import '../rules/rules_screen.dart';

/// The aggregated home payload. One request rather than five, because five
/// sequential encrypted round-trips is a visible delay on a mobile link.
final homeProvider = FutureProvider.family<
    ({HomeSnapshot snapshot, bool isStale, String? storedAt}),
    ({Lottery lottery, String playType})>((ref, key) async {
  final fetched = await ref.read(collectorRepositoryProvider).home(
        lottery: key.lottery.code,
        playType: key.playType,
      );
  return (
    snapshot: fetched.value,
    isStale: fetched.isStale,
    storedAt: fetched.storedAtLabel,
  );
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lottery = ref.watch(selectedLotteryProvider);
    final playType = ref.watch(selectedPlayTypeProvider);
    final key = (lottery: lottery, playType: playType);
    final async = ref.watch(homeProvider(key));
    final user = ref.watch(authStateProvider).user;
    final unread = ref.watch(messageCentreProvider).unreadCount;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          await ref
              .read(collectorRepositoryProvider)
              .home(lottery: lottery.code, playType: playType, forceRefresh: true);
          ref.invalidate(homeProvider(key));
        },
        child: AsyncView<({HomeSnapshot snapshot, bool isStale, String? storedAt})>(
          value: async,
          loading: const SkeletonList(itemHeight: 110),
          onRetry: () => ref.invalidate(homeProvider(key)),
          builder: (data) {
            final home = data.snapshot;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: _DynamicIslandHeader(unread: unread, initial: user?.initial ?? '?'),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _LotterySelector(selected: lottery),
                ),
                if (data.isStale)
                  SliverToBoxAdapter(
                    child: OfflineBanner(
                      storedAtLabel: data.storedAt,
                      onRetry: () => ref.invalidate(homeProvider(key)),
                    ),
                  ),
                if (!home.hasAnyData)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: EmptyState(
                        message: '暂无数据',
                        detail: '该彩种还没有开奖或采集记录',
                      ),
                    ),
                  ),
                if (home.latestDraw != null)
                  SliverToBoxAdapter(child: _HeroDrawBanner(home: home)),
                
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  if (home.comparisonSummary != null) _ComparisonBentoBox(home: home),
                                  const SizedBox(height: 10),
                                  if (home.recentJobs.isNotEmpty) _JobsBentoBox(home: home),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                children: [
                                  if (home.ratingsTop.isNotEmpty) _RatingsBentoBox(home: home),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (home.consensusGroups.isNotEmpty) _ConsensusBentoBox(home: home),
                      ],
                    ),
                  ),
                ),
                
                SliverToBoxAdapter(
                  child: _ControlCenterPanel(home: home),
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DynamicIslandHeader extends StatelessWidget {
  const _DynamicIslandHeader({required this.unread, required this.initial});
  final int unread;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: GlassContainer(
        height: 54,
        borderRadius: BorderRadius.circular(999),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Text(
              'Duiliao',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '消息中心',
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.notifications_outlined, size: 22),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MessagesScreen()),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              child: Container(
                margin: const EdgeInsets.only(right: 6, left: 4),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: DuiliaoColors.auroraGradient,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

class _LotterySelector extends ConsumerWidget {
  const _LotterySelector({required this.selected});

  final Lottery selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: GlassSegmentedControl<Lottery>(
          items: Lottery.all,
          selected: selected,
          labelBuilder: (l) => l.label,
          onChanged: (lottery) =>
              ref.read(selectedLotteryProvider.notifier).set(lottery),
        ),
      );
}

class _HeroDrawBanner extends StatelessWidget {
  const _HeroDrawBanner({required this.home});
  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    final draw = home.latestDraw!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.all(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DrawDetailScreen(
              lottery: Lottery.parse(draw.lottery),
              period: draw.period,
            ),
          ),
        ),
        // A subtle gradient fill for the hero banner
        fillColor: isDark
            ? DuiliaoColors.auroraViolet.withValues(alpha: 0.18)
            : DuiliaoColors.auroraIndigo.withValues(alpha: 0.10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GlassBadge(label: '最新开奖', color: Theme.of(context).colorScheme.primary, small: true),
                const SizedBox(width: 10),
                Text(
                  Period.compact(draw.period),
                  style: context.texts.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (draw.drawDate != null)
                  Text(
                    draw.drawDate!,
                    style: context.texts.labelSmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // We use standard DrawBallRow here but wrapped to look more spacious
            DrawBallRow(draw: draw, ballSize: 42),
            if (draw.summary != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insights, size: 14, color: context.colors.primary),
                    const SizedBox(width: 6),
                    Text(
                      '和值 ${draw.summary!.sum7}（${draw.summary!.sum7Size}${draw.summary!.sum7Odd}） · 特码 ${draw.summary!.temaXiao} · ${draw.summary!.temaHalfwave}',
                      style: context.texts.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComparisonBentoBox extends StatelessWidget {
  const _ComparisonBentoBox({required this.home});
  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    final summary = home.comparisonSummary!;
    final hasConflict = summary.conflicts > 0;
    
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ComparisonScreen(
            lottery: Lottery.parse(home.lottery),
            initialPeriod: home.consensusPeriod,
          ),
        ),
      ),
      borderColor: hasConflict ? DuiliaoColors.conflict.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.compare_arrows_rounded, size: 18),
              const SizedBox(width: 6),
              Text('对照视界', style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          // A mini grid of stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MiniStat('总数', '${summary.total}', context),
              _MiniStat('命中', '${summary.hits}', context, color: DuiliaoColors.hit),
              _MiniStat('未中', '${summary.misses}', context, color: DuiliaoColors.miss),
            ],
          ),
          const SizedBox(height: 10),
          if (hasConflict)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: DuiliaoColors.conflict.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DuiliaoColors.conflict.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 12, color: DuiliaoColors.conflict),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${summary.conflicts} 冲突预警',
                      style: const TextStyle(fontSize: 11, color: DuiliaoColors.conflict, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('数据一致无异常', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.context, {this.color});
  final String label;
  final String value;
  final BuildContext context;
  final Color? color;

  @override
  Widget build(BuildContext _) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color ?? context.colors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _RatingsBentoBox extends StatelessWidget {
  const _RatingsBentoBox({required this.home});
  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    final window = home.ratingsWindows.isEmpty ? 30 : home.ratingsWindows.first;
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RatingsScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, size: 18),
              const SizedBox(width: 6),
              Text('评级 Top 5', style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < home.ratingsTop.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: i == 0 ? Colors.amber : (i == 1 ? Colors.grey[400] : (i == 2 ? Colors.brown[300] : Colors.transparent)),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: i < 3 
                        ? Text('${i+1}', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold))
                        : Text('${i+1}', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      home.ratingsTop[i].sourceName,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatRate(home.ratingsTop[i].hitRate(window)),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ConsensusBentoBox extends StatelessWidget {
  const _ConsensusBentoBox({required this.home});
  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassContainer(
      padding: const EdgeInsets.symmetric(vertical: 14),
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConsensusScreen(
            lottery: Lottery.parse(home.lottery),
            initialPeriod: home.consensusPeriod,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(Icons.pie_chart_rounded, size: 18),
                const SizedBox(width: 6),
                Text('共识热力池', style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                for (final group in home.consensusGroups)
                  Container(
                    width: 130,
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              PlayTypes.labelFor(group.playType),
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const Spacer(),
                            if (group.leaderHit != null)
                              Icon(
                                group.leaderHit! ? Icons.check_circle : Icons.cancel,
                                size: 12,
                                color: group.leaderHit! ? DuiliaoColors.hit : DuiliaoColors.miss,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.leader == null || group.leader!.isEmpty
                                    ? '—'
                                    : group.leader!.map((a) => a.value).join(' '),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${group.leaderVotes}/${group.nVotes}',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        GlassLinearProgress(
                          value: group.nVotes > 0 ? group.leaderVotes / group.nVotes : 0,
                          height: 5,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobsBentoBox extends StatelessWidget {
  const _JobsBentoBox({required this.home});
  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_download_rounded, size: 18),
              const SizedBox(width: 6),
              Text('近期采集', style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              if (home.worker != null)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: home.worker!.running ? DuiliaoColors.hit : DuiliaoColors.pending,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final job in home.recentJobs.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    job.status == JobStatus.done ? Icons.check_circle : Icons.autorenew,
                    size: 12,
                    color: job.status == JobStatus.done ? DuiliaoColors.hit : DuiliaoColors.pending,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '#${job.id}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    job.successRatioLabel,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlCenterPanel extends StatelessWidget {
  const _ControlCenterPanel({required this.home});
  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(24),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('控制中心', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ControlButton(
                  icon: Icons.auto_awesome,
                  label: 'AI 研判',
                  color: DuiliaoColors.auroraFuchsia,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AiScreen(initialPeriod: home.consensusPeriod)),
                  ),
                ),
                _ControlButton(
                  icon: Icons.grid_view_rounded,
                  label: '号码百科',
                  color: DuiliaoColors.auroraIndigo,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NumbersScreen()),
                  ),
                ),
                _ControlButton(
                  icon: Icons.rule_rounded,
                  label: '玩法规则',
                  color: DuiliaoColors.auroraSky,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RulesScreen()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
