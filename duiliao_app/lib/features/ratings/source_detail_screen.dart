/// One source: configuration, health, and its prediction history.
library;

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

/// Configuration, health and history for one source, fetched together.
///
/// The three requests run concurrently — three sequential encrypted round-trips
/// would be a noticeable wait on a mobile link — and each degrades to null or an
/// empty list independently, so one failing block does not blank the screen.
final sourceDetailProvider = FutureProvider.family<
    ({
      CollectorSource? source,
      MonitorRow? monitor,
      List<PredictionRow> predictions,
    }),
    ({String sourceId, Lottery lottery})>((ref, key) async {
  final repo = ref.read(collectorRepositoryProvider);

  Future<CollectorSource?> loadSource() async {
    try {
      return await repo.source(key.sourceId);
    } catch (_) {
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
      return null;
    }
  }

  Future<List<PredictionRow>> loadPredictions() async {
    try {
      return await repo.predictions(
        sourceId: key.sourceId,
        lottery: key.lottery.code,
        limit: 60,
      );
    } catch (_) {
      return const [];
    }
  }

  final source = loadSource();
  final monitor = loadMonitor();
  final predictions = loadPredictions();

  return (
    source: await source,
    monitor: await monitor,
    predictions: await predictions,
  );
});

class SourceDetailScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (sourceId: sourceId, lottery: lottery);
    final async = ref.watch(sourceDetailProvider(key));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(sourceName ?? sourceId)),
      body: GlassBackground(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(sourceDetailProvider(key)),
          child: AsyncView<({CollectorSource? source, MonitorRow? monitor, List<PredictionRow> predictions})>(
            value: async,
            loading: const SkeletonList(itemHeight: 90),
            onRetry: () => ref.invalidate(sourceDetailProvider(key)),
            builder: (data) => ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 96),
              children: [
                if (data.source != null) _InfoCard(source: data.source!),
                if (data.monitor != null) _HealthCard(monitor: data.monitor!),
                const SectionHeader(
                  title: '历史预测流水',
                  subtitle: '最近 60 条',
                ),
                if (data.predictions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('暂无预测记录')),
                  )
                else
                  for (final row in data.predictions) _PredictionRowTile(row: row),
              ],
            ),
          ),
        ),
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
  const _PredictionRowTile({required this.row});

  final PredictionRow row;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (row.officialHit) {
      1 => ('中', DuiliaoColors.hit, Icons.check_circle),
      0 => ('挂', DuiliaoColors.miss, Icons.cancel),
      _ => ('待判', DuiliaoColors.pending, Icons.hourglass_empty),
    };

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.preds.isEmpty ? '（无有效预测）' : formatAtoms(row.preds),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${PlayTypes.labelFor(row.playType)}'
                  '${row.claimedStatus.isEmpty ? '' : ' · 自称 ${row.claimedStatus}'}',
                  style: context.texts.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlassBadge(label: label, color: color, icon: icon, small: true),
        ],
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

