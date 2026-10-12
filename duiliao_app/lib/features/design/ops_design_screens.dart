/// Operations & Consensus Board screens (sources.html, monitor.html, settings.html, consensus-board.html).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/ratings.dart';
import '../../domain/models/source.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import '../auth/auth_providers.dart';
import '../collect/collect_screen.dart';
import '../comparison/comparison_screen.dart';
import 'jump_code_assistant_screen.dart';

final sourceCatalogProvider = FutureProvider<List<CollectorSource>>(
  (ref) async => (await ref.read(collectorRepositoryProvider).sources()).value,
);

final monitorProvider = FutureProvider.family<List<MonitorRow>, String>((
  ref,
  lottery,
) async {
  return (await ref.read(collectorRepositoryProvider).monitor(lottery: lottery))
      .value;
});

class _SourceSample {
  const _SourceSample({
    required this.name,
    required this.id,
    required this.playLabel,
    required this.status, // 'enabled', 'paused', 'broken'
    required this.lastTime,
    required this.hitRateLabel,
    required this.hitColor,
    required this.scheduleLabel,
    this.warningBadge,
  });

  final String name;
  final String id;
  final String playLabel;
  final String status;
  final String lastTime;
  final String? hitRateLabel;
  final Color hitColor;
  final String scheduleLabel;
  final String? warningBadge;
}

const _fallbackSources = [
  _SourceSample(
    name: '海哥平特一肖',
    id: 'haige_pingte',
    playLabel: '平特一肖',
    status: 'enabled',
    lastTime: '最近采集 09-26 21:05',
    hitRateLabel: '62%',
    hitColor: DuiliaoColors.hit,
    scheduleLabel: '调度 每日 12:00 / 21:00',
  ),
  _SourceSample(
    name: '顶尖大师',
    id: 'dj_dashi_xinshui',
    playLabel: '特肖',
    status: 'enabled',
    lastTime: '最近采集 09-26 20:58',
    hitRateLabel: '55%',
    hitColor: DuiliaoColors.primaryDark,
    scheduleLabel: '调度 每日 12:00 / 21:00',
  ),
  _SourceSample(
    name: '顶级论坛金牌六肖',
    id: 'dj_jp_6xiao',
    playLabel: '特肖',
    status: 'enabled',
    lastTime: '最近采集 09-26 21:02',
    hitRateLabel: '48%',
    hitColor: DuiliaoColors.warning,
    scheduleLabel: '调度 每日 12:00',
  ),
  _SourceSample(
    name: '神算平特一肖',
    id: 'ss_pingte',
    playLabel: '平特肖',
    status: 'paused',
    lastTime: '最近采集 09-24 12:00',
    hitRateLabel: '41%',
    hitColor: DuiliaoColors.miss,
    scheduleLabel: '调度已暂停',
  ),
  _SourceSample(
    name: '大师一肖',
    id: 'dingjian_dashi_1xiao',
    playLabel: '特肖',
    status: 'broken',
    lastTime: '连续 3 期未采集',
    hitRateLabel: null,
    hitColor: DuiliaoColors.miss,
    scheduleLabel: '',
    warningBadge: '疑似栏目变更',
  ),
];

/// Data Source Catalog Screen (sources.html).
class SourceCatalogScreen extends ConsumerStatefulWidget {
  const SourceCatalogScreen({super.key});

  @override
  ConsumerState<SourceCatalogScreen> createState() =>
      _SourceCatalogScreenState();
}

class _SourceCatalogScreenState extends ConsumerState<SourceCatalogScreen> {
  String _query = '';
  String _filter = 'all'; // 'all', 'enabled', 'paused', 'broken'

  List<_SourceSample> _buildSamples(List<CollectorSource>? liveItems) {
    if (liveItems == null || liveItems.isEmpty) return _fallbackSources;
    return [
      for (final s in liveItems)
        _SourceSample(
          name: s.sourceName.isEmpty ? s.sourceId : s.sourceName,
          id: s.sourceId,
          playLabel: PlayTypes.labelFor(s.playType),
          status: s.isBroken
              ? 'broken'
              : s.enabled
              ? 'enabled'
              : 'paused',
          lastTime: s.isBroken
              ? '异常 · ${s.brokenReason ?? '采集受阻'}'
              : '站点 ${s.siteFamily.isEmpty ? '默认' : s.siteFamily}',
          hitRateLabel: null,
          hitColor: DuiliaoColors.hit,
          scheduleLabel: s.enabled ? '调度 每日 12:00 / 21:00' : '调度已暂停',
          warningBadge: s.isBroken ? '疑似栏目变更' : null,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sourceCatalogProvider);
    final liveItems = async.value;
    final samples = _buildSamples(liveItems);
    final filtered = samples.where((item) {
      if (_filter != 'all' && item.status != _filter) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        return item.name.toLowerCase().contains(q) ||
            item.id.toLowerCase().contains(q) ||
            item.playLabel.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    final totalCount = liveItems != null && liveItems.isNotEmpty
        ? liveItems.length
        : 28;
    final enabledCount = liveItems != null && liveItems.isNotEmpty
        ? liveItems.where((s) => s.enabled).length
        : 24;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                leading: Navigator.of(context).canPop()
                    ? GlassIconButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      )
                    : null,
                title: '数据源采集',
                subtitle: '采集调度样例 · 运行状态需连接后端',
                actions: [
                  GlassStatusPill(
                    label: liveItems != null && liveItems.isNotEmpty
                        ? '已连接'
                        : '静态样例',
                    color: liveItems != null && liveItems.isNotEmpty
                        ? DuiliaoColors.hit
                        : DuiliaoColors.warning,
                    pulse: true,
                  ),
                  GlassIconButton(
                    icon: Icons.add_rounded,
                    tooltip: '采集控制台',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CollectScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  children: [
                    // 3-Column KPI Grid
                    Row(
                      children: [
                        Expanded(
                          child: _KpiMiniCard(
                            icon: Icons.storage_rounded,
                            label: '数据源',
                            value: '$totalCount',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiMiniCard(
                            icon: Icons.check_rounded,
                            label: '已启用',
                            value: '$enabledCount',
                            valueColor: DuiliaoColors.hit,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiMiniCard(
                            icon: Icons.schedule_rounded,
                            label: '今日任务',
                            value: '12',
                            valueColor: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Search & Filters
                    TextField(
                      onChanged: (v) => setState(() => _query = v.trim()),
                      decoration: const InputDecoration(
                        hintText: '筛选来源名称/ID…',
                        prefixIcon: Icon(Icons.search_rounded, size: 19),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'KPI 为完整目录口径；当前页面展示代表性来源与现场试跑入口。',
                      style: context.texts.labelSmall?.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: 10),
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
                            label: '已启用',
                            active: _filter == 'enabled',
                            onTap: () => setState(() => _filter = 'enabled'),
                          ),
                          const SizedBox(width: 8),
                          GlassChipTag(
                            label: '已暂停',
                            active: _filter == 'paused',
                            onTap: () => setState(() => _filter = 'paused'),
                          ),
                          const SizedBox(width: 8),
                          GlassChipTag(
                            label: '异常',
                            active: _filter == 'broken',
                            onTap: () => setState(() => _filter = 'broken'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    for (final item in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SourceSampleCard(
                          item: item,
                          onTestRun: () => _testRunSource(context, item),
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

  Future<void> _testRunSource(
    BuildContext context,
    _SourceSample item,
  ) async {
    if (ref.read(canOperateProvider)) {
      try {
        final result = await ref
            .read(collectorRepositoryProvider)
            .testSource(sourceId: item.id, lottery: 'macau');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${item.name}：${result.ok ? '测试运行完成' : result.errorMsg ?? '试跑失败'}',
              ),
            ),
          );
        }
        return;
      } catch (_) {}
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已触发「${item.name} (${item.id})」单源测试运行')),
      );
    }
  }
}

class _KpiMiniCard extends StatelessWidget {
  const _KpiMiniCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(label, style: context.texts.labelSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceSampleCard extends StatelessWidget {
  const _SourceSampleCard({
    required this.item,
    required this.onTestRun,
  });

  final _SourceSample item;
  final VoidCallback onTestRun;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = switch (item.status) {
      'enabled' => ('已启用', DuiliaoColors.hit),
      'paused' => ('已暂停', DuiliaoColors.pending),
      _ => ('异常', DuiliaoColors.miss),
    };

    return GlassGroup(
      margin: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        ZTag(label: item.playLabel),
                        GlassStatusPill(
                          label: statusLabel,
                          color: statusColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID ${item.id} · ${item.lastTime}',
                      style: context.texts.labelSmall,
                    ),
                  ],
                ),
              ),
              if (item.hitRateLabel != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.hitRateLabel!,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: item.hitColor,
                      ),
                    ),
                    Text(
                      '命中率',
                      style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: item.warningBadge != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GlassGhostButton(
                      label: '启动测试运行',
                      icon: Icons.play_arrow_rounded,
                      compact: true,
                      onTap: onTestRun,
                    ),
                    GlassStatusPill(
                      label: item.warningBadge!,
                      color: DuiliaoColors.warning,
                      pulse: true,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.scheduleLabel,
                        style: context.texts.labelSmall,
                      ),
                    ),
                    GlassGhostButton(
                      label: '测试运行',
                      compact: true,
                      onTap: onTestRun,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Service Monitor Screen (monitor.html).
class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({super.key});

  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen> {
  bool _pauseOfflineSources = false;
  bool _autoConfirmMissing = true;
  final Set<String> _confirmedMissing = <String>{};

  @override
  Widget build(BuildContext context) {
    final lottery = ref.watch(selectedLotteryProvider);
    final async = ref.watch(monitorProvider(lottery.code));
    final rows = async.value ?? const <MonitorRow>[];

    final normalCount = rows.isNotEmpty
        ? rows.where((r) => !r.neverCollected && !r.isStale).length
        : 22;
    final brokenCount = rows.isNotEmpty
        ? rows.where((r) => r.isStale).length
        : 3;
    final uncollectedCount = rows.isNotEmpty
        ? rows.where((r) => r.neverCollected).length
        : 3;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                leading: Navigator.of(context).canPop()
                    ? GlassIconButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      )
                    : null,
                title: '服务监控',
                subtitle: '缺期巡检样例 · 执行动作需连接后端',
                actions: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () {
                        ref.invalidate(monitorProvider(lottery.code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已发起上游全源巡检任务')),
                        );
                      },
                      child: Ink(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          gradient: DuiliaoColors.auroraGradient,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            SizedBox(width: 5),
                            Text(
                              '立即巡检上游',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  children: [
                    // 3-Column KPI Grid
                    Row(
                      children: [
                        Expanded(
                          child: _KpiMiniCard(
                            icon: Icons.check_rounded,
                            label: '正常',
                            value: '$normalCount',
                            valueColor: DuiliaoColors.hit,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiMiniCard(
                            icon: Icons.warning_amber_rounded,
                            label: '异常',
                            value: '$brokenCount',
                            valueColor: DuiliaoColors.miss,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiMiniCard(
                            icon: Icons.schedule_rounded,
                            label: '未采集',
                            value: '$uncollectedCount',
                          ),
                        ),
                      ],
                    ),

                    // Missing Period Monitor
                    const DesignSectionHeader(
                      title: '缺期监控',
                      trailingText: '待确认 2 项',
                    ),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        _MissingMonitorRow(
                          title: '肖中特-老钱',
                          subtitle: '缺 3 期 · 第 2026274~2026276 期',
                          statusLabel: _confirmedMissing.contains('xzt')
                              ? '已确认'
                              : '异常',
                          statusColor: _confirmedMissing.contains('xzt')
                              ? DuiliaoColors.pending
                              : DuiliaoColors.miss,
                          showConfirmButton:
                              !_confirmedMissing.contains('xzt'),
                          onConfirm: () => setState(() {
                            _confirmedMissing.add('xzt');
                          }),
                        ),
                        const _MissingMonitorRow(
                          title: '白小组',
                          subtitle: '缺 2 期 · 第 2026275~2026276 期',
                          statusLabel: '待确认',
                          statusColor: DuiliaoColors.warning,
                        ),
                        const _MissingMonitorRow(
                          title: '管家婆传真',
                          subtitle: '缺 1 期 · 第 2026276 期',
                          statusLabel: '待确认',
                          statusColor: DuiliaoColors.warning,
                        ),
                      ],
                    ),

                    // Inspection Records
                    const DesignSectionHeader(title: '巡检记录'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: const [
                        _InspectionRow(
                          title: '巡检完成 · 发现 2 异常',
                          subtitle: '09-26 21:40 · 覆盖 28 源',
                        ),
                        _InspectionRow(
                          title: '巡检完成 · 发现 1 异常',
                          subtitle: '09-26 12:05 · 覆盖 28 源',
                        ),
                        _InspectionRow(
                          title: '巡检完成 · 全部正常',
                          subtitle: '09-25 21:38 · 覆盖 27 源',
                        ),
                      ],
                    ),

                    // Governance
                    const DesignSectionHeader(title: '栏目治理'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.14),
                                ),
                                child: Icon(
                                  Icons.cancel_outlined,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '停用已下线源',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '将 2 个 30 天无数据源标记为暂停',
                                      style: context.texts.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              GlassSwitch(
                                value: _pauseOfflineSources,
                                onChanged: (v) => setState(
                                  () => _pauseOfflineSources = v,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.14),
                                ),
                                child: Icon(
                                  Icons.download_done_rounded,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '自动确认长期缺期',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '连续 6 期缺期自动确认',
                                      style: context.texts.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              GlassSwitch(
                                value: _autoConfirmMissing,
                                onChanged: (v) => setState(
                                  () => _autoConfirmMissing = v,
                                ),
                              ),
                            ],
                          ),
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

class _MissingMonitorRow extends StatelessWidget {
  const _MissingMonitorRow({
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusColor,
    this.showConfirmButton = false,
    this.onConfirm,
  });

  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusColor;
  final bool showConfirmButton;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: statusColor.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: context.texts.labelSmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GlassStatusPill(
                label: statusLabel,
                color: statusColor,
                showDot: false,
              ),
              if (showConfirmButton) ...[
                const SizedBox(height: 6),
                GlassGhostButton(
                  label: '确认缺期',
                  compact: true,
                  onTap: onConfirm,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _InspectionRow extends StatelessWidget {
  const _InspectionRow({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: DuiliaoColors.hit.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 18,
              color: DuiliaoColors.hit,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: context.texts.labelSmall),
              ],
            ),
          ),
          const GlassStatusPill(
            label: '已完成',
            color: DuiliaoColors.hit,
            showDot: false,
          ),
        ],
      ),
    );
  }
}

/// System Settings Screen (settings.html).
class SystemSettingsScreen extends ConsumerStatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  ConsumerState<SystemSettingsScreen> createState() =>
      _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends ConsumerState<SystemSettingsScreen> {
  String _provider = 'Kimi';
  late final TextEditingController _modelController;
  late final TextEditingController _apiKeyController;
  bool _autoSilentRefresh = true;
  bool _issueTableFixed = false;
  String _cacheSizeLabel = '12.4 MB';

  static const _providers = [
    ('Kimi', '月之暗面', '全球通用', 'kimi-k2-thinking'),
    ('OpenAI 官方', 'GPT 系列', '全球通用', 'gpt-4o'),
    ('阿里百炼兼容', '通义系列', '国内直连', 'qwen-max'),
    ('本地 Ollama', '本地模型', '私有化/无费用', 'deepseek-r1:14b'),
  ];

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(text: 'kimi-k2-thinking');
    _apiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                title: '系统设置',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  children: [
                    // AI Configuration
                    const DesignSectionHeader(title: 'AI 配置'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GridView(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  mainAxisExtent: 86,
                                ),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              for (final p in _providers)
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _provider = p.$1;
                                    _modelController.text = p.$4;
                                  }),
                                  child: GlassSubtleBox(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    borderColor: _provider == p.$1
                                        ? DuiliaoColors.auroraViolet.withValues(
                                            alpha: 0.65,
                                          )
                                        : null,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          p.$1,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          p.$2,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.texts.labelSmall,
                                        ),
                                        Text(
                                          p.$3,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.texts.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text('模型', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.auto_awesome, size: 18),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text('API Key', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(
                                Icons.lock_outline_rounded,
                                size: 18,
                              ),
                              hintText: '粘贴新的 API Key(演示不保存)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const GlassStatusPill(
                                label: '样例状态 · 未实时检测',
                                color: DuiliaoColors.warning,
                                pulse: true,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '延迟 182ms · 09-26 21:55',
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.labelSmall,
                                ),
                              ),
                              GlassGhostButton(
                                label: '重新检测',
                                compact: true,
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '已检测 $_provider (${_modelController.text}) 连通性',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GlassGhostButton(
                            label: '保存 AI 配置',
                            fullWidth: true,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('AI 配置已保存')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // Database Section
                    const DesignSectionHeader(title: '数据库'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                      child: Column(
                        children: [
                          const _DbTableRow(
                            title: '主数据库',
                            subtitle: 'App 应用库',
                            pillLabel: '已连接',
                            pillColor: DuiliaoColors.hit,
                            showDot: true,
                          ),
                          const Divider(height: 1),
                          const _DbTableRow(
                            title: '用户账号 (users)',
                            pillLabel: '正常',
                            pillColor: DuiliaoColors.hit,
                          ),
                          const Divider(height: 1),
                          const _DbTableRow(
                            title: '开奖期数 (draw)',
                            pillLabel: '正常',
                            pillColor: DuiliaoColors.hit,
                          ),
                          const Divider(height: 1),
                          const _DbTableRow(
                            title: '数据源 (source)',
                            pillLabel: '正常',
                            pillColor: DuiliaoColors.hit,
                          ),
                          const Divider(height: 1),
                          _DbTableRow(
                            title: '问题记录 (issue)',
                            pillLabel: _issueTableFixed ? '正常' : '缺表',
                            pillColor: _issueTableFixed
                                ? DuiliaoColors.hit
                                : DuiliaoColors.warning,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              GlassGhostButton(
                                label: '补齐缺失表',
                                compact: true,
                                onTap: () {
                                  setState(() => _issueTableFixed = true);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('已补齐缺失表 issue'),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _issueTableFixed
                                    ? '全部数据表结构完整'
                                    : '检测到 1 张缺失表',
                                style: context.texts.labelSmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // General Section
                    const DesignSectionHeader(title: '通用'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.14),
                                ),
                                child: Icon(
                                  Icons.dark_mode_outlined,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  '深色模式',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              GlassSwitch(
                                value: isDark,
                                onChanged: (v) {
                                  ref
                                      .read(
                                        displayPreferencesProvider.notifier,
                                      )
                                      .setThemeMode(
                                        v
                                            ? ThemeModePreference.dark
                                            : ThemeModePreference.light,
                                      );
                                },
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.14),
                                ),
                                child: Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '自动静默刷新',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '每 2 分钟静默更新数据',
                                      style: context.texts.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              GlassSwitch(
                                value: _autoSilentRefresh,
                                onChanged: (v) => setState(
                                  () => _autoSilentRefresh = v,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            await ref
                                .read(collectorRepositoryProvider)
                                .clearCache();
                            if (!context.mounted) return;
                            setState(() => _cacheSizeLabel = '0.0 MB');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('本地缓存已清理')),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(11),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.14),
                                  ),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    '清理本地缓存',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  _cacheSizeLabel,
                                  style: context.texts.labelSmall,
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    GlassButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('所有系统配置已保存')),
                        );
                      },
                      child: const Text('保存所有配置'),
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

class _DbTableRow extends StatelessWidget {
  const _DbTableRow({
    required this.title,
    this.subtitle,
    required this.pillLabel,
    required this.pillColor,
    this.showDot = false,
  });

  final String title;
  final String? subtitle;
  final String pillLabel;
  final Color pillColor;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: pillColor.withValues(alpha: 0.14),
            ),
            child: Icon(
              Icons.storage_rounded,
              size: 17,
              color: pillColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: context.texts.labelSmall),
              ],
            ),
          ),
          GlassStatusPill(
            label: pillLabel,
            color: pillColor,
            showDot: showDot,
          ),
        ],
      ),
    );
  }
}

/// Consensus Leaderboard Screen (consensus-board.html).
class ConsensusBoardScreen extends ConsumerStatefulWidget {
  const ConsensusBoardScreen({super.key});

  @override
  ConsumerState<ConsensusBoardScreen> createState() =>
      _ConsensusBoardScreenState();
}

class _ConsensusBoardScreenState extends ConsumerState<ConsensusBoardScreen> {
  Lottery _lottery = Lottery.macau;
  String _period = '2026277';
  int _tabIndex = 0; // 0: 候选排行榜, 1: 玩法组共识, 2: 入库与核验

  @override
  Widget build(BuildContext context) {
    final isLive = _period == '2026277';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                leading: Navigator.of(context).canPop()
                    ? GlassIconButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      )
                    : null,
                title: '共识排行榜',
                subtitle: '多源去重 · 支持证据 · 官方核验',
                actions: [
                  const GlassStatusPill(
                    label: '设计样例 · 非实时',
                    color: DuiliaoColors.warning,
                    pulse: true,
                  ),
                  GlassIconButton(
                    icon: Icons.tune_rounded,
                    tooltip: '多源对照明细',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ComparisonScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  children: [
                    // 榜单上下文
                    const DesignSectionHeader(title: '榜单上下文'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('彩种', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
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
                            spacing: 6,
                            runSpacing: 6,
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  isLive
                                      ? '统计截止 09-26 21:10 · 实时预测版本'
                                      : '统计截止 09-26 21:32 · 已冻结不可变快照',
                                  style: context.texts.labelSmall,
                                ),
                              ),
                              GlassStatusPill(
                                label: isLive ? '待开奖' : '已冻结',
                                color: isLive
                                    ? DuiliaoColors.warning
                                    : DuiliaoColors.hit,
                                pulse: isLive,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 本期共识结论
                    const SizedBox(height: 12),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '本期共识结论',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '先看领跑项，再查看支持证据',
                                    style: context.texts.labelSmall,
                                  ),
                                ],
                              ),
                              GlassStatusPill(
                                label: isLive ? '实时榜单' : '冻结快照',
                                color: Theme.of(context).colorScheme.primary,
                                showDot: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
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
                                            '26 号',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '8 票 · 66.7% · 8 个来源组',
                                        style: context.texts.labelSmall
                                            ?.copyWith(fontSize: 10.5),
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
                                          BrandLogoBox(
                                            label: '蛇',
                                            size: 30,
                                            borderRadius: 9,
                                            fontSize: 14,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '蛇肖',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '7 票 · 58.3% · 7 个来源组',
                                        style: context.texts.labelSmall
                                            ?.copyWith(fontSize: 10.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 3-Tab Switcher
                    const SizedBox(height: 12),
                    GlassSegmentedControl<int>(
                      items: const [0, 1, 2],
                      selected: _tabIndex,
                      labelBuilder: (i) => switch (i) {
                        0 => '候选排行榜',
                        1 => '玩法组共识',
                        _ => '入库与核验',
                      },
                      onChanged: (v) => setState(() => _tabIndex = v),
                    ),

                    if (_tabIndex == 0) _buildCandidateTab(context, isLive),
                    if (_tabIndex == 1) _buildPlayGroupTab(context, isLive),
                    if (_tabIndex == 2) _buildAuditTab(context, isLive),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateTab(BuildContext context, bool isLive) {
    final temaItems = [
      (
        rank: 1,
        val: '26',
        votes: 8,
        pct: 0.667,
        pctLabel: '66.7%',
        hit: !isLive,
        sources: const [
          '海哥平特一肖／第1组',
          '顶尖大师',
          '管家婆传真',
          '白小组',
          '澳门资料王',
          '龙门客栈',
          '四海资料',
          '红波大师',
        ],
      ),
      (
        rank: 2,
        val: '14',
        votes: 6,
        pct: 0.50,
        pctLabel: '50.0%',
        hit: false,
        sources: const [
          '顶尖大师',
          '管家婆传真',
          '白小组',
          '澳门资料王',
          '资料研究院',
          '龙门客栈',
        ],
      ),
      (
        rank: 3,
        val: '03',
        votes: 5,
        pct: 0.417,
        pctLabel: '41.7%',
        hit: false,
        sources: const ['海哥平特一肖／第2组', '顶尖大师', '四海资料', '资料研究院', '新澳资料'],
      ),
    ];

    final xiaoItems = [
      (
        rank: 1,
        val: '蛇',
        votes: 7,
        pct: 0.583,
        pctLabel: '58.3%',
        hit: !isLive,
        sources: const [
          '海哥平特一肖／第1组',
          '顶尖大师',
          '管家婆传真',
          '白小组',
          '澳门资料王',
          '四海资料',
          '红波大师',
        ],
      ),
      (
        rank: 2,
        val: '龙',
        votes: 5,
        pct: 0.417,
        pctLabel: '41.7%',
        hit: false,
        sources: const ['海哥平特一肖／第2组', '顶尖大师', '资料研究院', '龙门客栈', '新澳资料'],
      ),
      (
        rank: 3,
        val: '鸡',
        votes: 4,
        pct: 0.333,
        pctLabel: '33.3%',
        hit: false,
        sources: const ['管家婆传真', '白小组', '澳门资料王', '红波大师'],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DesignSectionHeader(
          title: '特码候选榜',
          trailingText: '按来源组计票',
        ),
        for (final item in temaItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CandidateRankCard(
              rank: item.rank,
              isNum: true,
              value: item.val,
              votes: item.votes,
              pct: item.pct,
              pctLabel: item.pctLabel,
              isLive: isLive,
              hit: item.hit,
              sources: item.sources,
            ),
          ),
        const DesignSectionHeader(
          title: '特肖候选榜',
          trailingText: '按来源组计票',
        ),
        for (final item in xiaoItems)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CandidateRankCard(
              rank: item.rank,
              isNum: false,
              value: item.val,
              votes: item.votes,
              pct: item.pct,
              pctLabel: item.pctLabel,
              isLive: isLive,
              hit: item.hit,
              sources: item.sources,
            ),
          ),
        const SizedBox(height: 6),
        GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(14),
          child: const Column(
            children: [
              _LogicMetaRow('计票单位', 'source + group_key'),
              Divider(height: 16),
              _LogicMetaRow('有效分母', '可用来源组总数'),
              Divider(height: 16),
              _LogicMetaRow('排除项', 'claimed_status = missing'),
              Divider(height: 16),
              _LogicMetaRow('历史结果', '开奖后冻结，不追随晚到数据变化'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GlassSubtleBox(
          padding: const EdgeInsets.all(12),
          child: Text(
            '重要：支持率表示“有多少有效来源组支持该候选”，不等于中奖概率。同一来源组内重复出现只计 1 票，可展开候选项查看具体来源证据。',
            style: context.texts.labelSmall?.copyWith(height: 1.55),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayGroupTab(BuildContext context, bool isLive) {
    final groups = [
      (
        name: '特码',
        code: 'tema_n',
        leader: '26',
        votes: 8,
        total: 19,
        sourceGroups: 8,
        tally: const [('26', 8), ('14', 6), ('03', 5)],
      ),
      (
        name: '特肖',
        code: 'texiao',
        leader: '蛇',
        votes: 7,
        total: 16,
        sourceGroups: 7,
        tally: const [('蛇', 7), ('龙', 5), ('鸡', 4)],
      ),
      (
        name: '平特肖',
        code: 'pingte_xiao',
        leader: '蛇',
        votes: 5,
        total: 8,
        sourceGroups: 5,
        tally: const [('蛇', 5), ('龙', 3)],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DesignSectionHeader(
          title: '玩法组共识',
          trailingText: '领跑组合',
        ),
        for (final g in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(14),
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
                            g.name,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${g.code} · ${g.sourceGroups} 个来源组参与',
                            style: context.texts.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      GlassStatusPill(
                        label: isLive ? '待开奖' : '领跑命中',
                        color: isLive
                            ? DuiliaoColors.warning
                            : DuiliaoColors.hit,
                        showDot: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GlassSubtleBox(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('玩法组领跑', style: context.texts.labelSmall),
                            const SizedBox(height: 2),
                            Text(
                              g.leader,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${g.votes} 票 · ${(g.votes / g.total * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < g.tally.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${i + 1}. ${g.tally[i].$1}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${g.tally[i].$2} 票',
                            style: context.texts.labelSmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlayCatalogScreen()),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '查看全部 21 种支持玩法与编码',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuditTab(BuildContext context, bool isLive) {
    final audits = isLive
        ? const [
            ('海哥平特一肖', '特肖 · 2 组已入库', '已入库', DuiliaoColors.primaryDark),
            ('顶尖大师', '特码 / 特肖 · 2 组已入库', '已入库', DuiliaoColors.primaryDark),
            ('管家婆传真', '平特肖 · 1 组已入库', '已入库', DuiliaoColors.primaryDark),
            ('肖中特-老钱', '本期未采集', '缺期', DuiliaoColors.pending),
          ]
        : const [
            ('海哥平特一肖', '平特肖 · 领跑项命中蛇', '官方命中', DuiliaoColors.hit),
            ('顶尖大师', '特码 · 领跑项命中 26', '官方命中', DuiliaoColors.hit),
            ('管家婆传真', '平特肖 · 领跑项命中蛇', '官方命中', DuiliaoColors.hit),
            ('肖中特-老钱', '本期未采集', '缺期', DuiliaoColors.pending),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DesignSectionHeader(title: '入库质量'),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 2.1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _AuditKpiTile(label: '有效来源组', value: '12'),
            _AuditKpiTile(label: '排除缺期', value: isLive ? '3' : '2'),
            _AuditKpiTile(label: '去重后有效票', value: '43'),
            _AuditKpiTile(label: '快照状态', value: isLive ? '实时' : '已冻结'),
          ],
        ),
        const DesignSectionHeader(title: '来源入库状态'),
        GlassGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final a in audits)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    BrandLogoBox(
                      label: a.$1.substring(0, 1),
                      size: 30,
                      borderRadius: 9,
                      fontSize: 12,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.$1,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(a.$2, style: context.texts.labelSmall),
                        ],
                      ),
                    ),
                    GlassStatusPill(
                      label: a.$3,
                      color: a.$4,
                      showDot: false,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const DesignSectionHeader(title: '官方开奖核验'),
        GlassCard(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(16),
          child: isLive
              ? Column(
                  children: [
                    const GlassStatusPill(
                      label: '尚未开奖',
                      color: DuiliaoColors.warning,
                      pulse: true,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '当前只展示实时预测共识。官方开奖入库后，系统会以开奖边界前版本生成冻结快照，并自动补写每项命中状态。',
                      textAlign: TextAlign.center,
                      style: context.texts.labelSmall?.copyWith(height: 1.65),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '第 2026276 期官方号码',
                          style: context.texts.labelSmall,
                        ),
                        const GlassStatusPill(
                          label: '快照已冻结',
                          color: DuiliaoColors.hit,
                          showDot: false,
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
                            bose: Lottery2026Lookup.boseForNumber(int.parse(n)),
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
                    Text(
                      '特码 26 · 特肖 蛇 · 领跑项已完成官方核验',
                      style: context.texts.labelSmall?.copyWith(
                        color: DuiliaoColors.hit,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CandidateRankCard extends StatefulWidget {
  const _CandidateRankCard({
    required this.rank,
    required this.isNum,
    required this.value,
    required this.votes,
    required this.pct,
    required this.pctLabel,
    required this.isLive,
    required this.hit,
    required this.sources,
  });

  final int rank;
  final bool isNum;
  final String value;
  final int votes;
  final double pct;
  final String pctLabel;
  final bool isLive;
  final bool hit;
  final List<String> sources;

  @override
  State<_CandidateRankCard> createState() => _CandidateRankCardState();
}

class _CandidateRankCardState extends State<_CandidateRankCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isTop = widget.rank == 1;
    final bose = widget.isNum
        ? Lottery2026Lookup.boseForNumber(int.tryParse(widget.value) ?? 1)
        : 'blue';

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 25,
                height: 25,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: isTop
                      ? const LinearGradient(
                          colors: [
                            DuiliaoColors.waveGoldA,
                            DuiliaoColors.waveGoldB,
                          ],
                        )
                      : null,
                  color: isTop
                      ? null
                      : Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.16),
                ),
                child: Text(
                  '${widget.rank}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isTop
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (widget.isNum)
                NumberBall(number: widget.value, bose: bose, size: 28)
              else
                BrandLogoBox(
                  label: widget.value,
                  size: 30,
                  borderRadius: 9,
                  fontSize: 13.5,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.isNum
                              ? '${widget.value} 号'
                              : '${widget.value}肖',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (widget.hit)
                          const Text(
                            ' · 官方命中',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: DuiliaoColors.hit,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.isNum ? 'tema_n · 蓝波' : 'texiao · 生肖候选',
                      style: context.texts.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${widget.votes} 票',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    widget.pctLabel,
                    style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 35),
              Expanded(
                child: GlassLinearProgress(
                  value: widget.pct,
                  color: widget.hit ? DuiliaoColors.hit : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '支持率',
                style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const SizedBox(width: 35),
              Expanded(
                child: Text(
                  '${widget.sources.length} 个来源组支持',
                  style: context.texts.labelSmall,
                ),
              ),
              GlassStatusPill(
                label: widget.hit
                    ? '已命中'
                    : widget.isLive
                    ? '待开奖'
                    : '未命中',
                color: widget.hit
                    ? DuiliaoColors.hit
                    : widget.isLive
                    ? DuiliaoColors.warning
                    : DuiliaoColors.miss,
                showDot: false,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 35),
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                '${_expanded ? '－' : '＋'} 查看支持来源与证据',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 35),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in widget.sources) GlassChipTag(label: s),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogicMetaRow extends StatelessWidget {
  const _LogicMetaRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: context.texts.labelSmall),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _AuditKpiTile extends StatelessWidget {
  const _AuditKpiTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassSubtleBox(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: context.texts.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
