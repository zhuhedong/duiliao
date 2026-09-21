/// Read access to the collector endpoints, with caching and offline fallback.
///
/// Every method follows one policy:
///
/// * A fresh cache hit is returned without a request.
/// * Otherwise the network is tried; success refreshes the cache.
/// * If the network fails **and** a cached copy exists, the cached copy is
///   returned marked stale so the UI can say so. A 4xx is *not* treated this way
///   — it means the request was wrong, not that the device is offline.
library;

import '../core/net/api_client.dart';
import '../core/net/api_exception.dart';
import '../core/storage/cache_store.dart';
import '../domain/json.dart';
import '../domain/models/app_event.dart';
import '../domain/models/collect_job.dart';
import '../domain/models/consensus.dart';
import '../domain/models/draw.dart';
import '../domain/models/prediction.dart';
import '../domain/models/ratings.dart';
import '../domain/models/source.dart';
import '../domain/models/user.dart';

/// A value plus whether it came from a stale cache.
class Fetched<T> {
  const Fetched(this.value, {this.isStale = false, this.storedAtLabel});

  final T value;

  /// True when this is cached data served because the network was unavailable or
  /// the TTL had expired and the refresh failed.
  final bool isStale;

  /// `HH:mm` the cached copy was stored, for the offline banner.
  final String? storedAtLabel;

  Fetched<R> map<R>(R Function(T) transform) =>
      Fetched(transform(value), isStale: isStale, storedAtLabel: storedAtLabel);
}

class CollectorRepository {
  CollectorRepository({required this._client, required this._cache});

  final ApiClient _client;
  final CacheStore _cache;

  /// Shared cache-then-network flow.
  ///
  /// [forceRefresh] bypasses a fresh cache entry, which is what pull-to-refresh
  /// does.
  Future<Fetched<T>> _cached<T>({
    required String key,
    required Duration ttl,
    required Future<Object?> Function() fetch,
    required T Function(Object? json) parse,
    bool forceRefresh = false,
  }) async {
    CachedValue<Object?>? cached;
    try {
      cached = await _cache.read(key, ttl: ttl);
    } catch (_) {
      // A cache read must never be fatal.
      cached = null;
    }

    if (!forceRefresh && cached != null && !cached.isStale) {
      return Fetched(parse(cached.value), storedAtLabel: cached.storedAtLabel);
    }

    try {
      final fresh = await fetch();
      await _cache.write(key, fresh);
      return Fetched(parse(fresh));
    } on NetworkException {
      if (cached != null) {
        // Offline with something usable on disk: show it, labelled stale.
        return Fetched(
          parse(cached.value),
          isStale: true,
          storedAtLabel: cached.storedAtLabel,
        );
      }
      rethrow;
    } on ApiException catch (e) {
      // 5xx is a server problem the cache can paper over; 4xx means the request
      // itself was wrong and must surface.
      if (cached != null && (e.statusCode ?? 500) >= 500) {
        return Fetched(
          parse(cached.value),
          isStale: true,
          storedAtLabel: cached.storedAtLabel,
        );
      }
      rethrow;
    }
  }

  // ------------------------------------------------------------------ //
  // Reference data
  // ------------------------------------------------------------------ //
  Future<Fetched<List<RuleRow>>> rules({bool forceRefresh = false}) => _cached(
        key: CacheKeys.rules,
        ttl: CacheTtl.rules,
        forceRefresh: forceRefresh,
        fetch: () => _client.get<List<dynamic>>('/collector/rules'),
        parse: (json) => asModelList(json, RuleRow.fromJson),
      );

  Future<Fetched<List<CollectorSource>>> sources({bool forceRefresh = false}) =>
      _cached(
        key: CacheKeys.sources,
        ttl: CacheTtl.sources,
        forceRefresh: forceRefresh,
        fetch: () => _client.get<List<dynamic>>('/collector/sources'),
        parse: (json) => asModelList(json, CollectorSource.fromJson),
      );

  Future<Fetched<NumbersResult>> numbers({
    required String date,
    bool forceRefresh = false,
  }) =>
      _cached(
        key: CacheKeys.numbers(date),
        ttl: CacheTtl.numbers,
        forceRefresh: forceRefresh,
        fetch: () => _client.get<Map<String, dynamic>>(
          '/collector/numbers',
          query: {'date': date},
        ),
        parse: (json) => NumbersResult.fromJson(asMap(json)),
      );

  // ------------------------------------------------------------------ //
  // Draws
  // ------------------------------------------------------------------ //
  Future<Fetched<DrawListResult>> draws({
    required String lottery,
    int limit = 20,
    int offset = 0,
    String? periodFrom,
    String? periodTo,
    bool forceRefresh = false,
  }) {
    // A filtered query is not cached: the key space is unbounded and an operator
    // running a range query wants live data.
    final isFiltered = periodFrom != null || periodTo != null;
    if (isFiltered) {
      return _client
          .get<Map<String, dynamic>>('/collector/draws', query: {
            'lottery': lottery,
            'limit': limit,
            'offset': offset,
            'period_from': periodFrom,
            'period_to': periodTo,
          })
          .then((json) => Fetched(DrawListResult.fromJson(json)));
    }
    return _cached(
      key: CacheKeys.draws(lottery, limit, offset),
      ttl: CacheTtl.draws,
      forceRefresh: forceRefresh,
      fetch: () => _client.get<Map<String, dynamic>>(
        '/collector/draws',
        query: {'lottery': lottery, 'limit': limit, 'offset': offset},
      ),
      parse: (json) => DrawListResult.fromJson(asMap(json)),
    );
  }

  // ------------------------------------------------------------------ //
  // Consensus / comparison / ratings
  // ------------------------------------------------------------------ //
  Future<Fetched<ConsensusResult>> consensus({
    required String lottery,
    required String period,
    String? playType,
    bool forceRefresh = false,
  }) =>
      _cached(
        key: CacheKeys.consensus(lottery, period),
        ttl: CacheTtl.consensus,
        forceRefresh: forceRefresh,
        fetch: () => _client.get<Map<String, dynamic>>(
          '/collector/consensus',
          query: {'lottery': lottery, 'period': period, 'play_type': playType},
        ),
        parse: (json) => ConsensusResult.fromJson(asMap(json)),
      );

  Future<Fetched<PeriodComparisonResult>> comparison({
    required String lottery,
    required String period,
    bool forceRefresh = false,
  }) =>
      _cached(
        key: CacheKeys.comparison(lottery, period),
        ttl: CacheTtl.comparison,
        forceRefresh: forceRefresh,
        fetch: () => _client.get<Map<String, dynamic>>(
          '/collector/comparison',
          query: {'lottery': lottery, 'period': period},
        ),
        parse: (json) => PeriodComparisonResult.fromJson(asMap(json)),
      );

  /// Re-run judging for a period, then return the refreshed comparison.
  /// Requires staff/admin.
  Future<PeriodComparisonResult> rejudge({
    required String lottery,
    required String period,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/collector/comparison/judge',
      body: {'lottery': lottery, 'period': period},
    );
    // The stored copy is now wrong.
    await _cache.delete(CacheKeys.comparison(lottery, period));
    await _cache.delete(CacheKeys.consensus(lottery, period));
    return PeriodComparisonResult.fromJson(json);
  }

  Future<Fetched<RatingsResult>> ratings({
    required String lottery,
    required String playType,
    List<int> windows = const [30, 50, 100],
    bool forceRefresh = false,
  }) {
    final windowParam = windows.join(',');
    return _cached(
      key: CacheKeys.ratings(lottery, playType, windowParam),
      ttl: CacheTtl.ratings,
      forceRefresh: forceRefresh,
      fetch: () => _client.get<Map<String, dynamic>>(
        '/collector/ratings',
        query: {'lottery': lottery, 'play_type': playType, 'windows': windowParam},
      ),
      parse: (json) => RatingsResult.fromJson(asMap(json)),
    );
  }

  Future<Fetched<List<MonitorRow>>> monitor({
    String? lottery,
    bool forceRefresh = false,
  }) =>
      _cached(
        key: CacheKeys.monitor(lottery ?? 'all'),
        ttl: CacheTtl.ratings,
        forceRefresh: forceRefresh,
        fetch: () => _client.get<Map<String, dynamic>>(
          '/collector/monitor',
          query: {'lottery': lottery},
        ),
        parse: (json) => asModelList(asMap(json)['items'], MonitorRow.fromJson),
      );

  /// Prediction history, optionally for one source. Not cached — it is browsed
  /// on demand and the key space is unbounded.
  Future<List<PredictionRow>> predictions({
    String? lottery,
    String? period,
    String? sourceId,
    int limit = 100,
  }) async {
    final json = await _client.get<Object?>(
      '/collector/predictions',
      query: {
        'lottery': lottery,
        'period': period,
        'source_id': sourceId,
        'limit': limit,
      },
    );
    // The endpoint has returned both a bare list and a wrapped object across
    // revisions, so both are accepted.
    if (json is List) return asModelList(json, PredictionRow.fromJson);
    return asModelList(asMap(json)['items'], PredictionRow.fromJson);
  }

  Future<CollectorSource> source(String sourceId) async {
    final json =
        await _client.get<Map<String, dynamic>>('/collector/sources/$sourceId');
    return CollectorSource.fromJson(json);
  }

  // ------------------------------------------------------------------ //
  // Home aggregate
  // ------------------------------------------------------------------ //
  Future<Fetched<HomeSnapshot>> home({
    required String lottery,
    String playType = 'pingte_xiao',
    bool forceRefresh = false,
  }) =>
      _cached(
        key: CacheKeys.home(lottery, playType),
        ttl: CacheTtl.home,
        forceRefresh: forceRefresh,
        fetch: () => _client.get<Map<String, dynamic>>(
          '/app/home',
          query: {'lottery': lottery, 'play_type': playType},
        ),
        parse: (json) => HomeSnapshot.fromJson(asMap(json)),
      );

  // ------------------------------------------------------------------ //
  // Operations (staff/admin)
  // ------------------------------------------------------------------ //
  /// Submit a collection job. Returns immediately with the queued job.
  Future<CollectJob> submitCollectJob({
    required String lottery,
    String? period,
    List<String>? sourceIds,
    int concurrency = 8,
    bool ingest = true,
    bool autoJudge = true,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/app/collect-jobs',
      body: {
        'lottery': lottery,
        if (period != null && period.trim().isNotEmpty) 'period': period.trim(),
        'source_ids': ?sourceIds,
        'concurrency': concurrency,
        'ingest': ingest,
        'auto_judge': autoJudge,
      },
    );
    return CollectJob.fromJson(json);
  }

  Future<CollectJob> collectJob(int jobId) async {
    final json =
        await _client.get<Map<String, dynamic>>('/app/collect-jobs/$jobId');
    return CollectJob.fromJson(json);
  }

  Future<CollectJob> cancelCollectJob(int jobId) async {
    final json =
        await _client.delete<Map<String, dynamic>>('/app/collect-jobs/$jobId');
    return CollectJob.fromJson(json);
  }

  Future<CollectJobPage> collectJobs({
    int limit = 30,
    int offset = 0,
    String? lottery,
    String? status,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/app/collect-jobs',
      query: {
        'limit': limit,
        'offset': offset,
        'lottery': lottery,
        'status': status,
      },
    );
    return CollectJobPage.fromJson(json);
  }

  /// Run a single source in isolation, for field diagnosis. Returns raw
  /// stdout/stderr, which no other endpoint exposes.
  Future<ScriptRunResult> testSource({
    required String sourceId,
    String lottery = 'macau',
    String? period,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/collector/sources/$sourceId/test',
      body: {
        'lottery': lottery,
        if (period != null && period.trim().isNotEmpty) 'period': period.trim(),
        'ingest': false,
      },
    );
    return ScriptRunResult.fromJson(json);
  }

  // ------------------------------------------------------------------ //
  // Schedules
  // ------------------------------------------------------------------ //
  Future<SchedulesResponse> schedules({String? lottery}) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/collector/schedules',
      query: {'lottery': lottery},
    );
    return SchedulesResponse.fromJson(json);
  }

  /// Enable or disable a schedule. The app deliberately does not create or edit
  /// schedules — cron editing belongs in the web console.
  Future<CollectionSchedule> setScheduleEnabled(int id, bool enabled) async {
    final json = await _client.put<Map<String, dynamic>>(
      '/collector/schedules/$id',
      body: {'enabled': enabled},
    );
    return CollectionSchedule.fromJson(asMap(json['schedule']));
  }

  Future<Map<String, dynamic>> triggerSchedule(int id) =>
      _client.post<Map<String, dynamic>>('/collector/schedules/$id/trigger');

  Future<List<SchedulerLogEntry>> scheduleLogs(int id) async {
    final json =
        await _client.get<Map<String, dynamic>>('/collector/schedules/$id/logs');
    return asModelList(json['logs'], SchedulerLogEntry.fromJson);
  }

  // ------------------------------------------------------------------ //
  // Draw sync / judging (staff/admin)
  // ------------------------------------------------------------------ //
  Future<Map<String, dynamic>> syncDraws({
    required String lottery,
    String? period,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/collector/draws/sync',
        body: {'lottery': lottery, 'period': ?period},
      );

  Future<JudgeStats> judge({required String lottery, required String period}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/collector/judge',
      body: {'lottery': lottery, 'period': period},
    );
    await _cache.delete(CacheKeys.comparison(lottery, period));
    return JudgeStats.fromJson(json);
  }

  // ------------------------------------------------------------------ //
  // Events, subscriptions, version
  // ------------------------------------------------------------------ //
  Future<AppEventPage> events({
    String? since,
    String? lottery,
    int limit = 50,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/app/events',
      query: {'since': since, 'lottery': lottery, 'limit': limit},
    );
    return AppEventPage.fromJson(json);
  }

  Future<Subscription> subscription() async {
    final json =
        await _client.get<Map<String, dynamic>>('/users/me/subscriptions');
    return Subscription.fromJson(json);
  }

  Future<Subscription> saveSubscription(Subscription subscription) async {
    final json = await _client.put<Map<String, dynamic>>(
      '/users/me/subscriptions',
      body: subscription.toJson(),
    );
    return Subscription.fromJson(json);
  }

  Future<VersionInfo> version({
    required String platform,
    required String current,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/app/version',
      query: {'platform': platform, 'current': current},
    );
    return VersionInfo.fromJson(json);
  }

  // ------------------------------------------------------------------ //
  // AI
  // ------------------------------------------------------------------ //
  Future<List<AiPrompt>> aiPrompts() async {
    final json = await _client.get<List<dynamic>>('/ai/prompts');
    return asModelList(json, AiPrompt.fromJson);
  }

  /// Read a cached report. Returns null when none exists — reading must never
  /// trigger generation, which would bill an LLM call per viewer.
  Future<AiReport?> aiReport({
    required String lottery,
    required String period,
    required String promptId,
  }) async {
    try {
      final json = await _client.get<Map<String, dynamic>>(
        '/ai/report',
        query: {'lottery': lottery, 'period': period, 'prompt_id': promptId},
      );
      return AiReport.fromJson(json);
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  /// Generate and cache a report. Staff/admin only.
  Future<AiReport> generateAiReport({
    required String lottery,
    required String period,
    required String promptId,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/ai/report/generate',
      body: {
        'lottery': lottery,
        'period': period,
        'prompt_id': promptId,
        'fetch_fresh': true,
      },
    );
    return AiReport.fromJson(json);
  }

  /// Drop everything cached. Called when the signed-in user changes so one
  /// account never sees another's cached data.
  Future<void> clearCache() => _cache.clear();
}
