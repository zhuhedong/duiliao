/// Draw models, ported from `frontend/src/lib/collector.ts`.
library;

import '../json.dart';

/// Per-number attributes. Mirrors `NumberAttr`.
///
/// Fixed attributes (波色/大小/单双/头/尾/合数) are always present. The rest rotate
/// with the lunar year or are enrichment the endpoint may omit, so they are
/// nullable. `wuxing` is null for years with no authoritative table — rendered as
/// a placeholder, never as a guess.
class NumberAttr {
  const NumberAttr({
    required this.num,
    required this.xiao,
    required this.jiaye,
    required this.bose,
    required this.size,
    required this.odd,
    required this.head,
    required this.wei,
    required this.sum,
    this.wuxing,
    this.halfwave,
    this.isLianxiao,
    this.lianxiaoCount,
    this.isAdjacentLianxiao,
    this.role,
    this.flower,
    this.hour,
    this.dizhi,
    this.xiaoColor,
    this.stroke,
    this.tianDi,
    this.yinYang,
    this.gender,
    this.luck,
    this.season,
    this.direction,
  });

  /// Zero-padded `01`..`49`.
  final String num;

  /// 生肖.
  final String xiao;

  /// 家 / 野.
  final String jiaye;

  /// 红 / 蓝 / 绿.
  final String bose;

  /// 大 / 小.
  final String size;

  /// 单 / 双.
  final String odd;

  /// 头.
  final String head;

  /// 尾.
  final String wei;

  /// 合数单双.
  final String sum;

  /// 金/木/水/火/土, null when the lunar year has no authoritative table.
  final String? wuxing;

  /// 半波, e.g. 红大.
  final String? halfwave;

  /// True when this zodiac appears twice or more in the same draw.
  final bool? isLianxiao;

  /// Total balls sharing this zodiac in the draw.
  final int? lianxiaoCount;

  /// True when the adjacent ball in drop order shares this zodiac.
  final bool? isAdjacentLianxiao;

  // 2026 灵码 attributes.
  final String? role;
  final String? flower;
  final String? hour;
  final String? dizhi;
  final String? xiaoColor;
  final String? stroke;

  // Zodiac classifications.
  final String? tianDi;
  final String? yinYang;
  final String? gender;
  final String? luck;
  final String? season;
  final String? direction;

  factory NumberAttr.fromJson(Map<String, dynamic> json) => NumberAttr(
        num: asString(json['num']),
        xiao: asString(json['xiao']),
        jiaye: asString(json['jiaye']),
        bose: asString(json['bose']),
        size: asString(json['size']),
        odd: asString(json['odd']),
        head: asString(json['head']),
        wei: asString(json['wei']),
        sum: asString(json['sum']),
        wuxing: asStringOrNull(json['wuxing']),
        halfwave: asStringOrNull(json['halfwave']),
        isLianxiao: asBoolOrNull(json['is_lianxiao']),
        lianxiaoCount: asIntOrNull(json['lianxiao_count']),
        isAdjacentLianxiao: asBoolOrNull(json['is_adjacent_lianxiao']),
        role: asStringOrNull(json['role']),
        flower: asStringOrNull(json['flower']),
        hour: asStringOrNull(json['hour']),
        dizhi: asStringOrNull(json['dizhi']),
        xiaoColor: asStringOrNull(json['xiao_color']),
        stroke: asStringOrNull(json['stroke']),
        tianDi: asStringOrNull(json['tian_di']),
        yinYang: asStringOrNull(json['yin_yang']),
        gender: asStringOrNull(json['gender']),
        luck: asStringOrNull(json['luck']),
        season: asStringOrNull(json['season']),
        direction: asStringOrNull(json['direction']),
      );

  /// A screen-reader description, so the ball is not colour-only.
  ///
  /// Accessibility requirement: 波色 is conveyed by both fill colour *and* text,
  /// and this label carries the full attribute set for assistive technology.
  String get semanticLabel {
    final parts = <String>['号码 $num', bose, size, odd, '生肖$xiao'];
    if (wuxing != null) parts.add('五行$wuxing');
    return parts.where((p) => p.isNotEmpty).join('，');
  }

  /// True when 五行 is unavailable for this number's lunar year.
  bool get wuxingMissing => wuxing == null || wuxing!.isEmpty;
}

/// A group of balls in one draw sharing a zodiac. Mirrors `LianxiaoGroup`.
class LianxiaoGroup {
  const LianxiaoGroup({
    required this.xiao,
    required this.count,
    required this.nums,
    required this.positions,
  });

  final String xiao;
  final int count;
  final List<String> nums;

  /// Positions in drop order, e.g. `['z1', 'z4', '特']`.
  final List<String> positions;

  factory LianxiaoGroup.fromJson(Map<String, dynamic> json) => LianxiaoGroup(
        xiao: asString(json['xiao']),
        count: asInt(json['count']),
        nums: asStringList(json['nums']),
        positions: asStringList(json['positions']),
      );
}

/// Two adjacent balls in drop order sharing a zodiac. Mirrors `AdjacentLianxiao`.
class AdjacentLianxiao {
  const AdjacentLianxiao({
    required this.xiao,
    required this.pos1,
    required this.pos2,
    required this.num1,
    required this.num2,
  });

  final String xiao;
  final String pos1;
  final String pos2;
  final String num1;
  final String num2;

  factory AdjacentLianxiao.fromJson(Map<String, dynamic> json) => AdjacentLianxiao(
        xiao: asString(json['xiao']),
        pos1: asString(json['pos1']),
        pos2: asString(json['pos2']),
        num1: asString(json['num1']),
        num2: asString(json['num2']),
      );
}

/// Per-period derived summary. Mirrors `DrawSummary`.
class DrawSummary {
  const DrawSummary({
    this.sum7 = 0,
    this.sum7Size = '',
    this.sum7Odd = '',
    required this.temaXiao,
    required this.temaBose,
    this.temaWuxing,
    required this.temaSize,
    required this.temaOdd,
    this.temaSumOdd = '',
    required this.temaJiaye,
    this.temaHalfwave = '',
    this.hasLianxiao,
    this.hasAdjacentLianxiao,
    this.lianxiaoGroups = const [],
    this.adjacentLianxiao = const [],
    this.lianxiaoText,
  });

  /// Sum of all seven balls.
  final int sum7;

  /// 大 / 小 of [sum7].
  final String sum7Size;

  /// 单 / 双 of [sum7].
  final String sum7Odd;

  final String temaXiao;
  final String temaBose;
  final String? temaWuxing;
  final String temaSize;
  final String temaOdd;
  final String temaSumOdd;
  final String temaJiaye;
  final String temaHalfwave;

  final bool? hasLianxiao;
  final bool? hasAdjacentLianxiao;
  final List<LianxiaoGroup> lianxiaoGroups;
  final List<AdjacentLianxiao> adjacentLianxiao;
  final String? lianxiaoText;

  factory DrawSummary.fromJson(Map<String, dynamic> json) => DrawSummary(
        sum7: asInt(json['sum7']),
        sum7Size: asString(json['sum7_size']),
        sum7Odd: asString(json['sum7_odd']),
        temaXiao: asString(json['tema_xiao']),
        temaBose: asString(json['tema_bose']),
        temaWuxing: asStringOrNull(json['tema_wuxing']),
        temaSize: asString(json['tema_size']),
        temaOdd: asString(json['tema_odd']),
        temaSumOdd: asString(json['tema_sum_odd']),
        temaJiaye: asString(json['tema_jiaye']),
        temaHalfwave: asString(json['tema_halfwave']),
        hasLianxiao: asBoolOrNull(json['has_lianxiao']),
        hasAdjacentLianxiao: asBoolOrNull(json['has_adjacent_lianxiao']),
        lianxiaoGroups: asModelList(json['lianxiao_groups'], LianxiaoGroup.fromJson),
        adjacentLianxiao:
            asModelList(json['adjacent_lianxiao'], AdjacentLianxiao.fromJson),
        lianxiaoText: asStringOrNull(json['lianxiao_text']),
      );
}

/// One draw. Mirrors `DrawRow`.
class DrawRow {
  const DrawRow({
    required this.lottery,
    required this.period,
    this.periodRaw = '',
    this.drawDate,
    this.openedAt,
    required this.balls,
    required this.tema,
    this.source = '',
    this.tag = const {},
    this.ballsDetail = const [],
    this.temaDetail,
    this.summary,
  });

  final String lottery;

  /// Canonical `YYYYNNN`.
  final String period;

  /// Short form, e.g. `248`.
  final String periodRaw;

  final String? drawDate;
  final String? openedAt;

  /// z1..z6, the six 正码 in drop order. 特码 is [tema], kept separate.
  final List<String> balls;

  /// 特码.
  final String tema;

  final String source;
  final Map<String, dynamic> tag;

  /// Attributes for each of [balls], present when the row was enriched.
  final List<NumberAttr> ballsDetail;

  final NumberAttr? temaDetail;

  /// Derived summary; null on unenriched rows, so callers must degrade.
  final DrawSummary? summary;

  factory DrawRow.fromJson(Map<String, dynamic> json) => DrawRow(
        lottery: asString(json['lottery']),
        period: asString(json['period']),
        periodRaw: asString(json['period_raw']),
        drawDate: asStringOrNull(json['draw_date']),
        openedAt: asStringOrNull(json['opened_at']),
        balls: asStringList(json['balls']),
        tema: asString(json['tema']),
        source: asString(json['source']),
        tag: asMap(json['tag']),
        ballsDetail: asModelList(json['balls_detail'], NumberAttr.fromJson),
        temaDetail: asModelOrNull(json['tema_detail'], NumberAttr.fromJson),
        summary: asModelOrNull(json['summary'], DrawSummary.fromJson),
      );

  /// All seven numbers, 正码 then 特码.
  List<String> get allNumbers => [...balls, tema];

  /// True when per-ball attributes are available for the detail view.
  bool get isEnriched => ballsDetail.isNotEmpty;

  DateTime? get openedAtTime => asDateTimeOrNull(openedAt);
}

/// Paged draw list. Mirrors `DrawListResult`.
class DrawListResult {
  const DrawListResult({
    required this.ok,
    required this.total,
    required this.count,
    required this.items,
  });

  final bool ok;

  /// Total matching rows, for "no more" detection.
  final int total;

  /// Rows in this page.
  final int count;

  final List<DrawRow> items;

  factory DrawListResult.fromJson(Map<String, dynamic> json) => DrawListResult(
        ok: asBool(json['ok'], fallback: true),
        total: asInt(json['total']),
        count: asInt(json['count']),
        items: asModelList(json['items'], DrawRow.fromJson),
      );

  static const empty = DrawListResult(ok: true, total: 0, count: 0, items: []);
}

/// 01–49 attribute table for a date. Mirrors `NumbersResult`.
class NumbersResult {
  const NumbersResult({
    required this.ok,
    required this.date,
    required this.items,
    required this.wuxingAvailable,
    required this.wuxingYears,
  });

  final bool ok;

  /// The date the zodiac mapping was computed for.
  final String date;

  final List<NumberAttr> items;

  /// False when the lunar year has no authoritative 五行 table, which the UI must
  /// state explicitly rather than showing blanks.
  final bool wuxingAvailable;

  /// Years for which a 五行 table exists.
  final List<int> wuxingYears;

  factory NumbersResult.fromJson(Map<String, dynamic> json) => NumbersResult(
        ok: asBool(json['ok'], fallback: true),
        date: asString(json['date']),
        items: asModelList(json['items'], NumberAttr.fromJson),
        wuxingAvailable: asBool(json['wuxing_available']),
        wuxingYears: asList(json['wuxing_years'])
            .map(asIntOrNull)
            .whereType<int>()
            .toList(growable: false),
      );
}

/// A trend item from the getTrend API.
class TrendItem {
  const TrendItem({
    required this.id,
    required this.period,
    required this.date,
    required this.code,
  });

  final String id;
  final String period;
  final String date;
  final List<String> code;

  factory TrendItem.fromJson(Map<String, dynamic> json) => TrendItem(
        id: json['id']?.toString() ?? '',
        period: asString(json['period']),
        date: asString(json['date']),
        code: asStringList(json['code']),
      );
}

/// A response from the getTrend API matching djds-129.dhd1k5.com.
class TrendResponse {
  const TrendResponse({
    required this.code,
    required this.msg,
    required this.data,
    this.lottery = '',
    this.total = 0,
  });

  final int code;
  final String msg;
  final List<TrendItem> data;
  final String lottery;
  final int total;

  factory TrendResponse.fromJson(Map<String, dynamic> json) => TrendResponse(
        code: asInt(json['code']),
        msg: asString(json['msg']),
        data: asModelList(json['data'], TrendItem.fromJson),
        lottery: asString(json['lottery']),
        total: asInt(json['total']),
      );

  static const empty = TrendResponse(code: 1, msg: '', data: []);
}

class PingteMatchedBall {
  const PingteMatchedBall({
    required this.position,
    required this.isTema,
    required this.number,
    this.bose = '',
    this.wuxing = '',
  });

  final int position;
  final bool isTema;
  final String number;
  final String bose;
  final String wuxing;

  factory PingteMatchedBall.fromJson(Map<String, dynamic> json) =>
      PingteMatchedBall(
        position: asInt(json['position'] ?? json['pos']),
        isTema: asBool(json['is_tema']),
        number: asString(json['number'] ?? json['num']),
        bose: asString(json['bose']),
        wuxing: asString(json['wuxing']),
      );
}

class PingteAllBall {
  const PingteAllBall({
    required this.position,
    required this.isTema,
    required this.number,
    required this.xiao,
    this.bose = '',
    this.wuxing = '',
    this.isTarget = false,
  });

  final int position;
  final bool isTema;
  final String number;
  final String xiao;
  final String bose;
  final String wuxing;
  final bool isTarget;

  factory PingteAllBall.fromJson(Map<String, dynamic> json) => PingteAllBall(
        position: asInt(json['position'] ?? json['pos']),
        isTema: asBool(json['is_tema']),
        number: asString(json['number'] ?? json['num']),
        xiao: asString(json['xiao']),
        bose: asString(json['bose']),
        wuxing: asString(json['wuxing']),
        isTarget: asBool(json['is_target'] ?? json['is_match']),
      );
}

class PingteSegmentRange {
  const PingteSegmentRange({
    required this.type,
    required this.typeLabel,
    required this.startPeriod,
    required this.endPeriod,
    this.startDate = '',
    this.endDate = '',
    required this.length,
    required this.text,
    this.isCurrent = false,
  });

  final String type;
  final String typeLabel;
  final String startPeriod;
  final String endPeriod;
  final String startDate;
  final String endDate;
  final int length;
  final String text;
  final bool isCurrent;

  factory PingteSegmentRange.fromJson(Map<String, dynamic> json) =>
      PingteSegmentRange(
        type: asString(json['type']),
        typeLabel: asString(json['type_label']),
        startPeriod: asString(json['start_period']),
        endPeriod: asString(json['end_period']),
        startDate: asString(json['start_date']),
        endDate: asString(json['end_date']),
        length: asInt(json['length']),
        text: asString(json['text']),
        isCurrent: asBool(json['is_current']),
      );
}

class PingteSegmentPeriodItem {
  const PingteSegmentPeriodItem({
    required this.period,
    this.drawDate = '',
    required this.isHit,
    this.ballCount = 0,
    this.hasTema = false,
    this.matchedNumbers = const [],
    this.matchedBalls = const [],
  });

  final String period;
  final String drawDate;
  final bool isHit;
  final int ballCount;
  final bool hasTema;
  final List<String> matchedNumbers;
  final List<PingteMatchedBall> matchedBalls;

  factory PingteSegmentPeriodItem.fromJson(Map<String, dynamic> json) {
    final balls = asModelList(json['matched_balls'], PingteMatchedBall.fromJson);
    final nums = asStringList(json['matched_numbers']);
    return PingteSegmentPeriodItem(
      period: asString(json['period']),
      drawDate: asString(json['draw_date'] ?? json['date']),
      isHit: asBool(json['is_hit'] ?? json['hit']),
      ballCount: asInt(json['ball_count']),
      hasTema: asBool(json['has_tema'] ?? json['tema_hit']),
      matchedNumbers: nums.isNotEmpty ? nums : balls.map((b) => b.number).toList(),
      matchedBalls: balls,
    );
  }
}

class PingteSegment {
  const PingteSegment({
    required this.segmentId,
    required this.type,
    required this.typeLabel,
    required this.startPeriod,
    required this.endPeriod,
    this.startDate = '',
    this.endDate = '',
    required this.length,
    this.totalBalls = 0,
    this.temaHits = 0,
    this.isCurrent = false,
    required this.text,
    this.periods = const [],
  });

  final int segmentId;
  final String type;
  final String typeLabel;
  final String startPeriod;
  final String endPeriod;
  final String startDate;
  final String endDate;
  final int length;
  final int totalBalls;
  final int temaHits;
  final bool isCurrent;
  final String text;
  final List<PingteSegmentPeriodItem> periods;

  factory PingteSegment.fromJson(Map<String, dynamic> json) => PingteSegment(
        segmentId: asInt(json['segment_id']),
        type: asString(json['type']),
        typeLabel: asString(json['type_label']),
        startPeriod: asString(json['start_period']),
        endPeriod: asString(json['end_period']),
        startDate: asString(json['start_date']),
        endDate: asString(json['end_date']),
        length: asInt(json['length']),
        totalBalls: asInt(json['total_balls']),
        temaHits: asInt(json['tema_hits']),
        isCurrent: asBool(json['is_current']),
        text: asString(json['text']),
        periods: asModelList(json['periods'], PingteSegmentPeriodItem.fromJson),
      );
}

class PingteDistributionItem {
  const PingteDistributionItem({
    required this.length,
    required this.count,
    this.label = '',
    this.latestStartPeriod = '',
    this.latestEndPeriod = '',
    this.latestText = '',
    this.isCurrent = false,
    this.ranges = const [],
  });

  final int length;
  final int count;
  final String label;
  final String latestStartPeriod;
  final String latestEndPeriod;
  final String latestText;
  final bool isCurrent;
  final List<PingteSegmentRange> ranges;

  factory PingteDistributionItem.fromJson(Map<String, dynamic> json) {
    final parsedRanges =
        asModelList(json['ranges'], PingteSegmentRange.fromJson);
    final firstRange = parsedRanges.isNotEmpty ? parsedRanges.first : null;
    final rawStart = asString(json['latest_start_period']);
    final rawEnd = asString(json['latest_end_period']);
    final rawText = asString(json['latest_text']);
    return PingteDistributionItem(
      length: asInt(json['length']),
      count: asInt(json['count']),
      label: asString(json['label']),
      latestStartPeriod:
          rawStart.isNotEmpty ? rawStart : (firstRange?.startPeriod ?? ''),
      latestEndPeriod:
          rawEnd.isNotEmpty ? rawEnd : (firstRange?.endPeriod ?? ''),
      latestText: rawText.isNotEmpty ? rawText : (firstRange?.text ?? ''),
      isCurrent: json['is_current'] != null
          ? asBool(json['is_current'])
          : (firstRange?.isCurrent ?? false),
      ranges: parsedRanges,
    );
  }
}

class PingteZodiacPeriodRecord {
  const PingteZodiacPeriodRecord({
    required this.period,
    this.drawDate = '',
    required this.isHit,
    this.ballCount = 0,
    this.hasTema = false,
    this.matchedNumbers = const [],
    this.matchedBalls = const [],
    this.allBalls = const [],
    this.segmentId = 0,
    this.segmentType = '',
    this.segmentTypeLabel = '',
    this.segmentStep = 0,
    this.segmentLength = 0,
    this.segmentStartPeriod = '',
    this.segmentEndPeriod = '',
    this.segmentText = '',
    this.runningText = '',
  });

  final String period;
  final String drawDate;
  final bool isHit;
  final int ballCount;
  final bool hasTema;
  final List<String> matchedNumbers;
  final List<PingteMatchedBall> matchedBalls;
  final List<PingteAllBall> allBalls;
  final int segmentId;
  final String segmentType;
  final String segmentTypeLabel;
  final int segmentStep;
  final int segmentLength;
  final String segmentStartPeriod;
  final String segmentEndPeriod;
  final String segmentText;
  final String runningText;

  factory PingteZodiacPeriodRecord.fromJson(Map<String, dynamic> json) {
    final balls = asModelList(json['matched_balls'], PingteMatchedBall.fromJson);
    final nums = asStringList(json['matched_numbers']);
    final segTypeLabel = asString(json['segment_type_label'] ?? json['run_type_label']);
    final segStep = asInt(json['segment_step'] ?? json['run_step']);
    final rawRunning = asString(json['running_text']);
    return PingteZodiacPeriodRecord(
      period: asString(json['period']),
      drawDate: asString(json['draw_date'] ?? json['date']),
      isHit: asBool(json['is_hit'] ?? json['hit']),
      ballCount: asInt(json['ball_count']),
      hasTema: asBool(json['has_tema'] ?? json['tema_hit']),
      matchedNumbers: nums.isNotEmpty ? nums : balls.map((b) => b.number).toList(),
      matchedBalls: balls,
      allBalls: asModelList(json['all_balls'], PingteAllBall.fromJson),
      segmentId: asInt(json['segment_id']),
      segmentType: asString(json['segment_type'] ?? json['run_type']),
      segmentTypeLabel: segTypeLabel,
      segmentStep: segStep,
      segmentLength: asInt(json['segment_length']),
      segmentStartPeriod: asString(json['segment_start_period'] ?? json['segment_start']),
      segmentEndPeriod: asString(json['segment_end_period'] ?? json['segment_end']),
      segmentText: asString(json['segment_text']),
      runningText: rawRunning.isNotEmpty
          ? rawRunning
          : (segTypeLabel.isNotEmpty && segStep > 0 ? '$segTypeLabel第$segStep期' : ''),
    );
  }
}

class PingteZodiacRank {
  const PingteZodiacRank({
    required this.name,
    required this.label,
    required this.count,
    this.pingCount = 0,
    this.temaCount = 0,
    required this.periodsCount,
    this.missPeriodsCount = 0,
    this.multiBallPeriodsCount = 0,
    required this.frequency,
    required this.currentOmission,
    required this.maxOmission,
    required this.maxConsecutive,
    required this.currentConsecutive,
    this.currentRange,
    this.maxConsecutiveRange,
    this.maxOmissionRange,
    this.segmentsCount = 0,
    this.hitSegmentsCount = 0,
    this.missSegmentsCount = 0,
    this.recentSegments = const [],
    this.streakDistribution = const [],
    this.omissionDistribution = const [],
    this.segments = const [],
    this.periodHistory = const [],
    required this.numbers,
    required this.rank,
    this.isHot = false,
    this.isCold = false,
  });

  final String name;
  final String label;
  final int count;
  final int pingCount;
  final int temaCount;
  final int periodsCount;
  final int missPeriodsCount;
  final int multiBallPeriodsCount;
  final double frequency;
  final int currentOmission;
  final int maxOmission;
  final int maxConsecutive;
  final int currentConsecutive;
  final PingteSegmentRange? currentRange;
  final PingteSegmentRange? maxConsecutiveRange;
  final PingteSegmentRange? maxOmissionRange;
  final int segmentsCount;
  final int hitSegmentsCount;
  final int missSegmentsCount;
  final List<PingteSegment> recentSegments;
  final List<PingteDistributionItem> streakDistribution;
  final List<PingteDistributionItem> omissionDistribution;
  final List<PingteSegment> segments;
  final List<PingteZodiacPeriodRecord> periodHistory;
  final List<String> numbers;
  final int rank;
  final bool isHot;
  final bool isCold;

  factory PingteZodiacRank.fromJson(Map<String, dynamic> json) =>
      PingteZodiacRank(
        name: asString(json['name']),
        label: asString(json['label']),
        count: asInt(json['count']),
        pingCount: asInt(json['ping_count']),
        temaCount: asInt(json['tema_count']),
        periodsCount: asInt(json['periods_count']),
        missPeriodsCount: asInt(json['miss_periods_count']),
        multiBallPeriodsCount: asInt(json['multi_ball_periods_count']),
        frequency: asDouble(json['frequency']),
        currentOmission: asInt(json['current_omission']),
        maxOmission: asInt(json['max_omission']),
        maxConsecutive: asInt(json['max_consecutive']),
        currentConsecutive: asInt(json['current_consecutive']),
        currentRange:
            asModelOrNull(json['current_range'], PingteSegmentRange.fromJson),
        maxConsecutiveRange: asModelOrNull(
            json['max_consecutive_range'], PingteSegmentRange.fromJson),
        maxOmissionRange: asModelOrNull(
            json['max_omission_range'], PingteSegmentRange.fromJson),
        segmentsCount: asInt(json['segments_count']),
        hitSegmentsCount: asInt(json['hit_segments_count']),
        missSegmentsCount: asInt(json['miss_segments_count']),
        recentSegments:
            asModelList(json['recent_segments'], PingteSegment.fromJson),
        streakDistribution: asModelList(
            json['streak_distribution'], PingteDistributionItem.fromJson),
        omissionDistribution: asModelList(
            json['omission_distribution'], PingteDistributionItem.fromJson),
        segments: asModelList(json['segments'], PingteSegment.fromJson),
        periodHistory: asModelList(
            json['period_history'], PingteZodiacPeriodRecord.fromJson),
        numbers: asStringList(json['numbers']),
        rank: asInt(json['rank']),
        isHot: asBool(json['is_hot']),
        isCold: asBool(json['is_cold']),
      );
}

class PingteZodiacHistoryResult {
  const PingteZodiacHistoryResult({
    required this.ok,
    required this.lottery,
    required this.samplePeriods,
    this.latestPeriod,
    this.earliestPeriod,
    this.latestDrawDate,
    this.selectedXiao,
    this.zodiacHistory,
    this.zodiacs = const [],
  });

  final bool ok;
  final String lottery;
  final int samplePeriods;
  final String? latestPeriod;
  final String? earliestPeriod;
  final String? latestDrawDate;
  final String? selectedXiao;
  final PingteZodiacRank? zodiacHistory;
  final List<PingteZodiacRank> zodiacs;

  factory PingteZodiacHistoryResult.fromJson(Map<String, dynamic> json) =>
      PingteZodiacHistoryResult(
        ok: asBool(json['ok'], fallback: true),
        lottery: asString(json['lottery']),
        samplePeriods: asInt(json['sample_periods']),
        latestPeriod: asStringOrNull(json['latest_period']),
        earliestPeriod: asStringOrNull(json['earliest_period']),
        latestDrawDate: asStringOrNull(json['latest_draw_date']),
        selectedXiao:
            asStringOrNull(json['selected_xiao'] ?? json['target_xiao']),
        zodiacHistory: asModelOrNull(
            json['zodiac_history'] ?? json['selected_zodiac'],
            PingteZodiacRank.fromJson),
        zodiacs: asModelList(json['zodiacs'], PingteZodiacRank.fromJson),
      );

  static const empty = PingteZodiacHistoryResult(
    ok: true,
    lottery: '',
    samplePeriods: 0,
  );
}

class PingteTailRank {
  const PingteTailRank({
    required this.name,
    required this.label,
    required this.count,
    required this.periodsCount,
    required this.frequency,
    required this.currentOmission,
    required this.maxOmission,
    required this.maxConsecutive,
    required this.currentConsecutive,
    required this.numbers,
    required this.rank,
    this.isHot = false,
    this.isCold = false,
  });

  final String name;
  final String label;
  final int count;
  final int periodsCount;
  final double frequency;
  final int currentOmission;
  final int maxOmission;
  final int maxConsecutive;
  final int currentConsecutive;
  final List<String> numbers;
  final int rank;
  final bool isHot;
  final bool isCold;

  factory PingteTailRank.fromJson(Map<String, dynamic> json) => PingteTailRank(
        name: asString(json['name']),
        label: asString(json['label']),
        count: asInt(json['count']),
        periodsCount: asInt(json['periods_count']),
        frequency: asDouble(json['frequency']),
        currentOmission: asInt(json['current_omission']),
        maxOmission: asInt(json['max_omission']),
        maxConsecutive: asInt(json['max_consecutive']),
        currentConsecutive: asInt(json['current_consecutive']),
        numbers: asStringList(json['numbers']),
        rank: asInt(json['rank']),
        isHot: asBool(json['is_hot']),
        isCold: asBool(json['is_cold']),
      );
}

class PingteNumberRank {
  const PingteNumberRank({
    required this.number,
    required this.count,
    required this.pingCount,
    required this.temaCount,
    required this.frequency,
    required this.currentOmission,
    required this.maxOmission,
    required this.maxConsecutive,
    required this.currentConsecutive,
    required this.bose,
    required this.xiao,
    required this.wuxing,
    required this.rank,
    this.isHot = false,
    this.isCold = false,
  });

  final String number;
  final int count;
  final int pingCount;
  final int temaCount;
  final double frequency;
  final int currentOmission;
  final int maxOmission;
  final int maxConsecutive;
  final int currentConsecutive;
  final String bose;
  final String xiao;
  final String wuxing;
  final int rank;
  final bool isHot;
  final bool isCold;

  factory PingteNumberRank.fromJson(Map<String, dynamic> json) => PingteNumberRank(
        number: asString(json['number']),
        count: asInt(json['count']),
        pingCount: asInt(json['ping_count']),
        temaCount: asInt(json['tema_count']),
        frequency: asDouble(json['frequency']),
        currentOmission: asInt(json['current_omission']),
        maxOmission: asInt(json['max_omission']),
        maxConsecutive: asInt(json['max_consecutive']),
        currentConsecutive: asInt(json['current_consecutive']),
        bose: asString(json['bose']),
        xiao: asString(json['xiao']),
        wuxing: asString(json['wuxing']),
        rank: asInt(json['rank']),
        isHot: asBool(json['is_hot']),
        isCold: asBool(json['is_cold']),
      );
}

class PingteBoseRank {
  const PingteBoseRank({
    required this.name,
    required this.label,
    required this.count,
    required this.periodsCount,
    required this.percentage,
    required this.currentOmission,
    required this.maxOmission,
    required this.maxConsecutive,
    this.currentConsecutive = 0,
    required this.numbers,
    required this.rank,
  });

  final String name;
  final String label;
  final int count;
  final int periodsCount;
  final double percentage;
  final int currentOmission;
  final int maxOmission;
  final int maxConsecutive;
  final int currentConsecutive;
  final List<String> numbers;
  final int rank;

  factory PingteBoseRank.fromJson(Map<String, dynamic> json) => PingteBoseRank(
        name: asString(json['name']),
        label: asString(json['label']),
        count: asInt(json['count']),
        periodsCount: asInt(json['periods_count']),
        percentage: asDouble(json['percentage']),
        currentOmission: asInt(json['current_omission']),
        maxOmission: asInt(json['max_omission']),
        maxConsecutive: asInt(json['max_consecutive']),
        currentConsecutive: asInt(json['current_consecutive']),
        numbers: asStringList(json['numbers']),
        rank: asInt(json['rank']),
      );
}

class PingteWuxingRank {
  const PingteWuxingRank({
    required this.name,
    required this.label,
    required this.count,
    required this.periodsCount,
    required this.percentage,
    required this.currentOmission,
    required this.maxOmission,
    required this.maxConsecutive,
    this.currentConsecutive = 0,
    required this.numbers,
    required this.rank,
  });

  final String name;
  final String label;
  final int count;
  final int periodsCount;
  final double percentage;
  final int currentOmission;
  final int maxOmission;
  final int maxConsecutive;
  final int currentConsecutive;
  final List<String> numbers;
  final int rank;

  factory PingteWuxingRank.fromJson(Map<String, dynamic> json) => PingteWuxingRank(
        name: asString(json['name']),
        label: asString(json['label']),
        count: asInt(json['count']),
        periodsCount: asInt(json['periods_count']),
        percentage: asDouble(json['percentage']),
        currentOmission: asInt(json['current_omission']),
        maxOmission: asInt(json['max_omission']),
        maxConsecutive: asInt(json['max_consecutive']),
        currentConsecutive: asInt(json['current_consecutive']),
        numbers: asStringList(json['numbers']),
        rank: asInt(json['rank']),
      );
}

class PingteRankingResult {
  const PingteRankingResult({
    required this.ok,
    required this.lottery,
    required this.samplePeriods,
    this.latestPeriod,
    this.earliestPeriod,
    this.zodiacRanking = const [],
    this.tailRanking = const [],
    this.numberRanking = const [],
    this.boseRanking = const [],
    this.wuxingRanking = const [],
  });

  final bool ok;
  final String lottery;
  final int samplePeriods;
  final String? latestPeriod;
  final String? earliestPeriod;
  final List<PingteZodiacRank> zodiacRanking;
  final List<PingteTailRank> tailRanking;
  final List<PingteNumberRank> numberRanking;
  final List<PingteBoseRank> boseRanking;
  final List<PingteWuxingRank> wuxingRanking;

  factory PingteRankingResult.fromJson(Map<String, dynamic> json) => PingteRankingResult(
        ok: asBool(json['ok'], fallback: true),
        lottery: asString(json['lottery']),
        samplePeriods: asInt(json['sample_periods']),
        latestPeriod: asStringOrNull(json['latest_period']),
        earliestPeriod: asStringOrNull(json['earliest_period']),
        zodiacRanking: asModelList(json['zodiac_ranking'], PingteZodiacRank.fromJson),
        tailRanking: asModelList(json['tail_ranking'], PingteTailRank.fromJson),
        numberRanking: asModelList(json['number_ranking'], PingteNumberRank.fromJson),
        boseRanking: asModelList(json['bose_ranking'], PingteBoseRank.fromJson),
        wuxingRanking: asModelList(json['wuxing_ranking'], PingteWuxingRank.fromJson),
      );

  static const empty = PingteRankingResult(
    ok: true,
    lottery: '',
    samplePeriods: 0,
  );
}


