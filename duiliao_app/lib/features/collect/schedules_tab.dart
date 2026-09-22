/// Scheduled tasks (view + toggle + trigger) and the run history.
///
/// Creating and editing schedules is deliberately **not** offered here: cron
/// editing needs room and careful validation, and belongs in the web console.
/// The app covers the operational cases — check status, pause something that is
/// misbehaving, trigger a catch-up run, read the log.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/collect_job.dart';
import '../../domain/models/source.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import 'collect_providers.dart';
String _formatCollectTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return raw;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}:${two(parsed.second)}';
}

class SchedulesTab extends ConsumerWidget {
  const SchedulesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(schedulesProvider(null));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(schedulesProvider(null)),
      child: AsyncView<SchedulesResponse>(
        value: async,
        loading: const SkeletonList(itemHeight: 120),
        onRetry: () => ref.invalidate(schedulesProvider(null)),
        builder: (data) => ListView(
          padding: const EdgeInsets.only(top: 6, bottom: 96),
          children: [
            _SchedulerStatusCard(status: data.scheduler),
            if (data.schedules.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: EmptyState(
                  message: '暂无定时任务',
                  detail: '请在 Web 后台创建',
                  icon: Icons.schedule,
                ),
              )
            else
              for (final schedule in data.schedules)
                _ScheduleCard(schedule: schedule),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '新建与编辑定时任务请在 Web 后台操作。此处仅支持启停、立即执行与查看日志。',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SchedulerStatusCard extends StatelessWidget {
  const _SchedulerStatusCard({required this.status});

  final SchedulerStatus status;

  @override
  Widget build(BuildContext context) {
    final isRunning = status.running;
    final color = isRunning ? DuiliaoColors.hit : DuiliaoColors.pending;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              isRunning ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: color,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isRunning ? '调度器运行中' : '调度器未运行',
                      style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    GlassBadge(
                      label: isRunning ? 'Active' : 'Paused',
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '检查间隔 ${status.checkIntervalSeconds}s · '
                  '进行中 ${status.activeTasksCount} 个',
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.schedule});

  final CollectionSchedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(scheduleActionProvider(schedule.id));
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  schedule.name,
                  style: context.texts.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Switch(
                value: schedule.enabled,
                onChanged: action == null ? (value) => _toggle(context, ref, value) : null,
              ),
            ],
          ),
          Text(
            '${Lottery.labelFor(schedule.lottery)} · '
            '${schedule.sourceCount == null ? '全部源' : '${schedule.sourceCount} 个源'}'
            ' · 并发 ${schedule.concurrency}',
            style: context.texts.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GlassBadge(
                label: schedule.isTimeWindow ? '时间窗口' : 'cron',
                color: context.colors.primary,
                icon: schedule.isTimeWindow ? Icons.timelapse : Icons.schedule,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  schedule.scheduleLabel,
                  style: context.texts.labelSmall?.copyWith(
                    fontFamily: schedule.isTimeWindow ? null : 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: '上次执行',
                    value: schedule.lastRunAt ?? '—',
                    valueColor:
                        schedule.lastRunFailed ? DuiliaoColors.miss : null,
                    hint: schedule.lastStatus == null
                        ? null
                        : (schedule.lastRunFailed ? '失败' : '成功'),
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: '下次执行',
                    value: schedule.displayNextRun ?? (schedule.enabled ? '—' : '已停用'),
                  ),
                ),
              ],
            ),
          ),
          if (schedule.lastRunFailed) ...[
            const SizedBox(height: 8),
            const WarningNote(
              message: '上次执行失败，请查看日志',
              icon: Icons.error_outline,
              color: DuiliaoColors.miss,
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: action == null ? () => _trigger(context, ref) : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('立即执行'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: action == null ? () => _showLogs(context, ref) : null,
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('日志'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool enabled) async {
    final action = ref.read(scheduleActionProvider(schedule.id).notifier);
    if (action.state != null) return;
    action.state = ScheduleAction.toggle;
    try {
      await ref
          .read(collectorRepositoryProvider)
          .setScheduleEnabled(schedule.id, enabled);
      ref.invalidate(schedulesProvider(null));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(enabled ? '已启用「${schedule.name}」' : '已停用「${schedule.name}」')),
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
    } on NetworkException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
    } finally {
      action.state = null;
    }
  }

  Future<void> _trigger(BuildContext context, WidgetRef ref) async {
    final action = ref.read(scheduleActionProvider(schedule.id).notifier);
    if (action.state != null) return;
    action.state = ScheduleAction.trigger;
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('正在触发「${schedule.name}」…')));
    }
    try {
      await ref.read(collectorRepositoryProvider).triggerSchedule(schedule.id);
      ref.invalidate(schedulesProvider(null));
      ref.invalidate(jobHistoryProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已触发，请在运行记录中查看')));
      }
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
    } on NetworkException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
    } finally {
      action.state = null;
    }
  }

  Future<void> _showLogs(BuildContext context, WidgetRef ref) async {
    List<SchedulerLogEntry> logs;
    final action = ref.read(scheduleActionProvider(schedule.id).notifier);
    if (action.state != null) return;
    action.state = ScheduleAction.logs;
    try {
      logs = await ref.read(collectorRepositoryProvider).scheduleLogs(schedule.id);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
      action.state = null;
      return;
    } on NetworkException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
      action.state = null;
      return;
    }
    if (!context.mounted) {
      action.state = null;
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          blur: 35,
          fillColor: context.colors.surface.withValues(alpha: 0.88),
          padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.paddingOf(context).bottom + 24),
          child: ListView(
            controller: controller,
            children: [
              Text('${schedule.name} 执行日志', style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (logs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('暂无日志')),
                )
              else
                for (final log in logs)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          log.failed ? Icons.error_rounded : Icons.check_circle_rounded,
                          color: log.failed ? DuiliaoColors.miss : DuiliaoColors.hit,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(log.detail, style: context.texts.bodySmall),
                              const SizedBox(height: 4),
                              Text(
                                '${_formatCollectTime(log.timestamp)}'
                                '${log.durationSec == null ? '' : ' · ${log.durationSec}s'}',
                                style: context.texts.labelSmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
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
    action.state = null;
  }
}

/// Historical job runs, grouped by day.
class RunHistoryTab extends ConsumerWidget {
  const RunHistoryTab({super.key, this.onOpenJob});

  final VoidCallback? onOpenJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jobHistoryProvider(null));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(jobHistoryProvider(null)),
      child: AsyncView<CollectJobPage>(
        value: async,
        loading: const SkeletonList(itemHeight: 76),
        onRetry: () => ref.invalidate(jobHistoryProvider(null)),
        emptyCheck: (page) => page.items.isEmpty,
        emptyMessage: '暂无采集记录',
        builder: (page) {
          final grouped = page.groupedByDay;
          return ListView(
            padding: const EdgeInsets.only(top: 6, bottom: 96),
            children: [
              if (page.worker != null) _WorkerCard(worker: page.worker!),
              for (final entry in grouped.entries) ...[
                SectionHeader(
                  title: entry.key,
                  subtitle: '${entry.value.length} 个任务',
                ),
                for (final job in entry.value)
                  _HistoryTile(job: job, onOpenJob: onOpenJob),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WorkerCard extends StatelessWidget {
  const _WorkerCard({required this.worker});

  final CollectWorkerStatus worker;

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (worker.running ? DuiliaoColors.hit : DuiliaoColors.pending).withValues(alpha: 0.15),
              ),
              child: Icon(
                worker.running ? Icons.play_arrow_rounded : Icons.pause_rounded,
                color: worker.running ? DuiliaoColors.hit : DuiliaoColors.pending,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '采集执行器${worker.running ? '运行中' : '未运行'} · '
                '进行中 ${worker.activeJobsCount}/${worker.maxConcurrentJobs}',
                style: context.texts.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (worker.isSaturated)
              const GlassBadge(
                label: '已满排队中',
                color: DuiliaoColors.warning,
              ),
          ],
        ),
      );
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.job, this.onOpenJob});

  final CollectJob job;
  final VoidCallback? onOpenJob;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (color, icon) = switch (job.status) {
      JobStatus.done => (DuiliaoColors.hit, Icons.check_circle_rounded),
      JobStatus.failed => (DuiliaoColors.miss, Icons.error_rounded),
      JobStatus.cancelled => (DuiliaoColors.pending, Icons.cancel_rounded),
      JobStatus.interrupted => (DuiliaoColors.conflict, Icons.power_off_rounded),
      _ => (DuiliaoColors.warning, Icons.autorenew_rounded),
    };

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.all(12),
      onTap: () {
        ref.read(activeJobIdProvider.notifier).set(job.id);
        onOpenJob?.call();
      },
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${job.id} ${Lottery.labelFor(job.lottery)} '
                  '${job.period == null ? '自动期号' : Period.compact(job.period)}',
                  style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${job.successRatioLabel} 成功'
                  '${job.duration == null ? '' : ' · ${job.duration!.inSeconds}s'}'
                  '${job.startedAt == null ? '' : ' · ${_formatCollectTime(job.startedAt)}'}',
                  style: context.texts.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          GlassBadge(label: job.status.label, color: color),
        ],
      ),
    );
  }
}
