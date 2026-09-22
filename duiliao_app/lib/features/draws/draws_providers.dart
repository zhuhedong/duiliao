/// Providers for the draw list and detail screens.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/collector_repository.dart';
import '../../domain/lottery.dart';
import '../../domain/models/draw.dart';

/// Page size for the draw list. Chosen so the first screenful arrives quickly
/// while still giving a useful amount of scroll before the next fetch.
const int kDrawPageSize = 20;

/// Accumulated, paged draw list for one lottery.
@immutable
class DrawListState {
  const DrawListState({
    this.items = const [],
    this.total = 0,
    this.isLoadingMore = false,
    this.isStale = false,
    this.loadMoreError,
    this.storedAtLabel,
    this.periodFrom,
    this.periodTo,
  });

  final List<DrawRow> items;

  /// Total rows the server reports, used to decide when the list is exhausted.
  final int total;

  final bool isLoadingMore;

  /// A transient error from the last pagination request. The already-loaded
  /// rows remain usable while the footer offers an explicit retry.
  final String? loadMoreError;

  /// True when the visible rows came from the cache while offline.
  final bool isStale;

  final String? storedAtLabel;

  /// Active period-range filter, if any.
  final String? periodFrom;
  final String? periodTo;

  bool get hasMore => items.length < total;
  bool get isFiltered => periodFrom != null || periodTo != null;

  DrawListState copyWith({
    List<DrawRow>? items,
    int? total,
    bool? isLoadingMore,
    bool? isStale,
    String? loadMoreError,
    bool clearLoadMoreError = false,
    String? storedAtLabel,
    String? periodFrom,
    String? periodTo,
    bool clearFilter = false,
  }) =>
      DrawListState(
        items: items ?? this.items,
        total: total ?? this.total,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        isStale: isStale ?? this.isStale,
        loadMoreError: clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
        storedAtLabel: storedAtLabel ?? this.storedAtLabel,
        periodFrom: clearFilter ? null : (periodFrom ?? this.periodFrom),
        periodTo: clearFilter ? null : (periodTo ?? this.periodTo),
      );
}

/// Paged draw list, keyed by lottery so each tab keeps its own scroll position
/// and page depth.
final drawListProvider =
    AsyncNotifierProvider.family<DrawListNotifier, DrawListState, Lottery>(
  DrawListNotifier.new,
);

class DrawListNotifier extends AsyncNotifier<DrawListState> {
  // Riverpod 3 passes a family argument through the constructor.
  DrawListNotifier(this.lottery);

  final Lottery lottery;

  @override
  Future<DrawListState> build() => _loadFirstPage();

  CollectorRepository get _repo => ref.read(collectorRepositoryProvider);

  Future<DrawListState> _loadFirstPage({
    bool forceRefresh = false,
    String? periodFrom,
    String? periodTo,
  }) async {
    final result = await _repo.draws(
      lottery: lottery.code,
      limit: kDrawPageSize,
      offset: 0,
      periodFrom: periodFrom,
      periodTo: periodTo,
      forceRefresh: forceRefresh,
    );
    return DrawListState(
      items: result.value.items,
      total: result.value.total,
      isStale: result.isStale,
      storedAtLabel: result.storedAtLabel,
      periodFrom: periodFrom,
      periodTo: periodTo,
    );
  }

  /// Pull-to-refresh: bypass the cache and reset to the first page.
  ///
  /// The current rows stay on screen while the request runs — a pull-to-refresh
  /// that blanks the list is disorienting — so no loading state is emitted.
  Future<void> refresh() async {
    final current = state.value;
    try {
      state = AsyncValue.data(await _loadFirstPage(
        forceRefresh: true,
        periodFrom: current?.periodFrom,
        periodTo: current?.periodTo,
      ));
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// Apply or clear a period-range filter.
  Future<void> applyFilter({String? periodFrom, String? periodTo}) async {
    state = const AsyncValue<DrawListState>.loading();
    try {
      state = AsyncValue.data(await _loadFirstPage(
        forceRefresh: true,
        periodFrom: periodFrom,
        periodTo: periodTo,
      ));
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// Append the next page. Safe to call repeatedly: it no-ops while a fetch is
  /// in flight or when the list is already complete.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncValue.data(current.copyWith(
      isLoadingMore: true,
      clearLoadMoreError: true,
    ));
    try {
      final result = await _repo.draws(
        lottery: lottery.code,
        limit: kDrawPageSize,
        offset: current.items.length,
        periodFrom: current.periodFrom,
        periodTo: current.periodTo,
      );
      // Deduplicate by period: a draw appearing while paging would otherwise
      // shift the offset and produce a repeated row.
      final seen = current.items.map((d) => d.period).toSet();
      final appended = [
        ...current.items,
        ...result.value.items.where((d) => !seen.contains(d.period)),
      ];
      state = AsyncValue.data(current.copyWith(
        items: appended,
        total: result.value.total,
        isLoadingMore: false,
        isStale: result.isStale,
        storedAtLabel: result.storedAtLabel,
        clearLoadMoreError: true,
      ));
    } catch (_) {
      // Keep what is already on screen, but expose a retry affordance in the
      // footer instead of silently pretending pagination completed.
      state = AsyncValue.data(current.copyWith(
        isLoadingMore: false,
        loadMoreError: '加载失败，请重试',
      ));
    }
  }
}

/// A single draw, looked up from the already-loaded list where possible and
/// otherwise fetched by period range.
final drawDetailProvider = FutureProvider.family<DrawRow?, ({Lottery lottery, String period})>(
  (ref, key) async {
    final cached = ref.read(drawListProvider(key.lottery)).value;
    final existing =
        cached?.items.where((d) => d.period == key.period).firstOrNull;
    // The list rows are already enriched with per-ball attributes, so a cached
    // row is complete and needs no second request.
    if (existing != null && existing.isEnriched) return existing;

    final repo = ref.read(collectorRepositoryProvider);
    final result = await repo.draws(
      lottery: key.lottery.code,
      limit: 1,
      periodFrom: key.period,
      periodTo: key.period,
      forceRefresh: true,
    );
    return result.value.items.isEmpty ? null : result.value.items.first;
  },
);
