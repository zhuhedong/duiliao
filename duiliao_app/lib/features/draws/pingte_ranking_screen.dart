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

enum RankingTab { zodiac, zodiacHistory, tail, number, bose, wuxing }

const List<String> _kAllZodiacs = [
  '鼠',
  '牛',
  '虎',
  '兔',
  '龙',
  '蛇',
  '马',
  '羊',
  '猴',
  '鸡',
  '狗',
  '猪',
];

class PingteRankingScreen extends ConsumerStatefulWidget {
  const PingteRankingScreen({
    super.key,
    this.initialTab = RankingTab.zodiac,
    this.initialXiao,
  });

  final RankingTab initialTab;
  final String? initialXiao;

  @override
  ConsumerState<PingteRankingScreen> createState() =>
      _PingteRankingScreenState();
}

class _PingteRankingScreenState extends ConsumerState<PingteRankingScreen> {
  late RankingTab _tab = widget.initialTab;
  int _limit = 0; // 0 = 当年全部期数
  String _orderBy = 'count_desc';
  String _keyword = '';
  bool _forceRefresh = false;

  // Zodiac History state
  late String _selectedXiao = widget.initialXiao ?? '鼠';
  String _historySubMode = 'segments'; // 'segments' | 'periods' | 'all_zodiacs'
  String _segmentTypeFilter = 'all'; // 'all' | 'hit' | 'miss'
  int _minSegmentLength = 1;
  int? _exactSegmentLength;
  String _segmentSort = 'latest'; // 'latest' | 'oldest' | 'length_desc'
  String _periodFilter = 'all'; // 'all' | 'hit' | 'miss'
  final TextEditingController _periodFromCtrl = TextEditingController();
  final TextEditingController _periodToCtrl = TextEditingController();
  String? _appliedPeriodFrom;
  String? _appliedPeriodTo;

  @override
  void dispose() {
    _periodFromCtrl.dispose();
    _periodToCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() => _forceRefresh = true);
  }

  void _openZodiacHistory(String xiao) {
    setState(() {
      _selectedXiao = xiao;
      _tab = RankingTab.zodiacHistory;
      _exactSegmentLength = null;
    });
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

    final historyAsync = _tab == RankingTab.zodiacHistory
        ? ref.watch(
            pingteZodiacHistoryProvider((
              lottery: lottery,
              xiao: _selectedXiao,
              limit: _limit,
              periodFrom: _appliedPeriodFrom,
              periodTo: _appliedPeriodTo,
              forceRefresh: _forceRefresh,
            )),
          )
        : null;

    if (_forceRefresh &&
        !rankingAsync.isLoading &&
        (historyAsync == null || !historyAsync.isLoading)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _forceRefresh = false);
      });
    }

    final data = rankingAsync.value;
    final historyData = historyAsync?.value;

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
                title: '平特排行榜 & 生肖历史',
                subtitle: '7 码全域统计 · 连开/没出起止期号明细',
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

                    // Controls row: Sample limit
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [0, 30, 50, 100, 200, 500].map((lim) {
                                final hasCustomRange = _appliedPeriodFrom != null || _appliedPeriodTo != null;
                                final isSel = !hasCustomRange && _limit == lim;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(lim == 0 ? '当年' : '$lim期', style: const TextStyle(fontSize: 11)),
                                    selected: isSel,
                                    onSelected: (_) => setState(() {
                                      _limit = lim;
                                      _appliedPeriodFrom = null;
                                      _appliedPeriodTo = null;
                                      _periodFromCtrl.clear();
                                      _periodToCtrl.clear();
                                    }),
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

                    // Sort orders (shown on ranking tabs)
                    if (_tab != RankingTab.zodiacHistory) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            (order: 'count_desc', label: '🔥 热号榜'),
                            (order: 'count_asc', label: '❄️ 冷号榜'),
                            (order: 'current_consecutive_desc', label: '⚡ 连开榜'),
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
                    ],

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
                              decoration: InputDecoration(
                                hintText: _tab == RankingTab.zodiacHistory
                                    ? '搜索期号、开出号码或连开/没出描述...'
                                    : '搜索生肖或号码...',
                                hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
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
                          (tab: RankingTab.zodiacHistory, label: '📜 生肖历史 (连开/没出)'),
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
                            Expanded(
                              child: Text(
                                (_limit <= 0
                                    ? '样本: 当年 ${data.samplePeriods}期 (${data.earliestPeriod ?? ''}~${data.latestPeriod ?? ''})'
                                    : '样本: ${data.samplePeriods}期 (${data.earliestPeriod ?? ''}~${data.latestPeriod ?? ''})'),
                                style: const TextStyle(fontSize: 11, color: Colors.white70),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              () {
                                final streakZ = data.zodiacRanking.where((z) => z.currentConsecutive > 0).toList()
                                  ..sort((a, b) => b.currentConsecutive.compareTo(a.currentConsecutive));
                                final streakText = streakZ.isNotEmpty ? ' · 连开: ${streakZ.first.name}${streakZ.first.currentConsecutive}期' : '';
                                return '热肖: ${data.zodiacRanking.isNotEmpty ? data.zodiacRanking.first.label : ''}$streakText';
                              }(),
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
                    if (_tab == RankingTab.zodiacHistory)
                      _buildZodiacHistoryView(
                        historyAsync: historyAsync,
                        historyData: historyData,
                        fallbackZodiacs: data?.zodiacRanking ?? const [],
                      )
                    else if (rankingAsync.isLoading && data == null)
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
                        RankingTab.zodiacHistory => const SizedBox.shrink(),
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
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => _openZodiacHistory(item.name),
            borderRadius: BorderRadius.circular(14),
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
                            '${item.count}次 (平${item.pingCount}·特${item.temaCount})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: DuiliaoColors.primaryDark,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            '开出${item.periodsCount}期 / 没出${item.missPeriodsCount}期 · ${item.frequency}%',
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

                  // Streak & Omission period intervals
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.currentRange != null
                                    ? '当前: ${item.currentRange!.startPeriod}~${item.currentRange!.endPeriod} (${item.currentConsecutive > 0 ? '连开${item.currentConsecutive}期' : '没出${item.currentOmission}期'})'
                                    : (item.currentConsecutive > 0
                                        ? '当前: 连开 ${item.currentConsecutive}期'
                                        : '当前: 没出 ${item.currentOmission}期'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: item.currentConsecutive > 0
                                      ? DuiliaoColors.hit
                                      : (item.currentOmission >= 4
                                          ? DuiliaoColors.warning
                                          : Colors.white70),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: DuiliaoColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '📜 历史区间 ›',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: DuiliaoColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.maxConsecutiveRange != null
                                    ? '最长连开: ${item.maxConsecutiveRange!.startPeriod}~${item.maxConsecutiveRange!.endPeriod} (${item.maxConsecutive}期)'
                                    : '最长连开: ${item.maxConsecutive}期',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Colors.white60,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item.maxOmissionRange != null
                                    ? '最长没出: ${item.maxOmissionRange!.startPeriod}~${item.maxOmissionRange!.endPeriod} (${item.maxOmission}期)'
                                    : '最长没出: ${item.maxOmission}期',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: Colors.white60,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Recent segments trajectory
                  if (item.recentSegments.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: item.recentSegments.take(6).map((seg) {
                          final isHit = seg.type == 'hit';
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isHit
                                    ? DuiliaoColors.hit.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: isHit
                                      ? DuiliaoColors.hit.withValues(alpha: 0.35)
                                      : Colors.white12,
                                ),
                              ),
                              child: Text(
                                '${seg.startPeriod.length > 4 ? seg.startPeriod.substring(seg.startPeriod.length - 3) : seg.startPeriod}~${seg.endPeriod.length > 4 ? seg.endPeriod.substring(seg.endPeriod.length - 3) : seg.endPeriod} ${seg.typeLabel}${seg.length}期',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                  color: isHit ? DuiliaoColors.hit : Colors.white54,
                                  fontWeight: seg.isCurrent ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],

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
          ),
        );
      }).toList(),
    );
  }

  // TAB 2: Per-Zodiac Pingte History (连开/没出区间 + 逐期明细 + 12生肖总览)
  Widget _buildZodiacHistoryView({
    required AsyncValue<PingteZodiacHistoryResult>? historyAsync,
    required PingteZodiacHistoryResult? historyData,
    required List<PingteZodiacRank> fallbackZodiacs,
  }) {
    final allZodiacs = (historyData != null && historyData.zodiacs.isNotEmpty)
        ? historyData.zodiacs
        : fallbackZodiacs;

    PingteZodiacRank? activeZodiac =
        (historyData?.zodiacHistory != null &&
                historyData!.zodiacHistory!.name == _selectedXiao)
            ? historyData.zodiacHistory
            : null;
    if (activeZodiac == null && allZodiacs.isNotEmpty) {
      activeZodiac = allZodiacs
              .where((z) => z.name == _selectedXiao)
              .firstOrNull ??
          allZodiacs.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 12 Zodiac Selector Grid (6x2)
        GlassSubtleBox(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择生肖查看平特连开/没出历史',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  if (historyData != null && historyData.samplePeriods > 0)
                    Text(
                      '${historyData.earliestPeriod ?? ''}~${historyData.latestPeriod ?? ''} (${historyData.samplePeriods}期)',
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _kAllZodiacs.map((x) {
                  final zInfo = allZodiacs.where((z) => z.name == x).firstOrNull;
                  final isSel = _selectedXiao == x;
                  final isStreak = (zInfo?.currentConsecutive ?? 0) > 0;
                  return InkWell(
                    onTap: () => setState(() {
                      _selectedXiao = x;
                      _exactSegmentLength = null;
                    }),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 50,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSel
                            ? DuiliaoColors.primaryDark
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSel
                              ? DuiliaoColors.primary
                              : Colors.white12,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$x肖',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isSel ? Colors.white : Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            zInfo == null
                                ? '-'
                                : (isStreak
                                    ? '连${zInfo.currentConsecutive}期'
                                    : '漏${zInfo.currentOmission}期'),
                            style: TextStyle(
                              fontSize: 9,
                              color: isSel
                                  ? Colors.white70
                                  : (isStreak
                                      ? DuiliaoColors.hit
                                      : Colors.white38),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              // Custom Period Range Filter Row
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _periodFromCtrl,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.white,
                        ),
                        decoration: const InputDecoration(
                          hintText: '起始期号 如2026001',
                          hintStyle: TextStyle(fontSize: 10, color: Colors.white30),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('~', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                  Expanded(
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: TextField(
                        controller: _periodToCtrl,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.white,
                        ),
                        decoration: const InputDecoration(
                          hintText: '截止期号 如2026285',
                          hintStyle: TextStyle(fontSize: 10, color: Colors.white30),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => setState(() {
                      final pf = _periodFromCtrl.text.trim();
                      final pt = _periodToCtrl.text.trim();
                      _appliedPeriodFrom = pf.isEmpty ? null : pf;
                      _appliedPeriodTo = pt.isEmpty ? null : pt;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: DuiliaoColors.primaryDark,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '筛选',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (_appliedPeriodFrom != null || _appliedPeriodTo != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => setState(() {
                        _periodFromCtrl.clear();
                        _periodToCtrl.clear();
                        _appliedPeriodFrom = null;
                        _appliedPeriodTo = null;
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '清除',
                          style: TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (historyAsync != null && historyAsync.isLoading && activeZodiac == null)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (activeZodiac == null)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                '暂无该生肖平特历史数据',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          )
        else ...[
          // Selected Zodiac Summary Card
          GlassSubtleBox(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: DuiliaoColors.primaryDark,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        activeZodiac.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${activeZodiac.label} · 平特历史统计 (${activeZodiac.numbers.join(",")})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '共 ${activeZodiac.count} 球 (平码${activeZodiac.pingCount} · 特码${activeZodiac.temaCount}) · 开出${activeZodiac.periodsCount}期 / 没出${activeZodiac.missPeriodsCount}期 (${activeZodiac.frequency}%)',
                            style: const TextStyle(fontSize: 10, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 3 Interval Highlight Boxes: 当前状态 / 最大连开区间 / 最大没出区间
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeZodiac.currentRange != null
                            ? '⚡ 当前状态: ${activeZodiac.currentRange!.startPeriod}~${activeZodiac.currentRange!.endPeriod} ${activeZodiac.currentConsecutive > 0 ? '连开 ${activeZodiac.currentConsecutive} 期' : '没出 ${activeZodiac.currentOmission} 期'}'
                            : '⚡ 当前状态: ${activeZodiac.currentConsecutive > 0 ? '连开 ${activeZodiac.currentConsecutive} 期' : '没出 ${activeZodiac.currentOmission} 期'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: activeZodiac.currentConsecutive > 0
                              ? DuiliaoColors.hit
                              : DuiliaoColors.warning,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeZodiac.maxConsecutiveRange != null
                            ? '🔥 最长连开: ${activeZodiac.maxConsecutiveRange!.startPeriod}~${activeZodiac.maxConsecutiveRange!.endPeriod} 连开 ${activeZodiac.maxConsecutive} 期 (共${activeZodiac.hitSegmentsCount}段连开)'
                            : '🔥 最长连开: ${activeZodiac.maxConsecutive} 期',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeZodiac.maxOmissionRange != null
                            ? '❄️ 最长没出: ${activeZodiac.maxOmissionRange!.startPeriod}~${activeZodiac.maxOmissionRange!.endPeriod} 没出 ${activeZodiac.maxOmission} 期 (共${activeZodiac.missSegmentsCount}段没出)'
                            : '❄️ 最长没出: ${activeZodiac.maxOmission} 期',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),

                // Streak & Omission Distributions
                if (activeZodiac.streakDistribution.isNotEmpty ||
                    activeZodiac.omissionDistribution.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '连开 / 没出期数分布 (点击筛选对应长度波段):',
                    style: TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                  const SizedBox(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...activeZodiac.streakDistribution.map((d) {
                          final isSelected = _historySubMode == 'segments' &&
                              _segmentTypeFilter == 'hit' &&
                              _exactSegmentLength == d.length;
                          final shortRange = (d.length >= 3 &&
                                  d.latestStartPeriod.isNotEmpty &&
                                  d.latestEndPeriod.isNotEmpty)
                              ? ' (${d.latestStartPeriod.length > 3 ? d.latestStartPeriod.substring(d.latestStartPeriod.length - 3) : d.latestStartPeriod}~${d.latestEndPeriod.length > 3 ? d.latestEndPeriod.substring(d.latestEndPeriod.length - 3) : d.latestEndPeriod})'
                              : '';
                          return Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: InkWell(
                              onTap: () => setState(() {
                                _historySubMode = 'segments';
                                if (isSelected) {
                                  _segmentTypeFilter = 'all';
                                  _exactSegmentLength = null;
                                } else {
                                  _segmentTypeFilter = 'hit';
                                  _exactSegmentLength = d.length;
                                }
                              }),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? DuiliaoColors.hit
                                      : DuiliaoColors.hit.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: DuiliaoColors.hit.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  '连开${d.length}期×${d.count}次$shortRange',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: isSelected ? Colors.white : DuiliaoColors.hit,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        ...activeZodiac.omissionDistribution.map((d) {
                          final isSelected = _historySubMode == 'segments' &&
                              _segmentTypeFilter == 'miss' &&
                              _exactSegmentLength == d.length;
                          final shortRange = (d.length >= 3 &&
                                  d.latestStartPeriod.isNotEmpty &&
                                  d.latestEndPeriod.isNotEmpty)
                              ? ' (${d.latestStartPeriod.length > 3 ? d.latestStartPeriod.substring(d.latestStartPeriod.length - 3) : d.latestStartPeriod}~${d.latestEndPeriod.length > 3 ? d.latestEndPeriod.substring(d.latestEndPeriod.length - 3) : d.latestEndPeriod})'
                              : '';
                          return Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: InkWell(
                              onTap: () => setState(() {
                                _historySubMode = 'segments';
                                if (isSelected) {
                                  _segmentTypeFilter = 'all';
                                  _exactSegmentLength = null;
                                } else {
                                  _segmentTypeFilter = 'miss';
                                  _exactSegmentLength = d.length;
                                }
                              }),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? DuiliaoColors.warning
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(
                                  '没出${d.length}期×${d.count}次$shortRange',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: isSelected ? Colors.black : Colors.white70,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Sub-mode switcher: 连开/没出区间 | 逐期开奖明细 | 12生肖总览
          Row(
            children: [
              (mode: 'segments', label: '📊 连开/没出区间 (${activeZodiac.segments.length})'),
              (mode: 'periods', label: '📅 逐期明细 (${activeZodiac.periodHistory.length})'),
              (mode: 'all_zodiacs', label: '🗂️ 12生肖总览'),
            ].map((m) {
              final isSel = _historySubMode == m.mode;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => setState(() => _historySubMode = m.mode),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel
                            ? DuiliaoColors.primary
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSel ? DuiliaoColors.primaryDark : Colors.white12,
                        ),
                      ),
                      child: Text(
                        m.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          color: isSel ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          if (_historySubMode == 'segments')
            _buildHistorySegmentsList(activeZodiac)
          else if (_historySubMode == 'periods')
            _buildHistoryPeriodsList(activeZodiac)
          else
            _buildAllZodiacsOverviewList(allZodiacs),
        ],
      ],
    );
  }

  Widget _buildHistorySegmentsList(PingteZodiacRank zodiac) {
    var list = zodiac.segments.toList();
    if (_segmentTypeFilter == 'hit') {
      list = list.where((s) => s.type == 'hit').toList();
    } else if (_segmentTypeFilter == 'miss') {
      list = list.where((s) => s.type == 'miss').toList();
    }
    if (_exactSegmentLength != null) {
      list = list.where((s) => s.length == _exactSegmentLength).toList();
    } else if (_minSegmentLength > 1) {
      list = list.where((s) => s.length >= _minSegmentLength).toList();
    }
    if (_keyword.isNotEmpty) {
      list = list
          .where((s) =>
              s.startPeriod.contains(_keyword) ||
              s.endPeriod.contains(_keyword) ||
              (_keyword.length == s.startPeriod.length &&
                  _keyword.compareTo(s.startPeriod) >= 0 &&
                  _keyword.compareTo(s.endPeriod) <= 0) ||
              s.text.contains(_keyword) ||
              s.periods.any((p) =>
                  p.period.contains(_keyword) ||
                  p.matchedNumbers.any((n) => n.contains(_keyword))))
          .toList();
    }

    if (_segmentSort == 'latest') {
      list.sort((a, b) => b.segmentId.compareTo(a.segmentId));
    } else if (_segmentSort == 'oldest') {
      list.sort((a, b) => a.segmentId.compareTo(b.segmentId));
    } else if (_segmentSort == 'length_desc') {
      list.sort((a, b) {
        final cmp = b.length.compareTo(a.length);
        return cmp != 0 ? cmp : b.segmentId.compareTo(a.segmentId);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Segment filter bar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ...[
                (id: 'all', label: '全部'),
                (id: 'hit', label: '🔥 只看连开'),
                (id: 'miss', label: '❄️ 只看没出'),
              ].map((t) {
                final isSel = _segmentTypeFilter == t.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => setState(() {
                      _segmentTypeFilter = t.id;
                      _exactSegmentLength = null;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSel
                            ? DuiliaoColors.primaryDark
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        t.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          color: isSel ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              ...[1, 2, 3, 4, 5].map((minLen) {
                final isSel = _exactSegmentLength == null && _minSegmentLength == minLen;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => setState(() {
                      _exactSegmentLength = null;
                      _minSegmentLength = minLen;
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSel
                            ? DuiliaoColors.primary.withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        minLen == 1 ? '不限期数' : '≥$minLen期',
                        style: TextStyle(
                          fontSize: 10,
                          color: isSel ? Colors.white : Colors.white60,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              ...[
                (id: 'latest', label: '最新'),
                (id: 'length_desc', label: '最长'),
                (id: 'oldest', label: '最旧'),
              ].map((s) {
                final isSel = _segmentSort == s.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => setState(() => _segmentSort = s.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSel
                            ? Colors.white24
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        s.label,
                        style: TextStyle(
                          fontSize: 10,
                          color: isSel ? Colors.white : Colors.white60,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),

        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                '没有符合筛选条件的连开/没出区间',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          )
        else
          ...list.map((seg) {
            final isHit = seg.type == 'hit';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: GlassSubtleBox(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isHit
                                ? DuiliaoColors.hit.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isHit
                                  ? DuiliaoColors.hit.withValues(alpha: 0.5)
                                  : Colors.white24,
                            ),
                          ),
                          child: Text(
                            isHit ? '🔥 连开 ${seg.length} 期' : '❄️ 没出 ${seg.length} 期',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isHit ? DuiliaoColors.hit : Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            seg.startPeriod == seg.endPeriod
                                ? '第 ${seg.startPeriod} 期 (${seg.typeLabel}1期)'
                                : '${seg.startPeriod} ~ ${seg.endPeriod} 期 (${seg.typeLabel}${seg.length}期)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (seg.isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: DuiliaoColors.boseGold.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              '当前',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: DuiliaoColors.boseGold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '日期: ${seg.startDate == seg.endDate ? seg.startDate : '${seg.startDate} ~ ${seg.endDate}'}',
                          style: const TextStyle(fontSize: 10, color: Colors.white54),
                        ),
                        if (isHit)
                          Text(
                            '共开出 ${seg.totalBalls} 球${seg.temaHits > 0 ? ' (含特码${seg.temaHits}次)' : ''}',
                            style: const TextStyle(fontSize: 10, color: DuiliaoColors.hit),
                          )
                        else
                          Text(
                            '连续 ${seg.length} 期未出${zodiac.label}',
                            style: const TextStyle(fontSize: 10, color: Colors.white38),
                          ),
                      ],
                    ),
                    if (isHit && seg.periods.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: seg.periods.map((p) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Text(
                              '${p.period}期: ${p.matchedBalls.map((b) => '${b.number}${b.isTema ? '(特)' : ''}').join(' ')}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: Colors.white70,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildHistoryPeriodsList(PingteZodiacRank zodiac) {
    var list = zodiac.periodHistory.toList();
    if (_periodFilter == 'hit') {
      list = list.where((p) => p.isHit).toList();
    } else if (_periodFilter == 'miss') {
      list = list.where((p) => !p.isHit).toList();
    }
    if (_keyword.isNotEmpty) {
      list = list
          .where((p) =>
              p.period.contains(_keyword) ||
              p.segmentText.contains(_keyword) ||
              p.matchedNumbers.any((n) => n.contains(_keyword)))
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            (id: 'all', label: '全部期数 (${zodiac.periodHistory.length})'),
            (id: 'hit', label: '🔥 只看开出 (${zodiac.periodsCount})'),
            (id: 'miss', label: '❄️ 只看没出 (${zodiac.missPeriodsCount})'),
          ].map((f) {
            final isSel = _periodFilter == f.id;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => setState(() => _periodFilter = f.id),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSel
                        ? DuiliaoColors.primaryDark
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    f.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      color: isSel ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        ...list.take(150).map((row) {
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            child: GlassSubtleBox(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '第 ${row.period} 期 (${row.drawDate})',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: row.isHit
                              ? DuiliaoColors.hit.withValues(alpha: 0.2)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          row.isHit
                              ? '${row.runningText} · 开出${row.ballCount}球 (${row.matchedNumbers.join(",")})'
                              : '${row.runningText} · 没出',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: row.isHit ? DuiliaoColors.hit : Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '所属波段: ${row.segmentText}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Colors.white54,
                    ),
                  ),
                  if (row.allBalls.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: row.allBalls.map((b) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: b.isTarget
                                    ? DuiliaoColors.hit.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: b.isTarget
                                      ? DuiliaoColors.hit
                                      : Colors.white10,
                                ),
                              ),
                              child: Text(
                                '${b.number}${b.xiao}${b.isTema ? '(特)' : ''}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontFamily: 'monospace',
                                  fontWeight: b.isTarget ? FontWeight.bold : FontWeight.normal,
                                  color: b.isTarget ? Colors.white : Colors.white54,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAllZodiacsOverviewList(List<PingteZodiacRank> allZodiacs) {
    return Column(
      children: allZodiacs.map((z) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => setState(() {
              _selectedXiao = z.name;
              _historySubMode = 'segments';
            }),
            borderRadius: BorderRadius.circular(12),
            child: GlassSubtleBox(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${z.label} (平${z.pingCount}·特${z.temaCount} | 开${z.periodsCount}期/漏${z.missPeriodsCount}期)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${z.frequency}%',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: DuiliaoColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前: ${z.currentRange?.text ?? (z.currentConsecutive > 0 ? '连开${z.currentConsecutive}期' : '没出${z.currentOmission}期')}',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: z.currentConsecutive > 0 ? DuiliaoColors.hit : Colors.white70,
                    ),
                  ),
                  Text(
                    '最长连开: ${z.maxConsecutiveRange?.text ?? '${z.maxConsecutive}期'} · 最长没出: ${z.maxOmissionRange?.text ?? '${z.maxOmission}期'}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
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
                      item.currentConsecutive > 0
                          ? '当前: 连开 ${item.currentConsecutive}期'
                          : (item.currentOmission == 0
                              ? '当前: 本期开出'
                              : '当前遗漏: ${item.currentOmission}期'),
                      style: TextStyle(
                        fontSize: 10,
                        color: item.currentConsecutive > 0
                            ? DuiliaoColors.hit
                            : Colors.white60,
                        fontWeight: (item.currentConsecutive > 0 || item.currentOmission == 0)
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Text(
                      '当前连开: ${item.currentConsecutive}期 · 最大连出: ${item.maxConsecutive}期',
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
                      item.currentConsecutive > 0
                          ? '当前: 连开 ${item.currentConsecutive}期 · 连出: ${item.maxConsecutive}期'
                          : '遗漏: ${item.currentOmission == 0 ? '本期' : '${item.currentOmission}期'} · 连出: ${item.maxConsecutive}期',
                      style: TextStyle(
                        fontSize: 10,
                        color: (item.currentConsecutive > 0 || item.currentOmission == 0)
                            ? DuiliaoColors.hit
                            : Colors.white54,
                        fontWeight: item.currentConsecutive > 0 ? FontWeight.bold : FontWeight.normal,
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
                  '开出期数: ${b.periodsCount}期 · 当前: ${b.currentConsecutive > 0 ? '连开 ${b.currentConsecutive}期' : '遗漏 ${b.currentOmission}期'} · 最大连出: ${b.maxConsecutive}期',
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
                  '开出期数: ${w.periodsCount}期 · 当前: ${w.currentConsecutive > 0 ? '连开 ${w.currentConsecutive}期' : '遗漏 ${w.currentOmission}期'} · 最大连出: ${w.maxConsecutive}期',
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
