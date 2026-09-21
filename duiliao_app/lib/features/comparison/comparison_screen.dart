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
        appBar: AppBar(title: const Text('明细对照')),
        body: latest.when(
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
      );
    }

    final key = (lottery: lottery, period: _period!);
    final async = ref.watch(comparisonProvider(key));
    final canOperate = ref.watch(canOperateProvider);

    return Scaffold(
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
      body: RefreshIndicator(
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
                _SummaryBar(summary: result.summary),
                _StatusFilterBar(
                  summary: result.summary,
                  selected: _filter,
                  onChanged: (status) => setState(() => _filter = status),
                ),
                if (result.draw != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Text('开奖', style: context.texts.labelMedium),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DrawBallRow(
                                draw: result.draw!,
                                ballSize: 28,
                                showColorNames: false,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                          padding: const EdgeInsets.only(bottom: 24),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
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
    final counts = {
      ComparisonStatus.hit: summary.hits,
      ComparisonStatus.miss: summary.misses,
      ComparisonStatus.pending: summary.pending,
      ComparisonStatus.conflict: summary.conflicts,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            label: Text('全部 ${summary.total}'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          for (final entry in counts.entries) ...[
            const SizedBox(width: 6),
            FilterChip(
              label: Text('${entry.key.label} ${entry.value}'),
              selected: selected == entry.key,
              onSelected: (_) => onChanged(entry.key),
              // Conflict is tinted even when unselected so it draws the eye.
              backgroundColor: entry.key == ComparisonStatus.conflict &&
                      entry.value > 0
                  ? DuiliaoColors.conflict.withValues(alpha: 0.12)
                  : null,
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
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.sourceName}${item.groupSuffix}',
                      style: context.texts.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
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
              const SizedBox(height: 8),
              _AtomRow(item: item),
              if (item.isConflict) ...[
                const SizedBox(height: 8),
                // The single most decision-relevant state in the app: the source
                // said it hit and the judge says it did not.
                WarningNote(
                  message: '源自称「${item.claimedStatus}」，实际判定为未中',
                  icon: Icons.report_problem_outlined,
                  color: DuiliaoColors.conflict,
                ),
              ],
            ],
          ),
        ),
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
    // Number atoms render as balls so the colour information is preserved;
    // everything else renders as a text chip.
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
      runSpacing: 4,
      children: [
        for (final atom in item.preds)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: context.colors.secondaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              atom.value,
              style: context.texts.labelLarge
                  ?.copyWith(color: context.colors.onSecondaryContainer),
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
    // Icon and text together: hit and miss must not be distinguishable by colour
    // alone.
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
    return StatusChip(label: label, color: color, icon: icon);
  }
}

/// Full judgement evidence for one row.
///
/// The client renders the backend's `hit_detail` verbatim and performs **no
/// second judgement of its own**: a locally computed verdict could disagree with
/// the server's, and the server's is the one the ratings are built from.
class _EvidenceDrawer extends StatelessWidget {
  const _EvidenceDrawer({required this.item, required this.controller});

  final ComparisonItem item;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${item.sourceName}${item.groupSuffix}',
                style: context.texts.titleMedium,
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
              const SizedBox(height: 6),
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
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: context.texts.labelSmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    String text;
    try {
      text = const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      // A non-encodable value must not break the drawer.
      text = data.toString();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: context.texts.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}
