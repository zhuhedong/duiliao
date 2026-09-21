/// Event-feed and home-aggregation models for the `/app/*` endpoints.
library;

import '../json.dart';
import 'collect_job.dart';
import 'draw.dart';
import 'prediction.dart';
import 'ratings.dart';

/// Event types produced by `GET /app/events`.
enum AppEventType {
  drawPublished('draw_published', '新开奖'),
  sourceHit('source_hit', '关注源命中'),
  sourceMissStreak('source_miss_streak', '关注源连挂'),
  consensusLeaderChanged('consensus_leader_changed', '共识领先变动'),
  collectJobFinished('collect_job_finished', '采集任务');

  const AppEventType(this.code, this.label);
  final String code;
  final String label;

  static AppEventType? tryParse(String? code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }

  /// Notification channel id. Separate channels let a user silence one class of
  /// notification from the OS settings without losing the rest.
  String get channelId => 'duiliao_$code';
}

/// One event from the feed.
class AppEvent {
  const AppEvent({
    required this.type,
    required this.occurredAt,
    this.lottery,
    this.period,
    required this.title,
    required this.body,
    required this.data,
  });

  final AppEventType? type;

  /// Cursor value. Events are ordered by this and it is echoed back as `since`.
  final String occurredAt;

  final String? lottery;
  final String? period;
  final String title;
  final String body;
  final Map<String, dynamic> data;

  factory AppEvent.fromJson(Map<String, dynamic> json) => AppEvent(
        type: AppEventType.tryParse(asStringOrNull(json['type'])),
        occurredAt: asString(json['occurred_at']),
        lottery: asStringOrNull(json['lottery']),
        period: asStringOrNull(json['period']),
        title: asString(json['title']),
        body: asString(json['body']),
        data: asMap(json['data']),
      );

  Map<String, dynamic> toJson() => {
        'type': type?.code,
        'occurred_at': occurredAt,
        'lottery': lottery,
        'period': period,
        'title': title,
        'body': body,
        'data': data,
      };

  DateTime? get occurredAtTime => asDateTimeOrNull(occurredAt);

  /// Stable identity, so the message centre can deduplicate if the same event is
  /// seen twice across a cursor boundary.
  String get dedupeKey => '${type?.code}|$occurredAt|$lottery|$period|${data['job_id'] ?? data['source_id'] ?? ''}';

  /// Deep link for the notification tap.
  String? get deepLink {
    switch (type) {
      case AppEventType.drawPublished:
        return period == null ? '/draws' : '/draws/$lottery/$period';
      case AppEventType.sourceHit:
      case AppEventType.sourceMissStreak:
        final sourceId = asStringOrNull(data['source_id']);
        return sourceId == null ? '/ratings' : '/ratings/source/$sourceId';
      case AppEventType.consensusLeaderChanged:
        return period == null ? '/consensus' : '/consensus/$lottery/$period';
      case AppEventType.collectJobFinished:
        final jobId = asIntOrNull(data['job_id']);
        return jobId == null ? '/collect' : '/collect/job/$jobId';
      case null:
        return null;
    }
  }
}

/// `GET /app/events` response.
class AppEventPage {
  const AppEventPage({
    required this.count,
    required this.hasMore,
    this.nextCursor,
    required this.events,
  });

  final int count;

  /// True when the limit truncated the result, so the client should poll again
  /// immediately rather than waiting for the next tick.
  final bool hasMore;

  /// Persist and send back as `since`. Null only when there is no history at all.
  final String? nextCursor;

  final List<AppEvent> events;

  factory AppEventPage.fromJson(Map<String, dynamic> json) => AppEventPage(
        count: asInt(json['count']),
        hasMore: asBool(json['has_more']),
        nextCursor: asStringOrNull(json['next_cursor']),
        events: asModelList(json['events'], AppEvent.fromJson),
      );

  static const empty = AppEventPage(count: 0, hasMore: false, events: []);
}

/// A consensus leader summary block from `/app/home`.
class HomeConsensusGroup {
  const HomeConsensusGroup({
    required this.playType,
    required this.nSources,
    required this.nVotes,
    this.leader,
    required this.leaderVotes,
    this.leaderHit,
  });

  final String playType;
  final int nSources;
  final int nVotes;
  final List<PredAtom>? leader;
  final int leaderVotes;
  final bool? leaderHit;

  factory HomeConsensusGroup.fromJson(Map<String, dynamic> json) => HomeConsensusGroup(
        playType: asString(json['play_type']),
        nSources: asInt(json['n_sources']),
        nVotes: asInt(json['n_votes']),
        leader: json['leader'] == null
            ? null
            : asModelList(json['leader'], PredAtom.fromJson),
        leaderVotes: asInt(json['leader_votes']),
        leaderHit: asBoolOrNull(json['leader_hit']),
      );
}

/// The aggregated home payload.
///
/// Every block is nullable: `/app/home` degrades each dataset independently so a
/// single failing query returns null for that block rather than a 500 for the
/// whole screen.
class HomeSnapshot {
  const HomeSnapshot({
    required this.lottery,
    required this.playType,
    this.serverTime,
    this.latestDraw,
    this.consensusPeriod,
    this.consensusGroups = const [],
    this.comparisonSummary,
    this.ratingsTop = const [],
    this.ratingsWindows = const [30, 50, 100],
    this.recentJobs = const [],
    this.worker,
    this.ruleVersion,
  });

  final String lottery;
  final String playType;
  final String? serverTime;
  final DrawRow? latestDraw;
  final String? consensusPeriod;
  final List<HomeConsensusGroup> consensusGroups;
  final ComparisonSummary? comparisonSummary;
  final List<RatingRow> ratingsTop;
  final List<int> ratingsWindows;
  final List<CollectJob> recentJobs;
  final CollectWorkerStatus? worker;

  /// The server's `rules.py` VERSION, compared against the transcribed table to
  /// detect a client that has fallen behind.
  final String? ruleVersion;

  factory HomeSnapshot.fromJson(Map<String, dynamic> json) {
    final consensus = asMapOrNull(json['consensus']);
    final ratings = asMapOrNull(json['ratings_top']);
    return HomeSnapshot(
      lottery: asString(json['lottery']),
      playType: asString(json['play_type']),
      serverTime: asStringOrNull(json['server_time']),
      latestDraw: asModelOrNull(json['latest_draw'], DrawRow.fromJson),
      consensusPeriod: asStringOrNull(consensus?['period']),
      consensusGroups: asModelList(consensus?['groups'], HomeConsensusGroup.fromJson),
      comparisonSummary:
          asModelOrNull(json['comparison_summary'], ComparisonSummary.fromJson),
      ratingsTop: asModelList(ratings?['sources'], RatingRow.fromJson),
      ratingsWindows: ratings == null
          ? const [30, 50, 100]
          : asList(ratings['windows'])
              .map(asIntOrNull)
              .whereType<int>()
              .toList(growable: false),
      recentJobs: asModelList(json['recent_jobs'], CollectJob.fromJson),
      worker: asModelOrNull(json['collect_worker'], CollectWorkerStatus.fromJson),
      ruleVersion: asStringOrNull(json['rule_version']),
    );
  }

  bool get hasAnyData =>
      latestDraw != null ||
      consensusGroups.isNotEmpty ||
      ratingsTop.isNotEmpty ||
      recentJobs.isNotEmpty;
}

/// `GET /app/version` response, driving the force-update gate.
class VersionInfo {
  const VersionInfo({
    required this.platform,
    this.current,
    this.latest,
    this.minSupported,
    this.downloadUrl,
    this.releaseNotes,
    required this.updateAvailable,
    required this.updateRequired,
  });

  final String platform;
  final String? current;
  final String? latest;

  /// Builds below this are blocked. Raising it is how a signing-secret rotation
  /// is made safe: older builds would otherwise fail every request with
  /// `bad_signature` and show no explanation.
  final String? minSupported;

  final String? downloadUrl;
  final String? releaseNotes;
  final bool updateAvailable;
  final bool updateRequired;

  factory VersionInfo.fromJson(Map<String, dynamic> json) => VersionInfo(
        platform: asString(json['platform']),
        current: asStringOrNull(json['current']),
        latest: asStringOrNull(json['latest']),
        minSupported: asStringOrNull(json['min_supported']),
        downloadUrl: asStringOrNull(json['download_url']),
        releaseNotes: asStringOrNull(json['release_notes']),
        updateAvailable: asBool(json['update_available']),
        updateRequired: asBool(json['update_required']),
      );
}

/// A cached AI report from `GET /ai/report`.
class AiReport {
  const AiReport({
    required this.lottery,
    required this.period,
    required this.promptId,
    required this.content,
    this.provider,
    this.model,
    this.elapsedSec,
    this.generatedAt,
    this.generatedBy,
  });

  final String lottery;
  final String period;
  final String promptId;

  /// Markdown.
  final String content;

  final String? provider;
  final String? model;
  final double? elapsedSec;
  final String? generatedAt;
  final String? generatedBy;

  factory AiReport.fromJson(Map<String, dynamic> json) => AiReport(
        lottery: asString(json['lottery']),
        period: asString(json['period']),
        promptId: asString(json['prompt_id']),
        content: asString(json['content']),
        provider: asStringOrNull(json['provider']),
        model: asStringOrNull(json['model']),
        elapsedSec: asDoubleOrNull(json['elapsed_sec']),
        generatedAt: asStringOrNull(json['generated_at']),
        generatedBy: asStringOrNull(json['generated_by']),
      );

  /// Provider and model, for the attribution line beside the disclaimer.
  String get modelLabel {
    final parts = [provider, model].whereType<String>().where((s) => s.isNotEmpty);
    return parts.isEmpty ? '未知模型' : parts.join(' · ');
  }
}

/// An AI prompt template from `GET /ai/prompts`.
class AiPrompt {
  const AiPrompt({required this.id, this.name, this.description});

  final String id;
  final String? name;
  final String? description;

  factory AiPrompt.fromJson(Map<String, dynamic> json) => AiPrompt(
        id: asString(json['id']),
        name: asStringOrNull(json['name']),
        description: asStringOrNull(json['description']),
      );

  String get displayName => name?.isNotEmpty == true ? name! : id;
}
