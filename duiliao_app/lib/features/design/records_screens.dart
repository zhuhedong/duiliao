/// Betting Records screens (records.html, record-add*.html, record-detail.html, record-stats.html).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/lottery.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import 'jump_code_assistant_screen.dart';

class BettingRecordItem {
  const BettingRecordItem({
    required this.id,
    required this.lottery,
    required this.period,
    required this.playType,
    required this.timeLabel,
    required this.numbers,
    required this.xiaos,
    required this.stakePerNote,
    required this.multiplier,
    required this.notesCount,
    required this.totalAmount,
    required this.status, // 'pending', 'won', 'lost'
    this.hitNumbers = const <String>[],
    this.payout = 0,
    this.netProfit = 0,
    this.rawInput = '',
    this.note,
    this.sourceBadge,
  });

  final String id;
  final Lottery lottery;
  final String period;
  final String playType;
  final String timeLabel;
  final List<String> numbers;
  final List<String> xiaos;
  final int stakePerNote;
  final int multiplier;
  final int notesCount;
  final int totalAmount;
  final String status;
  final List<String> hitNumbers;
  final int payout;
  final int netProfit;
  final String rawInput;
  final String? note;
  final String? sourceBadge;
}

class BettingRecordsNotifier extends Notifier<List<BettingRecordItem>> {
  @override
  List<BettingRecordItem> build() => _defaultRecords;

  void addRecord(BettingRecordItem item) {
    state = [item, ...state];
  }

  void removeRecord(String id) {
    state = state.where((r) => r.id != id).toList(growable: false);
  }
}

final bettingRecordsProvider =
    NotifierProvider<BettingRecordsNotifier, List<BettingRecordItem>>(
      BettingRecordsNotifier.new,
    );

const List<BettingRecordItem> _defaultRecords = [
  BettingRecordItem(
    id: 'rec-277-1',
    lottery: Lottery.macau,
    period: '2026277',
    playType: '正码',
    timeLabel: '20:42',
    numbers: ['18', '42', '39', '27', '28', '37', '49', '38', '02', '01'],
    xiaos: [],
    stakePerNote: 10,
    multiplier: 1,
    notesCount: 10,
    totalAmount: 100,
    status: 'pending',
    rawInput: '18-42-39-27-28-37-49-38-02-01各10',
  ),
  BettingRecordItem(
    id: 'rec-277-2',
    lottery: Lottery.macau,
    period: '2026277',
    playType: '正码',
    timeLabel: '20:15',
    numbers: ['05', '17', '29', '41'],
    xiaos: [],
    stakePerNote: 15,
    multiplier: 1,
    notesCount: 4,
    totalAmount: 60,
    status: 'pending',
    rawInput: '05 17 29 41 各 15',
  ),
  BettingRecordItem(
    id: 'rec-277-3',
    lottery: Lottery.macau,
    period: '2026277',
    playType: '特码',
    timeLabel: '19:50',
    numbers: ['26', '14', '03'],
    xiaos: [],
    stakePerNote: 20,
    multiplier: 1,
    notesCount: 3,
    totalAmount: 60,
    status: 'pending',
    sourceBadge: '来自 AI 研判',
    rawInput: '特码 26 14 03 各 20',
  ),
  BettingRecordItem(
    id: 'rec-277-4',
    lottery: Lottery.macau,
    period: '2026277',
    playType: '4连肖·复试',
    timeLabel: '19:18',
    numbers: [],
    xiaos: ['兔', '龙', '蛇', '马', '羊'],
    stakePerNote: 6,
    multiplier: 1,
    notesCount: 5,
    totalAmount: 30,
    status: 'pending',
    rawInput: '四连肖复试 兔 龙 蛇 马 羊 各 6',
  ),
  BettingRecordItem(
    id: 'rec-276-1',
    lottery: Lottery.macau,
    period: '2026276',
    playType: '正码',
    timeLabel: '09-25 20:30',
    numbers: ['08', '11', '14', '26', '33', '42'],
    xiaos: [],
    stakePerNote: 5,
    multiplier: 1,
    notesCount: 6,
    totalAmount: 30,
    status: 'won',
    hitNumbers: ['11', '26', '42'],
    payout: 105,
    netProfit: 75,
    rawInput: '08-11-14-26-33-42各5',
    note: '参考海哥+顶尖大师交集',
  ),
  BettingRecordItem(
    id: 'rec-276-2',
    lottery: Lottery.macau,
    period: '2026276',
    playType: '正码',
    timeLabel: '09-25 19:12',
    numbers: ['03', '09', '19', '27', '38'],
    xiaos: [],
    stakePerNote: 10,
    multiplier: 1,
    notesCount: 5,
    totalAmount: 50,
    status: 'won',
    hitNumbers: ['03', '19', '27'],
    payout: 70,
    netProfit: 20,
    rawInput: '03 09 19 27 38 各 10',
  ),
  BettingRecordItem(
    id: 'rec-275-1',
    lottery: Lottery.macau,
    period: '2026275',
    playType: '正码',
    timeLabel: '09-24 20:55',
    numbers: ['05', '12', '21', '30', '44', '49'],
    xiaos: [],
    stakePerNote: 10,
    multiplier: 1,
    notesCount: 6,
    totalAmount: 60,
    status: 'lost',
    hitNumbers: [],
    payout: 0,
    netProfit: -60,
    rawInput: '05 12 21 30 44 49 各 10',
  ),
  BettingRecordItem(
    id: 'rec-275-2',
    lottery: Lottery.macau,
    period: '2026275',
    playType: '特码',
    timeLabel: '09-24 20:10',
    numbers: ['07', '19'],
    xiaos: [],
    stakePerNote: 15,
    multiplier: 1,
    notesCount: 2,
    totalAmount: 30,
    status: 'won',
    hitNumbers: ['07'],
    payout: 100,
    netProfit: 70,
    rawInput: '特码 07 19 各 15',
  ),
];

/// Records List Screen (records.html).
class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen> {
  String _filter = 'all'; // 'all', 'pending', 'won', 'lost'

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(bettingRecordsProvider);
    final pendingCount = all.where((r) => r.status == 'pending').length;
    final wonCount = all.where((r) => r.status == 'won').length;
    final lostCount = all.where((r) => r.status == 'lost').length;

    final filtered = switch (_filter) {
      'pending' => all.where((r) => r.status == 'pending').toList(),
      'won' => all.where((r) => r.status == 'won').toList(),
      'lost' => all.where((r) => r.status == 'lost').toList(),
      _ => all,
    };

    final periods = <String>[];
    for (final item in filtered) {
      if (!periods.contains(item.period)) periods.add(item.period);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DesignAppHeader(
              title: '我的记录',
              subtitle: '澳门 · 近 30 期 · 共 47 单',
              actions: [
                GlassIconButton(
                  icon: Icons.bar_chart_rounded,
                  tooltip: '盈亏统计',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RecordStatsScreen(),
                    ),
                  ),
                ),
                GlassGhostButton(
                  label: '跳码助手',
                  icon: Icons.auto_awesome_motion,
                  compact: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const JumpCodeAssistantScreen(),
                    ),
                  ),
                ),
                SizedBox(
                  height: 34,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecordAddScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('新增'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                children: [
                  // Summary Hero Card
                  GlassCard(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '本期汇总 · 第 2026277 期',
                              style: context.texts.labelSmall,
                            ),
                            const GlassStatusPill(
                              label: '今晚 21:30 开奖',
                              color: DuiliaoColors.warning,
                              pulse: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCol(
                                label: '本期投入',
                                value: '¥250',
                                sub: '4 单 · 22 注',
                                valueColor:
                                    Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 44,
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                            const Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(left: 12),
                                child: _SummaryCol(
                                  label: '累计盈亏',
                                  value: '+¥175',
                                  sub: '近 30 期',
                                  valueColor: DuiliaoColors.hit,
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 44,
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: _SummaryCol(
                                  label: '中单率',
                                  value: '31.9%',
                                  sub: '15 / 47 单',
                                  valueColor:
                                      Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        GlassChipTag(
                          label: '全部',
                          active: _filter == 'all',
                          onTap: () => setState(() => _filter = 'all'),
                        ),
                        const SizedBox(width: 8),
                        GlassChipTag(
                          label: '待开奖 $pendingCount',
                          active: _filter == 'pending',
                          onTap: () => setState(() => _filter = 'pending'),
                        ),
                        const SizedBox(width: 8),
                        GlassChipTag(
                          label: '已中奖 $wonCount',
                          active: _filter == 'won',
                          onTap: () => setState(() => _filter = 'won'),
                        ),
                        const SizedBox(width: 8),
                        GlassChipTag(
                          label: '未中 $lostCount',
                          active: _filter == 'lost',
                          onTap: () => setState(() => _filter = 'lost'),
                        ),
                      ],
                    ),
                  ),

                  for (final period in periods) ...[
                    DesignSectionHeader(
                      title: _periodHeaderTitle(period),
                      trailingText: _periodHeaderRight(
                        period,
                        filtered.where((r) => r.period == period).toList(),
                      ),
                    ),
                    for (final item in filtered.where(
                      (r) => r.period == period,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RecordCard(item: item),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _periodHeaderTitle(String period) {
    if (period == '2026277') return '第 2026277 期 · 待开奖';
    return '第 $period 期 · 已结算';
  }

  String _periodHeaderRight(String period, List<BettingRecordItem> items) {
    if (period == '2026277') {
      final sum = items.fold<int>(0, (acc, r) => acc + r.totalAmount);
      return '小计 ¥$sum';
    }
    final net = items.fold<int>(0, (acc, r) => acc + r.netProfit);
    return net >= 0 ? '+¥$net' : '-¥${net.abs()}';
  }
}

class _SummaryCol extends StatelessWidget {
  const _SummaryCol({
    required this.label,
    required this.value,
    required this.sub,
    required this.valueColor,
  });

  final String label;
  final String value;
  final String sub;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.texts.labelSmall?.copyWith(fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(sub, style: context.texts.labelSmall?.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.item});
  final BettingRecordItem item;

  @override
  Widget build(BuildContext context) {
    final isWon = item.status == 'won';
    final isLost = item.status == 'lost';
    final isPending = item.status == 'pending';

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      borderColor: isWon
          ? DuiliaoColors.hit.withValues(alpha: 0.40)
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RecordDetailScreen(record: item)),
      ),
      child: Opacity(
        opacity: isLost ? 0.85 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ZTag(
                      label: item.playType,
                      variant: item.playType.contains('特') ||
                              item.playType.contains('复试')
                          ? ZTagVariant.primary
                          : ZTagVariant.neutral,
                    ),
                    Text(
                      '${item.timeLabel} 录入',
                      style: context.texts.labelSmall,
                    ),
                  ],
                ),
                if (isPending)
                  const GlassStatusPill(
                    label: '待开奖',
                    color: DuiliaoColors.warning,
                  )
                else if (isWon)
                  GlassStatusPill(
                    label:
                        '中 ${item.hitNumbers.length} 码 · +¥${item.netProfit}',
                    color: DuiliaoColors.hit,
                  )
                else
                  const GlassStatusPill(
                    label: '未中 · 0 码',
                    color: DuiliaoColors.pending,
                    showDot: false,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (item.xiaos.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final x in item.xiaos)
                    ZTag(label: x, variant: ZTagVariant.primary),
                ],
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final numStr in item.numbers)
                    NumberBall(
                      number: numStr,
                      bose: Lottery2026Lookup.boseForNumber(
                        int.tryParse(numStr) ?? 1,
                      ),
                      size: 28,
                      hitHighlight: item.hitNumbers.contains(numStr),
                      dimmed: isLost ||
                          (isWon && !item.hitNumbers.contains(numStr)),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.xiaos.isNotEmpty
                              ? '${item.xiaos.length} 肖复试 · 共 ${item.notesCount} 注 × ¥${item.stakePerNote}'
                              : '单注 ¥${item.stakePerNote} × ${item.notesCount} 注',
                          style: context.texts.labelSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.sourceBadge != null) ...[
                        const SizedBox(width: 6),
                        GlassStatusPill(
                          label: item.sourceBadge!,
                          color: Theme.of(context).colorScheme.primary,
                          showDot: false,
                        ),
                      ],
                    ],
                  ),
                ),
                if (isPending)
                  Text(
                    '合计 ¥${item.totalAmount}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                else if (isWon)
                  Text(
                    '投入 ¥${item.totalAmount} · 派彩 ¥${item.payout}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: DuiliaoColors.hit,
                    ),
                  )
                else
                  Text(
                    '-¥${item.totalAmount}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: DuiliaoColors.miss,
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

/// Add Record Screen supporting 号码单式, 连肖复试, and 不中码 (record-add*.html).
class RecordAddScreen extends ConsumerStatefulWidget {
  const RecordAddScreen({
    super.key,
    this.mode = '号码单式',
    this.initialText,
  });

  final String mode;
  final String? initialText;

  @override
  ConsumerState<RecordAddScreen> createState() => _RecordAddScreenState();
}

class _RecordAddScreenState extends ConsumerState<RecordAddScreen> {
  late String _mode;
  Lottery _lottery = Lottery.macau;
  String _period = '2026277';
  late String _selectedPlay;
  late final TextEditingController _inputController;
  late final TextEditingController _stakeController;
  late final TextEditingController _noteController;
  int _multiplier = 1;

  static const _singlePlays = [
    '特码',
    '正码',
    '特肖',
    '平特肖',
    '平特一肖',
    '一肖中特',
    '连肖',
    '杀肖',
    '特码波色',
    '特码单双',
    '特码大小',
    '特码头数',
    '特码尾数',
    '平特尾数',
    '特码合数',
    '家禽野兽',
    '天地肖',
    '男女肖',
    '五行',
    '特码两面',
    'N不中',
  ];

  static const _fushiPlays = ['3连肖 (中3)', '4连肖 (中4)', '5连肖 (中5)'];
  static const _nbuzhongPlays = ['5不中', '6不中', '7不中', '8不中'];

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _selectedPlay = switch (_mode) {
      '连肖复试' => '4连肖 (中4)',
      '不中码' => '5不中',
      _ => '正码',
    };
    _inputController = TextEditingController(
      text: widget.initialText ?? _defaultTextForMode(_mode),
    );
    _stakeController = TextEditingController(
      text: _mode == '连肖复试' ? '6' : '10',
    );
    _noteController = TextEditingController();
  }

  String _defaultTextForMode(String mode) {
    return switch (mode) {
      '连肖复试' => '四连肖复试 兔 龙 蛇 马 羊 各 6',
      '不中码' => '五不中 04 12 19 28 33 41 47 各 10',
      _ => '18-42-39-27-28-37-49-38-2-1各10',
    };
  }

  void _switchMode(String nextMode) {
    if (nextMode == '全部玩法') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PlayCatalogScreen()),
      );
      return;
    }
    setState(() {
      _mode = nextMode;
      _selectedPlay = switch (nextMode) {
        '连肖复试' => '4连肖 (中4)',
        '不中码' => '5不中',
        _ => '正码',
      };
      _inputController.text = _defaultTextForMode(nextMode);
      _stakeController.text = nextMode == '连肖复试' ? '6' : '10';
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _stakeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<String> _parseNumbers(String text) {
    final withoutStake = text.replaceAll(RegExp(r'各\s*\d+.*$'), '');
    final matches = RegExp(r'\b([0-4]?\d)\b').allMatches(withoutStake);
    final result = <String>[];
    for (final m in matches) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n != null && n >= 1 && n <= 49) {
        final formatted = n.toString().padLeft(2, '0');
        if (!result.contains(formatted)) result.add(formatted);
      }
    }
    return result;
  }

  List<String> _parseXiaos(String text) {
    final result = <String>[];
    for (final ch in text.characters) {
      if (Lottery2026Lookup.xiaoList.contains(ch) && !result.contains(ch)) {
        result.add(ch);
      }
    }
    return result;
  }

  List<List<String>> _combinations(List<String> items, int k) {
    if (k <= 0 || k > items.length) return const [];
    final out = <List<String>>[];
    void helper(int start, List<String> current) {
      if (current.length == k) {
        out.add(List<String>.of(current));
        return;
      }
      for (var i = start; i < items.length; i++) {
        current.add(items[i]);
        helper(i + 1, current);
        current.removeLast();
      }
    }

    helper(0, <String>[]);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final text = _inputController.text;
    final parsedStakeMatch = RegExp(r'各\s*(\d+)').firstMatch(text);
    final stake =
        int.tryParse(_stakeController.text.trim()) ??
        int.tryParse(parsedStakeMatch?.group(1) ?? '') ??
        10;

    final numbers = _parseNumbers(text);
    final xiaos = _parseXiaos(text);
    final fushiK = _selectedPlay.startsWith('3')
        ? 3
        : _selectedPlay.startsWith('5')
        ? 5
        : 4;
    final fushiCombos = _mode == '连肖复试'
        ? _combinations(xiaos, fushiK)
        : const <List<String>>[];

    final notesCount = switch (_mode) {
      '连肖复试' => fushiCombos.isEmpty ? 1 : fushiCombos.length,
      '不中码' => 1,
      _ => numbers.isEmpty ? 1 : numbers.length,
    };
    final totalAmount = notesCount * stake * _multiplier;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '新增记录',
                actions: [
                  TextButton(
                    onPressed: () {
                      _inputController.clear();
                      setState(() {});
                    },
                    child: const Text('清空'),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    // 4-mode switcher
                    GlassSegmentedControl<String>(
                      items: const ['号码单式', '连肖复试', '不中码', '全部玩法'],
                      selected: _mode,
                      labelBuilder: (m) => m,
                      onChanged: _switchMode,
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final item in Lottery.all) ...[
                            GlassChipTag(
                              label: item.label,
                              active: item == _lottery,
                              onTap: () => setState(() => _lottery = item),
                            ),
                            const SizedBox(width: 8),
                          ],
                          GlassChipTag(
                            label: '支持 21 种玩法 ›',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const PlayCatalogScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Smart input section
                    DesignSectionHeader(
                      title: '智能录入',
                      trailingText: switch (_mode) {
                        '连肖复试' => '自动拆解复试组合',
                        '不中码' => '所选号码全部不中才算赢',
                        _ => '支持自由格式粘贴',
                      },
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _inputController,
                            maxLines: 3,
                            onChanged: (v) {
                              final m = RegExp(r'各\s*(\d+)').firstMatch(v);
                              if (m != null) {
                                _stakeController.text = m.group(1)!;
                              }
                              setState(() {});
                            },
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              hintText: '粘贴或输入号码/生肖及单注金额…',
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              GlassGhostButton(
                                label: '粘贴剪贴板',
                                icon: Icons.content_paste_rounded,
                                compact: true,
                                onTap: () async {
                                  final data = await Clipboard.getData(
                                    'text/plain',
                                  );
                                  if (data?.text != null &&
                                      data!.text!.trim().isNotEmpty) {
                                    _inputController.text = data.text!.trim();
                                    setState(() {});
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              GlassGhostButton(
                                label: '跳码助手',
                                icon: Icons.auto_awesome_motion,
                                compact: true,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const JumpCodeAssistantScreen(),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _mode == '连肖复试'
                                    ? '例: 兔龙蛇马羊各6'
                                    : '例: 18-42-39各10',
                                style: context.texts.labelSmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Recognition Preview
                    DesignSectionHeader(
                      title: '识别预览',
                      trailingText: _mode == '连肖复试'
                          ? '已选 ${xiaos.length} 肖 · $_selectedPlay · 共 $notesCount 注'
                          : '共 ${numbers.length} 个号码 · 单注 ¥$stake',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_mode == '连肖复试')
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final x in xiaos)
                                  ZTag(
                                    label: '$x肖',
                                    variant: ZTagVariant.primary,
                                  ),
                                if (xiaos.isEmpty)
                                  Text(
                                    '请输入至少 $fushiK 个生肖',
                                    style: context.texts.bodySmall,
                                  ),
                              ],
                            )
                          else
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (final nStr in numbers)
                                  NumberBall(
                                    number: nStr,
                                    bose: Lottery2026Lookup.boseForNumber(
                                      int.tryParse(nStr) ?? 1,
                                    ),
                                    caption: _mode == '不中码' ? '不中' : '¥$stake',
                                    captionBold: _mode == '不中码',
                                    captionColor: _mode == '不中码'
                                        ? DuiliaoColors.warning
                                        : null,
                                  ),
                              ],
                            ),
                          if (_mode == '不中码') ...[
                            const SizedBox(height: 12),
                            GlassSubtleBox(
                              padding: const EdgeInsets.all(11),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '中奖条件：以上 ${numbers.length} 个号码全部不出现在开奖 7 码（6正+1特）中',
                                      style: context.texts.labelSmall,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const GlassStatusPill(
                                    label: '全不中即赢',
                                    color: DuiliaoColors.hit,
                                    showDot: false,
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const GlassStatusPill(
                                label: '解析成功',
                                color: DuiliaoColors.hit,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _mode == '连肖复试'
                                      ? 'C(${xiaos.length},$fushiK) = $notesCount 组 · 每组 ¥$stake'
                                      : '自动补零 · 已去重',
                                  style: context.texts.labelSmall,
                                ),
                              ),
                              Text(
                                '合计 ¥$totalAmount',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Combination Expansion for 连肖复试
                    if (_mode == '连肖复试' && fushiCombos.isNotEmpty) ...[
                      DesignSectionHeader(
                        title: '组合展开',
                        trailingText: '共 ${fushiCombos.length} 注 · 全部中出即赢',
                      ),
                      GlassGroup(
                        margin: EdgeInsets.zero,
                        children: [
                          for (var i = 0; i < fushiCombos.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 48,
                                    child: Text(
                                      '第 ${i + 1} 注',
                                      style: context.texts.labelSmall,
                                    ),
                                  ),
                                  Expanded(
                                    child: Wrap(
                                      spacing: 6,
                                      children: [
                                        for (final x in fushiCombos[i])
                                          ZTag(label: x),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '¥$stake',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],

                    // Recognition Rules
                    const DesignSectionHeader(title: '识别规则'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: switch (_mode) {
                          '连肖复试' => const [
                            _RuleBullet('生肖支持空格、连字符、顿号或直接连写：「兔龙蛇马羊」'),
                            SizedBox(height: 6),
                            _RuleBullet('支持「三连/四连/五连复试」关键字自动匹配连肖阶数'),
                            SizedBox(height: 6),
                            _RuleBullet('自动按组合公式 C(M,N) 拆解注数并计算总投入'),
                          ],
                          '不中码' => const [
                            _RuleBullet('支持「五不中 ~ 十二不中」关键字自动切换玩法阶数'),
                            SizedBox(height: 6),
                            _RuleBullet('号码范围 01–49，自动去重并校验最少号码数量'),
                            SizedBox(height: 6),
                            _RuleBullet('对奖口径：所选号码与当期 6 正码 + 特码均不重合即判定中奖'),
                          ],
                          _ => const [
                            _RuleBullet('号码可用 - 、 空格 , / 任意分隔，单数自动补 0（2 → 02）'),
                            SizedBox(height: 6),
                            _RuleBullet('金额支持「各10」「各 10 元」「*10」「@10」多种写法'),
                            SizedBox(height: 6),
                            _RuleBullet('支持多行混合录入，每行独立识别金额并自动汇总'),
                          ],
                        },
                      ),
                    ),

                    // Record Info Card
                    const DesignSectionHeader(title: '记录信息'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('期号', style: context.texts.labelSmall),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              GlassChipTag(
                                label: '第 2026277 期 · 今晚开奖',
                                active: _period == '2026277',
                                onTap: () =>
                                    setState(() => _period = '2026277'),
                              ),
                              GlassChipTag(
                                label: '第 2026276 期 (补录)',
                                active: _period == '2026276',
                                onTap: () =>
                                    setState(() => _period = '2026276'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _mode == '连肖复试'
                                ? '连肖阶数'
                                : _mode == '不中码'
                                ? '不中阶数'
                                : '玩法类型 (全部 21 种)',
                            style: context.texts.labelSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final p in switch (_mode) {
                                '连肖复试' => _fushiPlays,
                                '不中码' => _nbuzhongPlays,
                                _ => _singlePlays,
                              })
                                GlassChipTag(
                                  label: p,
                                  active: _selectedPlay == p,
                                  onTap: () =>
                                      setState(() => _selectedPlay = p),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _mode == '连肖复试'
                                          ? '每注金额 (元)'
                                          : '单注金额 (元)',
                                      style: context.texts.labelSmall,
                                    ),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _stakeController,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '倍数',
                                      style: context.texts.labelSmall,
                                    ),
                                    const SizedBox(height: 6),
                                    GlassSubtleBox(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          GlassGhostButton(
                                            label: '−',
                                            compact: true,
                                            onTap: () => setState(() {
                                              if (_multiplier > 1) {
                                                _multiplier--;
                                              }
                                            }),
                                          ),
                                          Text(
                                            '$_multiplier 倍',
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          GlassGhostButton(
                                            label: '+',
                                            compact: true,
                                            onTap: () => setState(() {
                                              _multiplier++;
                                            }),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text('备注 (可选)', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _noteController,
                            decoration: const InputDecoration(
                              hintText: '例如：参考海哥 + 顶尖大师共识',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Bottom action dock
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xE6141122)
                      : Colors.white.withValues(alpha: 0.90),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$notesCount 注 · 合计',
                            style: context.texts.labelSmall,
                          ),
                          Text(
                            '¥$totalAmount',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GlassButton(
                        onPressed: () {
                          final item = BettingRecordItem(
                            id: 'rec-${DateTime.now().millisecondsSinceEpoch}',
                            lottery: _lottery,
                            period: _period,
                            playType: _selectedPlay,
                            timeLabel: '刚刚',
                            numbers: numbers,
                            xiaos: xiaos,
                            stakePerNote: stake,
                            multiplier: _multiplier,
                            notesCount: notesCount,
                            totalAmount: totalAmount,
                            status: 'pending',
                            rawInput: _inputController.text.trim(),
                            note: _noteController.text.trim().isEmpty
                                ? null
                                : _noteController.text.trim(),
                          );
                          ref
                              .read(bettingRecordsProvider.notifier)
                              .addRecord(item);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('记录已保存')),
                          );
                          Navigator.of(context).maybePop();
                        },
                        child: const Text('保存记录'),
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

class _RuleBullet extends StatelessWidget {
  const _RuleBullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• ',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: context.texts.labelSmall?.copyWith(height: 1.45),
          ),
        ),
      ],
    );
  }
}

/// Record Detail Screen (record-detail.html).
class RecordDetailScreen extends ConsumerWidget {
  const RecordDetailScreen({super.key, this.record});

  final BettingRecordItem? record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item =
        record ??
        _defaultRecords.firstWhere(
          (r) => r.id == 'rec-276-1',
          orElse: () => _defaultRecords.first,
        );
    final isWon = item.status == 'won';
    final isPending = item.status == 'pending';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '记录详情',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    // Hero Settlement Card
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(20),
                      borderColor: isWon
                          ? DuiliaoColors.hit.withValues(alpha: 0.45)
                          : null,
                      child: Column(
                        children: [
                          GlassStatusPill(
                            label: isPending
                                ? '待开奖'
                                : isWon
                                ? '已中奖'
                                : '未中奖',
                            color: isPending
                                ? DuiliaoColors.warning
                                : isWon
                                ? DuiliaoColors.hit
                                : DuiliaoColors.miss,
                            pulse: isPending,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isPending
                                ? '¥${item.totalAmount}'
                                : isWon
                                ? '+¥${item.netProfit}'
                                : '-¥${item.totalAmount}',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: isPending
                                  ? Theme.of(context).colorScheme.onSurface
                                  : isWon
                                  ? DuiliaoColors.hit
                                  : DuiliaoColors.miss,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '第 ${item.period} 期 · ${item.playType} · ${isPending ? '等待开奖' : '已对奖'}',
                            style: context.texts.labelSmall,
                          ),
                        ],
                      ),
                    ),

                    // My Numbers
                    DesignSectionHeader(
                      title: '我的号码',
                      trailingText: isPending
                          ? '共 ${item.numbers.length} 码'
                          : '中 ${item.hitNumbers.length} / ${item.numbers.length} 码',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: item.xiaos.isNotEmpty
                          ? Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final x in item.xiaos)
                                  ZTag(label: '$x肖', variant: ZTagVariant.primary),
                              ],
                            )
                          : Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.spaceAround,
                              children: [
                                for (final nStr in item.numbers)
                                  NumberBall(
                                    number: nStr,
                                    bose: Lottery2026Lookup.boseForNumber(
                                      int.tryParse(nStr) ?? 1,
                                    ),
                                    size: 40,
                                    hitHighlight: item.hitNumbers.contains(
                                      nStr,
                                    ),
                                    dimmed: !isPending &&
                                        !item.hitNumbers.contains(nStr),
                                    caption: isPending
                                        ? '¥${item.stakePerNote}'
                                        : item.hitNumbers.contains(nStr)
                                        ? '中'
                                        : '未中',
                                    captionBold: item.hitNumbers.contains(nStr),
                                    captionColor: item.hitNumbers.contains(nStr)
                                        ? DuiliaoColors.hit
                                        : null,
                                  ),
                              ],
                            ),
                    ),

                    // Draw Comparison
                    const DesignSectionHeader(title: '开奖对照'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '第 ${item.period} 期开奖号码',
                                style: context.texts.labelSmall,
                              ),
                              Text(
                                '09-25 21:32',
                                style: context.texts.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (final n in [
                                '03',
                                '11',
                                '19',
                                '27',
                                '34',
                                '42',
                              ])
                                NumberBall(
                                  number: n,
                                  bose: Lottery2026Lookup.boseForNumber(
                                    int.parse(n),
                                  ),
                                  size: 28,
                                ),
                              const Text(
                                '+',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const NumberBall(
                                number: '26',
                                bose: 'blue',
                                isGold: true,
                                size: 28,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GlassStatusPill(
                            label:
                                '号码命中 ${item.hitNumbers.length} 个 · 命中率 ${item.numbers.isEmpty ? 0 : (item.hitNumbers.length / item.numbers.length * 100).round()}%',
                            color: DuiliaoColors.hit,
                          ),
                        ],
                      ),
                    ),

                    // Settlement Details
                    const DesignSectionHeader(title: '结算明细'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        _DetailRow(
                          label: '投入金额',
                          sub: '¥${item.stakePerNote} × ${item.notesCount} 注 × ${item.multiplier} 倍',
                          value: '¥${item.totalAmount}',
                        ),
                        _DetailRow(
                          label: '中单注数',
                          sub: item.hitNumbers.isEmpty
                              ? '无命中号码'
                              : '命中号码 ${item.hitNumbers.join(' / ')}',
                          value: '${item.hitNumbers.length} 注',
                          valueColor: DuiliaoColors.hit,
                        ),
                        _DetailRow(
                          label: '派彩金额',
                          sub: '按个人记录赔率计算',
                          value: '¥${item.payout}',
                          valueColor: DuiliaoColors.hit,
                        ),
                        _DetailRow(
                          label: '本期盈亏',
                          sub: '派彩 − 投入',
                          value: item.netProfit >= 0
                              ? '+¥${item.netProfit}'
                              : '-¥${item.netProfit.abs()}',
                          valueColor: item.netProfit >= 0
                              ? DuiliaoColors.hit
                              : DuiliaoColors.miss,
                        ),
                      ],
                    ),

                    // Raw Input
                    const DesignSectionHeader(title: '原始录入'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.rawInput.isEmpty ? '—' : item.rawInput,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '录入时间 ${item.timeLabel}${item.note == null ? '' : ' · 备注：${item.note}'}',
                            style: context.texts.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Bottom action bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  children: [
                    GlassGhostButton(
                      label: '复制格式',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: item.rawInput));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制原始录入格式')),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    GlassGhostButton(
                      label: '删除',
                      isDanger: true,
                      onTap: () {
                        ref
                            .read(bettingRecordsProvider.notifier)
                            .removeRecord(item.id);
                        Navigator.of(context).maybePop();
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GlassButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => RecordAddScreen(
                                initialText: item.rawInput,
                              ),
                            ),
                          );
                        },
                        child: const Text('再来一单'),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.sub,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String sub;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(sub, style: context.texts.labelSmall),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Record Stats Screen (record-stats.html).
class RecordStatsScreen extends StatefulWidget {
  const RecordStatsScreen({super.key});

  @override
  State<RecordStatsScreen> createState() => _RecordStatsScreenState();
}

class _RecordStatsScreenState extends State<RecordStatsScreen> {
  String _window = '30';

  static const _dailyPnl = [
    ('09-20', 40),
    ('09-21', -30),
    ('09-22', 65),
    ('09-23', -20),
    ('09-24', 10),
    ('09-25', 95),
    ('09-26', 15),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '盈亏统计',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  children: [
                    GlassSegmentedControl<String>(
                      items: const ['7', '30', '90'],
                      selected: _window,
                      labelBuilder: (w) => '近 $w 天',
                      onChanged: (v) => setState(() => _window = v),
                    ),
                    const SizedBox(height: 12),

                    // 2x2 KPI Grid
                    GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.55,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _StatKpiCard(
                          label: '总投入',
                          value: '¥1,290',
                          delta: '47 单 · 268 注',
                        ),
                        const _StatKpiCard(
                          label: '总派彩',
                          value: '¥1,465',
                          valueColor: DuiliaoColors.hit,
                          delta: '中 15 单 · 39 码',
                          deltaColor: DuiliaoColors.hit,
                        ),
                        const _StatKpiCard(
                          label: '净盈亏',
                          value: '+¥175',
                          valueColor: DuiliaoColors.hit,
                          delta: '回报率 +13.6%',
                          deltaColor: DuiliaoColors.hit,
                        ),
                        _StatKpiCard(
                          label: '中单率',
                          value: '31.9%',
                          valueColor: Theme.of(context).colorScheme.primary,
                          delta: '最高连中 4 期',
                        ),
                      ],
                    ),

                    // Bidirectional Daily PnL Chart
                    const DesignSectionHeader(
                      title: '每日盈亏',
                      trailingText: '近 7 期',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 132,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                                Row(
                                  children: [
                                    for (final bar in _dailyPnl)
                                      Expanded(
                                        child: _BiBarColumn(
                                          date: bar.$1,
                                          value: bar.$2,
                                        ),
                                      ),
                                  ],
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
                                '盈利 5 期 · 亏损 2 期',
                                style: context.texts.labelSmall,
                              ),
                              const Text(
                                '7 期合计 +¥175',
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

                    // Play Distribution
                    const DesignSectionHeader(title: '玩法分布'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '正码',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '36 单 · 投入 ¥980',
                                style: context.texts.labelSmall,
                              ),
                              const Text(
                                '+¥145',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: DuiliaoColors.hit,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const GlassLinearProgress(
                            value: 0.76,
                            color: DuiliaoColors.hit,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '特码',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '11 单 · 投入 ¥310',
                                style: context.texts.labelSmall,
                              ),
                              Text(
                                '+¥30',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const GlassLinearProgress(value: 0.24),
                        ],
                      ),
                    ),

                    // Frequent Hit Numbers
                    const DesignSectionHeader(
                      title: '常中号码',
                      trailingText: '个人命中 Top',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          NumberBall(
                            number: '26',
                            bose: 'blue',
                            caption: '中 4 次',
                            captionBold: true,
                            captionColor: DuiliaoColors.hit,
                          ),
                          NumberBall(
                            number: '11',
                            bose: 'green',
                            caption: '中 3 次',
                            captionBold: true,
                            captionColor: DuiliaoColors.hit,
                          ),
                          NumberBall(
                            number: '07',
                            bose: 'red',
                            caption: '中 3 次',
                            captionBold: true,
                            captionColor: DuiliaoColors.hit,
                          ),
                          NumberBall(
                            number: '42',
                            bose: 'blue',
                            caption: '中 2 次',
                          ),
                          NumberBall(
                            number: '19',
                            bose: 'red',
                            caption: '中 2 次',
                          ),
                        ],
                      ),
                    ),

                    // Monthly Summary
                    const DesignSectionHeader(title: '月度小结'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: const [
                        _DetailRow(
                          label: '2026 年 9 月',
                          sub: '47 单 · 中单率 31.9%',
                          value: '+¥175',
                          valueColor: DuiliaoColors.hit,
                        ),
                        _DetailRow(
                          label: '2026 年 8 月',
                          sub: '62 单 · 中单率 27.4%',
                          value: '-¥85',
                          valueColor: DuiliaoColors.miss,
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
    );
  }
}

class _StatKpiCard extends StatelessWidget {
  const _StatKpiCard({
    required this.label,
    required this.value,
    required this.delta,
    this.valueColor,
    this.deltaColor,
  });

  final String label;
  final String value;
  final String delta;
  final Color? valueColor;
  final Color? deltaColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.texts.labelSmall),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          Text(
            delta,
            style: context.texts.labelSmall?.copyWith(
              color: deltaColor,
              fontWeight: deltaColor != null ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _BiBarColumn extends StatelessWidget {
  const _BiBarColumn({required this.date, required this.value});

  final String date;
  final int value;

  @override
  Widget build(BuildContext context) {
    final isPos = value >= 0;
    final barHeight = (value.abs() / 100.0 * 44.0).clamp(6.0, 44.0);
    return Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: isPos
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+$value',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: DuiliaoColors.hit,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 14,
                        height: barHeight,
                        decoration: const BoxDecoration(
                          color: DuiliaoColors.hit,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: !isPos
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: barHeight,
                        decoration: const BoxDecoration(
                          color: DuiliaoColors.miss,
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$value',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: DuiliaoColors.miss,
                        ),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      date,
                      style: context.texts.labelSmall?.copyWith(fontSize: 9.5),
                    ),
                  ),
          ),
        ),
        if (!isPos)
          Text(
            date,
            style: context.texts.labelSmall?.copyWith(fontSize: 9.5),
          ),
      ],
    );
  }
}
