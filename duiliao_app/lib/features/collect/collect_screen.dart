/// Collection execution: submit a run, watch per-source progress, read the result.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/collect_job.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../comparison/comparison_screen.dart';
import 'collect_providers.dart';
import 'schedules_tab.dart';
import 'source_picker.dart';

class CollectScreen extends ConsumerStatefulWidget {
  const CollectScreen({super.key});

  @override
  ConsumerState<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends ConsumerState<CollectScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('采集'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '立即采集'),
            Tab(text: '定时任务'),
            Tab(text: '运行记录'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ImmediateCollectTab(),
          SchedulesTab(),
          RunHistoryTab(),
        ],
      ),
    );
  }
}

class _ImmediateCollectTab extends ConsumerWidget {
  const _ImmediateCollectTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeJobId = ref.watch(activeJobIdProvider);
    if (activeJobId != null) {
      return _JobProgressView(jobId: activeJobId);
    }
    return const _CollectForm();
  }
}

class _CollectForm extends ConsumerWidget {
  const _CollectForm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(collectDraftProvider);
    final controller = ref.read(collectDraftProvider.notifier);
    final sourcesAsync = ref.watch(sourcesForLotteryProvider(draft.lottery));
    final totalEnabled = sourcesAsync.value?.length ?? 0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<Lottery>(
                  initialValue: draft.lottery,
                  decoration: const InputDecoration(labelText: '彩种'),
                  items: [
                    for (final l in Lottery.all)
                      DropdownMenuItem(value: l, child: Text(l.label)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    // Switching lottery invalidates the source selection, since
                    // sources are lottery-specific.
                    ref.read(selectedLotteryProvider.notifier).set(value);
                    controller.clearSources();
                  },
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动检测期号'),
                  subtitle: const Text('由采集到的数据推断，适用于刚开奖时'),
                  value: draft.autoDetectPeriod,
                  onChanged: controller.setAutoDetect,
                ),
                if (!draft.autoDetectPeriod)
                  TextFormField(
                    initialValue: draft.period,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '期号',
                      helperText: '可填 248 或 2026248',
                    ),
                    onChanged: controller.setPeriod,
                  ),
              ],
            ),
          ),
        ),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('数据源', style: context.texts.titleSmall),
                    ),
                    TextButton.icon(
                      onPressed: () => _openSourcePicker(context, draft.lottery),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('选择'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  draft.sourceIds.isEmpty
                      // An empty selection is not "nothing": the backend treats
                      // it as every enabled source.
                      ? '未选择，将采集全部 $totalEnabled 个启用源'
                      : '已选 ${draft.sourceIds.length} / $totalEnabled 个源',
                  style: context.texts.bodyMedium,
                ),
              ],
            ),
          ),
        ),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('并发', style: context.texts.titleSmall),
                    const Spacer(),
                    Text(
                      '${draft.concurrency}',
                      style: context.texts.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Slider(
                  value: draft.concurrency.toDouble(),
                  min: 1,
                  max: 32,
                  divisions: 31,
                  label: '${draft.concurrency}',
                  onChanged: (value) => controller.setConcurrency(value.round()),
                ),
                Text(
                  '每个源都是一个子进程，并发过高会加重服务器负载',
                  style: context.texts.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('采集后入库'),
                  subtitle: const Text('关闭后仅抓取，不写入数据库'),
                  value: draft.ingest,
                  onChanged: controller.setIngest,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('入库后自动判定'),
                  // Judging reads ingested rows, so it cannot run without ingest.
                  subtitle: Text(
                    draft.ingest ? '需要已开奖才会产生判定结果' : '需先开启入库',
                  ),
                  value: draft.autoJudge,
                  onChanged: draft.ingest ? controller.setAutoJudge : null,
                ),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => _submit(context, ref),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始采集'),
          ),
        ),
      ],
    );
  }

  void _openSourcePicker(BuildContext context, Lottery lottery) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scrollController) => SourcePicker(
          lottery: lottery,
          scrollController: scrollController,
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final draft = ref.read(collectDraftProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (!draft.autoDetectPeriod && !Period.looksValid(draft.period)) {
      messenger.showSnackBar(const SnackBar(content: Text('期号格式不正确')));
      return;
    }

    try {
      final job = await ref.read(collectorRepositoryProvider).submitCollectJob(
            lottery: draft.lottery.code,
            period: draft.autoDetectPeriod ? null : draft.period,
            sourceIds: draft.sourceIds.isEmpty ? null : draft.sourceIds.toList(),
            concurrency: draft.concurrency,
            ingest: draft.ingest,
            autoJudge: draft.autoJudge,
          );
      // Submission returns immediately; the run continues server-side.
      ref.read(activeJobIdProvider.notifier).set(job.id);
      ref.invalidate(jobHistoryProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } on NetworkException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }
}

/// Live per-source progress for a running job, and the result once finished.
class _JobProgressView extends ConsumerWidget {
  const _JobProgressView({required this.jobId});

  final int jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jobProgressProvider(jobId));

    return AsyncView<CollectJob>(
      value: async,
      loading: const SkeletonList(itemHeight: 60),
      onRetry: () => ref.invalidate(jobProgressProvider(jobId)),
      builder: (job) => ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _JobHeaderCard(job: job),
          if (job.isTerminal) _JobResultCard(job: job),
          const SectionHeader(title: '逐源状态'),
          for (final item in job.items) _SourceProgressTile(item: item),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                if (job.isActive)
                  OutlinedButton.icon(
                    onPressed: () => _cancel(context, ref, job),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('取消任务'),
                  )
                else ...[
                  if (job.failedSourceIds.isNotEmpty)
                    FilledButton.icon(
                      onPressed: () => _retryFailed(context, ref, job),
                      icon: const Icon(Icons.replay),
                      label: Text('只重采失败源（${job.failedSourceIds.length}）'),
                    ),
                  const SizedBox(height: 8),
                  if (job.period != null)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ComparisonScreen(
                            lottery: Lottery.parse(job.lottery),
                            initialPeriod: job.period,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('查看本期对照'),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.read(activeJobIdProvider.notifier).set(null),
                    child: const Text('返回采集表单'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, CollectJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('取消采集任务？'),
        // Being explicit avoids the expectation that cancelling is instantaneous.
        content: const Text('已在执行的源会跑完，尚未开始的源将被跳过。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续执行'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消任务'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(collectorRepositoryProvider).cancelCollectJob(job.id);
      ref.invalidate(jobProgressProvider(job.id));
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
    }
  }

  Future<void> _retryFailed(
    BuildContext context,
    WidgetRef ref,
    CollectJob job,
  ) async {
    // Re-submitting with only the failed subset is all that is needed; there is
    // no separate retry endpoint.
    ref.read(collectDraftProvider.notifier).setSources(job.failedSourceIds);
    try {
      final next = await ref.read(collectorRepositoryProvider).submitCollectJob(
            lottery: job.lottery,
            period: job.period,
            sourceIds: job.failedSourceIds,
            concurrency: job.concurrency,
            ingest: job.doIngest,
            autoJudge: job.autoJudge,
          );
      ref.read(activeJobIdProvider.notifier).set(next.id);
      ref.invalidate(jobHistoryProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.displayMessage)));
      }
    }
  }
}

class _JobHeaderCard extends StatelessWidget {
  const _JobHeaderCard({required this.job});

  final CollectJob job;

  @override
  Widget build(BuildContext context) {
    final elapsed = job.duration;
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
                    '任务 #${job.id} · ${Lottery.labelFor(job.lottery)} '
                    '${job.period == null ? '自动期号' : Period.compact(job.period)}',
                    style: context.texts.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _JobStatusChip(job: job),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: job.isActive && job.sourceTotal == 0 ? null : job.progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${job.sourceDone}/${job.sourceTotal} 完成 · '
                  '成功 ${job.sourceOk} · 失败 ${job.sourceFailed}',
                  style: context.texts.bodySmall,
                ),
                const Spacer(),
                if (elapsed != null)
                  Text(
                    '${elapsed.inSeconds} 秒',
                    style: context.texts.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _PhaseChip(phase: job.phase, current: true),
                const SizedBox(width: 6),
                Text(
                  '并发 ${job.concurrency}'
                  '${job.doIngest ? ' · 入库' : ' · 不入库'}'
                  '${job.autoJudge && job.doIngest ? ' · 自动判定' : ''}',
                  style: context.texts.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
            if (job.cancelRequested && job.isActive) ...[
              const SizedBox(height: 8),
              const WarningNote(
                message: '已请求取消，正在执行的源会跑完后停止',
                icon: Icons.stop_circle_outlined,
              ),
            ],
            if (job.status == JobStatus.interrupted) ...[
              const SizedBox(height: 8),
              const WarningNote(
                message: '任务被服务端重启中断，结果可能不完整，请重新发起',
                icon: Icons.power_off,
              ),
            ],
            if (job.error != null) ...[
              const SizedBox(height: 8),
              WarningNote(
                message: job.error!,
                icon: Icons.error_outline,
                color: DuiliaoColors.miss,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JobStatusChip extends StatelessWidget {
  const _JobStatusChip({required this.job});

  final CollectJob job;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (job.status) {
      JobStatus.queued => (DuiliaoColors.pending, Icons.schedule),
      JobStatus.running => (DuiliaoColors.warning, Icons.autorenew),
      JobStatus.done => (DuiliaoColors.hit, Icons.check_circle),
      JobStatus.failed => (DuiliaoColors.miss, Icons.error),
      JobStatus.cancelled => (DuiliaoColors.pending, Icons.cancel),
      JobStatus.interrupted => (DuiliaoColors.conflict, Icons.power_off),
    };
    return StatusChip(label: job.status.label, color: color, icon: icon);
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase, this.current = false});

  final JobPhase phase;
  final bool current;

  @override
  Widget build(BuildContext context) => StatusChip(
        label: phase.label,
        color: current ? context.colors.primary : context.colors.onSurfaceVariant,
        compact: true,
      );
}

/// One source's state. Icons are distinct shapes, not just colours, so the list
/// is readable at a glance and without relying on hue.
class _SourceProgressTile extends StatelessWidget {
  const _SourceProgressTile({required this.item});

  final CollectJobItem item;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.state) {
      SourceState.queued => (Icons.radio_button_unchecked, DuiliaoColors.pending),
      SourceState.running => (Icons.autorenew, DuiliaoColors.warning),
      SourceState.ok => (Icons.check_circle, DuiliaoColors.hit),
      SourceState.fail => (Icons.cancel, DuiliaoColors.miss),
    };

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: item.state == SourceState.running
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: color, size: 20),
      title: Text(item.displayName, overflow: TextOverflow.ellipsis),
      subtitle: item.state == SourceState.fail && item.errorLabel != null
          ? Text(
              '${item.errorLabel}'
              '${item.errorMsg == null ? '' : ' · ${item.errorMsg}'}',
              style: TextStyle(color: color),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : (item.state == SourceState.ok
              ? Text('${item.itemCount ?? 0} 条 · ${item.elapsedLabel ?? '—'}')
              : Text(item.state.label)),
      trailing: item.state == SourceState.ok
          ? Text(
              '${item.itemCount ?? 0}',
              style: context.texts.titleSmall?.copyWith(
                color: DuiliaoColors.hit,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          : null,
    );
  }
}

class _JobResultCard extends StatelessWidget {
  const _JobResultCard({required this.job});

  final CollectJob job;

  @override
  Widget build(BuildContext context) {
    final ingest = job.ingestStats;
    final judge = job.judgeStats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('任务结果', style: context.texts.titleSmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: '成功比',
                    value: job.successRatioLabel,
                    valueColor: job.sourceFailed > 0 ? DuiliaoColors.warning : null,
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: '耗时',
                    value: '${job.duration?.inSeconds ?? 0} 秒',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: '期号',
                    value: job.period == null ? '—' : Period.short(job.period),
                  ),
                ),
              ],
            ),
            if (ingest != null) ...[
              const Divider(height: 22),
              Text('入库统计', style: context.texts.labelLarge),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: StatTile(label: '新增', value: '${ingest.inserted}')),
                  Expanded(child: StatTile(label: '更新', value: '${ingest.updated}')),
                  Expanded(child: StatTile(label: '未变', value: '${ingest.unchanged}')),
                  Expanded(child: StatTile(label: '条目', value: '${ingest.items}')),
                ],
              ),
            ] else if (!job.doIngest) ...[
              const Divider(height: 22),
              const WarningNote(
                message: '本次未开启入库，数据仅抓取未写入',
                icon: Icons.info_outline,
              ),
            ],
            if (judge != null) ...[
              const Divider(height: 22),
              Text('判定统计', style: context.texts.labelLarge),
              const SizedBox(height: 6),
              if (judge.ok)
                Row(
                  children: [
                    Expanded(child: StatTile(label: '已判', value: '${judge.judged}')),
                    Expanded(
                      child: StatTile(
                        label: '命中',
                        value: '${judge.hits}',
                        valueColor: DuiliaoColors.hit,
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: '脏源',
                        value: '${judge.dirtyClaimed}',
                        valueColor: judge.dirtyClaimed > 0
                            ? DuiliaoColors.conflict
                            : null,
                      ),
                    ),
                  ],
                )
              else
                WarningNote(
                  // A judge failure does not invalidate the collection itself.
                  message: '判定未成功：${judge.error ?? '未知原因'}（采集与入库不受影响）',
                  icon: Icons.gavel,
                ),
            ],
            if (job.failedSourceIds.isNotEmpty) ...[
              const Divider(height: 22),
              Text(
                '失败源（${job.failedSourceIds.length}）',
                style: context.texts.labelLarge,
              ),
              const SizedBox(height: 4),
              for (final item in job.items.where((i) => i.state == SourceState.fail))
                Text(
                  '· ${item.displayName} — ${item.errorLabel ?? '未知错误'}',
                  style: context.texts.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
