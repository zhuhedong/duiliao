/// Source rating and monitoring models from `collector.ts`.
library;

import '../json.dart';

/// Below this sample size a hit rate is not informative and the UI must say so.
/// A source showing 100% on three samples looks better than one showing 60% on
/// fifty, and acting on that would be a mistake.
const int kSmallSampleThreshold = 10;

/// Difference between pre- and post-draw hit rate above which the source is
/// flagged as probably editing its predictions after the result is known.
const double kEditSuspicionDelta = 0.15;

/// One source's rating. Mirrors `RatingRow`.
///
/// The per-window fields (`n_30`, `hit_30`, `n_50`, ...) are **dynamic**: which
/// keys exist depends on the `windows` query parameter. They are therefore kept
/// in [raw] and read through [sampleSize] / [hitRate] rather than being declared
/// as fixed fields.
class RatingRow {
  const RatingRow({
    required this.sourceId,
    required this.sourceName,
    required this.dirtyFlags,
    required this.missing,
    required this.pending,
    required this.uncovered,
    required this.beforeN,
    this.beforeRate,
    required this.afterN,
    this.afterRate,
    required this.afterEdits,
    required this.longestHit,
    required this.longestMiss,
    required this.currentStreak,
    this.currentResult,
    required this.raw,
  });

  final String sourceId;
  final String sourceName;

  /// Count of integrity violations recorded against this source.
  final int dirtyFlags;

  /// Periods with no prediction from this source.
  final int missing;

  /// Predictions awaiting judgement.
  final int pending;

  /// Periods outside this source's coverage.
  final int uncovered;

  /// Samples where the prediction was captured **before** the draw.
  final int beforeN;

  /// Hit rate on pre-draw samples. Null when there are none.
  final double? beforeRate;

  /// Samples first captured **after** the draw.
  final int afterN;

  /// Hit rate on post-draw samples. Null when there are none.
  final double? afterRate;

  /// Times the stored prediction changed after the draw was known.
  final int afterEdits;

  final int longestHit;
  final int longestMiss;

  /// Positive for a hit streak, negative for a miss streak.
  final int currentStreak;

  /// Most recent judgement: 1 hit, 0 miss, null unjudged.
  final int? currentResult;

  /// The whole row, for the dynamic per-window keys.
  final Map<String, dynamic> raw;

  factory RatingRow.fromJson(Map<String, dynamic> json) => RatingRow(
        sourceId: asString(json['source_id']),
        sourceName: asString(json['source_name']),
        dirtyFlags: asInt(json['dirty_flags']),
        missing: asInt(json['missing']),
        pending: asInt(json['pending']),
        uncovered: asInt(json['uncovered']),
        beforeN: asInt(json['before_n']),
        beforeRate: asDoubleOrNull(json['before_rate']),
        afterN: asInt(json['after_n']),
        afterRate: asDoubleOrNull(json['after_rate']),
        afterEdits: asInt(json['after_edits']),
        longestHit: asInt(json['longest_hit']),
        longestMiss: asInt(json['longest_miss']),
        currentStreak: asInt(json['current_streak']),
        currentResult: asIntOrNull(json['current_result']),
        raw: Map.unmodifiable(json),
      );

  /// Sample size for a window, e.g. `sampleSize(30)` reads `n_30`.
  /// Null when the window was not requested.
  int? sampleSize(int window) => asIntOrNull(raw['n_$window']);

  /// Hit rate for a window, e.g. `hitRate(30)` reads `hit_30`.
  ///
  /// Returns **null**, not 0, when the value is absent or null — "no data" and
  /// "never hit" are different findings and must not be conflated.
  double? hitRate(int window) => asDoubleOrNull(raw['hit_$window']);

  /// True when the window's sample is too small for its rate to mean anything.
  bool isSmallSample(int window) {
    final n = sampleSize(window);
    return n != null && n < kSmallSampleThreshold;
  }

  /// True when the post-draw rate materially exceeds the pre-draw rate, which
  /// suggests the source rewrites predictions once the result is known. When this
  /// holds, the headline hit rate is not trustworthy.
  bool get suspectedPostDrawEditing {
    final before = beforeRate;
    final after = afterRate;
    if (before == null || after == null) return false;
    // Require a usable pre-draw sample, or a low count alone produces false alarms.
    if (beforeN < 5) return false;
    return (after - before) >= kEditSuspicionDelta;
  }

  bool get hasDirtyFlags => dirtyFlags > 0;
  bool get hasPostDrawEdits => afterEdits > 0;

  /// Any reason to distrust this source's numbers.
  bool get hasIntegrityWarning =>
      hasDirtyFlags || hasPostDrawEdits || suspectedPostDrawEditing;

  /// Current streak as text, e.g. `连中 4` / `连挂 3`.
  String get streakLabel {
    if (currentStreak == 0) return '—';
    return currentStreak > 0 ? '连中 $currentStreak' : '连挂 ${currentStreak.abs()}';
  }

  /// Consecutive misses, as a positive number. Zero when currently hitting.
  int get missStreak => currentStreak < 0 ? currentStreak.abs() : 0;

  /// Periods with a definite outcome.
  int get coveredPeriods => beforeN + afterN;
}

/// A ratings board. Mirrors `RatingsResult`.
class RatingsResult {
  const RatingsResult({
    required this.ok,
    required this.lottery,
    required this.playType,
    required this.windows,
    required this.periods,
    this.periodFrom,
    this.periodTo,
    required this.sources,
  });

  final bool ok;
  final String lottery;
  final String playType;

  /// The windows actually returned, which determines the dynamic keys present.
  final List<int> windows;

  /// Periods included in the calculation.
  final List<String> periods;

  final String? periodFrom;
  final String? periodTo;
  final List<RatingRow> sources;

  factory RatingsResult.fromJson(Map<String, dynamic> json) => RatingsResult(
        ok: asBool(json['ok'], fallback: true),
        lottery: asString(json['lottery']),
        playType: asString(json['play_type']),
        windows: asList(json['windows'])
            .map(asIntOrNull)
            .whereType<int>()
            .toList(growable: false),
        periods: asStringList(json['periods']),
        periodFrom: asStringOrNull(json['period_from']),
        periodTo: asStringOrNull(json['period_to']),
        sources: asModelList(json['sources'], RatingRow.fromJson),
      );

  static const empty = RatingsResult(
    ok: true,
    lottery: '',
    playType: '',
    windows: [30, 50, 100],
    periods: [],
    sources: [],
  );

  /// The primary (smallest) window, used for the headline column.
  int get primaryWindow => windows.isEmpty ? 30 : windows.first;

  /// Sorted by hit rate in [window] descending, with null rates last.
  ///
  /// Nulls sort last to match the backend's own ordering, so a source with no
  /// data never appears to outrank one with a measured rate.
  List<RatingRow> sortedBy(int window) {
    final sorted = [...sources];
    sorted.sort((a, b) {
      final left = a.hitRate(window);
      final right = b.hitRate(window);
      if (left == null && right == null) return a.sourceName.compareTo(b.sourceName);
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    return sorted;
  }
}

/// Source health. Mirrors `MonitorRow`.
class MonitorRow {
  const MonitorRow({
    required this.sourceId,
    required this.sourceName,
    required this.lottery,
    required this.playType,
    required this.enabled,
    this.latestPeriod,
    this.latestDraw,
    this.lag,
    required this.pending,
    required this.pendingTotal,
    required this.confirmed,
    required this.confirmedTotal,
    required this.neverCollected,
    this.lastSeen,
  });

  final String sourceId;
  final String sourceName;
  final String lottery;
  final String playType;
  final bool enabled;

  /// Newest period this source has a prediction for.
  final String? latestPeriod;

  /// Newest published draw, for comparison with [latestPeriod].
  final String? latestDraw;

  /// How many periods behind the source is. Null when unknown.
  final int? lag;

  final List<String> pending;
  final int pendingTotal;
  final List<String> confirmed;
  final int confirmedTotal;

  /// True when the source has never produced anything.
  final bool neverCollected;

  final String? lastSeen;

  factory MonitorRow.fromJson(Map<String, dynamic> json) => MonitorRow(
        sourceId: asString(json['source_id']),
        sourceName: asString(json['source_name']),
        lottery: asString(json['lottery']),
        playType: asString(json['play_type']),
        enabled: asBool(json['enabled']),
        latestPeriod: asStringOrNull(json['latest_period']),
        latestDraw: asStringOrNull(json['latest_draw']),
        lag: asIntOrNull(json['lag']),
        pending: asStringList(json['pending']),
        pendingTotal: asInt(json['pending_total']),
        confirmed: asStringList(json['confirmed']),
        confirmedTotal: asInt(json['confirmed_total']),
        neverCollected: asBool(json['never_collected']),
        lastSeen: asStringOrNull(json['last_seen']),
      );

  /// True when the source is materially behind the latest draw.
  bool get isStale => (lag ?? 0) > 1;
}
