/// Pingte appearance ranking screen for Flutter mobile app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/draw.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import 'draws_providers.dart';

enum RankingTab { zodiac, tail, number, bose, wuxing }

class PingteRankingScreen extends ConsumerStatefulWidget {
  const PingteRankingScreen({super.key});

  @override
  ConsumerState<PingteRankingScreen> createState() =>
      _PingteRankingScreenState();
}

class _PingteRankingScreenState extends ConsumerState<PingteRankingScreen> {
  RankingTab _tab = RankingTab.zodiac;
  int _limit = 0; // 0 = 当年全部期数
  String _orderBy = 'count_desc';
  String _keyword = '';
  bool _forceRefresh = false;

  void _refresh() {
    setState(() => _forceRefresh = true);
  }

  @override
  Widget build(BuildContext context) {
    final lottery = ref.watch(selectedLotteryProvider);
    final rankingAsync = ref.watch(
      pingteRankingProvider((
        lottery: lottery,
        limit: _limit,
        dimension: 'all',
        orderBy: _orderBy,
        forceRefresh: _forceRefresh,
      )),
    );

    if (_forceRefresh && !rankingAsync.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _forceRefresh = false);
      });
    }

    final data = rankingAsync.value;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '平特出现排行榜',
                subtitle: '7 码全域统计 · 默认当年全部期数',
                actions: [
                  GlassIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '刷新排行榜',
                    onTap: _refresh,
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    // Lottery switcher
                    GlassSegmentedControl<Lottery>(
                      items: Lottery.all,
                      selected: lottery,
                      labelBuilder: (l) => l.label,
                      onChanged: (next) =>
                          ref.read(selectedLotteryProvider.notifier).set(next),
                    ),
                    const SizedBox(height: 10),

                    // Controls row: Sample limit & Sort
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [0, 30, 50, 100, 200, 500].map((lim) {
                                final isSel = _limit == lim;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(lim == 0 ? '当年' : '$lim期', style: const TextStyle(fontSize: 11)),
                                    selected: isSel,
                                    onSelected: (_) => setState(() => _limit = lim),
                                    selectedColor: DuiliaoColors.primary.withValues(alpha: 0.25),
                                    backgroundColor: Colors.black.withValues(alpha: 0.1),
                                    side: BorderSide(
                                      color: isSel ? DuiliaoColors.primary : Colors.white12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Sort orders
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          (order: 'count_desc', label: '🔥 热号榜'),
                          (order: 'count_asc', label: '❄️ 冷号榜'),
                          (order: 'omission_desc', label: '⚡ 遗漏榜'),
                          (order: 'consecutive_desc', label: '👑 连出王'),
                        ].map((s) {
                          final isSel = _orderBy == s.order;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => setState(() => _orderBy = s.order),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? DuiliaoColors.primary
                                      : Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSel ? DuiliaoColors.primaryDark : Colors.white10,
                                  ),
                                ),
                                child: Text(
                                  s.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                    color: isSel ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Search input
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 16, color: Colors.white54),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setState(() => _keyword = v.trim()),
                              style: const TextStyle(fontSize: 12, color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: '搜索生肖或号码...',
                                hintStyle: TextStyle(fontSize: 12, color: Colors.white38),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (_keyword.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() => _keyword = ''),
                              child: const Icon(Icons.close, size: 14, color: Colors.white54),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Sub-tabs
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          (tab: RankingTab.zodiac, label: '平特生肖'),
                          (tab: RankingTab.tail, label: '平特尾数'),
                          (tab: RankingTab.number, label: '平特号码'),
                          (tab: RankingTab.bose, label: '平特波色'),
                          (tab: RankingTab.wuxing, label: '平特五行'),
                        ].map((t) {
                          final isSel = _tab == t.tab;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => setState(() => _tab = t.tab),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? DuiliaoColors.primaryDark
                                      : Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSel ? DuiliaoColors.primaryDark : Colors.white10,
                                  ),
                                ),
                                child: Text(
                                  t.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                    color: isSel ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Stats banner
                    if (data != null && data.samplePeriods > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              (_limit <= 0
                                  ? '样本: 当年 ${data.samplePeriods}期 (${data.earliestPeriod ?? ''}~${data.latestPeriod ?? ''})'
                                  : '样本: ${data.samplePeriods}期 (${data.earliestPeriod ?? ''}~${data.latestPeriod ?? ''})'),
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                            Text(
                              '热肖: ${data.zodiacRanking.isNotEmpty ? data.zodiacRanking.first.label : ''}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: DuiliaoColors.boseGold,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Content
                    if (rankingAsync.isLoading && data == null)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (data == null || data.samplePeriods == 0)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            '暂无排行榜数据',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      switch (_tab) {
                        RankingTab.zodiac => _buildZodiacList(data.zodiacRanking),
                        RankingTab.tail => _buildTailList(data.tailRanking),
                        RankingTab.number => _buildNumberList(data.numberRanking),
                        RankingTab.bose => _buildBoseList(data.boseRanking),
                        RankingTab.wuxing => _buildWuxingList(data.wuxingRanking),
                      },
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAB 1: Zodiac List
  Widget _buildZodiacList(List<PingteZodiacRank> list) {
    var items = list;
    if (_keyword.isNotEmpty) {
      items = items
          .where((z) =>
              z.name.contains(_keyword) ||
              z.label.contains(_keyword) ||
              z.numbers.any((n) => n.contains(_keyword)))
          .toList();
    }

    return Column(
      children: items.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final medal = idx == 0
            ? '🥇'
            : idx == 1
                ? '🥈'
                : idx == 2
                    ? '🥉'
                    : '#${idx + 1}';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: GlassSubtleBox(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        medal,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: DuiliaoColors.primaryDark,
                        shape: BoxShape.circle,
                        border: Border.all(color: DuiliaoColors.primaryDark),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (item.isHot) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: DuiliaoColors.boseRed.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '热',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: DuiliaoColors.boseRed,
                          ),
                        ),
                      ),
                    ],
                    if (item.isCold) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: DuiliaoColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '冷',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: DuiliaoColors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.count}次',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: DuiliaoColors.primaryDark,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          '${item.periodsCount}期 · ${item.frequency}%',
                          style: const TextStyle(fontSize: 10, color: Colors.white54),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (item.frequency / 100).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation(DuiliaoColors.primary),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.currentOmission == 0
                          ? '当前: 本期开出'
                          : '当前遗漏: ${item.currentOmission}期',
                      style: TextStyle(
                        fontSize: 10,
                        color: item.currentOmission == 0
                            ? DuiliaoColors.hit
                            : (item.currentOmission > 5
                                ? DuiliaoColors.warning
                                : Colors.white60),
                        fontWeight: item.currentOmission == 0
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Text(
                      '最大遗漏: ${item.maxOmission}期 · 最大连出: ${item.maxConsecutive}期',
                      style: const TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: item.numbers.map((n) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            n,
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // TAB 2: Tail List
  Widget _buildTailList(List<PingteTailRank> list) {
    var items = list;
    if (_keyword.isNotEmpty) {
      items = items
          .where((t) =>
              t.name.contains(_keyword) ||
              t.label.contains(_keyword) ||
              t.numbers.any((n) => n.contains(_keyword)))
          .toList();
    }

    return Column(
      children: items.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final medal = idx == 0
            ? '🥇'
            : idx == 1
                ? '🥈'
                : idx == 2
                    ? '🥉'
                    : '#${idx + 1}';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: GlassSubtleBox(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        medal,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.count}次',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.purpleAccent,
                            fontFamily: 'monospace',
                          ),
                        ),
                        Text(
                          '${item.periodsCount}期 · ${item.frequency}%',
                          style: const TextStyle(fontSize: 10, color: Colors.white54),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (item.frequency / 100).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation(Colors.purpleAccent),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.currentOmission == 0
                          ? '当前: 本期开出'
                          : '当前遗漏: ${item.currentOmission}期',
                      style: TextStyle(
                        fontSize: 10,
                        color: item.currentOmission == 0
                            ? DuiliaoColors.hit
                            : Colors.white60,
                      ),
                    ),
                    Text(
                      '最大遗漏: ${item.maxOmission}期 · 最大连出: ${item.maxConsecutive}期',
                      style: const TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: item.numbers.map((n) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            n,
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // TAB 3: Number List
  Widget _buildNumberList(List<PingteNumberRank> list) {
    var items = list;
    if (_keyword.isNotEmpty) {
      items = items
          .where((n) =>
              n.number.contains(_keyword) ||
              n.xiao.contains(_keyword) ||
              n.bose.contains(_keyword) ||
              n.wuxing.contains(_keyword))
          .toList();
    }

    return Column(
      children: items.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: GlassSubtleBox(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '#${idx + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white54,
                    ),
                  ),
                ),
                NumberBall(
                  number: item.number,
                  bose: item.bose,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${item.xiao}肖',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (item.wuxing.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            '· ${item.wuxing}',
                            style: const TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '遗漏: ${item.currentOmission == 0 ? '本期' : '${item.currentOmission}期'} · 连出: ${item.maxConsecutive}期',
                      style: TextStyle(
                        fontSize: 10,
                        color: item.currentOmission == 0
                            ? DuiliaoColors.hit
                            : Colors.white54,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${item.count}次',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: DuiliaoColors.primaryDark,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      '平${item.pingCount} · 特${item.temaCount}',
                      style: const TextStyle(fontSize: 10, color: Colors.white54),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // TAB 4: Bose List
  Widget _buildBoseList(List<PingteBoseRank> list) {
    return Column(
      children: list.map((b) {
        final color = b.name.contains('红')
            ? DuiliaoColors.boseRed
            : (b.name.contains('蓝') ? DuiliaoColors.boseBlue : DuiliaoColors.boseGreen);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: GlassSubtleBox(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          b.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${b.percentage}% · ${b.count}球',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '开出期数: ${b.periodsCount}期 · 当前遗漏: ${b.currentOmission}期 · 最大连出: ${b.maxConsecutive}期',
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: b.numbers.map((n) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            n,
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // TAB 5: Wuxing List
  Widget _buildWuxingList(List<PingteWuxingRank> list) {
    const wxColors = {
      '金': DuiliaoColors.boseGold,
      '木': DuiliaoColors.boseGreen,
      '水': DuiliaoColors.boseBlue,
      '火': DuiliaoColors.boseRed,
      '土': Colors.brown,
    };

    return Column(
      children: list.map((w) {
        final color = wxColors[w.name] ?? Colors.white54;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: GlassSubtleBox(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: color),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            w.name,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          w.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${w.percentage}% · ${w.count}球',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '开出期数: ${w.periodsCount}期 · 当前遗漏: ${w.currentOmission}期 · 最大连出: ${w.maxConsecutive}期',
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: w.numbers.map((n) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            n,
                            style: const TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
