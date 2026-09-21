/// Asynchronous collection job models, matching `/app/collect-jobs`.
library;

import '../json.dart';
import 'source.dart';

/// Overall job state.
enum JobStatus {
  queued('queued', '排队中'),
  running('running', '执行中'),
  done('done', '已完成'),
  failed('failed', '失败'),
  cancelled('cancelled', '已取消'),

  /// The server restarted while the job was in flight. Jobs run in-process, so
  /// there is no way to resume one — it is marked interrupted at startup rather
  /// than left polling as "running" forever.
  interrupted('interrupted', '已中断');

  const JobStatus(this.code, this.label);
  final String code;
  final String label;

  static JobStatus? tryParse(String? code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }

  bool get isTerminal => this != queued && this != running;
  bool get isActive => this == queued || this == running;
}

/// Which stage the job is in.
enum JobPhase {
  queued('queued', '排队'),
  collecting('collecting', '采集中'),
  ingesting('ingesting', '入库中'),
  judging('judging', '判定中'),
  done('done', '完成');

  const JobPhase(this.code, this.label);
  final String code;
  final String label;

  static JobPhase? tryParse(String? code) {
    for (final phase in values) {
      if (phase.code == code) return phase;
    }
    return null;
  }
}

/// Per-source state within a job.
enum SourceState {
  queued('queued', '排队'),
  running('running', '运行中'),
  ok('ok', '成功'),
  fail('fail', '失败');

  const SourceState(this.code, this.label);
  final String code;
  final String label;

  static SourceState tryParse(String? code) {
    for (final state in values) {
      if (state.code == code) return state;
    }
    return SourceState.queued;
  }

  bool get isFinished => this == ok || this == fail;
}

/// One source's progress inside a job.
class CollectJobItem {
  const CollectJobItem({
    required this.sourceId,
    this.sourceName,
    required this.state,
    this.itemCount,
    this.elapsedMs,
    this.exitCode,
    this.errorCode,
    this.errorMsg,
  });

  final String sourceId;
  final String? sourceName;
  final SourceState state;

  /// Predictions extracted. Null until the source finishes.
  final int? itemCount;

  final int? elapsedMs;
  final int? exitCode;

  /// `timeout` | `no_script` | `bad_json` | `empty_stdout` | `source_fail` |
  /// `cancelled` | `worker_error`.
  final String? errorCode;

  final String? errorMsg;

  factory CollectJobItem.fromJson(Map<String, dynamic> json) => CollectJobItem(
        sourceId: asString(json['source_id']),
        sourceName: asStringOrNull(json['source_name']),
        state: SourceState.tryParse(asStringOrNull(json['state'])),
        itemCount: asIntOrNull(json['item_count']),
        elapsedMs: asIntOrNull(json['elapsed_ms']),
        exitCode: asIntOrNull(json['exit_code']),
        errorCode: asStringOrNull(json['error_code']),
        errorMsg: asStringOrNull(json['error_msg']),
      );

  String get displayName => sourceName?.isNotEmpty == true ? sourceName! : sourceId;

  /// Chinese explanation of the failure reason.
  String? get errorLabel {
    switch (errorCode) {
      case null:
        return null;
      case 'timeout':
        return '超时';
      case 'no_script':
        return '脚本缺失';
      case 'bad_script_path':
        return '脚本路径无效';
      case 'empty_stdout':
        return '无输出';
      case 'bad_json':
        return '输出格式错误';
      case 'source_fail':
        return '源返回失败';
      case 'cancelled':
        return '已取消';
      case 'worker_error':
        return '执行异常';
      default:
        return errorCode;
    }
  }

  String? get elapsedLabel {
    final ms = elapsedMs;
    if (ms == null) return null;
    return ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';
  }
}

/// A collection job.
class CollectJob {
  const CollectJob({
    required this.id,
    required this.lottery,
    this.period,
    required this.sourceIds,
    required this.concurrency,
    required this.doIngest,
    required this.autoJudge,
    required this.status,
    required this.phase,
    this.runId,
    required this.sourceTotal,
    required this.sourceDone,
    required this.sourceOk,
    required this.cancelRequested,
    this.createdBy,
    this.scheduleId,
    this.error,
    required this.items,
    this.result,
    this.failed = const [],
    this.createdAt,
    this.startedAt,
    this.finishedAt,
  });

  final int id;
  final String lottery;

  /// Null until a period is detected from the collected data.
  final String? period;

  final List<String> sourceIds;
  final int concurrency;
  final bool doIngest;
  final bool autoJudge;
  final JobStatus status;
  final JobPhase phase;
  final String? runId;
  final int sourceTotal;
  final int sourceDone;
  final int sourceOk;
  final bool cancelRequested;
  final String? createdBy;

  /// Set when the job came from a schedule rather than a manual submission.
  final int? scheduleId;

  final String? error;

  /// Per-source progress, in submitted order so the list does not reshuffle
  /// between polls.
  final List<CollectJobItem> items;

  /// Final statistics; absent from the list view, which omits it for size.
  final Map<String, dynamic>? result;

  /// Failed sources, for the one-tap retry.
  final List<CollectJobItem> failed;

  final String? createdAt;
  final String? startedAt;
  final String? finishedAt;

  factory CollectJob.fromJson(Map<String, dynamic> json) => CollectJob(
        id: asInt(json['id']),
        lottery: asString(json['lottery']),
        period: asStringOrNull(json['period']),
        sourceIds: asStringList(json['source_ids']),
        concurrency: asInt(json['concurrency'], fallback: 8),
        doIngest: asBool(json['do_ingest'], fallback: true),
        autoJudge: asBool(json['auto_judge'], fallback: true),
        status: JobStatus.tryParse(asStringOrNull(json['status'])) ?? JobStatus.queued,
        phase: JobPhase.tryParse(asStringOrNull(json['phase'])) ?? JobPhase.queued,
        runId: asStringOrNull(json['run_id']),
        sourceTotal: asInt(json['source_total']),
        sourceDone: asInt(json['source_done']),
        sourceOk: asInt(json['source_ok']),
        cancelRequested: asBool(json['cancel_requested']),
        createdBy: asStringOrNull(json['created_by']),
        scheduleId: asIntOrNull(json['schedule_id']),
        error: asStringOrNull(json['error']),
        items: asModelList(json['items'], CollectJobItem.fromJson),
        result: asMapOrNull(json['result']),
        failed: asModelList(json['failed'], CollectJobItem.fromJson),
        createdAt: asStringOrNull(json['created_at']),
        startedAt: asStringOrNull(json['started_at']),
        finishedAt: asStringOrNull(json['finished_at']),
      );

  /// Completion in `0..1`. Zero rather than NaN when no sources matched.
  double get progress => sourceTotal == 0 ? 0 : sourceDone / sourceTotal;

  int get sourceFailed => sourceDone - sourceOk;

  bool get isActive => status.isActive;
  bool get isTerminal => status.isTerminal;

  /// Source ids that failed, for re-submitting only those.
  List<String> get failedSourceIds =>
      items.where((i) => i.state == SourceState.fail).map((i) => i.sourceId).toList();

  IngestStats? get ingestStats =>
      asModelOrNull(result?['ingest'], IngestStats.fromJson);

  JudgeStats? get judgeStats => asModelOrNull(result?['judge'], JudgeStats.fromJson);

  DateTime? get startedAtTime => asDateTimeOrNull(startedAt);
  DateTime? get finishedAtTime => asDateTimeOrNull(finishedAt);
  DateTime? get createdAtTime => asDateTimeOrNull(createdAt);

  /// Wall-clock duration, using now as the end for a job still running.
  Duration? get duration {
    final start = startedAtTime;
    if (start == null) return null;
    final end = finishedAtTime ?? DateTime.now();
    final delta = end.difference(start);
    return delta.isNegative ? Duration.zero : delta;
  }

  String get successRatioLabel => '$sourceOk/$sourceTotal';
}

/// `GET /app/collect-jobs` response.
class CollectJobPage {
  const CollectJobPage({
    required this.total,
    required this.count,
    required this.items,
    this.worker,
  });

  final int total;
  final int count;
  final List<CollectJob> items;
  final CollectWorkerStatus? worker;

  factory CollectJobPage.fromJson(Map<String, dynamic> json) => CollectJobPage(
        total: asInt(json['total']),
        count: asInt(json['count']),
        items: asModelList(json['items'], CollectJob.fromJson),
        worker: asModelOrNull(json['worker'], CollectWorkerStatus.fromJson),
      );

  static const empty = CollectJobPage(total: 0, count: 0, items: []);

  /// Jobs grouped by calendar day, newest day first, for the history view.
  Map<String, List<CollectJob>> get groupedByDay {
    final out = <String, List<CollectJob>>{};
    for (final job in items) {
      final at = job.createdAtTime;
      final key = at == null
          ? '未知日期'
          : '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
      out.putIfAbsent(key, () => []).add(job);
    }
    return out;
  }
}

/// Job worker runtime state.
class CollectWorkerStatus {
  const CollectWorkerStatus({
    required this.running,
    required this.checkIntervalSeconds,
    required this.maxConcurrentJobs,
    required this.activeJobsCount,
    required this.runningJobIds,
  });

  final bool running;
  final int checkIntervalSeconds;
  final int maxConcurrentJobs;
  final int activeJobsCount;
  final List<int> runningJobIds;

  factory CollectWorkerStatus.fromJson(Map<String, dynamic> json) => CollectWorkerStatus(
        running: asBool(json['running']),
        checkIntervalSeconds: asInt(json['check_interval_seconds']),
        maxConcurrentJobs: asInt(json['max_concurrent_jobs'], fallback: 1),
        activeJobsCount: asInt(json['active_jobs_count']),
        runningJobIds: asList(json['running_job_ids'])
            .map(asIntOrNull)
            .whereType<int>()
            .toList(growable: false),
      );

  /// True when the worker is already at its job limit, so a new submission will
  /// queue rather than start immediately.
  bool get isSaturated => activeJobsCount >= maxConcurrentJobs;
}
