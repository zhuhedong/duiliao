/// Consensus models from `collector.ts`.
library;

import '../json.dart';
import 'draw.dart';
import 'prediction.dart';

/// One voted-for scheme within a play type. Mirrors `ConsensusTallyItem`.
class ConsensusTallyItem {
  const ConsensusTallyItem({
    required this.preds,
    required this.votes,
    required this.sources,
    this.hit,
    this.hitDetail,
  });

  /// The predicted atoms this group of sources agreed on.
  final List<PredAtom> preds;

  /// Vote count. Sources in the same site family, and near-duplicate wording,
  /// are collapsed to a single vote server-side — so this is a count of
  /// independent opinions, not of rows.
  final int votes;

  /// Source display names that voted for this scheme.
  final List<String> sources;

  /// Null before the draw is published.
  final bool? hit;

  final Map<String, dynamic>? hitDetail;

  factory ConsensusTallyItem.fromJson(Map<String, dynamic> json) => ConsensusTallyItem(
        preds: asModelList(json['preds'], PredAtom.fromJson),
        votes: asInt(json['votes']),
        sources: asStringList(json['sources']),
        hit: asBoolOrNull(json['hit']),
        hitDetail: asMapOrNull(json['hit_detail']),
      );
}

/// Consensus within one play type. Mirrors `ConsensusGroup`.
class ConsensusGroup {
  const ConsensusGroup({
    required this.playType,
    required this.nSources,
    required this.nVotes,
    this.leader,
    required this.leaderVotes,
    this.leaderHit,
    this.leaderHitDetail,
    required this.tally,
  });

  final String playType;

  /// Distinct sources contributing to this play type.
  final int nSources;

  /// Total votes cast.
  final int nVotes;

  /// The leading scheme, null when there were no predictions.
  final List<PredAtom>? leader;

  final int leaderVotes;

  /// Null before the draw is published.
  final bool? leaderHit;

  final Map<String, dynamic>? leaderHitDetail;

  /// All schemes, which the UI sorts by votes.
  final List<ConsensusTallyItem> tally;

  factory ConsensusGroup.fromJson(Map<String, dynamic> json) => ConsensusGroup(
        playType: asString(json['play_type']),
        nSources: asInt(json['n_sources']),
        nVotes: asInt(json['n_votes']),
        leader: json['leader'] == null
            ? null
            : asModelList(json['leader'], PredAtom.fromJson),
        leaderVotes: asInt(json['leader_votes']),
        leaderHit: asBoolOrNull(json['leader_hit']),
        leaderHitDetail: asMapOrNull(json['leader_hit_detail']),
        tally: asModelList(json['tally'], ConsensusTallyItem.fromJson),
      );

  /// Schemes ordered by descending votes, which is the display order.
  List<ConsensusTallyItem> get sortedTally {
    final sorted = [...tally]..sort((a, b) => b.votes.compareTo(a.votes));
    return sorted;
  }

  /// Leader share of total votes, for the confidence bar. Null when no votes.
  double? get leaderShare => nVotes == 0 ? null : leaderVotes / nVotes;
}

/// A single-atom heat entry (特码 01–49 or 特肖). Mirrors `AtomTallyItem`.
class AtomTallyItem {
  const AtomTallyItem({
    required this.value,
    required this.kind,
    required this.votes,
    required this.percentage,
    required this.sources,
    this.hit,
  });

  /// `08` for a number, `猪` for a zodiac.
  final String value;

  /// `num` or `xiao`.
  final String kind;

  final int votes;

  /// Share of votes. The backend already expresses this as a percentage value.
  final double percentage;

  final List<String> sources;
  final bool? hit;

  factory AtomTallyItem.fromJson(Map<String, dynamic> json) => AtomTallyItem(
        value: asString(json['value']),
        kind: asString(json['kind']),
        votes: asInt(json['votes']),
        percentage: asDouble(json['percentage']),
        sources: asStringList(json['sources']),
        hit: asBoolOrNull(json['hit']),
      );

  /// Bar width in `0..1`, clamped so a malformed percentage cannot overflow.
  double get barFraction => (percentage / 100).clamp(0.0, 1.0);
}

/// Consensus for one period. Mirrors `ConsensusResult`.
class ConsensusResult {
  const ConsensusResult({
    required this.ok,
    required this.lottery,
    required this.period,
    this.draw,
    required this.groups,
    this.temaTallies = const [],
    this.texiaoTallies = const [],
  });

  final bool ok;
  final String lottery;
  final String period;

  /// Null before the draw is published.
  final DrawRow? draw;

  final List<ConsensusGroup> groups;

  /// 特码 heat, from `atom_tallies.tema_n`. Empty when absent.
  final List<AtomTallyItem> temaTallies;

  /// 特肖 heat, from `atom_tallies.texiao`.
  final List<AtomTallyItem> texiaoTallies;

  factory ConsensusResult.fromJson(Map<String, dynamic> json) {
    final tallies = asMapOrNull(json['atom_tallies']);
    return ConsensusResult(
      ok: asBool(json['ok'], fallback: true),
      lottery: asString(json['lottery']),
      period: asString(json['period']),
      draw: asModelOrNull(json['draw'], DrawRow.fromJson),
      groups: asModelList(json['groups'], ConsensusGroup.fromJson),
      temaTallies: asModelList(tallies?['tema_n'], AtomTallyItem.fromJson),
      texiaoTallies: asModelList(tallies?['texiao'], AtomTallyItem.fromJson),
    );
  }

  /// True when the draw has happened, so hit/miss marks are meaningful.
  bool get isDrawn => draw != null;

  /// Groups ordered by leader votes descending, so the strongest consensus is
  /// first.
  List<ConsensusGroup> get sortedGroups {
    final sorted = [...groups]..sort((a, b) => b.leaderVotes.compareTo(a.leaderVotes));
    return sorted;
  }

  bool get hasAtomTallies => temaTallies.isNotEmpty || texiaoTallies.isNotEmpty;
}
