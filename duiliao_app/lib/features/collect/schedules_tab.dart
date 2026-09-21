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
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import 'collect_providers.dart';

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
          padding: const EdgeInsets.only(bottom: 32),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              status.running ? Icons.play_circle : Icons.pause_circle,
              color: status.running ? DuiliaoColors.hit : DuiliaoColors.pending,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.running ? '调度器运行中' : '调度器未运行',
                    style: context.texts.titleSmall,
                  ),
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
      ),
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.schedule});

  final CollectionSchedule schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                  onChanged: (value) => _toggle(context, ref, value),
                ),
              ],
            ),
            Text(
              '${Lottery.labelFor(schedule.lottery)} · '
              '${schedule.sourceCount == null ? '全部源' : '${schedule.sourceCount} 个源'}'
              ' · 并发 ${schedule.concurrency}',
              style: context.texts.bodySmall,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // The two scheduling modes read very differently, so they are
                // labelled rather than both shown as a raw cron string.
                StatusChip(
                  label: schedule.isTimeWindow ? '时间窗口' : 'cron',
                  color: context.colors.primary,
                  icon: schedule.isTimeWindow ? Icons.timelapse : Icons.schedule,
                  compact: true,
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
            const SizedBox(height: 8),
            Row(
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
                Expanded(
                  child: StatTile(
                    label: '下次执行',
                    // Suppressed when disabled: showing a next run for a paused
                    // task would be misleading.
                    value: schedule.displayNextRun ?? (schedule.enabled ? '—' : '已停用'),
                  ),
                ),
              ],
            ),
            if (schedule.lastRunFailed) ...[
              const SizedBox(height: 8),
              const WarningNote(
                message: '上次执行失败，请查看日志',
                icon: Icons.error_outline,
                color: DuiliaoColors.miss,
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _trigger(context, ref),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('立即执行'),
                ),
                TextButton.icon(
                  onPressed: () => _showLogs(context, ref),
                  icon: const Icon(Icons.article_outlined, size: 18),
                  label: const Text('日志'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(collectorRepositoryProvider)
          .setScheduleEnabled(schedule.id, enabled);
      ref.invalidate(schedulesProvider(null));
      messenger.showSnackBar(
        SnackBar(content: Text(enabled ? '已启用「${schedule.name}」' : '已停用「${schedule.name}」')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }

  Future<void> _trigger(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('正在触发「${schedule.name}」…')));
    try {
      await ref.read(collectorRepositoryProvider).triggerSchedule(schedule.id);
      ref.invalidate(schedulesProvider(null));
      ref.invalidate(jobHistoryProvider);
      messenger.showSnackBar(const SnackBar(content: Text('已触发，请在运行记录中查看')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }

  Future<void> _showLogs(BuildContext context, WidgetRef ref) async {
    List<SchedulerLogEntry> logs;
    try {
      logs = await ref.read(collectorRepositoryProvider).scheduleLogs(schedule.id);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
      return;
    }
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Text('${schedule.name} 执行日志', style: context.texts.titleMedium),
            const SizedBox(height: 12),
            if (logs.isEmpty)
              const Text('暂无日志')
            else
              for (final log in logs)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    log.failed ? Icons.error : Icons.check_circle,
                    color: log.failed ? DuiliaoColors.miss : DuiliaoColors.hit,
                    size: 18,
                  ),
                  title: Text(log.detail, style: context.texts.bodySmall),
                  subtitle: Text(
                    '${log.timestamp}'
                    '${log.durationSec == null ? '' : ' · ${log.durationSec}s'}',
                    style: context.texts.labelSmall,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Historical job runs, grouped by day.
class RunHistoryTab extends ConsumerWidget {
  const RunHistoryTab({super.key});

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
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (page.worker != null) _WorkerCard(worker: page.worker!),
              for (final entry in grouped.entries) ...[
                SectionHeader(
                  title: entry.key,
                  subtitle: '${entry.value.length} 个任务',
                ),
                for (final job in entry.value) _HistoryTile(job: job),
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
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                worker.running ? Icons.play_circle : Icons.pause_circle,
                color: worker.running ? DuiliaoColors.hit : DuiliaoColors.pending,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '采集执行器${worker.running ? '运行中' : '未运行'} · '
                  '进行中 ${worker.activeJobsCount}/${worker.maxConcurrentJobs}',
                  style: context.texts.bodySmall,
                ),
              ),
              if (worker.isSaturated)
                const StatusChip(
                  // Tells the operator why a new submission will sit queued.
                  label: '已满，新任务将排队',
                  color: DuiliaoColors.warning,
                  compact: true,
                ),
            ],
          ),
        ),
      );
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.job});

  final CollectJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (color, icon) = switch (job.status) {
      JobStatus.done => (DuiliaoColors.hit, Icons.check_circle),
      JobStatus.failed => (DuiliaoColors.miss, Icons.error),
      JobStatus.cancelled => (DuiliaoColors.pending, Icons.cancel),
      JobStatus.interrupted => (DuiliaoColors.conflict, Icons.power_off),
      _ => (DuiliaoColors.warning, Icons.autorenew),
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(
        '#${job.id} ${Lottery.labelFor(job.lottery)} '
        '${job.period == null ? '自动期号' : Period.compact(job.period)}',
      ),
      subtitle: Text(
        '${job.successRatioLabel} 成功'
        '${job.duration == null ? '' : ' · ${job.duration!.inSeconds}s'}'
        '${job.startedAt == null ? '' : ' · ${job.startedAt}'}',
        style: context.texts.labelSmall,
      ),
      trailing: StatusChip(label: job.status.label, color: color, compact: true),
      onTap: () {
        // Reopening a job reuses the live progress view, which also works for
        // finished jobs since it polls once and stops.
        ref.read(activeJobIdProvider.notifier).set(job.id);
        DefaultTabController.maybeOf(context)?.animateTo(0);
      },
    );
  }
}
