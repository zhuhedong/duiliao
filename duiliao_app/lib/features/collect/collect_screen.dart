/// Collection execution: submit a run, watch per-source progress, read the result.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/collect_job.dart';
import '../../ui/glass/glass_widgets.dart';
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
      backgroundColor: Colors.transparent,
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
      body: GlassBackground(
        child: TabBarView(
          controller: _tabs,
          children: const [
            _ImmediateCollectTab(),
            SchedulesTab(),
            RunHistoryTab(),
          ],
        ),
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
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      children: [
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.all(16),
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
                  ref.read(selectedLotteryProvider.notifier).set(value);
                  controller.clearSources();
                },
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动检测期号', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('由采集到的数据推断，适用于刚开奖时'),
                value: draft.autoDetectPeriod,
                onChanged: controller.setAutoDetect,
              ),
              if (!draft.autoDetectPeriod) ...[
                const SizedBox(height: 8),
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
            ],
          ),
        ),

        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '数据源选择',
                      style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openSourcePicker(context, draft.lottery),
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('配置源'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                draft.sourceIds.isEmpty
                    ? '未选择，将采集全部 $totalEnabled 个启用源'
                    : '已选 ${draft.sourceIds.length} / $totalEnabled 个源',
                style: context.texts.bodyMedium?.copyWith(
                  color: draft.sourceIds.isEmpty
                      ? context.colors.onSurfaceVariant
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: draft.sourceIds.isEmpty ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '并发线程数',
                    style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${draft.concurrency}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                title: const Text('采集后入库', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('关闭后仅抓取，不写入数据库'),
                value: draft.ingest,
                onChanged: controller.setIngest,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('入库后自动判定', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  draft.ingest ? '需要已开奖才会产生判定结果' : '需先开启入库',
                ),
                value: draft.autoJudge,
                onChanged: draft.ingest ? controller.setAutoJudge : null,
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: GlassButton(
            height: 50,
            onPressed: () => _submit(context, ref),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, size: 22),
                SizedBox(width: 8),
                Text('开始执行采集', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
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
      backgroundColor: Colors.transparent,
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
        padding: const EdgeInsets.only(top: 6, bottom: 96),
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
                  GlassButton(
                    color: DuiliaoColors.miss,
                    onPressed: () => _cancel(context, ref, job),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.stop_circle_outlined, size: 20),
                        SizedBox(width: 6),
                        Text('取消任务'),
                      ],
                    ),
                  )
                else ...[
                  if (job.failedSourceIds.isNotEmpty) ...[
                    GlassButton(
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: () => _retryFailed(context, ref, job),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.replay, size: 20),
                          const SizedBox(width: 6),
                          Text('只重采失败源（${job.failedSourceIds.length}）'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
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
                  '任务 #${job.id} · ${Lottery.labelFor(job.lottery)} '
                  '${job.period == null ? '自动期号' : Period.compact(job.period)}',
                  style: context.texts.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _JobStatusChip(job: job),
            ],
          ),
          const SizedBox(height: 12),
          GlassLinearProgress(
            value: job.isActive && job.sourceTotal == 0 ? 0.0 : job.progress,
            height: 10,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${job.sourceDone}/${job.sourceTotal} 完成 · '
                '成功 ${job.sourceOk} · 失败 ${job.sourceFailed}',
                style: context.texts.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (elapsed != null)
                Text(
                  '${elapsed.inSeconds} 秒',
                  style: context.texts.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _PhaseChip(phase: job.phase, current: true),
              const SizedBox(width: 8),
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
    return GlassBadge(label: job.status.label, color: color, icon: icon, small: true);
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase, this.current = false});

  final JobPhase phase;
  final bool current;

  @override
  Widget build(BuildContext context) => GlassBadge(
        label: phase.label,
        color: current ? Theme.of(context).colorScheme.primary : DuiliaoColors.pending,
        small: true,
      );
}

/// One source's state in glass card.
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

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3.5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          item.state == SourceState.running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                item.state == SourceState.fail && item.errorLabel != null
                    ? Text(
                        '${item.errorLabel}${item.errorMsg == null ? '' : ' · ${item.errorMsg}'}',
                        style: TextStyle(color: color, fontSize: 11.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : (item.state == SourceState.ok
                        ? Text(
                            '${item.itemCount ?? 0} 条 · ${item.elapsedLabel ?? '—'}',
                            style: context.texts.labelSmall
                                ?.copyWith(color: context.colors.onSurfaceVariant),
                          )
                        : Text(item.state.label, style: context.texts.labelSmall)),
              ],
            ),
          ),
          if (item.state == SourceState.ok)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: DuiliaoColors.hit.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${item.itemCount ?? 0}',
                style: const TextStyle(
                  color: DuiliaoColors.hit,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
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
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '任务结果',
            style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
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
            Text('入库统计', style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
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
            Text('判定统计', style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
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
                message: '判定未成功：${judge.error ?? '未知原因'}（采集与入库不受影响）',
                icon: Icons.gavel,
              ),
          ],
          if (job.failedSourceIds.isNotEmpty) ...[
            const Divider(height: 22),
            Text(
              '失败源（${job.failedSourceIds.length}）',
              style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final item in job.items.where((i) => i.state == SourceState.fail))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '· ${item.displayName} — ${item.errorLabel ?? '未知错误'}',
                  style: context.texts.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

