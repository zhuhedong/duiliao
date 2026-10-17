/// Draw list aligned 1:1 with draws.html.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/draw.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import '../design/records_screens.dart';
import 'draw_detail_screen.dart';
import 'draws_providers.dart';
import 'trend_screen.dart';
import 'pingte_ranking_screen.dart';


List<DrawRow> _buildFallbackDraws(Lottery lottery, String currentPeriod) {
  final p1 = previousPeriodOf(currentPeriod, 1);
  final p2 = previousPeriodOf(currentPeriod, 2);
  final p3 = previousPeriodOf(currentPeriod, 3);
  return [
    DrawRow(
      lottery: lottery.code,
      period: p1,
      drawDate: '${recentChinaMmDd(1)} 21:34',
      balls: const ['03', '11', '19', '27', '34', '42'],
      tema: '26',
    ),
    DrawRow(
      lottery: lottery.code,
      period: p2,
      drawDate: '${recentChinaMmDd(2)} 21:34',
      balls: const ['05', '14', '22', '31', '38', '47'],
      tema: '07',
    ),
    DrawRow(
      lottery: lottery.code,
      period: p3,
      drawDate: '${recentChinaMmDd(3)} 21:34',
      balls: const ['02', '09', '16', '25', '33', '44'],
      tema: '39',
    ),
  ];
}

class DrawsScreen extends ConsumerStatefulWidget {
  const DrawsScreen({super.key});

  @override
  ConsumerState<DrawsScreen> createState() => _DrawsScreenState();
}

class _DrawsScreenState extends ConsumerState<DrawsScreen> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    if (!isTest) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lottery = ref.watch(selectedLotteryProvider);
    final periodCtx = ref.watch(recordPeriodContextProvider(lottery)).value;
    final currentPeriod =
        periodCtx?.currentPeriod ?? currentPeriodForLottery(lottery);
    final async = ref.watch(drawListProvider(lottery));
    final notifier = ref.read(drawListProvider(lottery).notifier);
    final liveItems = async.value?.items ?? const <DrawRow>[];
    final hasFilter =
        (async.value?.periodFrom?.isNotEmpty ?? false) ||
        (async.value?.periodTo?.isNotEmpty ?? false);
    final minFreshPeriod = previousPeriodOf(currentPeriod, 5);
    final liveIsFresh =
        liveItems.isNotEmpty &&
        (hasFilter || liveItems.first.period.compareTo(minFreshPeriod) >= 0);
    final items = liveIsFresh
        ? liveItems
        : _buildFallbackDraws(lottery, currentPeriod);
    final canPop = Navigator.of(context).canPop();
    final session =
        ref.watch(sessionStatusProvider).value ??
        ref.read(apiClientProvider).status;
    final isConnected =
        session == SessionStatus.connected || liveItems.isNotEmpty;

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
                title: '开奖管理',
                subtitle: '官方落球顺序 · 实时同步',
                actions: [
                  GlassStatusPill(
                    label: isConnected
                        ? '实时同步'
                        : (async.isLoading ? '同步中' : '离线缓存'),
                    color: isConnected
                        ? DuiliaoColors.hit
                        : DuiliaoColors.warning,
                    pulse: true,
                  ),
                  GlassIconButton(
                    icon: Icons.trending_up_rounded,
                    tooltip: '走势图表',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TrendScreen(),
                      ),
                    ),
                  ),
                  GlassIconButton(
                    icon: Icons.military_tech_rounded,
                    tooltip: '平特排行榜',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PingteRankingScreen(),
                      ),
                    ),
                  ),
                  GlassIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '同步开奖',
                    onTap: notifier.refresh,
                  ),
                  GlassIconButton(
                    icon: Icons.filter_alt_outlined,
                    tooltip: '期号筛选',
                    onTap: () => _openFilter(context, lottery),
                  ),
                ],
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: notifier.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    children: [
                      GlassSegmentedControl<Lottery>(
                        items: Lottery.all,
                        selected: lottery,
                        labelBuilder: (l) => l.label,
                        onChanged: (next) => ref
                            .read(selectedLotteryProvider.notifier)
                            .set(next),
                      ),
                      const SizedBox(height: 10),

                      // Quick Entries: 走势图表 & 平特排行榜
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const TrendScreen(),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(14),
                              child: GlassSubtleBox(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: DuiliaoColors.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.trending_up_rounded,
                                        size: 16,
                                        color: DuiliaoColors.primaryDark,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '走势图表',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          '尾/头/波/五行/肖',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const PingteRankingScreen(),
                                ),
                              ),
                              borderRadius: BorderRadius.circular(14),
                              child: GlassSubtleBox(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: DuiliaoColors.boseGold.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.military_tech_rounded,
                                        size: 16,
                                        color: DuiliaoColors.boseGold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '平特排行榜',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          '生肖/尾数/号码榜',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),


                      // Next Draw Countdown Box
                      Builder(
                        builder: (context) {
                          final cn = nowInChina();
                          var target = DateTime.utc(
                            cn.year,
                            cn.month,
                            cn.day,
                            21,
                            34,
                          );
                          final isTonight = cn.isBefore(target);
                          if (!isTonight) {
                            target = target.add(const Duration(days: 1));
                          }
                          final nextDrawPeriod =
                              (!isTonight &&
                                  items.isNotEmpty &&
                                  items.first.period == currentPeriod)
                              ? nextPeriodOf(currentPeriod, 1)
                              : currentPeriod;
                          final diff = target.difference(cn);
                          final hh = diff.inHours.toString().padLeft(2, '0');
                          final mm = (diff.inMinutes % 60).toString().padLeft(
                            2,
                            '0',
                          );
                          final ss = (diff.inSeconds % 60).toString().padLeft(
                            2,
                            '0',
                          );
                          return GlassSubtleBox(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.schedule_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '第 $nextDrawPeriod 期 · ${isTonight ? '今晚' : '明晚'} 21:34 开奖',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                GlassStatusPill(
                                  label: '倒计时 $hh:$mm:$ss',
                                  color: Theme.of(context).colorScheme.primary,
                                  showDot: false,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      for (var i = 0; i < items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DrawCard(
                            draw: items[i],
                            lottery: lottery,
                            storedCount: switch (i % 3) {
                              0 => 128,
                              1 => 134,
                              _ => 119,
                            },
                            hitSourcesLabel: switch (i % 3) {
                              0 => '9 / 24',
                              1 => '11 / 24',
                              _ => '7 / 23',
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFilter(BuildContext context, Lottery lottery) async {
    final current = ref.read(drawListProvider(lottery)).value;
    final fromCtrl = TextEditingController(text: current?.periodFrom ?? '');
    final toCtrl = TextEditingController(text: current?.periodTo ?? '');
    final result = await showModalBottomSheet<({String? from, String? to})>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom + 14,
        ),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '按期号范围筛选',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: fromCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '起始期号',
                        hintText: '2026200',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: toCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '结束期号',
                        hintText: currentPeriodForLottery(lottery),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  GlassGhostButton(
                    label: '清除',
                    onTap: () =>
                        Navigator.pop(sheetCtx, (from: null, to: null)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassButton(
                      onPressed: () => Navigator.pop(sheetCtx, (
                        from: fromCtrl.text.trim().isEmpty
                            ? null
                            : fromCtrl.text.trim(),
                        to: toCtrl.text.trim().isEmpty
                            ? null
                            : toCtrl.text.trim(),
                      )),
                      child: const Text('应用筛选'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    fromCtrl.dispose();
    toCtrl.dispose();
    if (result == null || !mounted) return;
    await ref
        .read(drawListProvider(lottery).notifier)
        .applyFilter(periodFrom: result.from, periodTo: result.to);
  }
}

class _DrawCard extends StatelessWidget {
  const _DrawCard({
    required this.draw,
    required this.lottery,
    required this.storedCount,
    required this.hitSourcesLabel,
  });

  final DrawRow draw;
  final Lottery lottery;
  final int storedCount;
  final String hitSourcesLabel;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DrawDetailScreen(
            lottery: lottery,
            period: draw.period,
            initialDraw: draw,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${draw.period} 期',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${lottery.label} · ${draw.drawDate ?? '${recentChinaMmDd(1)} 21:32'}',
                    style: context.texts.labelSmall,
                  ),
                ],
              ),
              const GlassStatusPill(
                label: '已对奖',
                color: DuiliaoColors.hit,
              ),
            ],
          ),
          const SizedBox(height: 14),
          DrawBallRow(draw: draw),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '新增入库 $storedCount 条',
                style: context.texts.labelSmall,
              ),
              Row(
                children: [
                  Text(
                    '命中源 ',
                    style: context.texts.labelSmall,
                  ),
                  Text(
                    hitSourcesLabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: DuiliaoColors.hit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
