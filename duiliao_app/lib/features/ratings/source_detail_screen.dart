/// One source: configuration, health, and its prediction history.
library;

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/prediction.dart';
import '../../domain/models/ratings.dart';
import '../../domain/models/source.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../../ui/widgets/number_ball.dart';

/// Configuration, health and history for one source, fetched together.
final sourceDetailProvider = FutureProvider.family<
    ({
      CollectorSource? source,
      SourceHistoryStats? stats,
      MonitorRow? monitor,
      List<PredictionRow> predictions,
      bool hasError,
    }),
    ({String sourceId, Lottery lottery})>((ref, key) async {
  final repo = ref.read(collectorRepositoryProvider);
  var hasError = false;

  Future<({CollectorSource source, SourceHistoryStats stats, List<PredictionRow> items, int total})?> loadHistory() async {
    try {
      return await repo.sourceHistory(
        sourceId: key.sourceId,
        lottery: key.lottery.code,
        limit: 200,
      );
    } catch (_) {
      hasError = true;
      return null;
    }
  }

  Future<MonitorRow?> loadMonitor() async {
    try {
      final fetched = await repo.monitor(lottery: key.lottery.code);
      return fetched.value
          .where((row) => row.sourceId == key.sourceId)
          .firstOrNull;
    } catch (_) {
      hasError = true;
      return null;
    }
  }

  final historyFuture = loadHistory();
  final monitorFuture = loadMonitor();

  final history = await historyFuture;
  final monitor = await monitorFuture;

  CollectorSource? fallbackSource;
  if (history == null) {
    try {
      fallbackSource = await repo.source(key.sourceId);
    } catch (_) {}
  }

  return (
    source: history?.source ?? fallbackSource,
    stats: history?.stats,
    monitor: monitor,
    predictions: history?.items ?? const [],
    hasError: hasError,
  );
});

class SourceDetailScreen extends ConsumerStatefulWidget {
  const SourceDetailScreen({
    super.key,
    required this.sourceId,
    required this.lottery,
    this.sourceName,
  });

  final String sourceId;
  final Lottery lottery;
  final String? sourceName;

  @override
  ConsumerState<SourceDetailScreen> createState() => _SourceDetailScreenState();
}

class _SourceDetailScreenState extends ConsumerState<SourceDetailScreen> {
  String? _statusFilter; // null for all, 'hit', 'miss', 'pending', 'conflict'

  @override
  Widget build(BuildContext context) {
    final key = (sourceId: widget.sourceId, lottery: widget.lottery);
    final async = ref.watch(sourceDetailProvider(key));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(widget.sourceName ?? widget.sourceId)),
      body: GlassBackground(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.refresh(sourceDetailProvider(key).future);
          },
          child: AsyncView<({
            CollectorSource? source,
            SourceHistoryStats? stats,
            MonitorRow? monitor,
            List<PredictionRow> predictions,
            bool hasError,
          })>(
            value: async,
            loading: const SkeletonList(itemHeight: 90),
            onRetry: () => ref.invalidate(sourceDetailProvider(key)),
            builder: (data) {
              final stats = data.stats;
              final filteredPredictions = data.predictions.where((p) {
                if (_statusFilter == null) return true;
                if (_statusFilter == 'hit') return p.officialHit == 1;
                if (_statusFilter == 'miss') return p.officialHit == 0 && !p.isConflict;
                if (_statusFilter == 'pending') return p.officialHit == null;
                if (_statusFilter == 'conflict') return p.isConflict;
                return true;
              }).toList();

              return ListView(
                padding: const EdgeInsets.only(top: 6, bottom: 96),
                children: [
                  if (data.hasError)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 6, 14, 2),
                      child: WarningNote(
                        message: '部分详情加载失败，显示内容可能不完整',
                        icon: Icons.cloud_off_outlined,
                      ),
                    ),
                  if (stats != null) _StatsCard(stats: stats),
                  if (data.source != null) _InfoCard(source: data.source!),
                  if (data.monitor != null) _HealthCard(monitor: data.monitor!),
                  SectionHeader(
                    title: '全量历史对奖流水',
                    subtitle: '共 ${data.predictions.length} 期记录'
                        '${_statusFilter != null ? ' (筛选显示 ${filteredPredictions.length} 期)' : ''}',
                  ),
                  if (data.predictions.isNotEmpty)
                    _FilterBar(
                      stats: stats,
                      totalCount: data.predictions.length,
                      selected: _statusFilter,
                      onChanged: (val) => setState(() => _statusFilter = val),
                    ),
                  if (filteredPredictions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('无匹配的历史预测记录')),
                    )
                  else
                    for (final row in filteredPredictions)
                      _PredictionRowTile(
                        row: row,
                        onTap: () => _showEvidence(context, row),
                      ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showEvidence(BuildContext context, PredictionRow row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, controller) =>
            _EvidenceDrawer(row: row, controller: controller),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final SourceHistoryStats stats;

  @override
  Widget build(BuildContext context) {
    final pctText = (stats.hitRate * 100).toStringAsFixed(1);
    final streakText = stats.currentStatus == 'hit'
        ? '连中 ${stats.currentStreak} 期'
        : (stats.currentStatus == 'miss'
            ? '连挂 ${stats.currentStreak} 期'
            : (stats.currentStatus == 'pending' ? '最新期待判' : '—'));

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '历史战绩统计',
                style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: stats.hitRate >= 0.7
                      ? DuiliaoColors.hit.withValues(alpha: 0.15)
                      : (stats.hitRate >= 0.4
                          ? DuiliaoColors.warning.withValues(alpha: 0.15)
                          : DuiliaoColors.miss.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '命中率 $pctText%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: stats.hitRate >= 0.7
                        ? DuiliaoColors.hit
                        : (stats.hitRate >= 0.4 ? DuiliaoColors.warning : DuiliaoColors.miss),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '总预测期数',
                  value: '${stats.total}',
                  hint: '已判定 ${stats.judged} 期',
                ),
              ),
              Expanded(
                child: StatTile(
                  label: '命中',
                  value: '${stats.hits}',
                  valueColor: DuiliaoColors.hit,
                ),
              ),
              Expanded(
                child: StatTile(
                  label: '挂',
                  value: '${stats.misses}',
                  valueColor: DuiliaoColors.miss,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '当前连态',
                  value: streakText,
                  valueColor: stats.currentStatus == 'hit'
                      ? DuiliaoColors.hit
                      : (stats.currentStatus == 'miss' ? DuiliaoColors.miss : null),
                ),
              ),
              Expanded(
                child: StatTile(
                  label: '最长连中/连挂',
                  value: '${stats.longestHit}中 / ${stats.longestMiss}挂',
                ),
              ),
              Expanded(
                child: StatTile(
                  label: '待判 / 缺期',
                  value: '${stats.pending} / ${stats.missing}',
                ),
              ),
            ],
          ),
          if (stats.conflicts > 0) ...[
            const SizedBox(height: 10),
            WarningNote(
              message: '发现 ${stats.conflicts} 期自称命中但实际挂（虚假自称预警）',
              icon: Icons.warning_amber_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.stats,
    required this.totalCount,
    required this.selected,
    required this.onChanged,
  });

  final SourceHistoryStats? stats;
  final int totalCount;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          GlassFilterPill(
            label: '全部',
            count: stats?.total ?? totalCount,
            isSelected: selected == null,
            onTap: () => onChanged(null),
          ),
          const SizedBox(width: 8),
          GlassFilterPill(
            label: '命中',
            count: stats?.hits,
            color: DuiliaoColors.hit,
            isSelected: selected == 'hit',
            onTap: () => onChanged('hit'),
          ),
          const SizedBox(width: 8),
          GlassFilterPill(
            label: '挂',
            count: stats?.misses,
            color: DuiliaoColors.miss,
            isSelected: selected == 'miss',
            onTap: () => onChanged('miss'),
          ),
          const SizedBox(width: 8),
          GlassFilterPill(
            label: '待判',
            count: stats?.pending,
            color: DuiliaoColors.pending,
            isSelected: selected == 'pending',
            onTap: () => onChanged('pending'),
          ),
          if ((stats?.conflicts ?? 0) > 0) ...[
            const SizedBox(width: 8),
            GlassFilterPill(
              label: '冲突',
              count: stats?.conflicts,
              color: DuiliaoColors.conflict,
              isSelected: selected == 'conflict',
              onTap: () => onChanged('conflict'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.source});

  final CollectorSource source;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  source.sourceName,
                  style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              GlassBadge(
                label: source.enabled ? '已启用' : '已停用',
                color: source.enabled
                    ? DuiliaoColors.hit
                    : DuiliaoColors.pending,
                icon: source.enabled ? Icons.check_circle : Icons.pause_circle,
                small: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _KeyValue(label: '源 ID', value: source.sourceId),
          _KeyValue(label: '站族', value: source.siteFamily),
          _KeyValue(label: '玩法', value: PlayTypes.labelFor(source.playType)),
          _KeyValue(label: '判定模式', value: source.hitMode),
          _KeyValue(label: '脚本', value: source.scriptPath),
          _KeyValue(label: '超时', value: '${source.timeoutSec} 秒'),
          if (source.remark != null && source.remark!.isNotEmpty)
            _KeyValue(label: '备注', value: source.remark!),
          if (source.isBroken) ...[
            const SizedBox(height: 10),
            const WarningNote(
              message: '脚本文件缺失或路径无效，该源无法执行',
              icon: Icons.error_outline,
            ),
          ],
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.monitor});

  final MonitorRow monitor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '健康度',
            style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '最新预测期',
                  value: monitor.latestPeriod == null
                      ? '—'
                      : Period.short(monitor.latestPeriod),
                ),
              ),
              Expanded(
                child: StatTile(
                  label: '最新开奖期',
                  value: monitor.latestDraw == null
                      ? '—'
                      : Period.short(monitor.latestDraw),
                ),
              ),
              Expanded(
                child: StatTile(
                  label: '落后期数',
                  value: monitor.lag?.toString() ?? '—',
                  valueColor: monitor.isStale ? DuiliaoColors.warning : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StatTile(label: '待判', value: '${monitor.pendingTotal}'),
              ),
              Expanded(
                child: StatTile(label: '已确认', value: '${monitor.confirmedTotal}'),
              ),
              Expanded(
                child: StatTile(
                  label: '最后出现',
                  value: monitor.lastSeen ?? '—',
                ),
              ),
            ],
          ),
          if (monitor.neverCollected) ...[
            const SizedBox(height: 10),
            const WarningNote(
              message: '该源从未成功采集过任何数据',
              icon: Icons.cloud_off,
            ),
          ] else if (monitor.isStale) ...[
            const SizedBox(height: 10),
            WarningNote(
              message: '该源已落后最新开奖 ${monitor.lag} 期',
              icon: Icons.schedule,
            ),
          ],
        ],
      ),
    );
  }
}

class _PredictionRowTile extends StatelessWidget {
  const _PredictionRowTile({required this.row, required this.onTap});

  final PredictionRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (row.officialHit) {
      1 => ('中', DuiliaoColors.hit, Icons.check_circle),
      0 => ('挂', DuiliaoColors.miss, Icons.cancel),
      _ => ('待判', DuiliaoColors.pending, Icons.hourglass_empty),
    };

    final isConflict = row.isConflict;
    final draw = row.draw;

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      onTap: onTap,
      borderColor: isConflict ? DuiliaoColors.conflict.withValues(alpha: 0.55) : null,
      fillColor: isConflict ? DuiliaoColors.conflict.withValues(alpha: 0.05) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  Period.short(row.period),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                PlayTypes.labelFor(row.playType),
                style: context.texts.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (isConflict) ...[
                const GlassBadge(
                  label: '冲突',
                  color: DuiliaoColors.conflict,
                  icon: Icons.report_problem,
                  small: true,
                ),
                const SizedBox(width: 6),
              ],
              GlassBadge(label: label, color: color, icon: icon, small: true),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  row.preds.isEmpty ? '（无有效预测）' : formatAtoms(row.preds),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (draw != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '特 ',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        draw.tema,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: DuiliaoColors.forBose(draw.summary?.temaBose),
                        ),
                      ),
                      if (draw.summary?.temaXiao.isNotEmpty == true) ...[
                        const SizedBox(width: 2),
                        Text(
                          '(${draw.summary!.temaXiao})',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (isConflict || row.claimedStatus.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (row.claimedStatus.isNotEmpty)
                  Text(
                    '源自称: ${row.claimedStatus}',
                    style: context.texts.labelSmall?.copyWith(
                      color: isConflict ? DuiliaoColors.conflict : context.colors.onSurfaceVariant,
                    ),
                  ),
                if (isConflict) ...[
                  const SizedBox(width: 6),
                  const Text(
                    '· 虚假自称预警',
                    style: TextStyle(
                      fontSize: 11,
                      color: DuiliaoColors.conflict,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceDrawer extends StatelessWidget {
  const _EvidenceDrawer({required this.row, required this.controller});

  final PredictionRow row;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final draw = row.draw;
    final explanation = row.hitDetail?['explanation'] as String?;
    final rule = row.hitDetail?['rule'] as String?;
    final ruleVersion = row.hitDetail?['rule_version'] as String?;

    return GlassContainer(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      fillColor: isDark
          ? const Color(0xFF090D16).withValues(alpha: 0.90)
          : Colors.white.withValues(alpha: 0.92),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${row.sourceName ?? row.sourceId} · ${Period.compact(row.period)}',
                  style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              _StatusBadge(officialHit: row.officialHit, isConflict: row.isConflict),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${PlayTypes.labelFor(row.playType)}'
            '${row.hitMode.isNotEmpty ? ' · 判定模式 ${row.hitMode}' : ''}',
            style: context.texts.bodyMedium
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),

          if (draw != null)
            _EvidenceSection(
              title: '官方开奖结果',
              subtitle: '第 ${Period.short(draw.period)} 期',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DrawBallRow(draw: draw, ballSize: 34),
                  if (draw.summary != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _AttributeChip(label: '特肖: ${draw.summary!.temaXiao}'),
                        _AttributeChip(label: '波色: ${draw.summary!.temaBose}'),
                        _AttributeChip(label: '形态: ${draw.summary!.temaSize}${draw.summary!.temaOdd}'),
                        _AttributeChip(label: '总分: ${draw.summary!.sum7} (${draw.summary!.sum7Size}${draw.summary!.sum7Odd})'),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          _EvidenceSection(
            title: '预测内容',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AtomWrap(preds: row.preds),
                const SizedBox(height: 8),
                Text(
                  '源自称状态：${row.claimedStatus.isEmpty ? '（无）' : row.claimedStatus}',
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),

          if (row.officialHit != null)
            _EvidenceSection(
              title: '官方判定说明',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(explanation ?? (row.officialHit == 1 ? '官方判定为命中' : '官方判定为未中')),
                  if (rule != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '依据规则：$rule ${ruleVersion != null ? "($ruleVersion)" : ""}',
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            )
          else
            const WarningNote(
              message: '尚未判定：该期开奖数据尚未产生或待更新',
              icon: Icons.hourglass_empty,
            ),

          _EvidenceSection(
            title: '采集原文',
            subtitle: '抓取到的原始文字，留证追溯',
            child: SelectableText(
              row.rawText.isEmpty ? '（无抓取原文）' : row.rawText,
              style: context.texts.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),

          if (row.fetchedAt != null)
            _EvidenceSection(
              title: '采集时间',
              child: Text(row.fetchedAt!),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.officialHit, required this.isConflict});

  final int? officialHit;
  final bool isConflict;

  @override
  Widget build(BuildContext context) {
    if (isConflict) {
      return const GlassBadge(
        label: '冲突',
        color: DuiliaoColors.conflict,
        icon: Icons.report_problem,
        small: true,
      );
    }
    final (label, color, icon) = switch (officialHit) {
      1 => ('中', DuiliaoColors.hit, Icons.check_circle),
      0 => ('挂', DuiliaoColors.miss, Icons.cancel),
      _ => ('待判', DuiliaoColors.pending, Icons.hourglass_empty),
    };
    return GlassBadge(label: label, color: color, icon: icon, small: true);
  }
}

class _AtomWrap extends StatelessWidget {
  const _AtomWrap({required this.preds});

  final List<PredAtom> preds;

  @override
  Widget build(BuildContext context) {
    if (preds.isEmpty) {
      return Text(
        '（无有效预测）',
        style: context.texts.bodySmall?.copyWith(color: context.colors.error),
      );
    }
    final isNumeric = preds.every((p) => p.kind == 'num');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (isNumeric)
          for (final atom in preds)
            NumberBall(number: atom.value, size: 28, showColorName: false)
        else
          for (final atom in preds)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFF007AFF).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : const Color(0xFF007AFF).withValues(alpha: 0.20),
                  width: 0.8,
                ),
              ),
              child: Text(
                atom.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF007AFF),
                ),
              ),
            ),
      ],
    );
  }
}

class _AttributeChip extends StatelessWidget {
  const _AttributeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassContainer(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: context.texts.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: context.texts.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
}
