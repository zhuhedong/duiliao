/// Collection-job submission and progress polling.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    // Follow whichever lottery the operator is browsing elsewhere.
    final lottery = ref.watch(selectedLotteryProvider);
    return CollectRequestDraft(lottery: lottery);
  }

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

/// Polls one job until it reaches a terminal state.
///
/// Implemented as a stream so polling stops automatically when nothing is
/// listening — leaving the screen must not keep an encrypted request running
/// every two seconds. The job itself continues server-side regardless, so
/// returning to the screen resumes from wherever it has got to.
final jobProgressProvider =
    StreamProvider.family<CollectJob, int>((ref, jobId) async* {
  final repo = ref.read(collectorRepositoryProvider);
  while (true) {
    final job = await repo.collectJob(jobId);
    yield job;
    if (job.isTerminal) return;
    await Future<void>.delayed(kJobPollInterval);
  }
});

/// Run history.
final jobHistoryProvider =
    FutureProvider.family<CollectJobPage, Lottery?>((ref, lottery) async {
  return ref
      .read(collectorRepositoryProvider)
      .collectJobs(limit: 50, lottery: lottery?.code);
});

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
