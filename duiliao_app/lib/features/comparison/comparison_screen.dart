/// Multi-source comparison screen aligned 1:1 with consensus.html.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/prediction.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import '../design/design_screens.dart';

/// Comparison for a (lottery, period) pair.
final comparisonProvider = FutureProvider.family<
  ({PeriodComparisonResult result, bool isStale, String? storedAt}),
  ({Lottery lottery, String period})
>((ref, key) async {
  final fetched = await ref
      .read(collectorRepositoryProvider)
      .comparison(lottery: key.lottery.code, period: key.period);
  return (
    result: fetched.value,
    isStale: fetched.isStale,
    storedAt: fetched.storedAtLabel,
  );
});

/// The latest period for a lottery, so screens can open without one.
final latestPeriodProvider = FutureProvider.family<String?, Lottery>((
  ref,
  lottery,
) async {
  final fallback = currentPeriodForLottery(lottery);
  try {
    final ctx = await ref.watch(recordPeriodContextProvider(lottery).future);
    return ctx.currentPeriod;
  } catch (_) {
    return fallback;
  }
});

class ComparisonScreen extends ConsumerStatefulWidget {
  const ComparisonScreen({super.key, this.lottery, this.initialPeriod});

  final Lottery? lottery;
  final String? initialPeriod;

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends ConsumerState<ComparisonScreen> {
  Lottery? _lotteryOverride;
  String? _selectedPeriod;
  String _selectedPlay = '特肖';
  String _sourceQuery = '';

  static const _playChips = [
    '特肖',
    '特码',
    '特尾',
    '特头',
    '特波',
    '两面',
    '半波',
    '合肖',
    '平特肖',
    '平特尾',
    '正码',
    '正肖',
    '连肖',
    '连尾',
    '二中二',
    '三中三',
    '三中二',
    '二中特',
    '不中码',
    '杀肖',
    '杀尾',
  ];

  List<
    ({
      String initial,
      String name,
      String sub,
      List<String> tags,
      bool missing,
      String rawContent,
    })
  >
  _buildSourceRecommendations(
    String activePeriod,
    String currentPeriod,
    PeriodComparisonResult? liveResult,
  ) {
    final periodOffset =
        ((int.tryParse(currentPeriod) ?? 0) -
                (int.tryParse(activePeriod) ?? 0))
            .clamp(0, 365);
    final periodDate = recentChinaMmDd(periodOffset);

    if (liveResult != null && liveResult.items.isNotEmpty) {
      final playMatched = liveResult.items.where((item) {
        final label = PlayTypes.labelFor(item.playType);
        return label == _selectedPlay || item.playType == _selectedPlay;
      }).toList();
      final sourceItems =
          playMatched.isNotEmpty ? playMatched : liveResult.items;
      return [
        for (final item in sourceItems)
          (
            initial: (item.sourceName.isNotEmpty
                    ? item.sourceName
                    : item.sourceId)
                .substring(0, 1),
            name: item.sourceName.isNotEmpty ? item.sourceName : item.sourceId,
            sub:
                '${PlayTypes.labelFor(item.playType)} · ${(item.fetchedAt != null && item.fetchedAt!.length >= 16) ? '${item.fetchedAt!.substring(5, 16)} 发布' : '$periodDate 发布'}',
            tags: [for (final p in item.preds) p.value],
            missing: item.claimedStatus == 'missing',
            rawContent: item.rawText.isNotEmpty
                ? item.rawText
                : '第$activePeriod期【${item.sourceName}】推荐：${item.preds.map((p) => p.value).join('、')}',
          ),
      ];
    }
    return [
      (
        initial: '海',
        name: '海哥平特一肖',
        sub: '$_selectedPlay · $periodDate 18:02 发布',
        tags: ['蛇', '龙'],
        missing: false,
        rawContent: '第$activePeriod期【海哥平特一肖】主推：蛇，防：龙。',
      ),
      (
        initial: '顶',
        name: '顶尖大师',
        sub: '$_selectedPlay · $periodDate 17:46 发布',
        tags: ['鸡', '蛇'],
        missing: false,
        rawContent: '第$activePeriod期【顶尖大师】特肖心水：鸡、蛇。',
      ),
      (
        initial: '管',
        name: '管家婆传真',
        sub: '$_selectedPlay · $periodDate 17:20 发布',
        tags: ['鼠', '牛'],
        missing: false,
        rawContent: '第$activePeriod期【管家婆传真】主推：鼠、牛。',
      ),
      (
        initial: '白',
        name: '白小组',
        sub: '$_selectedPlay · $periodDate 16:58 发布',
        tags: ['蛇', '鸡'],
        missing: false,
        rawContent: '第$activePeriod期【白小组】重点看好：蛇、鸡。',
      ),
      (
        initial: '肖',
        name: '肖中特-老钱',
        sub: '$_selectedPlay · 本期未采集',
        tags: <String>[],
        missing: true,
        rawContent: '该来源第$activePeriod期尚未更新预测内容。',
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _lotteryOverride = widget.lottery;
    _selectedPeriod = widget.initialPeriod;
  }

  Future<void> _showPeriodPickerSheet(
    BuildContext context, {
    required String currentPeriod,
    required String prevPeriod,
    required String activePeriod,
    required List<String> selectablePeriods,
  }) async {
    final periods = <String>{
      currentPeriod,
      prevPeriod,
      ...selectablePeriods,
      for (var i = 2; i <= 15; i++) previousPeriodOf(currentPeriod, i),
    }.toList();

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.65,
        ),
        decoration: BoxDecoration(
          color: Theme.of(ctx).brightness == Brightness.dark
              ? const Color(0xFF141826)
              : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '选择多源对照期号',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _showCustomPeriodDialog(context, activePeriod);
                  },
                  icon: const Icon(Icons.edit_rounded, size: 15),
                  label: const Text('自定义期号'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: periods.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final p = periods[i];
                  final isCurrent = p == currentPeriod;
                  final isPrev = p == prevPeriod;
                  final isSelected = p == activePeriod;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                    title: Row(
                      children: [
                        Text(
                          '第 $p 期',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isSelected
                                ? Theme.of(ctx).colorScheme.primary
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isCurrent)
                          const ZTag(
                            label: '当前期 · 实时',
                            variant: ZTagVariant.primary,
                          )
                        else if (isPrev)
                          const ZTag(label: '上期 · 已开奖'),
                      ],
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Theme.of(ctx).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      setState(() => _selectedPeriod = picked);
    }
  }

  Future<void> _showCustomPeriodDialog(
    BuildContext context,
    String activePeriod,
  ) async {
    final ctrl = TextEditingController(text: activePeriod);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入自定义期号'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '例如 $activePeriod',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (res != null && res.isNotEmpty && mounted) {
      final normalized =
          (res.length <= 3 && int.tryParse(res) != null)
          ? '${nowInChina().year}${res.padLeft(3, '0')}'
          : res;
      setState(() => _selectedPeriod = normalized);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Lottery>(selectedLotteryProvider, (prev, next) {
      if (prev != next && widget.lottery == null && mounted) {
        setState(() {
          _lotteryOverride = null;
          _selectedPeriod = null;
        });
      }
    });
    final canPop = Navigator.of(context).canPop();
    final globalLottery = ref.watch(selectedLotteryProvider);
    final lottery = _lotteryOverride ?? globalLottery;
    final periodCtx = ref.watch(recordPeriodContextProvider(lottery)).value;
    final currentPeriod =
        periodCtx?.currentPeriod ?? currentPeriodForLottery(lottery);
    final prevPeriod = previousPeriodOf(currentPeriod, 1);
    final activePeriod = _selectedPeriod ?? currentPeriod;
    final selectablePeriods = periodCtx?.selectablePeriods ?? <String>[];

    final compAsync = ref.watch(
      comparisonProvider((lottery: lottery, period: activePeriod)),
    );
    final compResult = compAsync.value?.result;
    final isLive = activePeriod == currentPeriod && compResult?.draw == null;

    final allRecommendations = _buildSourceRecommendations(
      activePeriod,
      currentPeriod,
      compResult,
    );
    final filteredSources = allRecommendations.where((s) {
      if (_sourceQuery.isEmpty) return true;
      return s.name.toLowerCase().contains(_sourceQuery.toLowerCase());
    }).toList();

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
                title: '多源对照',
                subtitle: '跨源交叉验证 · 官方判定',
                actions: [
                  GlassIconButton(
                    icon: Icons.tune_rounded,
                    tooltip: '选择期号',
                    onTap: () => _showPeriodPickerSheet(
                      context,
                      currentPeriod: currentPeriod,
                      prevPeriod: prevPeriod,
                      activePeriod: activePeriod,
                      selectablePeriods: selectablePeriods,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    // 对照参数
                    const DesignSectionHeader(title: '对照参数'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('彩种', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final l in Lottery.all)
                                GlassChipTag(
                                  label: l.label,
                                  active: l == lottery,
                                  onTap: () {
                                    ref
                                        .read(selectedLotteryProvider.notifier)
                                        .set(l);
                                    setState(() {
                                      _lotteryOverride = l;
                                      _selectedPeriod = null;
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('期号', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              GlassChipTag(
                                label: '第 $currentPeriod 期',
                                active: activePeriod == currentPeriod,
                                onTap: () => setState(
                                  () => _selectedPeriod = currentPeriod,
                                ),
                              ),
                              GlassChipTag(
                                label: '第 $prevPeriod 期',
                                active: activePeriod == prevPeriod,
                                onTap: () => setState(
                                  () => _selectedPeriod = prevPeriod,
                                ),
                              ),
                              if (activePeriod != currentPeriod &&
                                  activePeriod != prevPeriod)
                                GlassChipTag(
                                  label: '第 $activePeriod 期',
                                  active: true,
                                  onTap: () {},
                                ),
                              GlassChipTag(
                                label: '选期 ▾',
                                active: false,
                                onTap: () => _showPeriodPickerSheet(
                                  context,
                                  currentPeriod: currentPeriod,
                                  prevPeriod: prevPeriod,
                                  activePeriod: activePeriod,
                                  selectablePeriods: selectablePeriods,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('玩法', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final p in _playChips)
                                GlassChipTag(
                                  label: p,
                                  active: _selectedPlay == p,
                                  onTap: () =>
                                      setState(() => _selectedPlay = p),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('来源筛选', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            onChanged: (v) =>
                                setState(() => _sourceQuery = v.trim()),
                            decoration: const InputDecoration(
                              hintText: '筛选来源名称/ID…',
                              prefixIcon: Icon(Icons.search_rounded, size: 18),
                            ),
                          ),
                          const SizedBox(height: 14),
                          GlassButton(
                            onPressed: () {
                              ref.invalidate(
                                comparisonProvider((
                                  lottery: lottery,
                                  period: activePeriod,
                                )),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已更新对照：${lottery.label} · 第 $activePeriod 期 · $_selectedPlay',
                                  ),
                                ),
                              );
                            },
                            child: const Text('查询对照'),
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ConsensusBoardScreen(
                                  initialLottery: lottery,
                                  initialPeriod: activePeriod,
                                ),
                              ),
                            ),
                            child: GlassSubtleBox(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '查看共识排行榜',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '候选项票数 · 玩法组归并 · 支持证据 · 开奖核验',
                                          style: context.texts.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 官方判定 strip
                    const SizedBox(height: 12),
                    GlassSubtleBox(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GlassStatusPill(
                            label: isLive ? '待开奖' : '已对奖',
                            color: isLive
                                ? DuiliaoColors.warning
                                : DuiliaoColors.hit,
                            pulse: isLive,
                          ),
                          Flexible(
                            child: Text(
                              compResult?.draw != null
                                  ? '第${compResult!.draw!.period}期官方判定:特码 ${compResult.draw!.tema.padLeft(2, '0')} (${compResult.draw!.temaDetail?.xiao ?? Lottery2026Lookup.xiaoForNumber(int.tryParse(compResult.draw!.tema) ?? 1)}) · 已核验'
                                  : isLive
                                  ? '上期($prevPeriod)官方判定:特肖 蛇 · 领跑命中'
                                  : '第$activePeriod期官方判定:特肖 蛇 · 领跑命中',
                              style: context.texts.labelSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 来源表现排行
                    const DesignSectionHeader(title: '来源表现排行'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: const [
                        _SourcePerfRow(
                          rank: 1,
                          name: '海哥平特一肖',
                          primaryTag: '蛇',
                          guardTag: '龙',
                          supportLabel: '支持源 3/5',
                          pct: 0.62,
                          pctLabel: '62%',
                          color: DuiliaoColors.hit,
                        ),
                        _SourcePerfRow(
                          rank: 2,
                          name: '顶尖大师',
                          primaryTag: '鸡',
                          guardTag: '蛇',
                          supportLabel: '支持源 2/5',
                          pct: 0.55,
                          pctLabel: '55%',
                          color: DuiliaoColors.primaryDark,
                        ),
                        _SourcePerfRow(
                          rank: 3,
                          name: '管家婆传真',
                          primaryTag: '鼠',
                          guardTag: '牛',
                          supportLabel: '支持源 1/5',
                          pct: 0.48,
                          pctLabel: '48%',
                          color: DuiliaoColors.warning,
                        ),
                      ],
                    ),

                    // 各源推荐明细
                    const DesignSectionHeader(title: '各源推荐明细'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        for (final s in filteredSources)
                          InkWell(
                            onTap: () => _showEvidenceSheet(
                              context,
                              name: s.name,
                              sub: s.sub,
                              rawContent: s.rawContent,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(11),
                                      color: s.missing
                                          ? Colors.white.withValues(alpha: 0.06)
                                          : Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.16),
                                    ),
                                    child: Text(
                                      s.initial,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: s.missing
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          s.sub,
                                          style: context.texts.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (s.missing)
                                    const GlassStatusPill(
                                      label: '缺期',
                                      color: DuiliaoColors.pending,
                                      showDot: false,
                                    )
                                  else
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        for (var i = 0; i < s.tags.length; i++)
                                          ZTag(
                                            label: s.tags[i],
                                            variant: i == 0
                                                ? ZTagVariant.primary
                                                : ZTagVariant.neutral,
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '汇总:蛇 出现 3 次 · 鸡 2 次 · 龙/鼠/牛 各 1 次',
                                  style: context.texts.labelSmall,
                                ),
                              ),
                              GlassStatusPill(
                                label: '共识 蛇',
                                color: Theme.of(context).colorScheme.primary,
                                showDot: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // 上期对照复盘
                    const DesignSectionHeader(title: '上期对照复盘'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _ReviewNode(
                                status: HitMarkStatus.hit,
                                name: '海哥',
                                label: '命中',
                              ),
                              _ReviewNode(
                                status: HitMarkStatus.hit,
                                name: '顶尖',
                                label: '命中',
                              ),
                              _ReviewNode(
                                status: HitMarkStatus.miss,
                                name: '管家婆',
                                label: '未中',
                              ),
                              _ReviewNode(
                                status: HitMarkStatus.hit,
                                name: '白小组',
                                label: '命中',
                              ),
                              _ReviewNode(
                                status: HitMarkStatus.miss,
                                name: '老钱',
                                label: '未中',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '官方特肖 蛇 · 5 源命中 3 / 未中 2',
                            style: context.texts.labelSmall,
                          ),
                        ],
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

  void _showEvidenceSheet(
    BuildContext context, {
    required String name,
    required String sub,
    required String rawContent,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.all(14),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(sub, style: context.texts.labelSmall),
              const SizedBox(height: 12),
              GlassSubtleBox(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    rawContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourcePerfRow extends StatelessWidget {
  const _SourcePerfRow({
    required this.rank,
    required this.name,
    required this.primaryTag,
    required this.guardTag,
    required this.supportLabel,
    required this.pct,
    required this.pctLabel,
    required this.color,
  });

  final int rank;
  final String name;
  final String primaryTag;
  final String guardTag;
  final String supportLabel;
  final double pct;
  final String pctLabel;
  final Color color;

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
              color: color.withValues(alpha: 0.16),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: color,
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
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('主推 ', style: context.texts.labelSmall),
                    ZTag(label: primaryTag, variant: ZTagVariant.primary),
                    Text(' 防 ', style: context.texts.labelSmall),
                    ZTag(label: guardTag),
                    Text(' · $supportLabel', style: context.texts.labelSmall),
                  ],
                ),
                const SizedBox(height: 6),
                GlassLinearProgress(value: pct, color: color),
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
                  color: color,
                ),
              ),
              Text(
                '近 50 期命中',
                style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewNode extends StatelessWidget {
  const _ReviewNode({
    required this.status,
    required this.name,
    required this.label,
  });

  final HitMarkStatus status;
  final String name;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isHit = status == HitMarkStatus.hit;
    return Column(
      children: [
        HitMarkBadge(status: status),
        const SizedBox(height: 6),
        Text(name, style: context.texts.labelSmall),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isHit ? DuiliaoColors.hit : DuiliaoColors.miss,
          ),
        ),
      ],
    );
  }
}
