/// Mobile workbench aligned 1:1 with dashboard.html.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/app_event.dart';
import '../../domain/models/draw.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import '../auth/auth_providers.dart';
import '../design/design_screens.dart';
import '../draws/draw_detail_screen.dart';
import '../draws/draws_screen.dart';
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

const DrawRow _fallbackLatestDraw = DrawRow(
  lottery: 'macau',
  period: '2026276',
  drawDate: '09-26 21:32',
  balls: ['03', '11', '19', '27', '34', '42'],
  tema: '26',
  summary: DrawSummary(
    temaXiao: '蛇',
    temaBose: '蓝波',
    temaOdd: '双',
    temaSize: '小',
    temaJiaye: '野兽',
  ),
);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lottery = ref.watch(selectedLotteryProvider);
    final playType = ref.watch(selectedPlayTypeProvider);
    final key = (lottery: lottery, playType: playType);
    final async = ref.watch(homeProvider(key));
    final user = ref.watch(authStateProvider).user;
    final session =
        ref.watch(sessionStatusProvider).value ??
        ref.read(apiClientProvider).status;

    final snapshot = async.value?.snapshot;
    final draw = snapshot?.latestDraw ?? _fallbackLatestDraw;
    final temaInt = int.tryParse(draw.tema) ?? 26;
    final temaXiao =
        draw.summary?.temaXiao ?? Lottery2026Lookup.xiaoForNumber(temaInt);
    final temaBoseLabel = switch (Lottery2026Lookup.boseForNumber(temaInt)) {
      'red' => '红波',
      'green' => '绿波',
      _ => '蓝波',
    };
    final temaOdd = draw.summary?.temaOdd ?? (temaInt.isOdd ? '单' : '双');
    final temaSize = draw.summary?.temaSize ?? (temaInt >= 25 ? '大' : '小');
    final temaJiaye =
        draw.summary?.temaJiaye ??
        (Lottery2026Lookup.jiaXiao.contains(temaXiao) ? '家禽' : '野兽');

    final isConnected =
        session == SessionStatus.connected ||
        (snapshot != null && !(async.value?.isStale ?? false));
    final statusLabel = isConnected
        ? '链路正常 · 实时'
        : (async.isLoading ? '正在连接 · 同步中' : '离线缓存 · 待重连');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              try {
                await ref
                    .read(collectorRepositoryProvider)
                    .home(
                      lottery: lottery.code,
                      playType: playType,
                      forceRefresh: true,
                    );
              } catch (_) {}
              ref.invalidate(homeProvider(key));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                // Top App Header matching dashboard.html
                DesignAppHeader(
                  leadingSubtitle: '下午好,${user?.displayName ?? '收藏家'}',
                  title: '工作台',
                  actions: [
                    GlassStatusPill(
                      label: statusLabel,
                      color: isConnected
                          ? DuiliaoColors.hit
                          : DuiliaoColors.warning,
                      pulse: true,
                    ),
                    GlassIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: '刷新数据',
                      onTap: () => ref.invalidate(homeProvider(key)),
                    ),
                    GestureDetector(
                      onTap: () => _push(context, const ProfileScreen()),
                      child: BrandLogoBox(
                        label: user?.initial ?? '料',
                        size: 38,
                        borderRadius: 19,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section 1: 最新开奖
                      DesignSectionHeader(
                        title: '最新开奖',
                        trailingText: '开奖管理 ›',
                        onTrailingTap: () =>
                            _push(context, const DrawsScreen()),
                      ),
                      GlassCard(
                        margin: EdgeInsets.zero,
                        padding: const EdgeInsets.all(16),
                        onTap: () => _push(
                          context,
                          DrawDetailScreen(
                            lottery: Lottery.parse(draw.lottery),
                            period: draw.period,
                            initialDraw: draw,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${Lottery.labelFor(draw.lottery)}六合彩',
                                        style: context.texts.labelSmall,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '第 ${draw.period} 期 · ${draw.drawDate ?? '09-26 21:32'} 开奖',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const GlassStatusPill(
                                  label: '已对奖',
                                  color: DuiliaoColors.hit,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            DrawBallRow(draw: draw),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ZTag(
                                  label: '特码 ${draw.tema} · $temaBoseLabel',
                                  variant: ZTagVariant.primary,
                                ),
                                ZTag(label: '特肖 $temaXiao'),
                                ZTag(label: '$temaOdd / $temaSize'),
                                ZTag(label: temaJiaye),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Section 2: 本期共识摘要
                      DesignSectionHeader(
                        title: '本期共识摘要',
                        trailingText: '共识排行榜 ›',
                        onTrailingTap: () =>
                            _push(context, const ConsensusBoardScreen()),
                      ),
                      GlassCard(
                        margin: EdgeInsets.zero,
                        padding: const EdgeInsets.all(16),
                        onTap: () =>
                            _push(context, const ConsensusBoardScreen()),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '澳门 · 第 ${snapshot?.consensusPeriod ?? '2026277'} 期',
                                        style: context.texts.labelSmall,
                                      ),
                                      const SizedBox(height: 3),
                                      const Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              '实时预测榜',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          GlassStatusPill(
                                            label: '待开奖',
                                            color: DuiliaoColors.warning,
                                            pulse: true,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '来源组 12',
                                  style: context.texts.labelSmall,
                                ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: GlassSubtleBox(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '领跑特码',
                                        style: context.texts.labelSmall,
                                      ),
                                      const SizedBox(height: 7),
                                      const Row(
                                        children: [
                                          NumberBall(
                                            number: '26',
                                            bose: 'blue',
                                            size: 28,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '8 票',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '支持率 66.7%',
                                        style: context.texts.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GlassSubtleBox(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '领跑特肖',
                                        style: context.texts.labelSmall,
                                      ),
                                      const SizedBox(height: 7),
                                      const Row(
                                        children: [
                                          ZTag(
                                            label: '蛇',
                                            variant: ZTagVariant.primary,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '7 票',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '支持率 58.3%',
                                        style: context.texts.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '支持率是有效来源组占比，不等于中奖概率；开奖后榜单会冻结并补写命中状态。',
                            style: context.texts.labelSmall?.copyWith(
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Section 3: 我的记录
                    DesignSectionHeader(
                      title: '我的记录',
                      trailingText: '全部记录 ›',
                      onTrailingTap: () =>
                          _push(context, const RecordsScreen()),
                    ),
                    Builder(
                      builder: (context) {
                        final allRecords = ref.watch(bettingRecordsProvider);
                        final pendingRecs = allRecords
                            .where((r) => r.status == 'pending')
                            .toList();
                        final settledRecs = allRecords
                            .where((r) => r.status != 'pending')
                            .toList();
                        final pendingStake = pendingRecs.fold<int>(
                          0,
                          (s, r) => s + r.totalAmount,
                        );
                        final pendingNotes = pendingRecs.fold<int>(
                          0,
                          (s, r) => s + r.notesCount,
                        );
                        final settledNet = settledRecs.fold<int>(
                          0,
                          (s, r) => s + r.netProfit,
                        );
                        final latestPendingPeriod = pendingRecs.isNotEmpty
                            ? pendingRecs.first.period
                            : (snapshot?.consensusPeriod ?? '2026277');
                        final previewNums = <String>[];
                        for (final r in pendingRecs.isNotEmpty
                            ? pendingRecs
                            : allRecords) {
                          for (final n in r.numbers) {
                            if (!previewNums.contains(n)) previewNums.add(n);
                          }
                        }
                        return GlassCard(
                          margin: EdgeInsets.zero,
                          padding: const EdgeInsets.all(16),
                          onTap: () => _push(context, const RecordsScreen()),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '第 $latestPendingPeriod 期 · 待开奖',
                                          style: context.texts.labelSmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Text(
                                              '¥$pendingStake',
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                '${pendingRecs.length} 单 · $pendingNotes 注',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: context.texts.labelSmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '累计盈亏(已结 ${settledRecs.length} 单)',
                                        style: context.texts.labelSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        settledNet >= 0
                                            ? '+¥$settledNet'
                                            : '−¥${settledNet.abs()}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: settledNet >= 0
                                              ? DuiliaoColors.hit
                                              : DuiliaoColors.miss,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: previewNums.isNotEmpty
                                        ? Wrap(
                                            spacing: 5,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              for (final n
                                                  in previewNums.take(5))
                                                NumberBall(
                                                  number: n,
                                                  bose: 'red',
                                                  size: 26,
                                                ),
                                              if (previewNums.length > 5)
                                                Text(
                                                  '+${previewNums.length - 5} 码',
                                                  style:
                                                      context.texts.labelSmall,
                                                ),
                                            ],
                                          )
                                        : Text(
                                            allRecords.isEmpty
                                                ? '暂无记录 · 点击进入智能识别录入'
                                                : '共 ${allRecords.length} 条记录 · 点击管理或查看对奖',
                                            style: context.texts.labelSmall,
                                          ),
                                  ),
                                  const SizedBox(width: 8),
                                  GlassStatusPill(
                                    label: pendingRecs.isNotEmpty
                                        ? '今晚 21:30 开奖'
                                        : '自动对奖',
                                    color: pendingRecs.isNotEmpty
                                        ? DuiliaoColors.warning
                                        : DuiliaoColors.hit,
                                    pulse: pendingRecs.isNotEmpty,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Section 4: 近 7 日对料趋势
                    const DesignSectionHeader(
                      title: '近 7 日对料趋势',
                      trailingText: '入库 / 命中',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const SizedBox(
                            height: 92,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _TrendBar(date: '09-20', factor: 0.46),
                                SizedBox(width: 6),
                                _TrendBar(date: '09-21', factor: 0.62),
                                SizedBox(width: 6),
                                _TrendBar(date: '09-22', factor: 0.52),
                                SizedBox(width: 6),
                                _TrendBar(date: '09-23', factor: 0.78),
                                SizedBox(width: 6),
                                _TrendBar(date: '09-24', factor: 0.68),
                                SizedBox(width: 6),
                                _TrendBar(date: '09-25', factor: 0.84),
                                SizedBox(width: 6),
                                _TrendBar(
                                  date: '09-26',
                                  factor: 0.95,
                                  hot: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '7 日入库 6,412 条',
                                style: context.texts.labelSmall,
                              ),
                              const Text(
                                '命中 38 期',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: DuiliaoColors.hit,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Section 5: 源命中率排行
                    DesignSectionHeader(
                      title: '源命中率排行',
                      trailingText: '可信评级 ›',
                      onTrailingTap: () =>
                          _push(context, const RatingsScreen()),
                    ),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: const [
                        _SourceRankRow(
                          rank: 1,
                          name: '海哥平特一肖',
                          pct: 0.62,
                          pctLabel: '62%',
                          badgeColor: DuiliaoColors.hit,
                        ),
                        _SourceRankRow(
                          rank: 2,
                          name: '顶尖大师',
                          pct: 0.55,
                          pctLabel: '55%',
                          badgeColor: DuiliaoColors.primaryDark,
                        ),
                        _SourceRankRow(
                          rank: 3,
                          name: '管家婆传真',
                          pct: 0.48,
                          pctLabel: '48%',
                          badgeColor: DuiliaoColors.warning,
                        ),
                        _SourceRankRow(
                          rank: 4,
                          name: '白小组',
                          pct: 0.41,
                          pctLabel: '41%',
                          badgeColor: DuiliaoColors.pending,
                        ),
                      ],
                    ),
                  ],
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

class _TrendBar extends StatelessWidget {
  const _TrendBar({
    required this.date,
    required this.factor,
    this.hot = false,
  });

  final String date;
  final double factor;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: factor,
                widthFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: hot
                          ? const [
                              DuiliaoColors.auroraFuchsia,
                              DuiliaoColors.auroraViolet,
                            ]
                          : [
                              DuiliaoColors.auroraViolet.withValues(
                                alpha: 0.85,
                              ),
                              DuiliaoColors.auroraIndigo.withValues(
                                alpha: 0.35,
                              ),
                            ],
                    ),
                    boxShadow: hot
                        ? [
                            BoxShadow(
                              color: DuiliaoColors.auroraFuchsia.withValues(
                                alpha: 0.45,
                              ),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            date,
            style: context.texts.labelSmall?.copyWith(fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

class _SourceRankRow extends StatelessWidget {
  const _SourceRankRow({
    required this.rank,
    required this.name,
    required this.pct,
    required this.pctLabel,
    required this.badgeColor,
  });

  final int rank;
  final String name;
  final double pct;
  final String pctLabel;
  final Color badgeColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: badgeColor.withValues(alpha: 0.16),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: badgeColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                GlassLinearProgress(
                  value: pct,
                  color: rank == 1 ? DuiliaoColors.hit : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pctLabel,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: rank == 1 ? DuiliaoColors.hit : null,
                ),
              ),
              Text(
                '近 50 期',
                style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}
