/// Mobile workbench: a calm, priority-first operator overview.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/providers.dart';
import '../../domain/json.dart';
import '../../domain/lottery.dart';
import '../../domain/models/app_event.dart';
import '../../domain/models/collect_job.dart';
import '../../domain/models/draw.dart';
import '../../domain/play_type.dart';
import '../../ui/mobile/mobile_components.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../../ui/tokens.dart';
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

final homeProvider =
    FutureProvider.family<
      ({HomeSnapshot snapshot, bool isStale, String? storedAt}),
      ({Lottery lottery, String playType})
    >((ref, key) async {
      final fetched = await ref
          .read(collectorRepositoryProvider)
          .home(lottery: key.lottery.code, playType: key.playType);
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
    final session =
        ref.watch(sessionStatusProvider).value ?? SessionStatus.disconnected;

    return Scaffold(
      // The shell owns the Aurora canvas; keeping this layer transparent lets
      // the glow and grid show through the workbench cards like dashboard.html.
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        notificationPredicate: (notification) => notification.depth <= 1,
        onRefresh: () async {
          await ref
              .read(collectorRepositoryProvider)
              .home(
                lottery: lottery.code,
                playType: playType,
                forceRefresh: true,
              );
          ref.invalidate(homeProvider(key));
        },
        child: async.when(
          loading: () => const _HomeLoadingState(),
          error: (error, _) => _RefreshableHomeState(
            child: ErrorState(
              error: error,
              onRetry: () => ref.invalidate(homeProvider(key)),
            ),
          ),
          data: (data) => _WorkbenchContent(
            data: data,
            lottery: lottery,
            userInitial: user?.initial ?? '?',
            unread: unread,
            session: session,
            onRetry: () => ref.invalidate(homeProvider(key)),
            onLotteryChanged: (next) =>
                ref.read(selectedLotteryProvider.notifier).set(next),
          ),
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
        ),
      ),
    );
  }
}

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  @override
  Widget build(BuildContext context) {
    final color = context.colors.surfaceContainerHighest;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(DuiliaoTokens.space4),
      children: [
        for (final height in [92.0, 64.0, 156.0, 120.0, 120.0])
          Container(
            height: height,
            margin: const EdgeInsets.only(bottom: DuiliaoTokens.space3),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(DuiliaoTokens.radiusLarge),
            ),
          ),
      ],
    );
  }
}

class _RefreshableHomeState extends StatelessWidget {
  const _RefreshableHomeState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _WorkbenchContent extends StatelessWidget {
  const _WorkbenchContent({
    required this.data,
    required this.lottery,
    required this.userInitial,
    required this.unread,
    required this.session,
    required this.onRetry,
    required this.onLotteryChanged,
  });

  final ({HomeSnapshot snapshot, bool isStale, String? storedAt}) data;
  final Lottery lottery;
  final String userInitial;
  final int unread;
  final SessionStatus session;
  final VoidCallback onRetry;
  final ValueChanged<Lottery> onLotteryChanged;

  @override
  Widget build(BuildContext context) {
    final home = data.snapshot;
    final wide =
        MediaQuery.sizeOf(context).width >= DuiliaoTokens.tabletBreakpoint;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: DuiliaoPage(
            child: _WorkbenchHeader(
              userInitial: userInitial,
              unread: unread,
              session: session,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: DuiliaoPage(
            child: _LotteryStrip(
              selected: lottery,
              onChanged: onLotteryChanged,
            ),
          ),
        ),
        if (data.isStale)
          SliverToBoxAdapter(
            child: DuiliaoPage(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DuiliaoTokens.space4,
                  vertical: DuiliaoTokens.space2,
                ),
                child: OfflineBanner(
                  storedAtLabel: data.storedAt,
                  onRetry: onRetry,
                ),
              ),
            ),
          ),
        if (!home.hasAnyData)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: MobileEmptyState(
              title: '暂无工作台数据',
              detail: '开奖、采集或评级数据出现后，会在这里聚合展示。',
            ),
          )
        else ...[
          if (home.latestDraw != null)
            SliverToBoxAdapter(
              child: DuiliaoPage(
                child: _LatestDrawCard(draw: home.latestDraw!),
              ),
            ),
          SliverToBoxAdapter(
            child: DuiliaoPage(
              child: _PrioritySection(home: home, wide: wide),
            ),
          ),
          SliverToBoxAdapter(
            child: DuiliaoPage(
              child: _InsightSection(home: home, wide: wide),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _WorkbenchHeader extends StatelessWidget {
  const _WorkbenchHeader({
    required this.userInitial,
    required this.unread,
    required this.session,
  });

  final String userInitial;
  final int unread;
  final SessionStatus session;

  @override
  Widget build(BuildContext context) {
    final (status, color, icon) = switch (session) {
      SessionStatus.connected => (
        '链路正常',
        DuiliaoColors.hit,
        Icons.check_circle_outline,
      ),
      SessionStatus.connecting => ('连接中', DuiliaoColors.warning, Icons.sync),
      SessionStatus.disconnected => (
        '链路断开',
        DuiliaoColors.offline,
        Icons.cloud_off_outlined,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DuiliaoTokens.space4,
        DuiliaoTokens.space4,
        DuiliaoTokens.space4,
        DuiliaoTokens.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('对料工作台', style: context.texts.headlineSmall),
                const SizedBox(height: 4),
                Text('今天先看关键变化，再处理需要动作的事项。', style: context.texts.bodySmall),
                const SizedBox(height: 8),
                Semantics(
                  label: '连接状态：$status',
                  child: MobileStatusChip(
                    label: status,
                    color: color,
                    icon: icon,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '消息中心${unread > 0 ? '，$unread 条未读' : ''}',
            onPressed: () => _push(context, const MessagesScreen()),
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 4),
          Semantics(
            button: true,
            label: '个人中心',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _push(context, const ProfileScreen()),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: context.colors.primaryContainer,
                child: Text(
                  userInitial,
                  style: TextStyle(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LotteryStrip extends StatelessWidget {
  const _LotteryStrip({required this.selected, required this.onChanged});

  final Lottery selected;
  final ValueChanged<Lottery> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: DuiliaoTokens.space4,
          vertical: 8,
        ),
        scrollDirection: Axis.horizontal,
        itemCount: Lottery.all.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = Lottery.all[index];
          final active = item == selected;
          return Semantics(
            button: true,
            selected: active,
            label: '${item.label}${active ? '，当前彩种' : ''}',
            child: ChoiceChip(
              selected: active,
              label: Text(item.label),
              onSelected: (_) => onChanged(item),
              avatar: Icon(
                active
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LatestDrawCard extends StatelessWidget {
  const _LatestDrawCard({required this.draw});

  final DrawRow draw;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DuiliaoTokens.space4,
        DuiliaoTokens.space3,
        DuiliaoTokens.space4,
        DuiliaoTokens.space2,
      ),
      child: MobileSurface(
        color: context.colors.primaryContainer,
        padding: const EdgeInsets.all(DuiliaoTokens.space6),
        onTap: () => _push(
          context,
          DrawDetailScreen(
            lottery: Lottery.parse(draw.lottery),
            period: draw.period,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '最新开奖 · ${draw.drawDate ?? '刚刚更新'}',
                    style: context.texts.labelSmall?.copyWith(
                      color: context.colors.primary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            const SizedBox(height: DuiliaoTokens.space2),
            Text(
              Period.compact(draw.period),
              style: context.texts.headlineSmall,
            ),
            const SizedBox(height: DuiliaoTokens.space4),
            DrawBallRow(draw: draw, ballSize: 30, showColorNames: false),
            if (draw.summary != null) ...[
              const SizedBox(height: DuiliaoTokens.space3),
              Text(
                '和值 ${draw.summary!.sum7} · ${draw.summary!.sum7Size}${draw.summary!.sum7Odd} · 特${draw.summary!.temaXiao}',
                style: context.texts.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrioritySection extends StatelessWidget {
  const _PrioritySection({required this.home, required this.wide});

  final HomeSnapshot home;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final summary = home.comparisonSummary;
    final alerts = <String>[
      if (summary != null && summary.conflicts > 0)
        '${summary.conflicts} 条预测与判定存在冲突',
      if (home.worker?.running == true) '采集任务正在运行',
      if (home.recentJobs.any((job) => job.status == JobStatus.failed))
        '最近采集有失败数据源',
    ];

    return MobileSection(
      title: '优先处理',
      subtitle: alerts.isEmpty ? '当前没有需要立即介入的异常' : '建议先处理这些变化',
      action: TextButton.icon(
        onPressed: () => _push(context, const ComparisonScreen()),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('查看对照'),
      ),
      child: Column(
        children: [
          if (alerts.isNotEmpty)
            MobileSurface(
              color: context.colors.errorContainer,
              margin: const EdgeInsets.only(bottom: DuiliaoTokens.space3),
              padding: const EdgeInsets.all(DuiliaoTokens.space4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: context.colors.onErrorContainer,
                  ),
                  const SizedBox(width: DuiliaoTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '需要关注',
                          style: context.texts.titleSmall?.copyWith(
                            color: context.colors.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final alert in alerts)
                          Text(
                            '· $alert',
                            style: context.texts.bodySmall?.copyWith(
                              color: context.colors.onErrorContainer,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (summary != null)
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = wide && constraints.maxWidth >= 640 ? 4 : 2;
                return GridView.builder(
                  itemCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: DuiliaoTokens.space2,
                    crossAxisSpacing: DuiliaoTokens.space2,
                    mainAxisExtent: wide ? 132 : 128,
                  ),
                  itemBuilder: (context, index) => [
                    MobileStatCard(
                      label: '总数',
                      value: '${summary.total}',
                      icon: Icons.list_alt_outlined,
                    ),
                    MobileStatCard(
                      label: '命中',
                      value: '${summary.hits}',
                      color: DuiliaoColors.hit,
                      icon: Icons.check_circle_outline,
                    ),
                    MobileStatCard(
                      label: '未中',
                      value: '${summary.misses}',
                      color: DuiliaoColors.miss,
                      icon: Icons.cancel_outlined,
                    ),
                    MobileStatCard(
                      label: '命中率',
                      value: summary.judged == 0
                          ? '—'
                          : '${(summary.hitRate * 100).toStringAsFixed(1)}%',
                      caption: '已判 ${summary.judged} 组',
                      icon: Icons.percent,
                    ),
                  ][index],
                );
              },
            ),
          if (home.recentJobs.isNotEmpty) ...[
            const SizedBox(height: DuiliaoTokens.space3),
            MobileSurface(
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.sync_alt_rounded,
                        size: 18,
                        color: context.colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text('最近采集', style: context.texts.titleSmall),
                      const Spacer(),
                      Text(
                        '${home.recentJobs.length} 条',
                        style: context.texts.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: DuiliaoTokens.space2),
                  for (final job in home.recentJobs.take(3)) _JobRow(job: job),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});

  final CollectJob job;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (job.status) {
      JobStatus.done => (DuiliaoColors.hit, Icons.check_circle_outline),
      JobStatus.failed => (DuiliaoColors.miss, Icons.error_outline),
      JobStatus.running => (DuiliaoColors.warning, Icons.sync),
      _ => (DuiliaoColors.pending, Icons.schedule),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text('任务 #${job.id}', style: context.texts.bodyMedium),
          ),
          MobileStatusChip(label: job.status.label, color: color),
        ],
      ),
    );
  }
}

class _InsightSection extends StatelessWidget {
  const _InsightSection({required this.home, required this.wide});

  final HomeSnapshot home;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return MobileSection(
      title: '快速洞察',
      subtitle: '从共识、评级和规则中快速进入下一步',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = wide && constraints.maxWidth >= 640 ? 2 : 1;
          final cards = <Widget>[
            if (home.consensusGroups.isNotEmpty) _ConsensusCard(home: home),
            if (home.ratingsTop.isNotEmpty) _RatingsCard(home: home),
            _ActionCard(
              icon: Icons.auto_awesome,
              title: 'AI 研判',
              detail: '阅读缓存报告或生成新的运营研判',
              onTap: () =>
                  _push(context, AiScreen(initialPeriod: home.consensusPeriod)),
            ),
            _ActionCard(
              icon: Icons.grid_view_rounded,
              title: '号码百科',
              detail: '查询号码属性与玩法规则',
              onTap: () => _push(context, const NumbersScreen()),
            ),
          ];
          return GridView.builder(
            itemCount: cards.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: DuiliaoTokens.space2,
              crossAxisSpacing: DuiliaoTokens.space2,
              mainAxisExtent: wide ? 156 : 168,
            ),
            itemBuilder: (context, index) => cards[index],
          );
        },
      ),
    );
  }
}

class _ConsensusCard extends StatelessWidget {
  const _ConsensusCard({required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context) {
    return MobileSurface(
      onTap: () => _push(
        context,
        ConsensusScreen(
          lottery: Lottery.parse(home.lottery),
          initialPeriod: home.consensusPeriod,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart_outline,
                size: 18,
                color: context.colors.primary,
              ),
              const SizedBox(width: 8),
              Text('共识领先', style: context.texts.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            home.consensusGroups
                .take(2)
                .map(
                  (group) =>
                      '${PlayTypes.labelFor(group.playType)} ${group.leaderVotes}/${group.nVotes}',
                )
                .join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall,
          ),
        ],
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
    final top = home.ratingsTop.first;
    return MobileSurface(
      onTap: () => _push(context, const RatingsScreen()),
      child: Row(
        children: [
          Expanded(
            child: MobileStatCard(
              label: '评级 Top 1',
              value: formatRate(top.hitRate(window)),
              caption: top.sourceName.length > 16
                  ? '${top.sourceName.substring(0, 16)}…'
                  : top.sourceName,
              color: context.colors.primary,
              icon: Icons.insights_outlined,
            ),
          ),
          const SizedBox(width: DuiliaoTokens.space3),
          Expanded(
            child: Text(
              '查看 ${home.ratingsTop.length} 个数据源的近期稳定性与完整性。',
              style: context.texts.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title：$detail',
      child: MobileSurface(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: context.colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: context.colors.primary),
            ),
            const SizedBox(width: DuiliaoTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: context.texts.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}
