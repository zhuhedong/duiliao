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
import '../profile/profile_screen.dart';
import '../ratings/ratings_screen.dart';

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
      appBar: AppBar(
        title: const Text('Duiliao'),
        actions: [
          IconButton(
            tooltip: '消息中心',
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MessagesScreen()),
            ),
          ),
          // "My account" lives behind the avatar rather than taking a tab slot.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: '我的',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              icon: CircleAvatar(
                radius: 15,
                backgroundColor: context.colors.primaryContainer,
                child: Text(
                  user?.initial ?? '?',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (data.isStale)
                  OfflineBanner(
                    storedAtLabel: data.storedAt,
                    onRetry: () => ref.invalidate(homeProvider(key)),
                  ),
                _LotterySelector(selected: lottery),
                if (!home.hasAnyData)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: EmptyState(
                      message: '暂无数据',
                      detail: '该彩种还没有开奖或采集记录',
                    ),
                  ),
                if (home.latestDraw != null) _LatestDrawCard(home: home),
                if (home.consensusGroups.isNotEmpty) _ConsensusCard(home: home),
                if (home.comparisonSummary != null) _ComparisonCard(home: home),
                if (home.ratingsTop.isNotEmpty) _RatingsCard(home: home),
                if (home.recentJobs.isNotEmpty) _JobsCard(home: home),
                _QuickLinks(home: home),
              ],
            );
          },
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SegmentedButton<Lottery>(
          segments: [
            for (final l in Lottery.all)
              ButtonSegment(value: l, label: Text(l.label)),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              ref.read(selectedLotteryProvider.notifier).set(selection.first),
        ),
      );
}

class _LatestDrawCard extends StatelessWidget {
  const _LatestDrawCard({required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    final draw = home.latestDraw!;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DrawDetailScreen(
              lottery: Lottery.parse(draw.lottery),
              period: draw.period,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('最新开奖', style: context.texts.titleSmall),
                  const SizedBox(width: 8),
                  Text(
                    Period.compact(draw.period),
                    style: context.texts.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (draw.drawDate != null)
                    Text(draw.drawDate!, style: context.texts.labelSmall),
                ],
              ),
              const SizedBox(height: 12),
              DrawBallRow(draw: draw, ballSize: 36),
              if (draw.summary != null) ...[
                const SizedBox(height: 10),
                Text(
                  '和值 ${draw.summary!.sum7}（${draw.summary!.sum7Size}'
                  '${draw.summary!.sum7Odd}） · 特码 ${draw.summary!.temaXiao}'
                  ' · ${draw.summary!.temaHalfwave}',
                  style: context.texts.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsensusCard extends StatelessWidget {
  const _ConsensusCard({required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ConsensusScreen(
              lottery: Lottery.parse(home.lottery),
              initialPeriod: home.consensusPeriod,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('共识摘要', style: context.texts.titleSmall),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              for (final group in home.consensusGroups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(
                          PlayTypes.labelFor(group.playType),
                          style: context.texts.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          group.leader == null || group.leader!.isEmpty
                              ? '—'
                              : group.leader!.map((a) => a.value).join(' '),
                          style: context.texts.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${group.leaderVotes}/${group.nVotes} 票',
                        style: context.texts.labelSmall,
                      ),
                      if (group.leaderHit != null) ...[
                        const SizedBox(width: 6),
                        Icon(
                          group.leaderHit! ? Icons.check_circle : Icons.cancel,
                          size: 14,
                          color: group.leaderHit!
                              ? DuiliaoColors.hit
                              : DuiliaoColors.miss,
                        ),
                      ],
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

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    final summary = home.comparisonSummary!;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ComparisonScreen(
              lottery: Lottery.parse(home.lottery),
              initialPeriod: home.consensusPeriod,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('本期对照汇总', style: context.texts.titleSmall),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  StatTile(label: '总数', value: '${summary.total}'),
                  StatTile(
                    label: '命中',
                    value: '${summary.hits}',
                    valueColor: DuiliaoColors.hit,
                  ),
                  StatTile(
                    label: '未中',
                    value: '${summary.misses}',
                    valueColor: DuiliaoColors.miss,
                  ),
                  StatTile(label: '待判', value: '${summary.pending}'),
                  StatTile(
                    label: '冲突',
                    value: '${summary.conflicts}',
                    valueColor:
                        summary.conflicts > 0 ? DuiliaoColors.conflict : null,
                  ),
                ],
              ),
              if (summary.conflicts > 0) ...[
                const SizedBox(height: 10),
                WarningNote(
                  message: '有 ${summary.conflicts} 条源自称命中但判定未中',
                  icon: Icons.report_problem_outlined,
                  color: DuiliaoColors.conflict,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingsCard extends StatelessWidget {
  const _RatingsCard({required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    final window = home.ratingsWindows.isEmpty ? 30 : home.ratingsWindows.first;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RatingsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('源评级 Top 5', style: context.texts.titleSmall),
                  const SizedBox(width: 6),
                  Text(
                    '${PlayTypes.labelFor(home.playType)} · $window 期',
                    style: context.texts.labelSmall
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 8),
              for (final row in home.ratingsTop)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.sourceName,
                          style: context.texts.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Warn inline: a top-5 placement on three samples is not a
                      // recommendation.
                      if (row.hasIntegrityWarning)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.report_problem_outlined,
                            size: 14,
                            color: DuiliaoColors.conflict,
                          ),
                        )
                      else if (row.isSmallSample(window))
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: DuiliaoColors.warning,
                          ),
                        ),
                      Text(
                        formatRate(row.hitRate(window)),
                        style: context.texts.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 44,
                        child: Text(
                          'n=${row.sampleSize(window) ?? 0}',
                          style: context.texts.labelSmall,
                          textAlign: TextAlign.right,
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
}

class _JobsCard extends StatelessWidget {
  const _JobsCard({required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('近期采集', style: context.texts.titleSmall),
                const Spacer(),
                if (home.worker != null)
                  Text(
                    home.worker!.running ? '执行器运行中' : '执行器未运行',
                    style: context.texts.labelSmall?.copyWith(
                      color: home.worker!.running
                          ? DuiliaoColors.hit
                          : DuiliaoColors.pending,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final job in home.recentJobs)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      switch (job.status) {
                        JobStatus.done => Icons.check_circle,
                        JobStatus.failed => Icons.error,
                        JobStatus.cancelled => Icons.cancel,
                        JobStatus.interrupted => Icons.power_off,
                        _ => Icons.autorenew,
                      },
                      size: 14,
                      color: switch (job.status) {
                        JobStatus.done => DuiliaoColors.hit,
                        JobStatus.failed => DuiliaoColors.miss,
                        JobStatus.interrupted => DuiliaoColors.conflict,
                        _ => DuiliaoColors.warning,
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '#${job.id} ${job.period == null ? '自动期号' : Period.compact(job.period)}'
                        ' · ${job.successRatioLabel}',
                        style: context.texts.bodySmall,
                      ),
                    ),
                    Text(job.status.label, style: context.texts.labelSmall),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickLinks extends ConsumerWidget {
  const _QuickLinks({required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('AI 研判'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AiScreen(initialPeriod: home.consensusPeriod),
              ),
            ),
          ),
          if (home.ruleVersion != null)
            Chip(
              avatar: const Icon(Icons.rule, size: 16),
              label: Text('规则 ${home.ruleVersion}'),
            ),
        ],
      ),
    );
  }
}
