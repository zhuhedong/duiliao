/// Source catalogue, script-run and schedule models from `collector.ts`.
library;

import '../json.dart';

/// A configured collection source. Mirrors `CollectorSource`.
class CollectorSource {
  const CollectorSource({
    required this.sourceId,
    required this.sourceName,
    required this.siteFamily,
    required this.lottery,
    required this.playType,
    required this.hitMode,
    required this.scriptPath,
    required this.timeoutSec,
    required this.enabled,
    this.remark,
    this.extra = const {},
    this.scriptExists,
    this.scriptPathValid,
  });

  final String sourceId;
  final String sourceName;

  /// Sites sharing a family are collapsed to one consensus vote, so this
  /// identifies which sources are not independent of each other.
  final String siteFamily;

  final String lottery;
  final String playType;

  /// `any` or `all`.
  final String hitMode;

  final String scriptPath;
  final int timeoutSec;
  final bool enabled;
  final String? remark;
  final Map<String, dynamic> extra;

  /// Set by the catalogue check; false means the script file is missing.
  final bool? scriptExists;
  final bool? scriptPathValid;

  factory CollectorSource.fromJson(Map<String, dynamic> json) => CollectorSource(
        sourceId: asString(json['source_id']),
        sourceName: asString(json['source_name']),
        siteFamily: asString(json['site_family']),
        lottery: asString(json['lottery']),
        playType: asString(json['play_type']),
        hitMode: asString(json['hit_mode']),
        scriptPath: asString(json['script_path']),
        timeoutSec: asInt(json['timeout_sec'], fallback: 30),
        enabled: asBool(json['enabled'], fallback: true),
        remark: asStringOrNull(json['remark']),
        extra: asMap(json['extra']),
        scriptExists: asBoolOrNull(json['script_exists']),
        scriptPathValid: asBoolOrNull(json['script_path_valid']),
      );

  /// True when the source is configured but cannot actually run.
  bool get isBroken => scriptExists == false || scriptPathValid == false;

  /// Case-insensitive match across the fields an operator would search by.
  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return sourceName.toLowerCase().contains(q) ||
        sourceId.toLowerCase().contains(q) ||
        siteFamily.toLowerCase().contains(q);
  }
}

/// Result of running one source script. Mirrors `ScriptRunResult`.
///
/// This is the only place `stdout` / `stderr` surface, which is what makes it
/// useful for diagnosing a failing source in the field.
class ScriptRunResult {
  const ScriptRunResult({
    required this.ok,
    this.sourceId,
    this.name,
    required this.lottery,
    this.period,
    this.exitCode,
    required this.elapsedMs,
    required this.itemCount,
    required this.stdout,
    required this.stderr,
    this.errorCode,
    this.errorMsg,
    this.data,
    this.ingest,
  });

  final bool ok;
  final String? sourceId;

  /// Set instead of [sourceId] when a script was run by filename.
  final String? name;

  final String lottery;
  final String? period;

  /// Process exit code. Null when the script never started.
  final int? exitCode;

  final int elapsedMs;

  /// Predictions extracted.
  final int itemCount;

  final String stdout;
  final String stderr;

  /// `timeout` | `no_script` | `bad_script_path` | `empty_stdout` | `bad_json` |
  /// `source_fail`.
  final String? errorCode;

  final String? errorMsg;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? ingest;

  factory ScriptRunResult.fromJson(Map<String, dynamic> json) => ScriptRunResult(
        ok: asBool(json['ok']),
        sourceId: asStringOrNull(json['source_id']),
        name: asStringOrNull(json['name']),
        lottery: asString(json['lottery']),
        period: asStringOrNull(json['period']),
        exitCode: asIntOrNull(json['exit_code']),
        elapsedMs: asInt(json['elapsed_ms']),
        itemCount: asInt(json['item_count']),
        // Two run_one error branches omit these keys entirely.
        stdout: asString(json['stdout']),
        stderr: asString(json['stderr']),
        errorCode: asStringOrNull(json['error_code']),
        errorMsg: asStringOrNull(json['error_msg']),
        data: asMapOrNull(json['data']),
        ingest: asMapOrNull(json['ingest']),
      );

  String get elapsedLabel => elapsedMs < 1000
      ? '$elapsedMs ms'
      : '${(elapsedMs / 1000).toStringAsFixed(1)} s';

  /// True when stderr is worth showing, i.e. the run failed and wrote something.
  bool get hasDiagnostics => !ok && stderr.trim().isNotEmpty;
}

/// A scheduled collection task. Mirrors `CollectionSchedule`.
///
/// The app is read-plus-toggle only: creating and editing schedules stays in the
/// web console, where there is room for cron editing.
class CollectionSchedule {
  const CollectionSchedule({
    required this.id,
    required this.name,
    required this.lottery,
    this.period,
    this.sourceIds,
    this.cron,
    this.startAt,
    this.endAt,
    required this.intervalMinutes,
    required this.enabled,
    required this.doIngest,
    required this.autoJudge,
    this.nextRunAt,
    this.lastRunAt,
    this.lastStatus,
    this.lastResult,
    this.spec,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String lottery;
  final String? period;

  /// Null means every enabled source for the lottery.
  final List<String>? sourceIds;

  /// A 5-field cron expression, when scheduling is cron-based.
  final String? cron;

  final String? startAt;
  final String? endAt;

  /// Non-zero when scheduling is a repeating time window instead of cron.
  final int intervalMinutes;

  final bool enabled;
  final bool doIngest;
  final bool autoJudge;
  final String? nextRunAt;
  final String? lastRunAt;

  /// `success` | `error` | null.
  final String? lastStatus;

  final Map<String, dynamic>? lastResult;
  final Map<String, dynamic>? spec;
  final String? createdAt;
  final String? updatedAt;

  factory CollectionSchedule.fromJson(Map<String, dynamic> json) => CollectionSchedule(
        id: asInt(json['id']),
        name: asString(json['name']),
        lottery: asString(json['lottery']),
        period: asStringOrNull(json['period']),
        sourceIds: json['source_ids'] == null ? null : asStringList(json['source_ids']),
        cron: asStringOrNull(json['cron']),
        startAt: asStringOrNull(json['start_at']),
        endAt: asStringOrNull(json['end_at']),
        intervalMinutes: asInt(json['interval_minutes']),
        enabled: asBool(json['enabled']),
        doIngest: asBool(json['do_ingest'], fallback: true),
        autoJudge: asBool(json['auto_judge'], fallback: true),
        nextRunAt: asStringOrNull(json['next_run_at']),
        lastRunAt: asStringOrNull(json['last_run_at']),
        lastStatus: asStringOrNull(json['last_status']),
        lastResult: asMapOrNull(json['last_result']),
        spec: asMapOrNull(json['spec']),
        createdAt: asStringOrNull(json['created_at']),
        updatedAt: asStringOrNull(json['updated_at']),
      );

  bool get lastRunFailed => lastStatus == 'error';

  /// True when this uses a repeating time window rather than cron. The two modes
  /// display differently.
  bool get isTimeWindow => intervalMinutes > 0 && (cron == null || cron!.isEmpty);

  /// Concurrency from `spec`, where the web console stores it.
  int get concurrency => asInt(spec?['concurrency'], fallback: 8);

  /// Source count, or null when it means "all enabled sources".
  int? get sourceCount => sourceIds?.length;

  /// Human description of the schedule mode.
  String get scheduleLabel {
    if (cron != null && cron!.isNotEmpty) return 'cron $cron';
    if (intervalMinutes > 0) return '每 $intervalMinutes 分钟';
    if (startAt != null) return '单次 $startAt';
    return '未配置';
  }

  /// Next run, suppressed when disabled since it would be misleading.
  String? get displayNextRun => enabled ? nextRunAt : null;
}

/// Scheduler runtime state. Mirrors `SourceSchedulerStatus`.
class SchedulerStatus {
  const SchedulerStatus({
    required this.running,
    required this.checkIntervalSeconds,
    required this.activeTasksCount,
    required this.runningTaskIds,
    required this.recentLogs,
  });

  final bool running;
  final int checkIntervalSeconds;
  final int activeTasksCount;
  final List<int> runningTaskIds;
  final List<SchedulerLogEntry> recentLogs;

  factory SchedulerStatus.fromJson(Map<String, dynamic> json) => SchedulerStatus(
        running: asBool(json['running']),
        checkIntervalSeconds: asInt(json['check_interval_seconds']),
        activeTasksCount: asInt(json['active_tasks_count']),
        runningTaskIds: asList(json['running_task_ids'])
            .map(asIntOrNull)
            .whereType<int>()
            .toList(growable: false),
        recentLogs: asModelList(json['recent_logs'], SchedulerLogEntry.fromJson),
      );

  static const empty = SchedulerStatus(
    running: false,
    checkIntervalSeconds: 0,
    activeTasksCount: 0,
    runningTaskIds: [],
    recentLogs: [],
  );
}

class SchedulerLogEntry {
  const SchedulerLogEntry({
    required this.timestamp,
    required this.scheduleId,
    required this.scheduleName,
    required this.action,
    required this.status,
    required this.detail,
    this.concurrency,
    this.durationSec,
  });

  final String timestamp;
  final int scheduleId;
  final String scheduleName;
  final String action;
  final String status;
  final String detail;
  final int? concurrency;
  final double? durationSec;

  factory SchedulerLogEntry.fromJson(Map<String, dynamic> json) => SchedulerLogEntry(
        timestamp: asString(json['timestamp']),
        scheduleId: asInt(json['schedule_id']),
        scheduleName: asString(json['schedule_name']),
        action: asString(json['action']),
        status: asString(json['status']),
        detail: asString(json['detail']),
        concurrency: asIntOrNull(json['concurrency']),
        durationSec: asDoubleOrNull(json['duration_sec']),
      );

  bool get failed => status == 'error';
}

/// `GET /collector/schedules` response. Mirrors `SchedulesResponse`.
class SchedulesResponse {
  const SchedulesResponse({required this.scheduler, required this.schedules});

  final SchedulerStatus scheduler;
  final List<CollectionSchedule> schedules;

  factory SchedulesResponse.fromJson(Map<String, dynamic> json) => SchedulesResponse(
        scheduler: asModelOrNull(json['scheduler'], SchedulerStatus.fromJson) ??
            SchedulerStatus.empty,
        schedules: asModelList(json['schedules'], CollectionSchedule.fromJson),
      );
}

/// One play-type rule. Mirrors `RuleRow`.
class RuleRow {
  const RuleRow({
    required this.playType,
    required this.name,
    required this.scope,
    required this.condition,
    required this.version,
    required this.modes,
  });

  final String playType;
  final String name;

  /// Which balls the rule applies to, e.g. `七球（含特码）`.
  final String scope;

  /// The hit condition in prose.
  final String condition;

  /// `rules.py` VERSION, which also stamps every `hit_detail`.
  final String version;

  final String modes;

  factory RuleRow.fromJson(Map<String, dynamic> json) => RuleRow(
        playType: asString(json['play_type']),
        name: asString(json['name']),
        scope: asString(json['scope']),
        condition: asString(json['condition']),
        version: asString(json['version']),
        modes: asString(json['modes']),
      );
}

/// Ingest counters. Mirrors `IngestStats`.
class IngestStats {
  const IngestStats({
    required this.ok,
    required this.runId,
    required this.inserted,
    required this.updated,
    required this.unchanged,
    required this.sourceOk,
    required this.sourceFail,
    required this.items,
    required this.missingAdded,
  });

  final bool ok;
  final String runId;
  final int inserted;
  final int updated;
  final int unchanged;
  final int sourceOk;
  final int sourceFail;
  final int items;
  final int missingAdded;

  factory IngestStats.fromJson(Map<String, dynamic> json) => IngestStats(
        ok: asBool(json['ok'], fallback: true),
        runId: asString(json['run_id']),
        inserted: asInt(json['inserted']),
        updated: asInt(json['updated']),
        unchanged: asInt(json['unchanged']),
        sourceOk: asInt(json['source_ok']),
        sourceFail: asInt(json['source_fail']),
        items: asInt(json['items']),
        missingAdded: asInt(json['missing_added']),
      );
}

/// Judge counters. Mirrors `JudgeResult`.
class JudgeStats {
  const JudgeStats({
    required this.ok,
    required this.lottery,
    required this.period,
    required this.judged,
    required this.hits,
    required this.dirtyClaimed,
    required this.deadletter,
    this.error,
  });

  final bool ok;
  final String lottery;
  final String period;
  final int judged;
  final int hits;

  /// Predictions where the source's own claim contradicted the judgement.
  final int dirtyClaimed;

  final List<String> deadletter;

  /// Set when judging failed, so a collection can still report success.
  final String? error;

  factory JudgeStats.fromJson(Map<String, dynamic> json) => JudgeStats(
        ok: asBool(json['ok'], fallback: true),
        lottery: asString(json['lottery']),
        period: asString(json['period']),
        judged: asInt(json['judged']),
        hits: asInt(json['hits']),
        dirtyClaimed: asInt(json['dirty_claimed']),
        deadletter: asStringList(json['deadletter']),
        error: asStringOrNull(json['error']),
      );
}
