/// Multi-source comparison screen aligned 1:1 with consensus.html.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/prediction.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
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
  final cn = DateTime.now().toUtc().add(const Duration(hours: 8));
  final doy = cn.difference(DateTime.utc(cn.year, 1, 1)).inDays + 1;
  final fallback = '${cn.year}${doy.toString().padLeft(3, '0')}';
  try {
    final res = await ref
        .read(apiClientProvider)
        .get('/collector/consensus/latest', query: {'lottery': lottery.code});
    final current = res['current_period']?.toString();
    if (current != null && current.isNotEmpty) return current;
  } catch (_) {}
  try {
    final draws = await ref
        .read(collectorRepositoryProvider)
        .draws(lottery: lottery.code, limit: 1);
    return draws.value.items.isEmpty ? fallback : draws.value.items.first.period;
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
  late Lottery _lottery;
  late String _period;
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

  static const _sourceRecommendations = [
    (
      initial: '海',
      name: '海哥平特一肖',
      sub: '特肖 · 09-27 18:02 发布',
      tags: ['蛇', '龙'],
      missing: false,
      rawContent: '第2026277期【海哥平特一肖】主推：蛇，防：龙。',
    ),
    (
      initial: '顶',
      name: '顶尖大师',
      sub: '特肖 · 09-27 17:46 发布',
      tags: ['鸡', '蛇'],
      missing: false,
      rawContent: '第2026277期【顶尖大师】特肖心水：鸡、蛇。',
    ),
    (
      initial: '管',
      name: '管家婆传真',
      sub: '特肖 · 09-27 17:20 发布',
      tags: ['鼠', '牛'],
      missing: false,
      rawContent: '第2026277期【管家婆传真】主推：鼠、牛。',
    ),
    (
      initial: '白',
      name: '白小组',
      sub: '特肖 · 09-27 16:58 发布',
      tags: ['蛇', '鸡'],
      missing: false,
      rawContent: '第2026277期【白小组】重点看好：蛇、鸡。',
    ),
    (
      initial: '肖',
      name: '肖中特-老钱',
      sub: '特肖 · 本期未采集',
      tags: <String>[],
      missing: true,
      rawContent: '该来源本期尚未更新预测内容。',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _lottery = widget.lottery ?? Lottery.macau;
    _period = widget.initialPeriod ?? '2026277';
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final filteredSources = _sourceRecommendations.where((s) {
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
                    tooltip: '对照参数',
                    onTap: () {},
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
                                  active: l == _lottery,
                                  onTap: () => setState(() => _lottery = l),
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
                                label: '第 2026277 期',
                                active: _period == '2026277',
                                onTap: () =>
                                    setState(() => _period = '2026277'),
                              ),
                              GlassChipTag(
                                label: '第 2026276 期',
                                active: _period == '2026276',
                                onTap: () =>
                                    setState(() => _period = '2026276'),
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已更新对照：${_lottery.label} · 第 $_period 期 · $_selectedPlay',
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
                                builder: (_) => const ConsensusBoardScreen(),
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
                            label: _period == '2026277' ? '待开奖' : '已对奖',
                            color: _period == '2026277'
                                ? DuiliaoColors.warning
                                : DuiliaoColors.hit,
                            pulse: _period == '2026277',
                          ),
                          Flexible(
                            child: Text(
                              '上期(2026276)官方判定:特肖 蛇 · 领跑命中',
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
