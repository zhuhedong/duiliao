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
    required this.sum7,
    required this.sum7Size,
    required this.sum7Odd,
    required this.temaXiao,
    required this.temaBose,
    this.temaWuxing,
    required this.temaSize,
    required this.temaOdd,
    required this.temaSumOdd,
    required this.temaJiaye,
    required this.temaHalfwave,
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
    required this.periodRaw,
    this.drawDate,
    this.openedAt,
    required this.balls,
    required this.tema,
    required this.source,
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
