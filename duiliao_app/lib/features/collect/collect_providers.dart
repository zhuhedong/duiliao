/// Collection-job submission and progress polling.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/collect_job.dart';
import '../../domain/models/source.dart';

/// How often a running job is polled. Fast enough to feel live, slow enough not
/// to hammer an encrypted endpoint.
const Duration kJobPollInterval = Duration(seconds: 2);

/// Form state for an immediate collection.
@immutable
class CollectRequestDraft {
  const CollectRequestDraft({
    this.lottery = Lottery.macau,
    this.period = '',
    this.autoDetectPeriod = true,
    this.sourceIds = const {},
    this.concurrency = 8,
    this.ingest = true,
    this.autoJudge = true,
  });

  final Lottery lottery;

  /// Raw user input; the backend normalises it.
  final String period;

  /// When true no period is sent and the backend infers it from the collected
  /// items. That is the usual case right after a draw.
  final bool autoDetectPeriod;

  /// Empty means every enabled source for the lottery.
  final Set<String> sourceIds;

  final int concurrency;
  final bool ingest;

  /// Judging needs ingested rows, so it is meaningless without [ingest].
  final bool autoJudge;

  bool get judgeEffective => ingest && autoJudge;

  CollectRequestDraft copyWith({
    Lottery? lottery,
    String? period,
    bool? autoDetectPeriod,
    Set<String>? sourceIds,
    int? concurrency,
    bool? ingest,
    bool? autoJudge,
  }) =>
      CollectRequestDraft(
        lottery: lottery ?? this.lottery,
        period: period ?? this.period,
        autoDetectPeriod: autoDetectPeriod ?? this.autoDetectPeriod,
        sourceIds: sourceIds ?? this.sourceIds,
        concurrency: concurrency ?? this.concurrency,
        ingest: ingest ?? this.ingest,
        autoJudge: autoJudge ?? this.autoJudge,
      );
}

final collectDraftProvider =
    NotifierProvider<CollectDraftController, CollectRequestDraft>(
  CollectDraftController.new,
);

class CollectDraftController extends Notifier<CollectRequestDraft> {
  @override
  CollectRequestDraft build() {
    // Seed the draft from the currently selected lottery, but do not watch it
    // here. Watching would rebuild the notifier and silently reset the
    // operator's period, concurrency, and ingest choices whenever another
    // screen changes the global lottery.
    final lottery = ref.read(selectedLotteryProvider);
    return CollectRequestDraft(lottery: lottery);
  }

  /// Change the lottery while keeping the rest of the collection draft.
  ///
  /// Source ids are intentionally cleared because source ids belong to a
  /// lottery and retaining them would submit sources from the previous one.
  void setLottery(Lottery lottery) =>
      state = state.copyWith(lottery: lottery, sourceIds: const {});

  void setPeriod(String period) => state = state.copyWith(period: period);
  void setAutoDetect(bool value) =>
      state = state.copyWith(autoDetectPeriod: value);
  void setConcurrency(int value) =>
      state = state.copyWith(concurrency: value.clamp(1, 32));
  void setIngest(bool value) => state = state.copyWith(ingest: value);
  void setAutoJudge(bool value) => state = state.copyWith(autoJudge: value);

  void toggleSource(String sourceId) {
    final next = {...state.sourceIds};
    if (!next.remove(sourceId)) next.add(sourceId);
    state = state.copyWith(sourceIds: next);
  }

  void selectAll(Iterable<String> sourceIds) =>
      state = state.copyWith(sourceIds: sourceIds.toSet());

  void clearSources() => state = state.copyWith(sourceIds: const {});

  /// Replace the selection, used by "retry failed sources only".
  void setSources(Iterable<String> sourceIds) =>
      state = state.copyWith(sourceIds: sourceIds.toSet());
}

/// The job the collect screen is currently watching, or null.
final activeJobIdProvider = NotifierProvider<ActiveJobId, int?>(ActiveJobId.new);

class ActiveJobId extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

/// UI action currently being sent for one job. Keeping this in a provider lets
/// every action button disable itself immediately, even while the request is
/// waiting on the encrypted network round-trip.
enum CollectionJobAction { cancel, retry }

class CollectionJobActionNotifier
    extends AutoDisposeFamilyNotifier<CollectionJobAction?, int> {
  @override
  CollectionJobAction? build(int arg) => null;

  set state(CollectionJobAction? value) => super.state = value;
  CollectionJobAction? get state => super.state;
}

final collectionJobActionProvider = NotifierProvider.autoDispose
    .family<CollectionJobActionNotifier, CollectionJobAction?, int>(
  CollectionJobActionNotifier.new,
);

/// True while the immediate collection form is submitting a new job.
class CollectSubmitBusyNotifier extends AutoDisposeNotifier<bool> {
  @override
  bool build() => false;

  set state(bool value) => super.state = value;
  bool get state => super.state;
}

final collectSubmitBusyProvider =
    NotifierProvider.autoDispose<CollectSubmitBusyNotifier, bool>(
  CollectSubmitBusyNotifier.new,
);

/// Prevents a schedule card from sending the same mutation more than once while
/// the previous request is still in flight.
enum ScheduleAction { toggle, trigger, logs }

class ScheduleActionNotifier
    extends AutoDisposeFamilyNotifier<ScheduleAction?, int> {
  @override
  ScheduleAction? build(int arg) => null;

  set state(ScheduleAction? value) => super.state = value;
  ScheduleAction? get state => super.state;
}

final scheduleActionProvider = NotifierProvider.autoDispose
    .family<ScheduleActionNotifier, ScheduleAction?, int>(
  ScheduleActionNotifier.new,
);

/// Number of consecutive transient poll failures for a job. The progress view
/// uses this to show a reconnecting banner while the stream keeps retrying.
class JobPollRetryNotifier extends AutoDisposeFamilyNotifier<int, int> {
  @override
  int build(int arg) => 0;

  set state(int value) => super.state = value;
  int get state => super.state;
}

final jobPollRetryProvider =
    NotifierProvider.autoDispose.family<JobPollRetryNotifier, int, int>(
  JobPollRetryNotifier.new,
);

/// Polls one job until it reaches a terminal state.
///
/// Implemented as a stream so polling stops automatically when nothing is
/// listening — leaving the screen must not keep an encrypted request running
/// every two seconds. The job itself continues server-side regardless, so
/// returning to the screen resumes from wherever it has got to.
final jobProgressProvider =
    StreamProvider.family<CollectJob, int>((ref, jobId) async* {
  final repo = ref.read(collectorRepositoryProvider);
  final retryState = ref.read(jobPollRetryProvider(jobId).notifier);
  var failures = 0;
  retryState.state = 0;

  while (true) {
    try {
      final job = await repo.collectJob(jobId);
      failures = 0;
      retryState.state = 0;
      yield job;
      if (job.isTerminal) return;
      await Future<void>.delayed(kJobPollInterval);
    } on NetworkException {
      failures += 1;
      retryState.state = failures;
      final multiplier = 1 << math.min(failures - 1, 4);
      final seconds = math.min(30, kJobPollInterval.inSeconds * multiplier);
      await Future<void>.delayed(Duration(seconds: seconds));
    } on ApiException catch (error) {
      // A temporary server failure is retriable. Client errors (404, 403,
      // malformed requests) still terminate the stream and reach the error UI.
      if ((error.statusCode ?? 0) < 500) rethrow;
      failures += 1;
      retryState.state = failures;
      final multiplier = 1 << math.min(failures - 1, 4);
      final seconds = math.min(30, kJobPollInterval.inSeconds * multiplier);
      await Future<void>.delayed(Duration(seconds: seconds));
    }
  }
});

/// Run history.
final jobHistoryProvider =
    FutureProvider.family<CollectJobPage, Lottery?>((ref, lottery) async {
  return ref
      .read(collectorRepositoryProvider)
      .collectJobs(limit: 50, lottery: lottery?.code);
});

/// Query for the paged history list. The equality implementation is important
/// for Riverpod family caching: rebuilding the widget with the same filters
/// should reuse the same request rather than starting another one.
@immutable
class CollectHistoryQuery {
  const CollectHistoryQuery({
    this.lottery,
    this.status,
    this.limit = 30,
    this.offset = 0,
  });

  final Lottery? lottery;
  final String? status;
  final int limit;
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is CollectHistoryQuery &&
      other.lottery == lottery &&
      other.status == status &&
      other.limit == limit &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(lottery, status, limit, offset);
}

final collectHistoryPageProvider =
    FutureProvider.autoDispose.family<CollectJobPage, CollectHistoryQuery>(
  (ref, query) => ref.read(collectorRepositoryProvider).collectJobs(
        limit: query.limit,
        offset: query.offset,
        lottery: query.lottery?.code,
        status: query.status,
      ),
);

/// Schedules plus the scheduler's runtime state.
final schedulesProvider =
    FutureProvider.family<SchedulesResponse, Lottery?>((ref, lottery) async {
  return ref.read(collectorRepositoryProvider).schedules(lottery: lottery?.code);
});

/// Source catalogue for the picker, filtered to one lottery.
final sourcesForLotteryProvider =
    FutureProvider.family<List<CollectorSource>, Lottery>((ref, lottery) async {
  final fetched = await ref.read(collectorRepositoryProvider).sources();
  final rows = fetched.value
      .where((s) => s.lottery == lottery.code && s.enabled)
      .toList();
  rows.sort((a, b) => a.sourceName.compareTo(b.sourceName));
  return rows;
});
