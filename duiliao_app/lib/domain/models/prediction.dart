/// Prediction, comparison and judgement models from `collector.ts`.
library;

import '../json.dart';
import 'draw.dart';

/// One prediction atom. Mirrors `PredAtom`.
class PredAtom {
  const PredAtom({required this.kind, required this.value, this.text});

  /// `num` | `xiao` | `wei` | `head` | `bose` | `size` | `odd`.
  final String kind;

  /// Normalised value, e.g. `08` or `猪`.
  final String value;

  /// Original wording, when it differed from [value].
  final String? text;

  factory PredAtom.fromJson(Map<String, dynamic> json) => PredAtom(
        kind: asString(json['kind']),
        value: asString(json['value']),
        text: asStringOrNull(json['text']),
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'value': value,
        if (text != null) 'text': text,
      };

  @override
  bool operator ==(Object other) =>
      other is PredAtom && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => value;
}

/// Render a list of atoms as a compact label, e.g. `猪 兔 龙`.
String formatAtoms(List<PredAtom> atoms, {String separator = ' '}) =>
    atoms.map((a) => a.value).join(separator);

/// Derived status of a comparison row. Mirrors the `status` union.
enum ComparisonStatus {
  hit('hit', '中'),
  miss('miss', '挂'),
  pending('pending', '待判'),

  /// The source claimed a hit but the official judgement is a miss. The most
  /// important state in the app: it is direct evidence a source is dishonest.
  conflict('conflict', '冲突');

  const ComparisonStatus(this.code, this.label);
  final String code;
  final String label;

  static ComparisonStatus? tryParse(String? code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

/// One source's prediction for a period, with its judgement. Mirrors
/// `ComparisonItem`.
class ComparisonItem {
  const ComparisonItem({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.lottery,
    required this.playType,
    required this.hitMode,
    required this.period,
    required this.periodRaw,
    required this.groupKey,
    required this.preds,
    required this.claimedStatus,
    required this.rawText,
    this.fetchedAt,
    this.officialHit,
    this.claimedHit,
    this.hitDetail,
    this.judgedAt,
    required this.status,
  });

  final int id;
  final String sourceId;
  final String sourceName;
  final String lottery;
  final String playType;

  /// `any` or `all`, how the atoms combine for this source.
  final String hitMode;

  final String period;
  final String periodRaw;

  /// Distinguishes multiple independent prediction groups from one source,
  /// rendered as `／第N组`.
  final String groupKey;

  final List<PredAtom> preds;

  /// What the source said about itself, verbatim.
  final String claimedStatus;

  /// The scraped text the prediction was parsed from, for the evidence drawer.
  final String rawText;

  final String? fetchedAt;

  /// The authoritative judgement: 1 hit, 0 miss, null not yet judged.
  /// Note this is an int on the wire, not a bool.
  final int? officialHit;

  /// What the source claimed, same encoding as [officialHit].
  final int? claimedHit;

  /// Full judgement evidence: `explanation`, `rule`, `rule_version`,
  /// `draw_snapshot`, `prediction_snapshot`. Opaque here; rendered as-is.
  final Map<String, dynamic>? hitDetail;

  final String? judgedAt;

  /// Server-derived status. The client never re-judges — the backend's
  /// `hit_detail` is the single source of truth, and a second opinion computed on
  /// the device would be a second, conflicting answer with no authority.
  final ComparisonStatus? status;

  factory ComparisonItem.fromJson(Map<String, dynamic> json) => ComparisonItem(
        id: asInt(json['id']),
        sourceId: asString(json['source_id']),
        sourceName: asString(json['source_name']),
        lottery: asString(json['lottery']),
        playType: asString(json['play_type']),
        hitMode: asString(json['hit_mode']),
        period: asString(json['period']),
        periodRaw: asString(json['period_raw']),
        groupKey: asString(json['group_key']),
        preds: asModelList(json['preds'], PredAtom.fromJson),
        claimedStatus: asString(json['claimed_status']),
        rawText: asString(json['raw_text']),
        fetchedAt: asStringOrNull(json['fetched_at']),
        officialHit: asIntOrNull(json['official_hit']),
        claimedHit: asIntOrNull(json['claimed_hit']),
        hitDetail: asMapOrNull(json['hit_detail']),
        judgedAt: asStringOrNull(json['judged_at']),
        status: ComparisonStatus.tryParse(asStringOrNull(json['status'])),
      );

  bool get isJudged => officialHit != null;
  bool get isHit => officialHit == 1;
  bool get isConflict => status == ComparisonStatus.conflict;

  /// Human explanation of the judgement, from `hit_detail.explanation`.
  String? get explanation => asStringOrNull(hitDetail?['explanation']);

  /// The rule applied, from `hit_detail.rule`.
  String? get rule => asStringOrNull(hitDetail?['rule']);

  /// Version of the rule set used, so an old judgement is identifiable.
  String? get ruleVersion => asStringOrNull(hitDetail?['rule_version']);

  String? get scopeLabel => asStringOrNull(hitDetail?['scope_label']);

  /// Draw state at judgement time.
  Map<String, dynamic>? get drawSnapshot => asMapOrNull(hitDetail?['draw_snapshot']);

  /// Prediction state at judgement time.
  Map<String, dynamic>? get predictionSnapshot =>
      asMapOrNull(hitDetail?['prediction_snapshot']);

  /// `／第N组` suffix, empty for the default group.
  String get groupSuffix {
    if (groupKey.isEmpty || groupKey == 'default' || groupKey == '0') return '';
    return '／$groupKey';
  }
}

/// Aggregate counters for a period. Mirrors the inline `summary` object.
class ComparisonSummary {
  const ComparisonSummary({
    required this.total,
    required this.judged,
    required this.hits,
    required this.misses,
    required this.pending,
    required this.conflicts,
    required this.hitRate,
  });

  final int total;
  final int judged;
  final int hits;
  final int misses;
  final int pending;
  final int conflicts;

  /// Already a fraction in `0..1` from the backend.
  final double hitRate;

  factory ComparisonSummary.fromJson(Map<String, dynamic> json) => ComparisonSummary(
        total: asInt(json['total']),
        judged: asInt(json['judged']),
        hits: asInt(json['hits']),
        misses: asInt(json['misses']),
        pending: asInt(json['pending']),
        conflicts: asInt(json['conflicts']),
        hitRate: asDouble(json['hit_rate']),
      );

  static const empty = ComparisonSummary(
    total: 0,
    judged: 0,
    hits: 0,
    misses: 0,
    pending: 0,
    conflicts: 0,
    hitRate: 0,
  );
}

/// Full comparison for one period. Mirrors `PeriodComparisonResult`.
class PeriodComparisonResult {
  const PeriodComparisonResult({
    required this.ok,
    required this.lottery,
    required this.period,
    this.draw,
    required this.summary,
    required this.items,
  });

  final bool ok;
  final String lottery;
  final String period;

  /// Null before the draw is published, which is normal, not an error.
  final DrawRow? draw;

  final ComparisonSummary summary;
  final List<ComparisonItem> items;

  factory PeriodComparisonResult.fromJson(Map<String, dynamic> json) =>
      PeriodComparisonResult(
        ok: asBool(json['ok'], fallback: true),
        lottery: asString(json['lottery']),
        period: asString(json['period']),
        draw: asModelOrNull(json['draw'], DrawRow.fromJson),
        summary: asModelOrNull(json['summary'], ComparisonSummary.fromJson) ??
            ComparisonSummary.empty,
        items: asModelList(json['items'], ComparisonItem.fromJson),
      );

  /// Rows with the given status, for the filter tabs.
  List<ComparisonItem> withStatus(ComparisonStatus? status) =>
      status == null ? items : items.where((i) => i.status == status).toList();
}

/// A stored prediction row. Mirrors what `/collector/predictions` returns.
class PredictionRow {
  const PredictionRow({
    required this.id,
    required this.sourceId,
    required this.lottery,
    required this.playType,
    required this.period,
    required this.periodRaw,
    required this.preds,
    required this.claimedStatus,
    required this.rawText,
    this.fetchedAt,
    this.officialHit,
    this.groupKey = '',
    this.hitMode = '',
    this.sourceName,
    this.status,
    this.draw,
    this.hitDetail,
  });

  final int id;
  final String sourceId;
  final String? sourceName;
  final String lottery;
  final String playType;
  final String period;
  final String periodRaw;
  final List<PredAtom> preds;
  final String claimedStatus;
  final String rawText;
  final String? fetchedAt;
  final int? officialHit;
  final String groupKey;
  final String hitMode;
  final String? status;
  final DrawRow? draw;
  final Map<String, dynamic>? hitDetail;

  factory PredictionRow.fromJson(Map<String, dynamic> json) => PredictionRow(
        id: asInt(json['id']),
        sourceId: asString(json['source_id']),
        sourceName: asStringOrNull(json['source_name']),
        lottery: asString(json['lottery']),
        playType: asString(json['play_type']),
        period: asString(json['period']),
        periodRaw: asString(json['period_raw']),
        preds: asModelList(json['preds'], PredAtom.fromJson),
        claimedStatus: asString(json['claimed_status']),
        rawText: asString(json['raw_text']),
        fetchedAt: asStringOrNull(json['fetched_at']),
        officialHit: asIntOrNull(json['official_hit']),
        groupKey: asString(json['group_key']),
        hitMode: asString(json['hit_mode']),
        status: asStringOrNull(json['status']),
        draw: asModelOrNull(json['draw'], DrawRow.fromJson),
        hitDetail: asMapOrNull(json['hit_detail']),
      );

  bool get isJudged => officialHit != null;
  bool get isHit => officialHit == 1;
  bool get isConflict => status == 'conflict' || (claimedStatus == 'hit' && officialHit == 0);
  bool get isMissing => claimedStatus == 'missing' || (hitDetail?['missing_period'] == true);
}

/// Aggregated stats returned by `/collector/sources/{id}/history`.
class SourceHistoryStats {
  const SourceHistoryStats({
    required this.total,
    required this.judged,
    required this.hits,
    required this.misses,
    required this.pending,
    required this.conflicts,
    required this.missing,
    required this.hitRate,
    required this.longestHit,
    required this.longestMiss,
    required this.currentStreak,
    this.currentStatus,
  });

  final int total;
  final int judged;
  final int hits;
  final int misses;
  final int pending;
  final int conflicts;
  final int missing;
  final double hitRate;
  final int longestHit;
  final int longestMiss;
  final int currentStreak;
  final String? currentStatus;

  factory SourceHistoryStats.fromJson(Map<String, dynamic> json) => SourceHistoryStats(
        total: asInt(json['total']),
        judged: asInt(json['judged']),
        hits: asInt(json['hits']),
        misses: asInt(json['misses']),
        pending: asInt(json['pending']),
        conflicts: asInt(json['conflicts']),
        missing: asInt(json['missing']),
        hitRate: asDouble(json['hit_rate']),
        longestHit: asInt(json['longest_hit']),
        longestMiss: asInt(json['longest_miss']),
        currentStreak: asInt(json['current_streak']),
        currentStatus: asStringOrNull(json['current_status']),
      );
}
