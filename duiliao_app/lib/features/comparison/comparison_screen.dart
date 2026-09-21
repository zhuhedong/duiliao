/// Period comparison: every source's prediction against the official judgement.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/prediction.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../../ui/widgets/number_ball.dart';
import '../auth/auth_providers.dart';

/// Comparison for a (lottery, period) pair.
final comparisonProvider = FutureProvider.family<
    ({PeriodComparisonResult result, bool isStale, String? storedAt}),
    ({Lottery lottery, String period})>((ref, key) async {
  final fetched = await ref
      .read(collectorRepositoryProvider)
      .comparison(lottery: key.lottery.code, period: key.period);
  return (
    result: fetched.value,
    isStale: fetched.isStale,
    storedAt: fetched.storedAtLabel,
  );
});

/// The latest period for a lottery, so the screen can open without one.
final latestPeriodProvider =
    FutureProvider.family<String?, Lottery>((ref, lottery) async {
  final draws = await ref
      .read(collectorRepositoryProvider)
      .draws(lottery: lottery.code, limit: 1);
  return draws.value.items.isEmpty ? null : draws.value.items.first.period;
});

class ComparisonScreen extends ConsumerStatefulWidget {
  const ComparisonScreen({super.key, this.lottery, this.initialPeriod});

  final Lottery? lottery;
  final String? initialPeriod;

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends ConsumerState<ComparisonScreen> {
  String? _period;
  ComparisonStatus? _filter;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
  }

  @override
  Widget build(BuildContext context) {
    final Lottery lottery = widget.lottery ?? ref.watch(selectedLotteryProvider);

    // With no explicit period, fall back to the newest one for this lottery.
    if (_period == null) {
      final latest = ref.watch(latestPeriodProvider(lottery));
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('明细对照')),
        body: GlassBackground(
          child: latest.when(
            loading: () => const SkeletonList(),
            error: (e, _) => ErrorState(
              error: e,
              onRetry: () => ref.invalidate(latestPeriodProvider(lottery)),
            ),
            data: (period) {
              if (period == null) {
                return const EmptyState(message: '暂无开奖期号');
              }
              // Adopt it and rebuild with a concrete period.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _period = period);
              });
              return const SkeletonList();
            },
          ),
        ),
      );
    }

    final key = (lottery: lottery, period: _period!);
    final async = ref.watch(comparisonProvider(key));
    final canOperate = ref.watch(canOperateProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('明细对照 ${Period.compact(_period)}'),
        actions: [
          IconButton(
            tooltip: '选择期号',
            icon: const Icon(Icons.event),
            onPressed: _pickPeriod,
          ),
          if (canOperate)
            IconButton(
              tooltip: '重新判定',
              icon: const Icon(Icons.gavel),
              onPressed: () => _rejudge(key),
            ),
        ],
      ),
      body: GlassBackground(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(comparisonProvider(key)),
          child: AsyncView<({PeriodComparisonResult result, bool isStale, String? storedAt})>(
            value: async,
            loading: const SkeletonList(itemHeight: 88),
            onRetry: () => ref.invalidate(comparisonProvider(key)),
            builder: (data) {
              final result = data.result;
              final rows = result.withStatus(_filter);
              return Column(
                children: [
                  if (data.isStale)
                    OfflineBanner(
                      storedAtLabel: data.storedAt,
                      onRetry: () => ref.invalidate(comparisonProvider(key)),
                    ),
                  const SizedBox(height: 6),
                  _SummaryBar(summary: result.summary),
                  _StatusFilterBar(
                    summary: result.summary,
                    selected: _filter,
                    onChanged: (status) => setState(() => _filter = status),
                  ),
                  if (result.draw != null)
                    GlassCard(
                      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '开奖结果',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DrawBallRow(
                              draw: result.draw!,
                              ballSize: 30,
                              showColorNames: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: rows.isEmpty
                        ? EmptyState(
                            message: _filter == null
                                ? '本期暂无源预测'
                                : '没有${_filter!.label}状态的记录',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 4, bottom: 96),
                            itemCount: rows.length,
                            itemBuilder: (context, index) => _ComparisonRow(
                              item: rows[index],
                              onTap: () => _showEvidence(rows[index]),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _pickPeriod() async {
    final controller = TextEditingController(text: Period.short(_period));
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('输入期号'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(helperText: '可填 248 或 2026248'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    if (!Period.looksValid(value)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('期号格式不正确')));
      return;
    }
    setState(() => _period = value);
  }

  Future<void> _rejudge(({Lottery lottery, String period}) key) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在重新判定…')));
    try {
      await ref.read(collectorRepositoryProvider).rejudge(
            lottery: key.lottery.code,
            period: key.period,
          );
      ref.invalidate(comparisonProvider(key));
      messenger.showSnackBar(const SnackBar(content: Text('判定已更新')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } on NetworkException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }

  void _showEvidence(ComparisonItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, controller) =>
            _EvidenceDrawer(item: item, controller: controller),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.summary});

  final ComparisonSummary summary;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          StatTile(label: '总数', value: '${summary.total}'),
          StatTile(
            label: '命中',
            value: '${summary.hits}',
            valueColor: DuiliaoColors.hit,
          ),
          StatTile(
            label: '未中',
            value: '${summary.misses}',
            valueColor: DuiliaoColors.miss,
          ),
          StatTile(
            label: '待判',
            value: '${summary.pending}',
            valueColor: DuiliaoColors.pending,
          ),
          StatTile(
            label: '冲突',
            value: '${summary.conflicts}',
            valueColor: summary.conflicts > 0 ? DuiliaoColors.conflict : null,
          ),
          StatTile(
            label: '命中率',
            value: formatRateDisplay(summary),
            hint: summary.judged == 0 ? '尚未判定' : '已判 ${summary.judged}',
          ),
        ],
      ),
    );
  }

  /// Hit rate is only meaningful once something has been judged; showing 0.0%
  /// before any judgement would read as "everything missed".
  static String formatRateDisplay(ComparisonSummary summary) =>
      summary.judged == 0 ? '—' : '${(summary.hitRate * 100).toStringAsFixed(1)}%';
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.summary,
    required this.selected,
    required this.onChanged,
  });

  final ComparisonSummary summary;
  final ComparisonStatus? selected;
  final ValueChanged<ComparisonStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    final counts = [
      (status: ComparisonStatus.hit, count: summary.hits, color: DuiliaoColors.hit),
      (status: ComparisonStatus.miss, count: summary.misses, color: DuiliaoColors.miss),
      (status: ComparisonStatus.pending, count: summary.pending, color: DuiliaoColors.pending),
      (status: ComparisonStatus.conflict, count: summary.conflicts, color: DuiliaoColors.conflict),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          GlassFilterPill(
            label: '全部',
            count: summary.total,
            isSelected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final item in counts) ...[
            const SizedBox(width: 8),
            GlassFilterPill(
              label: item.status.label,
              count: item.count,
              color: item.color,
              isSelected: selected == item.status,
              onTap: () => onChanged(item.status),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.item, required this.onTap});

  final ComparisonItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.sourceName}${item.groupSuffix}',
                  style: context.texts.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: item.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            PlayTypes.labelFor(item.playType),
            style: context.texts.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          _AtomRow(item: item),
          if (item.isConflict) ...[
            const SizedBox(height: 10),
            WarningNote(
              message: '源自称「${item.claimedStatus}」，实际判定为未中',
              icon: Icons.report_problem_outlined,
              color: DuiliaoColors.conflict,
            ),
          ],
        ],
      ),
    );
  }
}

class _AtomRow extends StatelessWidget {
  const _AtomRow({required this.item});

  final ComparisonItem item;

  @override
  Widget build(BuildContext context) {
    if (item.preds.isEmpty) {
      return Text(
        '无有效预测内容',
        style: context.texts.bodySmall?.copyWith(color: context.colors.error),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNumeric = item.preds.every((p) => p.kind == 'num');
    if (isNumeric) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final atom in item.preds)
            NumberBall(number: atom.value, size: 30, showColorName: false),
        ],
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: [
        for (final atom in item.preds)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFF007AFF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
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
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF007AFF),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ComparisonStatus? status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      ComparisonStatus.hit => ('中', DuiliaoColors.hit, Icons.check_circle),
      ComparisonStatus.miss => ('挂', DuiliaoColors.miss, Icons.cancel),
      ComparisonStatus.conflict => (
          '冲突',
          DuiliaoColors.conflict,
          Icons.report_problem,
        ),
      ComparisonStatus.pending => (
          '待判',
          DuiliaoColors.pending,
          Icons.hourglass_empty,
        ),
      null => ('未判定', DuiliaoColors.pending, Icons.help_outline),
    };
    return GlassBadge(label: label, color: color, icon: icon);
  }
}

/// Full judgement evidence for one row.
class _EvidenceDrawer extends StatelessWidget {
  const _EvidenceDrawer({required this.item, required this.controller});

  final ComparisonItem item;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1522) : const Color(0xFFF3F6FD),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${item.sourceName}${item.groupSuffix}',
                  style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _StatusBadge(status: item.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${PlayTypes.labelFor(item.playType)} · ${Period.compact(item.period)} · '
            '判定模式 ${item.hitMode}',
            style: context.texts.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const Divider(height: 24),

          if (!item.isJudged)
            const WarningNote(
              message: '尚未判定：该期开奖数据可能还未同步',
              icon: Icons.hourglass_empty,
            )
          else ...[
            _EvidenceSection(
              title: '判定说明',
              child: Text(item.explanation ?? '（后端未提供说明）'),
            ),
            _EvidenceSection(
              title: '适用规则',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.rule ?? item.playType),
                  if (item.scopeLabel != null)
                    Text(
                      '范围：${item.scopeLabel}',
                      style: context.texts.bodySmall,
                    ),
                  if (item.ruleVersion != null)
                    Text(
                      '规则版本：${item.ruleVersion}',
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],

          _EvidenceSection(
            title: '预测内容',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AtomRow(item: item),
                const SizedBox(height: 8),
                Text(
                  '源自称状态：${item.claimedStatus.isEmpty ? '（无）' : item.claimedStatus}',
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),

          if (item.drawSnapshot != null)
            _EvidenceSection(
              title: '开奖快照',
              subtitle: '判定当时所依据的开奖数据',
              child: _JsonBlock(data: item.drawSnapshot!),
            ),

          if (item.predictionSnapshot != null)
            _EvidenceSection(
              title: '预测快照',
              subtitle: '判定当时所依据的预测数据',
              child: _JsonBlock(data: item.predictionSnapshot!),
            ),

          _EvidenceSection(
            title: '采集原文',
            subtitle: '从站点抓取的原始文本',
            child: SelectableText(
              item.rawText.isEmpty ? '（无原文）' : item.rawText,
              style: context.texts.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),

          if (item.fetchedAt != null || item.judgedAt != null)
            _EvidenceSection(
              title: '时间线',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.fetchedAt != null) Text('采集于 ${item.fetchedAt}'),
                  if (item.judgedAt != null) Text('判定于 ${item.judgedAt}'),
                ],
              ),
            ),
        ],
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
      child: GlassCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: context.texts.labelSmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String text;
    try {
      text = const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      text = data.toString();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.8,
        ),
      ),
      child: SelectableText(
        text,
        style: context.texts.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

