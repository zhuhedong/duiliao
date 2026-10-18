/// Betting Records screens (records.html, record-add*.html, record-detail.html, record-stats.html).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../home/home_screen.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import 'jump_code_assistant_screen.dart';

class BettingRecordItem {
  const BettingRecordItem({
    required this.id,
    required this.lottery,
    required this.period,
    required this.playType,
    required this.timeLabel,
    required this.numbers,
    required this.xiaos,
    required this.stakePerNote,
    required this.multiplier,
    required this.notesCount,
    required this.totalAmount,
    required this.status, // 'pending', 'won', 'lost'
    this.fushiLink,
    this.fushiLinks = const <int>[],
    this.hitNumbers = const <String>[],
    this.hitNotes = 0,
    this.odds = 7.0,
    this.payout = 0,
    this.netProfit = 0,
    this.winPillLabel,
    this.rawInput = '',
    this.note,
    this.sourceBadge,
    this.drawNumbers = const <String>[],
    this.specialNumber = '',
    this.drawTime = '',
  });

  final String id;
  final Lottery lottery;
  final String period;
  final String playType;
  final String timeLabel;
  final List<String> numbers;
  final List<String> xiaos;
  final int stakePerNote;
  final int multiplier;
  final int notesCount;
  final int totalAmount;
  final String status;
  final int? fushiLink;
  final List<int> fushiLinks;
  final List<String> hitNumbers;
  final int hitNotes;
  final double odds;
  final int payout;
  final int netProfit;
  final String? winPillLabel;
  final String rawInput;
  final String? note;
  final String? sourceBadge;
  final List<String> drawNumbers;
  final String specialNumber;
  final String drawTime;

  /// Pure-zodiac plays (平特肖 / 特肖 / …) store `xiaos` but are NOT 连肖复试.
  bool get isPureXiaoPlay {
    const pure = {'平特肖', '平特一肖', '特肖', '合肖', '正肖', '杀肖'};
    return pure.contains(playType) || playType.contains('平特');
  }

  bool get isPingte => playType.contains('平特');

  bool get isLianxiao {
    if (isPureXiaoPlay || playType.contains('不中')) return false;
    return playType.contains('连') ||
        fushiLinks.isNotEmpty ||
        fushiLink != null ||
        (xiaos.isNotEmpty && numbers.isEmpty);
  }

  String get mode {
    if (isLianxiao) return '连肖复试';
    if (playType.contains('不中')) return '不中码';
    if (isPingte) return '平特肖';
    return '号码单式';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'lottery': lottery.code,
    'period': period,
    'play_type': playType,
    'time_label': timeLabel,
    'numbers': numbers,
    'xiaos': xiaos,
    'stake_per_note': stakePerNote,
    'multiplier': multiplier,
    'notes_count': notesCount,
    'total_amount': totalAmount,
    'status': status,
    'fushi_link': fushiLink,
    'fushi_links': fushiLinks,
    'hit_numbers': hitNumbers,
    'hit_notes': hitNotes,
    'odds': odds,
    'payout': payout,
    'net_profit': netProfit,
    'win_pill_label': winPillLabel,
    'raw_input': rawInput,
    'note': note,
    'source_badge': sourceBadge,
    'draw_numbers': drawNumbers,
    'special_number': specialNumber,
    'draw_time': drawTime,
  };

  BettingRecordItem copyWith({
    String? id,
    Lottery? lottery,
    String? period,
    String? playType,
    String? timeLabel,
    List<String>? numbers,
    List<String>? xiaos,
    int? stakePerNote,
    int? multiplier,
    int? notesCount,
    int? totalAmount,
    String? status,
    int? fushiLink,
    List<int>? fushiLinks,
    List<String>? hitNumbers,
    int? hitNotes,
    double? odds,
    int? payout,
    int? netProfit,
    String? winPillLabel,
    String? rawInput,
    String? note,
    String? sourceBadge,
    List<String>? drawNumbers,
    String? specialNumber,
    String? drawTime,
  }) {
    return BettingRecordItem(
      id: id ?? this.id,
      lottery: lottery ?? this.lottery,
      period: period ?? this.period,
      playType: playType ?? this.playType,
      timeLabel: timeLabel ?? this.timeLabel,
      numbers: numbers ?? this.numbers,
      xiaos: xiaos ?? this.xiaos,
      stakePerNote: stakePerNote ?? this.stakePerNote,
      multiplier: multiplier ?? this.multiplier,
      notesCount: notesCount ?? this.notesCount,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      fushiLink: fushiLink ?? this.fushiLink,
      fushiLinks: fushiLinks ?? this.fushiLinks,
      hitNumbers: hitNumbers ?? this.hitNumbers,
      hitNotes: hitNotes ?? this.hitNotes,
      odds: odds ?? this.odds,
      payout: payout ?? this.payout,
      netProfit: netProfit ?? this.netProfit,
      winPillLabel: winPillLabel ?? this.winPillLabel,
      rawInput: rawInput ?? this.rawInput,
      note: note ?? this.note,
      sourceBadge: sourceBadge ?? this.sourceBadge,
      drawNumbers: drawNumbers ?? this.drawNumbers,
      specialNumber: specialNumber ?? this.specialNumber,
      drawTime: drawTime ?? this.drawTime,
    );
  }

  factory BettingRecordItem.fromJson(Map<String, Object?> json) {
    final drawMap = json['draw'] is Map
        ? Map<String, Object?>.from(json['draw'] as Map)
        : null;
    final rawBalls =
        (drawMap?['balls'] as List?) ?? (json['draw_numbers'] as List?);
    final drawNums = rawBalls != null && rawBalls.isNotEmpty
        ? rawBalls
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .map((s) => s.padLeft(2, '0'))
              .toList()
        : const <String>[];
    final rawTema = (drawMap?['tema'] ?? json['special_number'] ?? '')
        .toString()
        .trim();
    final tema = rawTema.isNotEmpty ? rawTema.padLeft(2, '0') : '';
    final drawTime =
        (drawMap?['opened_at'] ??
                drawMap?['draw_date'] ??
                json['draw_time'] ??
                '')
            .toString();
    final hitNums =
        ((json['hit_numbers'] as List?) ?? const <Object?>[])
            .map((e) => e.toString())
            .toList();
    final status = (json['status'] ?? 'pending').toString();
    final netProfit = (json['net_profit'] as num?)?.toInt() ?? 0;
    final hitNotes = (json['hit_notes'] as num?)?.toInt() ?? hitNums.length;
    final odds = (json['odds'] as num?)?.toDouble() ?? 7.0;
    final playType = (json['play_type'] ?? '正码').toString();
    String? winPill = json['win_pill_label']?.toString();
    if (winPill == null && status == 'won') {
      if (playType.contains('特码')) {
        winPill = '特码中 +¥$netProfit';
      } else if (playType.contains('连')) {
        winPill = '中 $hitNotes 注 +¥$netProfit';
      } else if (playType.contains('不中')) {
        winPill = '全不中 +¥$netProfit';
      } else {
        winPill = '中 ${hitNums.length} 码 +¥$netProfit';
      }
    }
    return BettingRecordItem(
      id: (json['id'] ?? '').toString(),
      lottery: Lottery.parse((json['lottery'] ?? 'macau').toString()),
      period: (json['period'] ?? '').toString(),
      playType: playType,
      timeLabel: (json['time_label'] ?? '').toString(),
      numbers: ((json['numbers'] as List?) ?? const <Object?>[])
          .map((e) => e.toString())
          .toList(),
      xiaos: ((json['xiaos'] as List?) ?? const <Object?>[])
          .map((e) => e.toString())
          .toList(),
      stakePerNote: (json['stake_per_note'] as num?)?.toInt() ?? 5,
      multiplier: (json['multiplier'] as num?)?.toInt() ?? 1,
      notesCount: (json['notes_count'] as num?)?.toInt() ?? 1,
      totalAmount: (json['total_amount'] as num?)?.toInt() ?? 5,
      status: status,
      fushiLink: (json['fushi_link'] as num?)?.toInt(),
      fushiLinks: ((json['fushi_links'] as List?) ?? const <Object?>[])
          .map((e) => (e as num?)?.toInt() ?? int.tryParse(e.toString()) ?? 0)
          .where((v) => v >= 2 && v <= 5)
          .toList(),
      hitNumbers: hitNums,
      hitNotes: hitNotes,
      odds: odds,
      payout: (json['payout'] as num?)?.toInt() ?? 0,
      netProfit: netProfit,
      winPillLabel: winPill,
      rawInput: (json['raw_input'] ?? '').toString(),
      note: json['note']?.toString(),
      sourceBadge: json['source_badge']?.toString(),
      drawNumbers: drawNums,
      specialNumber: tema,
      drawTime: drawTime,
    );
  }
}

class BettingRecordsNotifier extends Notifier<List<BettingRecordItem>> {
  static const _cacheKey = 'betting_records:v2';
  static const _legacyFakeIds = <String>{
    'rec-277-1',
    'rec-277-2',
    'rec-277-3',
    'rec-277-4',
    'rec-276-1',
    'rec-276-2',
    'rec-275-1',
    'rec-275-2',
  };

  @override
  List<BettingRecordItem> build() {
    Future.microtask(_hydrate);
    return const <BettingRecordItem>[];
  }

  Future<void> _hydrate() async {
    try {
      final cache = ref.read(cacheStoreProvider);
      final cached = await cache.read(
        _cacheKey,
        ttl: const Duration(days: 30),
      );
      if (cached != null && cached.value is Map) {
        final payload = Map<String, Object?>.from(cached.value as Map);
        final items = payload['items'];
        if (items is List) {
          state = items
              .whereType<Map>()
              .map(
                (m) => BettingRecordItem.fromJson(
                  Map<String, Object?>.from(m),
                ),
              )
              .where((r) => r.id.isNotEmpty && !_legacyFakeIds.contains(r.id))
              .toList(growable: false);
        }
      }
    } catch (_) {
      // CacheStore may not be initialized in unit tests; ignore gracefully.
    }
    await syncFromServer();
  }

  Future<void> _persistLocal(List<BettingRecordItem> records) async {
    try {
      final cache = ref.read(cacheStoreProvider);
      await cache.write(_cacheKey, {
        'items': [for (final r in records) r.toJson()],
      });
    } catch (_) {}
  }

  Future<void> syncFromServer() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/app/records');
      final rawItems = res['items'];
      if (rawItems is List) {
        final serverList = rawItems
            .whereType<Map>()
            .map(
              (m) => BettingRecordItem.fromJson(
                Map<String, Object?>.from(m),
              ),
            )
            .where((r) => r.id.isNotEmpty && !_legacyFakeIds.contains(r.id))
            .toList(growable: false);
        state = serverList;
        await _persistLocal(serverList);
      }
    } catch (_) {
      // Offline or unauthenticated in widget tests: retain local state.
    }
  }

  void addRecord(BettingRecordItem item) {
    final next = [item, ...state];
    state = next;
    unawaited(_persistLocal(next));
    unawaited(_postToServer(item));
  }

  Future<void> _postToServer(BettingRecordItem item) async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post(
        '/app/records',
        body: {
          'lottery': item.lottery.code,
          'period': item.period,
          'mode': item.mode,
          'play_type': item.playType,
          'numbers': item.numbers,
          'xiaos': item.xiaos,
          'stake_per_note': item.stakePerNote,
          'multiplier': item.multiplier,
          'notes_count': item.notesCount,
          'total_amount': item.totalAmount,
          'raw_input': item.rawInput,
          'note': item.note,
          'source_badge': item.sourceBadge,
        },
      );
      final rawRecord = res['record'];
      if (rawRecord is Map) {
        final saved = BettingRecordItem.fromJson(
          Map<String, Object?>.from(rawRecord),
        );
        state = [
          for (final r in state)
            if (r.id == item.id) saved else r,
        ];
        await _persistLocal(state);
      }
    } catch (_) {}
  }

  void removeRecord(String id) {
    final next = state.where((r) => r.id != id).toList(growable: false);
    state = next;
    unawaited(_persistLocal(next));
    unawaited(_deleteOnServer(id));
  }

  Future<void> _deleteOnServer(String id) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.delete('/app/records/$id');
    } catch (_) {}
  }

  Future<void> clearAllRecords({String? statusFilter}) async {
    final next = (statusFilter == null || statusFilter == 'all')
        ? const <BettingRecordItem>[]
        : state.where((r) => r.status != statusFilter).toList(growable: false);
    state = next;
    await _persistLocal(next);
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(
        '/app/records',
        query: statusFilter != null && statusFilter != 'all'
            ? {'status': statusFilter}
            : null,
      );
    } catch (_) {}
  }

  Future<void> settleRecords() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/app/records/settle');
      final rawItems = res['items'];
      if (rawItems is List) {
        final serverList = rawItems
            .whereType<Map>()
            .map(
              (m) => BettingRecordItem.fromJson(
                Map<String, Object?>.from(m),
              ),
            )
            .where((r) => r.id.isNotEmpty && !_legacyFakeIds.contains(r.id))
            .toList(growable: false);
        state = serverList;
        await _persistLocal(serverList);
      }
    } catch (_) {}
  }

  Future<BettingRecordItem?> copyRecordToPeriod(
    String recordId,
    String targetPeriod,
  ) async {
    final existingIndex = state.indexWhere((r) => r.id == recordId);
    if (existingIndex < 0) return null;
    final src = state[existingIndex];
    final yearPrefix = '${DateTime.now().toUtc().add(const Duration(hours: 8)).year}';
    final trimmed = targetPeriod.trim();
    final normTarget = (trimmed.length <= 3 && int.tryParse(trimmed) != null)
        ? '$yearPrefix${trimmed.padLeft(3, '0')}'
        : trimmed;

    final tempId = 'rec-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';
    final cloned = src.copyWith(
      id: tempId,
      period: normTarget,
      status: 'pending',
      hitNumbers: const <String>[],
      hitNotes: 0,
      payout: 0,
      netProfit: -src.totalAmount,
      winPillLabel: null,
      timeLabel: '${recentChinaMmDd(0)} 复制',
      sourceBadge: src.sourceBadge ?? '复制自${src.period}期',
      drawNumbers: const <String>[],
      specialNumber: '',
      drawTime: '',
    );

    final next = [cloned, ...state];
    state = next;
    await _persistLocal(next);

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post(
        '/app/records/$recordId/copy',
        body: {'target_period': normTarget},
      );
      final rawRecord = res['record'];
      if (rawRecord is Map) {
        final serverRec = BettingRecordItem.fromJson(
          Map<String, Object?>.from(rawRecord),
        );
        state = [
          for (final r in state)
            if (r.id == tempId) serverRec else r,
        ];
        await _persistLocal(state);
        return serverRec;
      }
    } catch (_) {}

    return cloned;
  }

  Future<List<BettingRecordItem>> copyPeriodToPeriod(
    String sourcePeriod,
    String targetPeriod, {
    Lottery? lottery,
  }) async {
    final yearPrefix = '${DateTime.now().toUtc().add(const Duration(hours: 8)).year}';
    final trimmed = targetPeriod.trim();
    final normTarget = (trimmed.length <= 3 && int.tryParse(trimmed) != null)
        ? '$yearPrefix${trimmed.padLeft(3, '0')}'
        : trimmed;

    final matching = state.where((r) {
      if (r.period != sourcePeriod) return false;
      if (lottery != null && r.lottery != lottery) return false;
      return true;
    }).toList();

    if (matching.isEmpty) return const [];

    final rand = Random();
    final tempMap = <String, BettingRecordItem>{};
    final clonedList = <BettingRecordItem>[];

    for (var i = 0; i < matching.length; i++) {
      final src = matching[i];
      final tempId = 'rec-${DateTime.now().millisecondsSinceEpoch}-$i-${rand.nextInt(9999)}';
      final cloned = src.copyWith(
        id: tempId,
        period: normTarget,
        status: 'pending',
        hitNumbers: const <String>[],
        hitNotes: 0,
        payout: 0,
        netProfit: -src.totalAmount,
        winPillLabel: null,
        timeLabel: '${recentChinaMmDd(0)} 复制',
        sourceBadge: src.sourceBadge ?? '复制自${src.period}期',
        drawNumbers: const <String>[],
        specialNumber: '',
        drawTime: '',
      );
      tempMap[tempId] = cloned;
      clonedList.add(cloned);
    }

    final next = [...clonedList, ...state];
    state = next;
    await _persistLocal(next);

    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post(
        '/app/records/copy',
        body: {
          'source_period': sourcePeriod,
          'target_period': normTarget,
          if (lottery != null) 'lottery': lottery.code,
        },
      );
      final rawItems = res['items'];
      if (rawItems is List && rawItems.isNotEmpty) {
        final serverList = rawItems
            .whereType<Map>()
            .map((m) => BettingRecordItem.fromJson(Map<String, Object?>.from(m)))
            .toList();
        final tempIds = tempMap.keys.toSet();
        state = [
          ...serverList,
          ...state.where((r) => !tempIds.contains(r.id)),
        ];
        await _persistLocal(state);
        return serverList;
      }
    } catch (_) {}

    return clonedList;
  }
}

final bettingRecordsProvider =
    NotifierProvider<BettingRecordsNotifier, List<BettingRecordItem>>(
      BettingRecordsNotifier.new,
    );

DateTime nowInChina([DateTime? now]) {
  return (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
}

String recentChinaMmDd([int daysAgo = 0, DateTime? now]) {
  final cn = nowInChina(now).subtract(Duration(days: daysAgo));
  return '${cn.month.toString().padLeft(2, '0')}-${cn.day.toString().padLeft(2, '0')}';
}

String recentChinaDateIso([int daysAgo = 0, DateTime? now]) {
  final cn = nowInChina(now).subtract(Duration(days: daysAgo));
  return '${cn.year}-${cn.month.toString().padLeft(2, '0')}-${cn.day.toString().padLeft(2, '0')}';
}

int dayOfYearInChina([DateTime? now]) {
  final cn = nowInChina(now);
  final dateOnly = DateTime.utc(cn.year, cn.month, cn.day);
  final startOfYear = DateTime.utc(cn.year, 1, 1);
  return dateOnly.difference(startOfYear).inDays + 1;
}

String currentPeriodForLottery([Lottery? lottery, DateTime? now]) {
  final cn = nowInChina(now);
  final doy = dayOfYearInChina(now);
  return '${cn.year}${doy.toString().padLeft(3, '0')}';
}

String _dateBasedPeriod([DateTime? now]) {
  return currentPeriodForLottery(null, now);
}

String previousPeriodOf(String period, [int offset = 1]) {
  final parsed = int.tryParse(period);
  if (parsed != null) {
    return '${parsed - offset}';
  }
  return period;
}

String nextPeriodOf(String period, [int offset = 1]) {
  final parsed = int.tryParse(period);
  if (parsed != null) {
    return '${parsed + offset}';
  }
  return period;
}

String _nextPeriodFrom(String? latestDrawPeriod) {
  if (latestDrawPeriod == null || latestDrawPeriod.isEmpty) {
    return _dateBasedPeriod();
  }
  return nextPeriodOf(latestDrawPeriod, 1);
}

typedef RecordPeriodContext = ({
  String currentPeriod,
  String? officialDrawPeriod,
  String? predictionPeriod,
  List<String> selectablePeriods,
});

final recordPeriodContextProvider =
    FutureProvider.family<RecordPeriodContext, Lottery>((ref, lottery) async {
      String? officialPeriod;
      String? predictionPeriod;
      String? serverCurrent;
      String? latestDrawDate;
      final drawPeriods = <String>[];

      try {
        final api = ref.read(apiClientProvider);
        final res = await api.get(
          '/collector/consensus/latest',
          query: {'lottery': lottery.code},
        );
        officialPeriod = res['official_draw_period']?.toString();
        predictionPeriod = res['latest_prediction_period']?.toString();
        serverCurrent = res['current_period']?.toString();
      } catch (_) {}

      try {
        final drawsRes = await ref
            .read(collectorRepositoryProvider)
            .draws(lottery: lottery.code, limit: 20);
        for (final item in drawsRes.value.items) {
          if (item.period.isNotEmpty && !drawPeriods.contains(item.period)) {
            drawPeriods.add(item.period);
          }
        }
        if (drawsRes.value.items.isNotEmpty) {
          officialPeriod ??= drawsRes.value.items.first.period;
          latestDrawDate = drawsRes.value.items.first.drawDate;
        }
      } catch (_) {}

      final todayIso = recentChinaDateIso(0);
      final todayShort = recentChinaMmDd(0);
      final drawIsToday =
          latestDrawDate != null &&
          (latestDrawDate.contains(todayIso) ||
              latestDrawDate.startsWith(todayShort));

      final dateFallback = currentPeriodForLottery(lottery);

      String resolvedCurrent;
      if (predictionPeriod != null &&
          predictionPeriod.isNotEmpty &&
          (officialPeriod == null ||
              predictionPeriod.compareTo(officialPeriod) >= 0)) {
        if (predictionPeriod == officialPeriod && !drawIsToday) {
          resolvedCurrent = _nextPeriodFrom(officialPeriod);
        } else {
          resolvedCurrent = predictionPeriod;
        }
      } else if (officialPeriod != null && officialPeriod.isNotEmpty) {
        resolvedCurrent = drawIsToday
            ? officialPeriod
            : _nextPeriodFrom(officialPeriod);
      } else if (serverCurrent != null && serverCurrent.isNotEmpty) {
        resolvedCurrent = serverCurrent;
      } else {
        resolvedCurrent = dateFallback;
      }

      // Ensure stale database cursors from earlier days never make currentPeriod lag behind today.
      if (resolvedCurrent.compareTo(dateFallback) < 0) {
        resolvedCurrent = dateFallback;
      }

      final optionsSet = <String>{};
      void addPeriod(String? p) {
        if (p != null && p.trim().isNotEmpty) {
          optionsSet.add(p.trim());
        }
      }

      final nextAfterCurrent = _nextPeriodFrom(resolvedCurrent);
      addPeriod(resolvedCurrent);
      if (drawIsToday) {
        addPeriod(nextAfterCurrent);
      }
      addPeriod(officialPeriod);
      addPeriod(predictionPeriod);
      for (final dp in drawPeriods) {
        addPeriod(dp);
      }
      final baseInt = int.tryParse(resolvedCurrent);
      if (baseInt != null) {
        for (var i = 1; i <= 15; i++) {
          addPeriod('${baseInt - i}');
        }
      }

      final sorted = optionsSet.toList()..sort((a, b) => b.compareTo(a));
      // Keep resolvedCurrent at index 0 so the default active chip is always currentPeriod.
      sorted.remove(resolvedCurrent);
      final options = <String>[resolvedCurrent, ...sorted];

      return (
        currentPeriod: resolvedCurrent,
        officialDrawPeriod: officialPeriod,
        predictionPeriod: predictionPeriod,
        selectablePeriods: options,
      );
    });

Future<String?> showTargetPeriodSheet(
  BuildContext context, {
  required Lottery lottery,
  required String currentPeriod,
  required List<String> selectablePeriods,
  String? defaultTargetPeriod,
  String? title,
  String? subtitle,
}) async {
  final targetDefault = defaultTargetPeriod ?? currentPeriod;
  final ctrl = TextEditingController(text: targetDefault);

  final quickChips = <String>[];
  if (!quickChips.contains(currentPeriod)) quickChips.add(currentPeriod);
  final nextP = nextPeriodOf(currentPeriod);
  if (!quickChips.contains(nextP)) quickChips.add(nextP);
  for (final p in selectablePeriods.take(6)) {
    if (!quickChips.contains(p)) quickChips.add(p);
  }

  String selectedPeriod = targetDefault;

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF111827),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.content_copy_rounded,
                          size: 19,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          title ?? '复制记录到指定期',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  '快捷选择目标期号',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in quickChips) ...[
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setSheetState(() {
                              selectedPeriod = p;
                              ctrl.text = p;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: selectedPeriod == p
                                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedPeriod == p
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '第 $p 期',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: selectedPeriod == p ? FontWeight.w800 : FontWeight.w500,
                                    color: selectedPeriod == p
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white,
                                  ),
                                ),
                                if (p == currentPeriod) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: DuiliaoColors.hit.withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '当前期',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: DuiliaoColors.hit,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '指定期号',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    setSheetState(() {
                      selectedPeriod = val.trim();
                    });
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.pin_rounded, size: 18),
                    hintText: '例如：$currentPeriod（支持填3位如 ${dayOfYearInChina()} 自动补全年份）',
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: GlassButton(
                    height: 44,
                    onPressed: () {
                      final raw = ctrl.text.trim();
                      if (raw.isEmpty) return;
                      final yearPrefix = '${DateTime.now().toUtc().add(const Duration(hours: 8)).year}';
                      final norm = (raw.length <= 3 && int.tryParse(raw) != null)
                          ? '$yearPrefix${raw.padLeft(3, '0')}'
                          : raw;
                      Navigator.pop(ctx, norm);
                    },
                    child: const Text(
                      '确认一键复制',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Records List Screen (records.html).
class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen> {
  String _filter = 'all'; // 'all', 'pending', 'won', 'lost'

  Future<void> _confirmClearRecords(
    BuildContext context,
    int count,
  ) async {
    final filterLabel = switch (_filter) {
      'pending' => '待开奖',
      'won' => '已中奖',
      'lost' => '未中',
      _ => '全部',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清空$filterLabel记录'),
        content: Text('确定要删除当前显示的 $count 条记录吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '确认清空',
              style: TextStyle(color: DuiliaoColors.miss),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(bettingRecordsProvider.notifier)
          .clearAllRecords(statusFilter: _filter);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清空 $count 条记录')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final all = ref.watch(bettingRecordsProvider);
    final lottery = ref.watch(selectedLotteryProvider);
    final periodCtx = ref.watch(recordPeriodContextProvider(lottery)).value;
    final defaultUpcomingPeriod =
        periodCtx?.currentPeriod ?? currentPeriodForLottery(lottery);

    final pendingRecords = all.where((r) => r.status == 'pending').toList();
    final settledRecords = all.where((r) => r.status != 'pending').toList();
    final wonCount = all.where((r) => r.status == 'won').length;
    final lostCount = all.where((r) => r.status == 'lost').length;

    final currentPeriodStake = pendingRecords.fold<int>(
      0,
      (acc, r) => acc + r.totalAmount,
    );
    final currentPeriodNotes = pendingRecords.fold<int>(
      0,
      (acc, r) => acc + r.notesCount,
    );
    final settledNet = settledRecords.fold<int>(
      0,
      (acc, r) => acc + r.netProfit,
    );
    final netLabel = settledNet >= 0
        ? '+¥$settledNet'
        : '−¥${settledNet.abs()}';

    final totalSettledNotes = settledRecords.fold<int>(
      0,
      (acc, r) => acc + r.notesCount,
    );
    final totalHitNotes = settledRecords.fold<int>(
      0,
      (acc, r) =>
          acc +
          (r.hitNotes > 0
              ? r.hitNotes
              : (r.status == 'won'
                    ? (r.hitNumbers.isNotEmpty ? r.hitNumbers.length : 1)
                    : 0)),
    );
    final winRatePct = totalSettledNotes > 0
        ? (totalHitNotes / totalSettledNotes * 100)
        : (settledRecords.isNotEmpty
              ? (wonCount / settledRecords.length * 100)
              : 0.0);

    final filtered = switch (_filter) {
      'pending' => pendingRecords,
      'won' => all.where((r) => r.status == 'won').toList(),
      'lost' => all.where((r) => r.status == 'lost').toList(),
      _ => all,
    };

    final periods = <String>[];
    final periodItemsMap = <String, List<BettingRecordItem>>{};
    for (final item in filtered) {
      if (!periods.contains(item.period)) {
        periods.add(item.period);
      }
      (periodItemsMap[item.period] ??= []).add(item);
    }

    final summaryPeriodText = pendingRecords.isNotEmpty
        ? '第 ${pendingRecords.first.period} 期 · 待开奖'
        : (all.isNotEmpty
              ? '最新第 ${all.first.period} 期 · 自动对奖'
              : '第 $defaultUpcomingPeriod 期 · 今晚 21:34 开奖');

    final content = SafeArea(
      bottom: false,
      child: Column(
        children: [
          DesignAppHeader(
            leading: canPop
                ? GlassIconButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: '返回',
                    onTap: () => Navigator.of(context).maybePop(),
                  )
                : null,
            title: '记录',
            subtitle: '智能识别 · 自动对奖',
            actions: [
              GlassIconButton(
                icon: Icons.sync_rounded,
                tooltip: '立即对奖',
                onTap: () async {
                  await ref
                      .read(bettingRecordsProvider.notifier)
                      .settleRecords();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已同步官方开奖并完成对奖结算')),
                    );
                  }
                },
              ),
              if (filtered.isNotEmpty)
                GlassIconButton(
                  icon: Icons.delete_sweep_rounded,
                  tooltip: '清空记录',
                  onTap: () => _confirmClearRecords(context, filtered.length),
                ),
              GlassIconButton(
                icon: Icons.filter_center_focus_rounded,
                tooltip: '挑码助手',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const JumpCodeAssistantScreen(),
                  ),
                ),
              ),
              GlassIconButton(
                icon: Icons.bar_chart_rounded,
                tooltip: '统计',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecordStatsScreen()),
                ),
              ),
              _HeaderGlowButton(
                label: '新增',
                icon: Icons.add_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecordAddScreen()),
                ),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(bettingRecordsProvider.notifier).syncFromServer(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  // 本期汇总卡片 (records.html lines 41-63)
                  GlassCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '本期汇总',
                              style: context.texts.labelSmall?.copyWith(
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                summaryPeriodText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: context.texts.labelSmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCol(
                                label: '本期投入',
                                value: '¥$currentPeriodStake',
                                sub:
                                    '${pendingRecords.length} 单 · $currentPeriodNotes 注',
                                valueColor:
                                    Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Expanded(
                              child: _SummaryCol(
                                label: '累计盈亏',
                                value: netLabel,
                                sub: '已结 ${settledRecords.length} 单',
                                valueColor: settledNet >= 0
                                    ? DuiliaoColors.hit
                                    : DuiliaoColors.miss,
                              ),
                            ),
                            Expanded(
                              child: _SummaryCol(
                                label: '中单率',
                                value: '${winRatePct.toStringAsFixed(1)}%',
                                sub: '$totalHitNotes/$totalSettledNotes 注',
                                valueColor:
                                    Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 状态过滤 (records.html lines 67-74)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        GlassChipTag(
                          label: '全部',
                          trailingText: '${all.length}',
                          active: _filter == 'all',
                          onTap: () => setState(() => _filter = 'all'),
                        ),
                        const SizedBox(width: 8),
                        GlassChipTag(
                          label: '待开奖',
                          trailingText: '${pendingRecords.length}',
                          trailingColor: DuiliaoColors.warning,
                          active: _filter == 'pending',
                          onTap: () => setState(() => _filter = 'pending'),
                        ),
                        const SizedBox(width: 8),
                        GlassChipTag(
                          label: '已中奖',
                          trailingText: '$wonCount',
                          trailingColor: DuiliaoColors.hit,
                          active: _filter == 'won',
                          onTap: () => setState(() => _filter = 'won'),
                        ),
                        const SizedBox(width: 8),
                        GlassChipTag(
                          label: '未中',
                          trailingText: '$lostCount',
                          active: _filter == 'lost',
                          onTap: () => setState(() => _filter = 'lost'),
                        ),
                      ],
                    ),
                  ),

                  if (filtered.isEmpty) ...[
                    const SizedBox(height: 20),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 28,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 38,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            all.isEmpty ? '暂无投注记录' : '当前筛选下暂无记录',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            all.isEmpty
                                ? '支持「龙兔各数5」「鼠虎马猴鸡 给我打复试3，4连一组5块」等口语智能录入，服务端保存并在官方开奖后自动对奖结算。'
                                : '可切换上方筛选标签或点击右上角新增记录。',
                            textAlign: TextAlign.center,
                            style: context.texts.labelSmall?.copyWith(
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                          if (all.isEmpty) ...[
                            const SizedBox(height: 16),
                            GlassButton(
                              height: 40,
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RecordAddScreen(),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_rounded, size: 16),
                                  SizedBox(width: 4),
                                  Text('立即新增记录'),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else
                    for (final period in periods) ...[
                      DesignSectionHeader(
                        title: '第 $period 期',
                        trailing: _buildPeriodTrailing(
                          context,
                          period,
                          periodItemsMap[period] ?? const [],
                          lottery,
                          periodCtx,
                        ),
                      ),
                      for (final item in (periodItemsMap[period] ?? const []))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Dismissible(
                            key: ValueKey('record-${item.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: DuiliaoColors.miss.withValues(
                                  alpha: 0.22,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: DuiliaoColors.miss.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    color: DuiliaoColors.miss,
                                    size: 18,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '删除',
                                    style: TextStyle(
                                      color: DuiliaoColors.miss,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onDismissed: (_) {
                              ref
                                  .read(bettingRecordsProvider.notifier)
                                  .removeRecord(item.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已删除该条记录')),
                              );
                            },
                            child: _RecordCard(
                              item: item,
                              onCopy: () => _copySingleRecordFlow(
                                context,
                                item,
                                lottery,
                                periodCtx,
                              ),
                              onDelete: () {
                                ref
                                    .read(bettingRecordsProvider.notifier)
                                    .removeRecord(item.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已删除该条记录')),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: canPop ? GlassBackground(child: content) : content,
    );
  }

  Future<void> _copySingleRecordFlow(
    BuildContext context,
    BettingRecordItem item,
    Lottery lottery,
    RecordPeriodContext? periodCtx,
  ) async {
    final currentP = periodCtx?.currentPeriod ?? currentPeriodForLottery(lottery);
    final selectable = periodCtx?.selectablePeriods ?? [currentP];
    final target = await showTargetPeriodSheet(
      context,
      lottery: lottery,
      currentPeriod: currentP,
      selectablePeriods: selectable,
      defaultTargetPeriod: currentP,
      title: '一键复制记录到指定期',
      subtitle: '源：第 ${item.period} 期 · ${item.playType} · ¥${item.totalAmount} (${item.notesCount}注)',
    );

    if (target != null && target.isNotEmpty && context.mounted) {
      await ref
          .read(bettingRecordsProvider.notifier)
          .copyRecordToPeriod(item.id, target);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功复制该记录到第 $target 期（待开奖）'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    }
  }

  Future<void> _copyWholePeriodFlow(
    BuildContext context,
    String period,
    List<BettingRecordItem> items,
    Lottery lottery,
    RecordPeriodContext? periodCtx,
  ) async {
    final currentP = periodCtx?.currentPeriod ?? currentPeriodForLottery(lottery);
    final selectable = periodCtx?.selectablePeriods ?? [currentP];
    final totalStake = items.fold<int>(0, (acc, r) => acc + r.totalAmount);
    final totalNotes = items.fold<int>(0, (acc, r) => acc + r.notesCount);
    final target = await showTargetPeriodSheet(
      context,
      lottery: lottery,
      currentPeriod: currentP,
      selectablePeriods: selectable,
      defaultTargetPeriod: currentP,
      title: '一键复制整期到指定期',
      subtitle: '源：第 $period 期 · 共 ${items.length} 单 · $totalNotes 注 · 合计 ¥$totalStake',
    );

    if (target != null && target.isNotEmpty && context.mounted) {
      final copied = await ref
          .read(bettingRecordsProvider.notifier)
          .copyPeriodToPeriod(period, target, lottery: lottery);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功将第 $period 期的 ${copied.length} 条记录复制到第 $target 期（待开奖）'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    }
  }

  Widget _buildPeriodTrailing(
    BuildContext context,
    String period,
    List<BettingRecordItem> items,
    Lottery lottery,
    RecordPeriodContext? periodCtx,
  ) {
    final hasPending = items.any((r) => r.status == 'pending');
    final net = items.fold<int>(0, (acc, r) => acc + r.netProfit);
    final sign = net >= 0 ? '+' : '−';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _copyWholePeriodFlow(context, period, items, lottery, periodCtx),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.copy_all_rounded,
                  size: 13,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 3.5),
                Text(
                  '整期复制',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (hasPending)
          const GlassStatusPill(
            label: '待开奖 · 今晚 21:34',
            tone: GlassPillTone.warning,
            pulse: true,
          )
        else
          GlassStatusPill(
            label: '盈亏 $sign¥${net.abs()}',
            tone: net >= 0 ? GlassPillTone.success : GlassPillTone.danger,
            showDot: false,
          ),
      ],
    );
  }
}

class _HeaderGlowButton extends StatelessWidget {
  const _HeaderGlowButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            gradient: DuiliaoColors.auroraGradient,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCol extends StatelessWidget {
  const _SummaryCol({
    required this.label,
    required this.value,
    required this.sub,
    required this.valueColor,
  });

  final String label;
  final String value;
  final String sub;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: context.texts.labelSmall?.copyWith(fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: tabularStyle(
            TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(sub, style: context.texts.labelSmall?.copyWith(fontSize: 11)),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.item,
    required this.onDelete,
    this.onCopy,
  });
  final BettingRecordItem item;
  final VoidCallback onDelete;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final isWon = item.status == 'won';
    final isLost = item.status == 'lost';
    final isPending = item.status == 'pending';

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RecordDetailScreen(record: item)),
      ),
      child: Opacity(
        opacity: isLost ? 0.85 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: item.xiaos.isNotEmpty
                      ? Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final x in item.xiaos)
                              ZTag(label: x, variant: ZTagVariant.primary),
                          ],
                        )
                      : Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final numStr in item.numbers)
                              NumberBall(
                                number: numStr,
                                bose: Lottery2026Lookup.boseForNumber(numStr),
                                size: 28,
                                showColorName: false,
                                hitHighlight: item.hitNumbers.contains(numStr),
                              ),
                          ],
                        ),
                ),
                const SizedBox(width: 8),
                if (onCopy != null) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onCopy,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.content_copy_rounded,
                        size: 16.5,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Bottom: formula + tags on left, status pill on right (records.html lines 96-105)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildFormulaText(context),
                      ZTag(label: item.playType),
                      if (item.xiaos.isNotEmpty && item.multiplier > 1)
                        ZTag(label: '倍 ×${item.multiplier}'),
                      if (item.sourceBadge != null)
                        GlassChipTag(
                          label: item.sourceBadge!,
                          icon: Icons.auto_awesome_rounded,
                          compact: true,
                        ),
                      if (isPending && item.timeLabel.isNotEmpty)
                        Text(
                          '录入 ${item.timeLabel}',
                          style: context.texts.labelSmall?.copyWith(
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isPending)
                  const GlassStatusPill(
                    label: '待开奖',
                    tone: GlassPillTone.neutral,
                    showDot: false,
                  )
                else if (isWon)
                  GlassStatusPill(
                    label:
                        item.winPillLabel ??
                        '中 ${item.hitNumbers.length} 码 +¥${item.netProfit}',
                    tone: GlassPillTone.success,
                    showDot: false,
                  )
                else
                  GlassStatusPill(
                    label: '未中 −¥${item.netProfit.abs()}',
                    tone: GlassPillTone.danger,
                    showDot: false,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaText(BuildContext context) {
    final baseStyle = context.texts.labelSmall?.copyWith(fontSize: 11);
    final strongStyle = baseStyle?.copyWith(
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface,
    );

    if (item.isLianxiao && item.xiaos.isNotEmpty) {
      final ks = item.fushiLinks.isNotEmpty
          ? item.fushiLinks
          : <int>[item.fushiLink ?? 4];
      final linkLabel = ks.join(',');
      final combLabel = ks
          .map((k) => 'C(${item.xiaos.length},$k)')
          .join('+');
      final multPart = item.multiplier > 1 ? ' × ${item.multiplier} 倍' : '';
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(
              text:
                  '复试 $linkLabel 连 · $combLabel ${item.notesCount} 注 × ¥${item.stakePerNote}$multPart = ',
            ),
            TextSpan(text: '¥${item.totalAmount}', style: strongStyle),
          ],
        ),
      );
    }

    if (item.xiaos.isNotEmpty) {
      final multPart = item.multiplier > 1 ? ' × ${item.multiplier} 倍' : '';
      final playLabel = item.isPingte ? '平特' : item.playType;
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(
              text:
                  '$playLabel · ${item.xiaos.length} 肖 ${item.notesCount} 注 × ¥${item.stakePerNote}$multPart = ',
            ),
            TextSpan(text: '¥${item.totalAmount}', style: strongStyle),
          ],
        ),
      );
    }

    if (item.status == 'pending') {
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(
              text: '单注 ¥${item.stakePerNote} × ${item.notesCount} 注 = ',
            ),
            TextSpan(text: '¥${item.totalAmount}', style: strongStyle),
          ],
        ),
      );
    }

    return Text(
      '${item.notesCount} 注 × ¥${item.stakePerNote} = ¥${item.totalAmount}',
      style: baseStyle,
    );
  }
}

/// Add Record Screen supporting 号码单式, 连肖复试, 平特肖, and 不中码 (record-add*.html).
class RecordAddScreen extends ConsumerStatefulWidget {
  const RecordAddScreen({
    super.key,
    this.mode = '号码单式',
    this.initialText,
  });

  final String mode;
  final String? initialText;

  @override
  ConsumerState<RecordAddScreen> createState() => _RecordAddScreenState();
}

class _RecordAddScreenState extends ConsumerState<RecordAddScreen> {
  late String _mode;
  Lottery _lottery = Lottery.macau;
  late String _period;
  bool _periodManuallySet = false;
  late String _selectedPlay;
  late final TextEditingController _inputController;
  late final TextEditingController _stakeController;
  late final TextEditingController _noteController;
  int _multiplier = 1;

  static const _singlePlays = <({String label, String code})>[
    (label: '特码', code: 'tema_n'),
    (label: '正码', code: 'zhengma_n'),
    (label: '特肖', code: 'texiao'),
    (label: '特尾', code: 'tewei'),
    (label: '特头', code: 'tetou'),
    (label: '特波', code: 'tebo'),
    (label: '两面', code: 'liangmian'),
    (label: '半波', code: 'banbo'),
    (label: '合肖', code: 'hexiao'),
    (label: '平特肖', code: 'pingtexiao'),
    (label: '平特尾', code: 'pingtewei'),
    (label: '正肖', code: 'zhengxiao'),
    (label: '连肖', code: 'lianxiao'),
    (label: '连尾', code: 'lianwei'),
    (label: '二中二', code: 'erzhonger'),
    (label: '三中三', code: 'sanzhongsan'),
    (label: '三中二', code: 'sanzhonger'),
    (label: '二中特', code: 'erzhongte'),
    (label: '不中码', code: 'nbuzhong'),
    (label: '杀肖', code: 'shaxiao'),
    (label: '杀尾', code: 'shawei'),
  ];

  static const _fushiPlays = ['3 连', '4 连', '5 连'];
  static const _nbuzhongPlays = ['5 不中', '6 不中', '7 不中', '8 不中'];
  static const _pureXiaoPlayLabels = {
    '平特肖',
    '平特一肖',
    '特肖',
    '合肖',
    '正肖',
    '杀肖',
  };

  bool get _isPureXiaoSelected =>
      _mode == '平特肖' || _pureXiaoPlayLabels.contains(_selectedPlay);

  bool get _isPingteSelected =>
      _mode == '平特肖' || _selectedPlay.contains('平特');

  double get _defaultOddsForSelected {
    if (_mode == '连肖复试') return 30.0;
    if (_isPingteSelected) {
      final xs = _parseXiaos(_inputController.text);
      if (xs.length == 1 && xs.first == '马') return 1.8;
      return 2.0;
    }
    if (_selectedPlay == '特肖') return 11.5;
    if (_selectedPlay == '正码') return 7.0;
    if (_selectedPlay.contains('不中')) return 2.58;
    return 47.0;
  }

  static final RegExp _stakePrefixRe = RegExp(
    r'(?:各数|个数|各号|各码|每码|每注|每组|各组|每个|一组|1组|一注|1注|一个|1个|各|×|\*)\s*(\d+)\s*(?:块|元|米|蚊)?',
  );
  static final RegExp _stakeSuffixRe = RegExp(
    r'(\d+)\s*(?:块|元|米|蚊)?\s*(?:/|每|一|1)\s*(?:组|注|个|码)',
  );
  static final RegExp _lianxiaoExprRe = RegExp(
    r'(?:复[试式]\s*)?[2-5二三四五](?:\s*[,，、./\-~～\s连]*\s*[2-5二三四五])*\s*连(?:复[试式])?',
  );

  static int? _extractStake(String text) {
    final m =
        _stakePrefixRe.firstMatch(text) ?? _stakeSuffixRe.firstMatch(text);
    return m != null ? int.tryParse(m.group(1) ?? '') : null;
  }

  static String _normalizeCnLinkNums(String text) {
    return text
        .replaceAll('二', '2')
        .replaceAll('三', '3')
        .replaceAll('四', '4')
        .replaceAll('五', '5');
  }

  List<int> _parseFushiLinks(String text) {
    final norm = _normalizeCnLinkNums(text);
    final ks = <int>[];
    final linkMatches = RegExp(
      r'(?:复[试式]\s*)?([2-5](?:\s*[,，、./\-~～\s连]+\s*[2-5])*|[2-5]{2,4})\s*连',
    ).allMatches(norm);
    for (final m in linkMatches) {
      final grp = m.group(1) ?? '';
      for (final ch in grp.characters) {
        final v = int.tryParse(ch);
        if (v != null && v >= 2 && v <= 5 && !ks.contains(v)) {
          ks.add(v);
        }
      }
    }
    if (ks.isNotEmpty) return ks;

    final fushiOnlyMatches = RegExp(
      r'复[试式]\s*([2-5](?:\s*[,，、./\-~～\s]+\s*[2-5])*|[2-5]{2,4})',
    ).allMatches(norm);
    for (final m in fushiOnlyMatches) {
      final grp = m.group(1) ?? '';
      for (final ch in grp.characters) {
        final v = int.tryParse(ch);
        if (v != null && v >= 2 && v <= 5 && !ks.contains(v)) {
          ks.add(v);
        }
      }
    }
    if (ks.isNotEmpty) return ks;

    for (final ch in _selectedPlay.characters) {
      final v = int.tryParse(ch);
      if (v != null && v >= 2 && v <= 5 && !ks.contains(v)) {
        ks.add(v);
      }
    }
    return ks.isNotEmpty ? ks : const [4];
  }

  @override
  void initState() {
    super.initState();
    _lottery = ref.read(selectedLotteryProvider);
    _period = _dateBasedPeriod();
    _mode = widget.mode;
    _selectedPlay = switch (_mode) {
      '连肖复试' => '4 连',
      '平特肖' => '平特肖',
      '不中码' => '6 不中',
      _ => '特码',
    };
    _multiplier = 1;
    _inputController = TextEditingController(
      text: widget.initialText ?? '',
    );
    _stakeController = TextEditingController();
    _noteController = TextEditingController();
    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      _applyQuickText(widget.initialText!);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoReadClipboard();
      });
    }
  }

  bool _looksLikeBettingInput(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return false;
    for (final x in Lottery2026Lookup.xiaoList) {
      if (trimmed.contains(x)) return true;
    }
    final matches = RegExp(r'(?<!\d)([0-4]?\d)(?!\d)').allMatches(trimmed);
    for (final m in matches) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n != null && n >= 1 && n <= 49) return true;
    }
    return RegExp(
      r'(?:连|不中|特码|正码|平特|各数|个数|各|每码|单注|复[试式])',
    ).hasMatch(trimmed);
  }

  Future<void> _autoReadClipboard({bool showToast = true}) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final raw = data?.text?.trim();
      if (raw == null || raw.isEmpty) return;
      if (_inputController.text.trim().isNotEmpty) return;
      if (!_looksLikeBettingInput(raw)) return;

      _applyQuickText(raw);

      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.content_paste_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已自动读取剪切板：${raw.length > 24 ? '${raw.substring(0, 24)}…' : raw}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final raw = data?.text?.trim();
    if (raw != null && raw.isNotEmpty) {
      _applyQuickText(raw);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已读取剪切板内容'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('剪切板为空'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _applyQuickText(String text) {
    _inputController.text = text;
    final parsedS = _extractStake(text);
    if (parsedS != null) {
      _stakeController.text = '$parsedS';
    }
    final multMatch = RegExp(r'(?:倍\s*(\d+)|(\d+)\s*倍)').firstMatch(text);
    if (multMatch != null) {
      final parsedMult = int.tryParse(
        multMatch.group(1) ?? multMatch.group(2) ?? '',
      );
      if (parsedMult != null && parsedMult >= 1) {
        _multiplier = parsedMult;
      }
    } else {
      _multiplier = 1;
    }
    if ((RegExp(r'复[试式]').hasMatch(text) || _lianxiaoExprRe.hasMatch(text)) &&
        _parseXiaos(text).isNotEmpty) {
      _mode = '连肖复试';
      final ks = _parseFushiLinks(text);
      _selectedPlay = '${ks.join(",")} 连';
    } else if (text.contains('不中')) {
      _mode = '不中码';
      final m = RegExp(r'(\d+)\s*不中').firstMatch(text);
      if (m != null) {
        _selectedPlay = '${m.group(1)} 不中';
      } else {
        _selectedPlay = '6 不中';
      }
    } else if (text.contains('平特') && _parseXiaos(text).isNotEmpty) {
      _mode = '平特肖';
      _selectedPlay = '平特肖';
    } else if (text.contains('特肖') && _parseXiaos(text).isNotEmpty) {
      _mode = '号码单式';
      _selectedPlay = '特肖';
    } else {
      _mode = '号码单式';
      _selectedPlay = text.contains('正码') ? '正码' : '特码';
    }
    setState(() {});
  }

  Future<void> _promptCustomPeriod(BuildContext context) async {
    final ctrl = TextEditingController(text: _period);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入期号'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '例如：$_period（支持填3位如 ${dayOfYearInChina()} 自动补全年份）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final yearPrefix = '${DateTime.now().toUtc().add(const Duration(hours: 8)).year}';
      final normalized = result.length == 3 ? '$yearPrefix$result' : result;
      setState(() {
        _period = normalized;
        _periodManuallySet = true;
      });
    }
  }

  Future<void> _openPeriodPickerSheet(
    BuildContext context, {
    required List<String> allPeriods,
    required String currentPeriod,
    required String? officialDrawPeriod,
  }) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '选择期号 · ${_lottery.label}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx, '__custom__');
                      },
                      icon: const Icon(Icons.edit_rounded, size: 15),
                      label: const Text('手动输入'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: allPeriods.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (_, idx) {
                      final p = allPeriods[idx];
                      final isSelected = p == _period;
                      final isCurrent = p == currentPeriod;
                      final isOfficial = p == officialDrawPeriod;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        title: Row(
                          children: [
                            Text(
                              '第 $p 期',
                              style: tabularStyle(
                                TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isCurrent)
                              const GlassStatusPill(
                                label: '当前期 · 默认',
                                color: DuiliaoColors.hit,
                                showDot: false,
                              )
                            else if (isOfficial)
                              const GlassStatusPill(
                                label: '最新已开',
                                color: DuiliaoColors.primary,
                                showDot: false,
                              ),
                          ],
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 20,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, p),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted || chosen == null) return;
    if (chosen == '__custom__') {
      await _promptCustomPeriod(context);
      return;
    }
    setState(() {
      _period = chosen;
      _periodManuallySet = true;
    });
  }

  String _periodChipLabel(
    String p, {
    required String currentPeriod,
    required String? officialDrawPeriod,
  }) {
    if (p == currentPeriod) return '第 $p 期 (当前)';
    if (p == officialDrawPeriod) return '第 $p 期 (上期)';
    return '第 $p 期';
  }

  void _switchMode(String nextMode) {
    if (nextMode == '全部玩法') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PlayCatalogScreen()),
      );
      return;
    }
    setState(() {
      _mode = nextMode;
      _selectedPlay = switch (nextMode) {
        '连肖复试' => '4 连',
        '平特肖' => '平特肖',
        '不中码' => '6 不中',
        _ => '特码',
      };
      _multiplier = 1;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _stakeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<String> _parseNumbers(String text) {
    // 平特肖 / 特肖等纯生肖玩法不把生肖展开成号码
    if (_isPureXiaoSelected) {
      return const [];
    }
    if (_mode != '连肖复试') {
      final parsed = JumpCodeMatcher.parseExpression(text);
      final hasNonXiaoAttr = parsed.includedConditions.any(
        (c) => !Lottery2026Lookup.xiaoList.contains(c),
      );
      if (parsed.hasKillClause ||
          parsed.excludedConditions.isNotEmpty ||
          parsed.excludedNumbers.isNotEmpty ||
          hasNonXiaoAttr) {
        final onlyHeadTailOrXiao = parsed.includedConditions.every(
          (c) =>
              c.endsWith('头') ||
              c.endsWith('尾') ||
              Lottery2026Lookup.xiaoList.contains(c),
        );
        final evaluated = JumpCodeMatcher.evaluate(
          includedConditions: parsed.includedConditions,
          excludedConditions: parsed.excludedConditions,
          includedNumbers: parsed.includedNumbers,
          excludedNumbers: parsed.excludedNumbers,
          defaultEmptyKeepAll: false,
          crossGroupIntersectionForIncluded: !onlyHeadTailOrXiao,
        );
        return [
          for (final n in evaluated) n.toString().padLeft(2, '0'),
        ];
      }
    }

    var cleaned = text.replaceAll(_stakePrefixRe, '');
    cleaned = cleaned.replaceAll(_stakeSuffixRe, '');
    cleaned = cleaned.replaceAll(RegExp(r'[·\s]*\d+\s*不中.*$'), '');
    cleaned = cleaned.replaceAll(_lianxiaoExprRe, '');
    cleaned = cleaned.replaceAll(
      RegExp(r'复[试式]\s*[2-5二三四五,，、./\-~～\s]*'),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'(?:倍\s*\d+|\d+\s*倍)'), '');
    final result = <String>[];
    // Support zodiac-to-number expansion (e.g. "龙兔各数5" -> 龙: 03,15,27,39 + 兔: 04,16,28,40)
    if (_mode != '连肖复试') {
      for (final ch in cleaned.characters) {
        if (Lottery2026Lookup.xiaoList.contains(ch)) {
          for (final numStr in Lottery2026Lookup.numbersForXiao(ch)) {
            if (!result.contains(numStr)) {
              result.add(numStr);
            }
          }
        }
      }
    }
    final matches = RegExp(r'(?<!\d)([0-4]?\d)(?!\d)').allMatches(cleaned);
    for (final m in matches) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n != null && n >= 1 && n <= 49) {
        final formatted = n.toString().padLeft(2, '0');
        if (!result.contains(formatted)) result.add(formatted);
      }
    }
    return result;
  }

  List<String> _parseXiaos(String text) {
    final parsed = JumpCodeMatcher.parseExpression(text);
    if (parsed.hasKillClause || parsed.excludedConditions.isNotEmpty) {
      final killedXiaos = parsed.excludedConditions
          .where(Lottery2026Lookup.xiaoList.contains)
          .toSet();
      final pickedXiaos = parsed.includedConditions
          .where(Lottery2026Lookup.xiaoList.contains)
          .toList();
      if (_mode == '连肖复试') {
        final base = pickedXiaos.isNotEmpty
            ? pickedXiaos
            : Lottery2026Lookup.xiaoList;
        return base.where((x) => !killedXiaos.contains(x)).toList();
      }
      return pickedXiaos.where((x) => !killedXiaos.contains(x)).toList();
    }
    final result = <String>[];
    for (final ch in text.characters) {
      if (Lottery2026Lookup.xiaoList.contains(ch) && !result.contains(ch)) {
        result.add(ch);
      }
    }
    return result;
  }

  List<List<String>> _combinations(List<String> items, int k) {
    if (k <= 0 || k > items.length) return const [];
    final out = <List<String>>[];
    void helper(int start, List<String> current) {
      if (current.length == k) {
        out.add(List<String>.of(current));
        return;
      }
      for (var i = start; i < items.length; i++) {
        current.add(items[i]);
        helper(i + 1, current);
        current.removeLast();
      }
    }

    helper(0, <String>[]);
    return out;
  }

  String get _headerTitle => switch (_mode) {
    '连肖复试' => '新增记录 · 连肖',
    '平特肖' => '新增记录 · 平特',
    '不中码' => '新增记录 · 不中码',
    _ => '新增记录',
  };

  String get _selectedPlayCode {
    for (final p in _singlePlays) {
      if (p.label == _selectedPlay) return p.code;
    }
    return 'tema_n';
  }

  @override
  Widget build(BuildContext context) {
    final periodCtx = ref.watch(recordPeriodContextProvider(_lottery)).value;
    final homeSnap = ref
        .watch(
          homeProvider((lottery: _lottery, playType: 'pingte_xiao')),
        )
        .value;
    final latestOfficialPeriod =
        periodCtx?.officialDrawPeriod ?? homeSnap?.snapshot.latestDraw?.period;
    final currentPeriod =
        periodCtx?.currentPeriod ?? _nextPeriodFrom(latestOfficialPeriod);
    final dynamicPrevPeriod =
        latestOfficialPeriod ??
        (int.tryParse(currentPeriod) != null
            ? '${int.parse(currentPeriod) - 1}'
            : currentPeriod);

    if (!_periodManuallySet && _period != currentPeriod) {
      _period = currentPeriod;
    }

    final allSelectablePeriods = <String>{
      currentPeriod,
      dynamicPrevPeriod,
      ...?periodCtx?.selectablePeriods,
      if (_period.isNotEmpty) _period,
    }.toList(growable: false);

    final periodOptions = <String>{
      currentPeriod,
      dynamicPrevPeriod,
      ...allSelectablePeriods.take(4),
      if (_period.isNotEmpty) _period,
    }.take(5).toList(growable: false);

    final text = _inputController.text;
    final parsedStake = _extractStake(text);
    final typedStake = int.tryParse(_stakeController.text.trim());
    final stake = typedStake ?? parsedStake ?? 5;

    final numbers = _parseNumbers(text);
    final xiaos = _parseXiaos(text);
    final fushiKs = _mode == '连肖复试' ? _parseFushiLinks(text) : const [4];
    final fushiKLabel = fushiKs.join(',');
    final nbuzhongN = int.tryParse(_selectedPlay.split(' ').first) ?? 6;
    final fushiCombos = _mode == '连肖复试'
        ? <List<String>>[
            for (final k in fushiKs) ..._combinations(xiaos, k),
          ]
        : const <List<String>>[];
    final fushiFormulaLabel = fushiKs
        .map((k) => 'C(${xiaos.length},$k)')
        .join('+');

    final hasInput = text.trim().isNotEmpty;
    final notesCount = switch (_mode) {
      '连肖复试' => fushiCombos.length,
      '平特肖' => (!hasInput || xiaos.isEmpty) ? 0 : xiaos.length,
      '不中码' => (!hasInput || numbers.isEmpty) ? 0 : 1,
      _ => _isPureXiaoSelected
          ? ((!hasInput || xiaos.isEmpty) ? 0 : xiaos.length)
          : ((!hasInput || numbers.isEmpty) ? 0 : numbers.length),
    };
    final totalAmount = notesCount * stake * _multiplier;

    final fushiPlayOptions = fushiKs.length > 1
        ? <String>[..._fushiPlays, '$fushiKLabel 连']
        : _fushiPlays;
    final selectedFushiOption = fushiKs.length > 1
        ? '$fushiKLabel 连'
        : (_fushiPlays.contains(_selectedPlay)
              ? _selectedPlay
              : '${fushiKs.first} 连');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: '返回',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: _headerTitle,
                actions: [
                  GlassIconButton(
                    icon: Icons.filter_center_focus_rounded,
                    tooltip: '挑码助手',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const JumpCodeAssistantScreen(),
                        ),
                      );
                    },
                  ),
                  GlassIconButton(
                    icon: Icons.help_outline_rounded,
                    tooltip: '帮助',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PlayCatalogScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // 录入模式切换 (record-add.html lines 39-44)
                    GlassSegmentedControl<String>(
                      items: const ['号码单式', '连肖复试', '平特肖', '不中码', '全部玩法'],
                      selected: _mode,
                      labelBuilder: (m) => switch (m) {
                        '平特肖' => '平特',
                        '连肖复试' => '连肖',
                        '号码单式' => '单式',
                        '全部玩法' => '全部',
                        _ => m,
                      },
                      onChanged: _switchMode,
                    ),

                    // 彩种与期号 (默认当前期数，支持直接选期/更多期号/自定义)
                    const DesignSectionHeader(title: '彩种'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final item in Lottery.all)
                                GlassChipTag(
                                  label: item.label,
                                  compact: true,
                                  active: item == _lottery,
                                  onTap: () => setState(() {
                                    _lottery = item;
                                    _periodManuallySet = false;
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                Text('期号：', style: context.texts.labelSmall),
                                for (final p in periodOptions.take(2)) ...[
                                  GlassChipTag(
                                    label: _periodChipLabel(
                                      p,
                                      currentPeriod: currentPeriod,
                                      officialDrawPeriod: latestOfficialPeriod,
                                    ),
                                    compact: true,
                                    active: _period == p,
                                    onTap: () => setState(() {
                                      _period = p;
                                      _periodManuallySet = true;
                                    }),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (!periodOptions.take(2).contains(_period)) ...[
                                  GlassChipTag(
                                    label: '第 $_period 期',
                                    compact: true,
                                    active: true,
                                    onTap: () {},
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                GlassChipTag(
                                  label: '选期 ▾',
                                  compact: true,
                                  onTap: () => _openPeriodPickerSheet(
                                    context,
                                    allPeriods: allSelectablePeriods,
                                    currentPeriod: currentPeriod,
                                    officialDrawPeriod: latestOfficialPeriod,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GlassChipTag(
                                  label: '自定义…',
                                  compact: true,
                                  icon: Icons.edit_rounded,
                                  onTap: () => _promptCustomPeriod(context),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 智能录入 (record-add.html lines 64-78)
                    const DesignSectionHeader(title: '智能录入'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                switch (_mode) {
                                  '连肖复试' => '粘贴或输入连肖复试文本',
                                  '平特肖' => '粘贴或输入平特生肖文本',
                                  '不中码' => '粘贴或输入不中码文本',
                                  _ => '粘贴或输入号码/生肖文本',
                                },
                                style: context.texts.labelSmall,
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: _pasteFromClipboard,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.content_paste_rounded,
                                          size: 13,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          '读取剪切板',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (text.isNotEmpty) ...[
                                    const SizedBox(width: 12),
                                    InkWell(
                                      onTap: () => setState(() {
                                        _inputController.clear();
                                      }),
                                      child: Text(
                                        '清空输入',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _inputController,
                            maxLines: 2,
                            onChanged: (v) {
                              final parsedS = _extractStake(v);
                              if (parsedS != null) {
                                _stakeController.text = '$parsedS';
                              }
                              // Auto-switch to 连肖复试 when user enters fushi expression with zodiacs
                              if ((RegExp(r'复[试式]').hasMatch(v) ||
                                      _lianxiaoExprRe.hasMatch(v)) &&
                                  _parseXiaos(v).isNotEmpty) {
                                _mode = '连肖复试';
                                final ks = _parseFushiLinks(v);
                                _selectedPlay = '${ks.join(",")} 连';
                              } else if (v.contains('平特') &&
                                  _parseXiaos(v).isNotEmpty) {
                                _mode = '平特肖';
                                _selectedPlay = '平特肖';
                              } else if (v.contains('不中')) {
                                _mode = '不中码';
                                final m = RegExp(r'(\d+)\s*不中').firstMatch(v);
                                if (m != null) {
                                  _selectedPlay = '${m.group(1)} 不中';
                                }
                              }
                              final multMatch = RegExp(
                                r'(?:倍\s*(\d+)|(\d+)\s*倍)',
                              ).firstMatch(v);
                              if (multMatch != null) {
                                final parsedMult = int.tryParse(
                                  multMatch.group(1) ??
                                      multMatch.group(2) ??
                                      '',
                                );
                                if (parsedMult != null && parsedMult >= 1) {
                                  _multiplier = parsedMult;
                                }
                              } else {
                                _multiplier = 1;
                              }
                              setState(() {});
                            },
                            style: const TextStyle(
                              fontSize: 14.5,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              hintText:
                                  '如：龙兔各数5、蛇龙鸡平特各5、鼠虎马猴鸡复试3，4连…',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              GlassChipTag(
                                label: '示例：龙兔各数5',
                                compact: true,
                                onTap: () => _applyQuickText('龙兔各数5'),
                              ),
                              GlassChipTag(
                                label: '示例：平特蛇龙鸡各5',
                                compact: true,
                                onTap: () => _applyQuickText('蛇龙鸡平特各5'),
                              ),
                              GlassChipTag(
                                label: '示例：杀1头，2尾各5',
                                compact: true,
                                onTap: () => _applyQuickText('杀1头，2尾各5'),
                              ),
                              GlassChipTag(
                                label: '示例：复试3,4连一组5块',
                                compact: true,
                                onTap: () => _applyQuickText(
                                  '鼠虎马猴鸡 给我打复试3，4连一组5块',
                                ),
                              ),
                              GlassChipTag(
                                label: '示例：6不中各10',
                                compact: true,
                                onTap: () => _applyQuickText(
                                  '02.04.06.08.10.12·6不中个数10',
                                ),
                              ),
                            ],
                          ),
                          if (text.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Builder(
                              builder: (context) {
                                final pk = JumpCodeMatcher.parseExpression(text);
                                final killLabels = [
                                  ...pk.excludedConditions,
                                  for (final n in pk.excludedNumbers)
                                    n.toString().padLeft(2, '0'),
                                ];
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    GlassStatusPill(
                                      label: switch (_mode) {
                                        '连肖复试' =>
                                          '已识别 ${xiaos.length} 个生肖 · 复试 $fushiKLabel 连 · 单注 ¥$stake',
                                        '平特肖' =>
                                          '已识别 ${xiaos.length} 个平特生肖 · 单注 ¥$stake · 赔率 不带马1:2 / 带马1:1.8',
                                        '不中码' =>
                                          '已识别 ${numbers.length} 个号码 · $nbuzhongN 不中 · 单注 ¥$stake',
                                        _ =>
                                          killLabels.isNotEmpty
                                              ? '已杀 [${killLabels.join('、')}] · 保留 ${numbers.length} 码 · 单注 ¥$stake'
                                              : (_isPureXiaoSelected && xiaos.isNotEmpty
                                                    ? '已识别 ${xiaos.length} 个生肖（$_selectedPlay）· 单注 ¥$stake'
                                                    : (xiaos.isNotEmpty
                                                          ? '已识别 ${xiaos.join('')}转 ${numbers.length} 个号码 · 单注 ¥$stake'
                                                          : '已识别 ${numbers.length} 个号码 · 单注 ¥$stake')),
                                      },
                                      tone: GlassPillTone.success,
                                    ),
                                    const GlassStatusPill(
                                      label: '格式有效',
                                      tone: GlassPillTone.primary,
                                      showDot: false,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 识别预览 (record-add.html lines 81-101)
                    DesignSectionHeader(
                      title: (_mode == '连肖复试' || _mode == '平特肖')
                          ? '识别预览 · 已选 ${xiaos.length} 肖'
                          : '识别预览',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_mode == '连肖复试' || _mode == '平特肖' || _isPureXiaoSelected)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final x in xiaos)
                                  ZTag(label: x, variant: ZTagVariant.primary),
                                if (xiaos.isEmpty)
                                  Text(
                                    _mode == '平特肖' || _isPingteSelected
                                        ? '等待输入平特生肖（7 码任一命中）'
                                        : '等待输入生肖内容',
                                    style: context.texts.bodySmall,
                                  ),
                              ],
                            )
                          else ...[
                            Builder(
                              builder: (context) {
                                final pk = JumpCodeMatcher.parseExpression(
                                  text,
                                );
                                final killLabels = [
                                  ...pk.excludedConditions,
                                  for (final n in pk.excludedNumbers)
                                    n.toString().padLeft(2, '0'),
                                ];
                                if (killLabels.isEmpty && xiaos.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final k in killLabels)
                                        ZTag(
                                          label: '已杀: $k',
                                          variant: ZTagVariant.primary,
                                        ),
                                      for (final x in xiaos)
                                        ZTag(
                                          label:
                                              '$x (${Lottery2026Lookup.numbersForXiao(x).join("·")})',
                                          variant: ZTagVariant.hit,
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final nStr in numbers)
                                  NumberBall(
                                    number: nStr,
                                    bose: Lottery2026Lookup.boseForNumber(nStr),
                                    size: 28,
                                    showColorName: false,
                                  ),
                                if (numbers.isEmpty)
                                  Text(
                                    _mode == '不中码'
                                        ? '等待输入不中码号码'
                                        : '等待输入号码或生肖',
                                    style: context.texts.bodySmall,
                                  ),
                              ],
                            ),
                          ],
                          if (_mode == '不中码') ...[
                            const SizedBox(height: 12),
                            GlassSubtleBox(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Text.rich(
                                TextSpan(
                                  style: context.texts.labelSmall?.copyWith(
                                    fontSize: 11,
                                    height: 1.7,
                                  ),
                                  children: [
                                    const TextSpan(
                                      text: '中奖条件：',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const TextSpan(text: '以上 '),
                                    TextSpan(
                                      text: '${numbers.length}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          ' 个号码在第 $_period 期开奖号码(6 正码 + 特码)中',
                                    ),
                                    const TextSpan(
                                      text: '全部不开出',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const TextSpan(text: '即中奖。'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  switch (_mode) {
                                    '连肖复试' =>
                                      xiaos.isEmpty
                                          ? '等待录入生肖'
                                          : '复试 $fushiKLabel 连 · $fushiFormulaLabel = $notesCount 注',
                                    '平特肖' =>
                                      xiaos.isEmpty
                                          ? '等待录入平特生肖'
                                          : '平特 ${xiaos.length} 肖 · $notesCount 注 × ¥$stake × $_multiplier 倍',
                                    '不中码' =>
                                      numbers.isEmpty
                                          ? '等待录入号码'
                                          : '整组 1 注 × ¥$stake × $_multiplier 倍',
                                    _ =>
                                      (_isPureXiaoSelected
                                          ? (xiaos.isEmpty
                                                ? '等待录入生肖'
                                                : '$_selectedPlay · ${xiaos.length} 肖 · $notesCount 注 × ¥$stake')
                                          : (numbers.isEmpty
                                                ? '等待录入号码或生肖'
                                                : '共 $notesCount 注 × ¥$stake × $_multiplier 倍')),
                                  },
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.labelSmall?.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '合计 ',
                                    style: context.texts.labelSmall?.copyWith(
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '¥$totalAmount',
                                    style: tabularStyle(
                                      TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 组合展开 (record-add-fushi.html lines 92-123)
                    if (_mode == '连肖复试' && fushiCombos.isNotEmpty) ...[
                      DesignSectionHeader(
                        title: '组合展开 · ${fushiCombos.length} 注',
                      ),
                      GlassGroup(
                        margin: EdgeInsets.zero,
                        children: [
                          for (var i = 0; i < fushiCombos.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  GlassStatusPill(
                                    label: '注 ${i + 1}',
                                    tone: GlassPillTone.neutral,
                                    showDot: false,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final x in fushiCombos[i])
                                          ZTag(label: x),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '¥$stake × $_multiplier倍',
                                    style: tabularStyle(
                                      context.texts.labelSmall?.copyWith(
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],

                    // 识别规则 (record-add.html lines 104-113)
                    const DesignSectionHeader(title: '识别规则'),
                    GlassSubtleBox(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: switch (_mode) {
                          '连肖复试' => const [
                            _RuleBullet('① 生肖连续书写自动拆分：龙牛猴鸡兔 → 龙/牛/猴/鸡/兔'),
                            _RuleBullet('② 支持单连与多连复试：复试4连 → C(M,4) 注；复试3，4连 → C(M,3)+C(M,4) 注'),
                            _RuleBullet('③ 「一组5块」「各数10」「个数10」识别为每注单额；「倍2」「×2倍」识别为倍数'),
                            _RuleBullet('④ 示例：鼠虎马猴鸡 给我打复试3，4连一组5块 → C(5,3)+C(5,4)=15 注 × ¥5 = ¥75'),
                            _RuleBullet('⑤ 连肖赔率：不带马 2连=4 / 3连=10 / 4连=30 / 5连=100；带马 2连=3.8 / 3连=9 / 4连=28 / 5连=80'),
                          ],
                          '平特肖' => const [
                            _RuleBullet('① 生肖连续书写自动拆分：蛇龙鸡 → 蛇/龙/鸡，每个生肖 1 注'),
                            _RuleBullet('② 平特命中规则：所选生肖出现在当期 7 码（6 正码 + 1 特码）任一即中'),
                            _RuleBullet('③ 「各5」「个数5」「一组5块」识别为每注单额；赔率：不带马 1:2，带马 1:1.8'),
                            _RuleBullet('④ 示例：蛇龙鸡平特各5 → 3 注 × ¥5 = ¥15；开出蛇/龙/鸡任一即按命中肖数派彩'),
                          ],
                          '不中码' => const [
                            _RuleBullet('① 「不中码」为整组玩法：N 个号码合成 1 注，不逐码拆分'),
                            _RuleBullet('② 号码个数与 N 自动核对，不一致时标红提示'),
                            _RuleBullet('③ 「各数10」「个数10」为该整组单额；「倍2」「×2倍」识别为倍数'),
                            _RuleBullet('④ 本例：6 码 6 不中 → 1 注 × ¥10 = ¥10'),
                          ],
                          _ => const [
                            _RuleBullet('① 号码以「.」「,」「空格」「、」分隔，范围 01–49，自动去重、标注波色'),
                            _RuleBullet('② 「各数5」「个数5」「一组5块」「各5」「×5」「每码5」识别为单注金额'),
                            _RuleBullet('③ 生肖包码：龙兔各数5 → 龙(03·15·27·39)+兔(04·16·28·40)共 8 码 × ¥5 = ¥40'),
                            _RuleBullet('④ 平特肖：蛇龙鸡平特各5 → 3 肖 × ¥5 = ¥15，7 码任一命中即中；不带马1:2 / 带马1:1.8'),
                            _RuleBullet('⑤ 连肖复试：鼠虎马猴鸡 给我打复试3，4连一组5块 → C(5,3)+C(5,4)=15 注 × ¥5 = ¥75'),
                            _RuleBullet('⑥ 不中码：02.04.06.08.10.12·6不中个数10 → 整组 1 注，全不开出即中'),
                            _RuleBullet('⑦ 示例：18.42.39个数5 → 3 注 × ¥5 = ¥15'),
                          ],
                        },
                      ),
                    ),

                    // 记录信息 (record-add.html lines 116-170)
                    const DesignSectionHeader(title: '记录信息'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('期号', style: context.texts.labelSmall),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final p in periodOptions)
                                GlassChipTag(
                                  label: _periodChipLabel(
                                    p,
                                    currentPeriod: currentPeriod,
                                    officialDrawPeriod: latestOfficialPeriod,
                                  ),
                                  active: _period == p,
                                  onTap: () => setState(() {
                                    _period = p;
                                    _periodManuallySet = true;
                                  }),
                                ),
                              GlassChipTag(
                                label: '更多期号 ▾',
                                onTap: () => _openPeriodPickerSheet(
                                  context,
                                  allPeriods: allSelectablePeriods,
                                  currentPeriod: currentPeriod,
                                  officialDrawPeriod: latestOfficialPeriod,
                                ),
                              ),
                              GlassChipTag(
                                label: '自定义期号…',
                                icon: Icons.edit_rounded,
                                onTap: () => _promptCustomPeriod(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_mode == '连肖复试') ...[
                            Text(
                              '玩法 · 连肖复试连数',
                              style: context.texts.labelSmall,
                            ),
                            const SizedBox(height: 8),
                            GlassSegmentedControl<String>(
                              items: fushiPlayOptions,
                              selected: selectedFushiOption,
                              labelBuilder: (p) => p,
                              onChanged: (p) => setState(() {
                                _selectedPlay = p;
                                final k = p.split(' ').first;
                                if (_lianxiaoExprRe.hasMatch(
                                  _inputController.text,
                                )) {
                                  _inputController.text = _inputController.text
                                      .replaceFirst(_lianxiaoExprRe, '复试$k连');
                                }
                              }),
                            ),
                          ] else if (_mode == '平特肖') ...[
                            Text(
                              '玩法 · 平特肖',
                              style: context.texts.labelSmall,
                            ),
                            const SizedBox(height: 8),
                            GlassSubtleBox(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Text(
                                '7 码（正码+特码）任一出现所选生肖即中 · 不带马 1:2 / 带马 1:1.8',
                                style: context.texts.labelSmall?.copyWith(fontSize: 11),
                              ),
                            ),
                          ] else if (_mode == '不中码') ...[
                            Text(
                              '玩法 · 不中码个数(N)',
                              style: context.texts.labelSmall,
                            ),
                            const SizedBox(height: 8),
                            GlassSegmentedControl<String>(
                              items: _nbuzhongPlays,
                              selected: _selectedPlay,
                              labelBuilder: (p) => p,
                              onChanged: (p) =>
                                  setState(() => _selectedPlay = p),
                            ),
                          ] else ...[
                            Text(
                              '玩法（项目完整支持）',
                              style: context.texts.labelSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '当前选择：$_selectedPlay · $_selectedPlayCode',
                              style: context.texts.labelSmall?.copyWith(
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final p in _singlePlays)
                                  GlassChipTag(
                                    label: p.label,
                                    active: _selectedPlay == p.label,
                                    onTap: () => setState(
                                      () => _selectedPlay = p.label,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PlayCatalogScreen(),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '查看玩法编码与规则',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '单注金额',
                                      style: context.texts.labelSmall,
                                    ),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _stakeController,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setState(() {}),
                                      decoration: const InputDecoration(
                                        prefixText: '¥ ',
                                        hintText: '5',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '倍数',
                                      style: context.texts.labelSmall,
                                    ),
                                    const SizedBox(height: 6),
                                    GlassSubtleBox(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 7,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          GlassIconButton(
                                            icon: Icons.remove_rounded,
                                            size: 28,
                                            iconSize: 14,
                                            onTap: () => setState(() {
                                              if (_multiplier > 1) {
                                                _multiplier--;
                                              }
                                            }),
                                          ),
                                          Text(
                                            '$_multiplier',
                                            style: tabularStyle(
                                              const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          GlassIconButton(
                                            icon: Icons.add_rounded,
                                            size: 28,
                                            iconSize: 14,
                                            onTap: () => setState(() {
                                              _multiplier++;
                                            }),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text('备注', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _noteController,
                            decoration: InputDecoration(
                              hintText: switch (_mode) {
                                '连肖复试' => '可选，如：四肖防冷，复试求全',
                                '平特肖' => '可选，如：跟海哥平特一肖',
                                '不中码' => '可选，如：冷号组合，博全不开',
                                _ => '可选，如：跟海哥本期主推',
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 底部操作条 (record-add.html lines 173-176)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: GlassCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Text.rich(
                        TextSpan(
                          style: context.texts.labelSmall?.copyWith(
                            fontSize: 11,
                          ),
                          children: [
                            TextSpan(text: '$notesCount 注 · 合计 '),
                            TextSpan(
                              text: '¥$totalAmount',
                              style: tabularStyle(
                                TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GlassButton(
                          height: 42,
                          onPressed: () {
                            final usesXiaosOnly =
                                _mode == '连肖复试' ||
                                _mode == '平特肖' ||
                                _isPureXiaoSelected;
                            if (_mode == '连肖复试' &&
                                (xiaos.isEmpty || fushiCombos.isEmpty)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请先输入有效的生肖内容')),
                              );
                              return;
                            }
                            if ((_mode == '平特肖' || _isPureXiaoSelected) &&
                                xiaos.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请先输入有效的平特/生肖内容')),
                              );
                              return;
                            }
                            if (!usesXiaosOnly && numbers.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请先输入有效的号码或生肖内容')),
                              );
                              return;
                            }
                            if (stake <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请输入有效的单注金额')),
                              );
                              return;
                            }
                            final now = TimeOfDay.now();
                            final hh = now.hour.toString().padLeft(2, '0');
                            final mm = now.minute.toString().padLeft(2, '0');
                            final resolvedPlayType = _mode == '连肖复试'
                                ? (fushiKs.length > 1
                                      ? '连肖 $fushiKLabel连'
                                      : '连肖')
                                : (_mode == '平特肖' ? '平特肖' : _selectedPlay);
                            final item = BettingRecordItem(
                              id: 'rec-${DateTime.now().millisecondsSinceEpoch}',
                              lottery: _lottery,
                              period: _period,
                              playType: resolvedPlayType,
                              timeLabel: '$hh:$mm',
                              numbers: usesXiaosOnly ? const [] : numbers,
                              xiaos: usesXiaosOnly ? xiaos : const [],
                              fushiLink: _mode == '连肖复试' ? fushiKs.first : null,
                              fushiLinks: _mode == '连肖复试' ? fushiKs : const [],
                              stakePerNote: stake,
                              multiplier: _multiplier,
                              notesCount: notesCount,
                              totalAmount: totalAmount,
                              odds: _defaultOddsForSelected,
                              status: 'pending',
                              rawInput: _inputController.text.trim(),
                              note: _noteController.text.trim().isEmpty
                                  ? null
                                  : _noteController.text.trim(),
                            );
                            ref
                                .read(bettingRecordsProvider.notifier)
                                .addRecord(item);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('记录已保存')),
                            );
                            Navigator.of(context).maybePop();
                          },
                          child: const Text('保存记录'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleBullet extends StatelessWidget {
  const _RuleBullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: context.texts.labelSmall?.copyWith(fontSize: 11, height: 1.7),
      ),
    );
  }
}

/// Record Detail Screen (record-detail.html).
class RecordDetailScreen extends ConsumerWidget {
  const RecordDetailScreen({super.key, this.record});

  final BettingRecordItem? record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(bettingRecordsProvider);
    final item = record != null
        ? (all.where((r) => r.id == record!.id).firstOrNull ?? record!)
        : (all.isNotEmpty
              ? all.first
              : BettingRecordItem(
                  id: 'empty',
                  lottery: Lottery.macau,
                  period: currentPeriodForLottery(Lottery.macau),
                  playType: '正码',
                  timeLabel: '',
                  numbers: const [],
                  xiaos: const [],
                  stakePerNote: 5,
                  multiplier: 1,
                  notesCount: 0,
                  totalAmount: 0,
                  status: 'pending',
                ));
    final isWon = item.status == 'won';
    final isPending = item.status == 'pending';
    final hasDraw =
        item.drawNumbers.isNotEmpty || item.specialNumber.isNotEmpty;
    final totalTargets = item.numbers.isNotEmpty
        ? item.numbers.length
        : item.xiaos.length;
    final hitRate = totalTargets == 0
        ? 0
        : (item.hitNumbers.length / totalTargets * 100).round();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: '返回',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '记录详情',
                actions: [
                  GlassIconButton(
                    icon: Icons.content_copy_rounded,
                    tooltip: '复制到指定期',
                    onTap: () => _copyToTargetPeriod(context, ref, item),
                  ),
                  GlassIconButton(
                    icon: Icons.more_vert_rounded,
                    tooltip: '更多',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: item.rawInput));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制记录内容到剪贴板')),
                      );
                    },
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // 结算状态 hero (record-detail.html lines 38-42)
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          GlassStatusPill(
                            label: isPending
                                ? '待开奖'
                                : isWon
                                ? '已中奖'
                                : '未中奖',
                            tone: isPending
                                ? GlassPillTone.warning
                                : isWon
                                ? GlassPillTone.success
                                : GlassPillTone.danger,
                            pulse: isPending,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isPending
                                ? '¥${item.totalAmount}'
                                : isWon
                                ? '+¥${item.netProfit}'
                                : '−¥${item.netProfit.abs()}',
                            style: tabularStyle(
                              TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                                color: isPending
                                    ? Theme.of(context).colorScheme.onSurface
                                    : isWon
                                    ? DuiliaoColors.hit
                                    : DuiliaoColors.miss,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '第 ${item.period} 期 · ${item.playType} · ${isPending ? '待开奖' : '已对奖'}',
                            style: context.texts.labelSmall?.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 我的号码 (record-detail.html lines 45-75)
                    DesignSectionHeader(
                      title: isPending
                          ? '我的号码 · 共 $totalTargets 项'
                          : '我的号码 · 中 ${item.hitNumbers.length} 码',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: item.xiaos.isNotEmpty
                          ? Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final x in item.xiaos)
                                  ZTag(label: x, variant: ZTagVariant.primary),
                              ],
                            )
                          : (item.numbers.isEmpty
                                ? Text(
                                    '暂无号码明细',
                                    style: context.texts.labelSmall,
                                  )
                                : Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    alignment: WrapAlignment.spaceBetween,
                                    children: [
                                      for (final nStr in item.numbers)
                                        NumberBall(
                                          number: nStr,
                                          bose: Lottery2026Lookup.boseForNumber(
                                            nStr,
                                          ),
                                          size: 38,
                                          showColorName: false,
                                          hitHighlight: item.hitNumbers
                                              .contains(nStr),
                                          dimmed:
                                              !isPending &&
                                              !item.hitNumbers.contains(nStr),
                                          caption: isPending
                                              ? '·'
                                              : item.hitNumbers.contains(nStr)
                                              ? '中'
                                              : '·',
                                          captionBold: item.hitNumbers.contains(
                                            nStr,
                                          ),
                                          captionColor:
                                              item.hitNumbers.contains(nStr)
                                              ? DuiliaoColors.hit
                                              : null,
                                        ),
                                    ],
                                  )),
                    ),

                    // 开奖对照 (record-detail.html lines 78-96)
                    const DesignSectionHeader(title: '开奖对照'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '第 ${item.period} 期 · ${hasDraw && item.drawTime.isNotEmpty ? item.drawTime : '等待今晚 21:34 开奖'}',
                            style: context.texts.labelSmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (hasDraw)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                for (final n in item.drawNumbers)
                                  NumberBall(
                                    number: n,
                                    bose: Lottery2026Lookup.boseForNumber(n),
                                    size: 28,
                                    showColorName: false,
                                  ),
                                Text(
                                  '+',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (item.specialNumber.isNotEmpty)
                                  NumberBall(
                                    number: item.specialNumber,
                                    bose: Lottery2026Lookup.boseForNumber(
                                      item.specialNumber,
                                    ),
                                    isGold: true,
                                    isSpecial: true,
                                    size: 28,
                                    showColorName: false,
                                  ),
                              ],
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Text(
                                  '本期尚未开奖 · 官方开奖后系统将自动核对并结算',
                                  style: context.texts.labelSmall,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Center(
                            child: GlassChipTag(
                              label: isPending ? '等待今晚 21:34 官方开奖' : '号码命中',
                              trailingText: isPending
                                  ? null
                                  : '${item.hitNumbers.length} 个 · 命中率 $hitRate%',
                              trailingColor: DuiliaoColors.hit,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 结算明细 (record-detail.html lines 99-133)
                    const DesignSectionHeader(title: '结算明细'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        _DetailRow(
                          label: '投入',
                          sub:
                              '${item.notesCount} 注 × 单注 ¥${item.stakePerNote}${item.multiplier > 1 ? ' × ${item.multiplier} 倍' : ''}',
                          value: '¥${item.totalAmount}',
                        ),
                        _DetailRow(
                          label: '中单',
                          sub: item.hitNumbers.isEmpty && item.hitNotes == 0
                              ? (isPending ? '等待开奖对奖' : '未命中')
                              : (item.isLianxiao
                                  ? (item.notesCount == 1
                                      ? '${item.hitNumbers.join(' · ')} × 赔率 1:${item.odds % 1 == 0 ? item.odds.toInt() : item.odds}'
                                      : '${item.hitNumbers.join(' · ')} 命中 ${item.hitNotes} 组')
                                  : '${item.hitNumbers.join(' · ')} × 赔率 1:${item.odds % 1 == 0 ? item.odds.toInt() : item.odds}'),
                          value:
                              '${item.hitNotes > 0 ? item.hitNotes : item.hitNumbers.length} 注',
                        ),
                        _DetailRow(
                          label: '派彩',
                          sub: isPending
                              ? '待开奖后结算'
                              : (item.isLianxiao
                                  ? (item.notesCount == 1
                                      ? '${item.hitNotes > 0 ? item.hitNotes : 1} 注 × ¥${item.stakePerNote} × ${item.odds % 1 == 0 ? item.odds.toInt() : item.odds} 倍'
                                      : '按组合分档（带马/不带马）派彩 ¥${item.payout}')
                                  : '${item.hitNotes > 0 ? item.hitNotes : item.hitNumbers.length} 注 × ¥${item.stakePerNote} × ${item.odds % 1 == 0 ? item.odds.toInt() : item.odds} 倍'),
                          value: '¥${item.payout}',
                        ),
                        _DetailRow(
                          label: '盈亏',
                          sub: '派彩 ¥${item.payout} − 投入 ¥${item.totalAmount}',
                          value: isPending
                              ? '待结算'
                              : item.netProfit >= 0
                              ? '+¥${item.netProfit}'
                              : '−¥${item.netProfit.abs()}',
                          valueColor: isPending
                              ? null
                              : item.netProfit >= 0
                              ? DuiliaoColors.hit
                              : DuiliaoColors.miss,
                        ),
                      ],
                    ),

                    // 原始录入 (record-detail.html lines 136-142)
                    const DesignSectionHeader(title: '原始录入'),
                    GlassSubtleBox(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.rawInput.isEmpty ? '—' : item.rawInput,
                            style: tabularStyle(
                              const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '录入时间 ${item.timeLabel} · 智能识别 ${item.numbers.isNotEmpty ? '${item.numbers.length} 码' : '${item.xiaos.length} 肖'} · 单注 ¥${item.stakePerNote}',
                            style: context.texts.labelSmall?.copyWith(
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 底部操作 (record-detail.html lines 145-158)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: GlassCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      GlassGhostButton(
                        label: '复制到指定期',
                        icon: Icons.content_copy_rounded,
                        onTap: () => _copyToTargetPeriod(context, ref, item),
                      ),
                      const SizedBox(width: 8),
                      GlassGhostButton(
                        label: '删除',
                        icon: Icons.delete_outline_rounded,
                        isDanger: true,
                        onTap: () {
                          ref
                              .read(bettingRecordsProvider.notifier)
                              .removeRecord(item.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已删除该条记录')),
                          );
                          Navigator.of(context).maybePop();
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GlassButton(
                          height: 40,
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => RecordAddScreen(
                                  mode: item.mode,
                                  initialText: item.rawInput,
                                ),
                              ),
                            );
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, size: 16),
                              SizedBox(width: 4),
                              Text('再来一单', style: TextStyle(fontSize: 13.5)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyToTargetPeriod(
    BuildContext context,
    WidgetRef ref,
    BettingRecordItem item,
  ) async {
    final lottery = item.lottery;
    final periodCtx = ref.read(recordPeriodContextProvider(lottery)).value;
    final currentP = periodCtx?.currentPeriod ?? currentPeriodForLottery(lottery);
    final selectable = periodCtx?.selectablePeriods ?? [currentP];
    final target = await showTargetPeriodSheet(
      context,
      lottery: lottery,
      currentPeriod: currentP,
      selectablePeriods: selectable,
      defaultTargetPeriod: currentP,
      title: '一键复制记录到指定期',
      subtitle: '源：第 ${item.period} 期 · ${item.playType} · ¥${item.totalAmount} (${item.notesCount}注)',
    );

    if (target != null && target.isNotEmpty && context.mounted) {
      final copied = await ref
          .read(bettingRecordsProvider.notifier)
          .copyRecordToPeriod(item.id, target);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功复制该记录到第 $target 期（待开奖）'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        if (copied != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RecordDetailScreen(record: copied),
            ),
          );
        }
      }
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.sub,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String sub;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(sub, style: context.texts.labelSmall),
              ],
            ),
          ),
          Text(
            value,
            style: tabularStyle(
              TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Record Stats Screen (record-stats.html) computed dynamically from real records.
class RecordStatsScreen extends ConsumerStatefulWidget {
  const RecordStatsScreen({super.key});

  @override
  ConsumerState<RecordStatsScreen> createState() => _RecordStatsScreenState();
}

class _RecordStatsScreenState extends ConsumerState<RecordStatsScreen> {
  String _window = '30';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(bettingRecordsProvider);
    final settled = all.where((r) => r.status != 'pending').toList();

    final totalInvest = settled.fold<int>(0, (s, r) => s + r.totalAmount);
    final totalPayout = settled.fold<int>(0, (s, r) => s + r.payout);
    final netProfit = totalPayout - totalInvest;
    final totalNotes = settled.fold<int>(0, (s, r) => s + r.notesCount);
    final hitNotes = settled.fold<int>(
      0,
      (s, r) =>
          s +
          (r.hitNotes > 0
              ? r.hitNotes
              : (r.status == 'won'
                    ? (r.hitNumbers.isNotEmpty ? r.hitNumbers.length : 1)
                    : 0)),
    );
    final winRatePct = totalNotes > 0 ? (hitNotes / totalNotes * 100) : 0.0;
    final roiPct = totalInvest > 0 ? (netProfit / totalInvest * 100) : 0.0;

    final investStr = '¥$totalInvest';
    final payoutStr = '¥$totalPayout';
    final netStr = netProfit >= 0 ? '+¥$netProfit' : '−¥${netProfit.abs()}';
    final winRateStr = '${winRatePct.toStringAsFixed(1)}%';
    final ordersSub = '${settled.length} 单 · $totalNotes 注';
    final payoutSub = '中 $hitNotes 注';
    final netSub = '回报率 ${roiPct >= 0 ? '+' : ''}${roiPct.toStringAsFixed(1)}%';
    final rateSub = '$hitNotes/$totalNotes 注';

    // Group by period for bars
    final byPeriod = <String, int>{};
    for (final r in settled) {
      byPeriod[r.period] = (byPeriod[r.period] ?? 0) + r.netProfit;
    }
    final sortedPeriods = byPeriod.keys.toList()..sort();
    final recentPeriods = sortedPeriods.length > 7
        ? sortedPeriods.sublist(sortedPeriods.length - 7)
        : sortedPeriods;
    final maxAbsNet = recentPeriods.isEmpty
        ? 1
        : recentPeriods
              .map((p) => (byPeriod[p] ?? 0).abs())
              .fold<int>(1, (m, v) => v > m ? v : m);
    final maxWin = byPeriod.values
        .where((v) => v > 0)
        .fold<int>(0, (m, v) => v > m ? v : m);
    final maxLoss = byPeriod.values
        .where((v) => v < 0)
        .fold<int>(0, (m, v) => v < m ? v : m);

    final periodBars = <({String date, double factor, bool isPos, bool isHot})>[
      for (var i = 0; i < recentPeriods.length; i++)
        (
          date: recentPeriods[i].length > 4
              ? recentPeriods[i].substring(recentPeriods[i].length - 3)
              : recentPeriods[i],
          factor: ((byPeriod[recentPeriods[i]] ?? 0).abs() / maxAbsNet).clamp(
            0.08,
            1.0,
          ),
          isPos: (byPeriod[recentPeriods[i]] ?? 0) >= 0,
          isHot: i == recentPeriods.length - 1,
        ),
    ];

    // Play distribution across all records
    final totalAllStake = all.fold<int>(0, (s, r) => s + r.totalAmount);
    final byPlay = <String, int>{};
    for (final r in all) {
      byPlay[r.playType] = (byPlay[r.playType] ?? 0) + r.totalAmount;
    }
    final playEntries = byPlay.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Frequent hit numbers
    final hitCounts = <String, int>{};
    final hitProfits = <String, int>{};
    for (final r in settled.where((r) => r.status == 'won')) {
      for (final numStr in r.hitNumbers) {
        if (int.tryParse(numStr) != null) {
          final norm = numStr.padLeft(2, '0');
          hitCounts[norm] = (hitCounts[norm] ?? 0) + 1;
          hitProfits[norm] =
              (hitProfits[norm] ?? 0) + (r.stakePerNote * r.odds).round();
        }
      }
    }
    final frequentHits =
        hitCounts.keys
            .map(
              (n) => (
                numStr: n,
                boseLabel: switch (Lottery2026Lookup.boseForNumber(n)) {
                  'red' => '红波',
                  'blue' => '蓝波',
                  _ => '绿波',
                },
                count: hitCounts[n] ?? 0,
                profit: hitProfits[n] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: '返回',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '记录统计',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
                  children: [
                    // 时间范围 (record-stats.html lines 36-40)
                    GlassSegmentedControl<String>(
                      items: const ['7', '30', '90'],
                      selected: _window,
                      labelBuilder: (w) => '近 $w 天',
                      onChanged: (v) => setState(() => _window = v),
                    ),
                    const SizedBox(height: 12),

                    // KPI 总览 2x2 (record-stats.html lines 43-76)
                    Row(
                      children: [
                        Expanded(
                          child: _StatKpiCard(
                            icon: Icons.account_balance_wallet_outlined,
                            label: '总投入',
                            value: investStr,
                            delta: ordersSub,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatKpiCard(
                            icon: Icons.payments_outlined,
                            label: '总派彩',
                            value: payoutStr,
                            delta: payoutSub,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatKpiCard(
                            icon: Icons.trending_up_rounded,
                            label: '净盈亏',
                            value: netStr,
                            valueColor: netProfit >= 0
                                ? DuiliaoColors.hit
                                : DuiliaoColors.miss,
                            delta: netSub,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatKpiCard(
                            icon: Icons.track_changes_rounded,
                            label: '中单率',
                            value: winRateStr,
                            valueColor: Theme.of(context).colorScheme.primary,
                            delta: rateSub,
                          ),
                        ),
                      ],
                    ),

                    // 每日盈亏 (双向柱状图) (record-stats.html lines 79-132)
                    DesignSectionHeader(
                      title: '每日盈亏',
                      trailing: Text.rich(
                        TextSpan(
                          style: context.texts.labelSmall?.copyWith(
                            fontSize: 11,
                          ),
                          children: [
                            const TextSpan(text: '累计净 '),
                            TextSpan(
                              text: netStr,
                              style: tabularStyle(
                                TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: netProfit >= 0
                                      ? DuiliaoColors.hit
                                      : DuiliaoColors.miss,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (periodBars.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Text(
                                '暂无已结算期次，官方开奖对奖后将自动生成盈亏柱状图',
                                style: context.texts.labelSmall,
                                textAlign: TextAlign.center,
                              ),
                            )
                          else ...[
                            SizedBox(
                              height: 132,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Row(
                                    children: [
                                      for (final bar in periodBars)
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: Column(
                                              children: [
                                                Expanded(
                                                  child: Align(
                                                    alignment:
                                                        Alignment.bottomCenter,
                                                    child: bar.isPos
                                                        ? FractionallySizedBox(
                                                            heightFactor:
                                                                bar.factor,
                                                            widthFactor: 1.0,
                                                            child: DecoratedBox(
                                                              decoration: BoxDecoration(
                                                                gradient: bar.isHot
                                                                    ? DuiliaoColors
                                                                          .auroraGradient
                                                                    : LinearGradient(
                                                                        begin: Alignment
                                                                            .topCenter,
                                                                        end: Alignment
                                                                            .bottomCenter,
                                                                        colors: [
                                                                          Theme.of(
                                                                                context,
                                                                              )
                                                                              .colorScheme
                                                                              .primary
                                                                              .withValues(
                                                                                alpha: 0.85,
                                                                              ),
                                                                          Theme.of(
                                                                                context,
                                                                              )
                                                                              .colorScheme
                                                                              .primary
                                                                              .withValues(
                                                                                alpha: 0.35,
                                                                              ),
                                                                        ],
                                                                      ),
                                                                borderRadius:
                                                                    const BorderRadius.vertical(
                                                                      top: Radius.circular(
                                                                        7,
                                                                      ),
                                                                      bottom:
                                                                          Radius.circular(
                                                                            3,
                                                                          ),
                                                                    ),
                                                              ),
                                                            ),
                                                          )
                                                        : const SizedBox.shrink(),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Align(
                                                    alignment:
                                                        Alignment.topCenter,
                                                    child: !bar.isPos
                                                        ? FractionallySizedBox(
                                                            heightFactor:
                                                                bar.factor,
                                                            widthFactor: 1.0,
                                                            child: DecoratedBox(
                                                              decoration: BoxDecoration(
                                                                gradient:
                                                                    LinearGradient(
                                                                      begin: Alignment
                                                                          .topCenter,
                                                                      end: Alignment
                                                                          .bottomCenter,
                                                                      colors: [
                                                                        DuiliaoColors
                                                                            .miss
                                                                            .withValues(
                                                                              alpha:
                                                                                  0.70,
                                                                            ),
                                                                        DuiliaoColors
                                                                            .miss
                                                                            .withValues(
                                                                              alpha:
                                                                                  0.40,
                                                                            ),
                                                                      ],
                                                                    ),
                                                                borderRadius:
                                                                    const BorderRadius.vertical(
                                                                      top: Radius.circular(
                                                                        3,
                                                                      ),
                                                                      bottom:
                                                                          Radius.circular(
                                                                            7,
                                                                          ),
                                                                    ),
                                                              ),
                                                            ),
                                                          )
                                                        : const SizedBox.shrink(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Container(
                                    height: 1,
                                    color: Colors.white.withValues(alpha: 0.16),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                for (final bar in periodBars)
                                  Expanded(
                                    child: Text(
                                      bar.date,
                                      textAlign: TextAlign.center,
                                      style: tabularStyle(
                                        TextStyle(
                                          fontSize: 10,
                                          fontWeight: bar.isHot
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: bar.isHot
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text.rich(
                                TextSpan(
                                  style: context.texts.labelSmall?.copyWith(
                                    fontSize: 11,
                                  ),
                                  children: [
                                    const TextSpan(text: '最大单期盈利 '),
                                    TextSpan(
                                      text: '+¥$maxWin',
                                      style: tabularStyle(
                                        const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: DuiliaoColors.hit,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text.rich(
                                TextSpan(
                                  style: context.texts.labelSmall?.copyWith(
                                    fontSize: 11,
                                  ),
                                  children: [
                                    const TextSpan(text: '最大单期亏损 '),
                                    TextSpan(
                                      text: '−¥${maxLoss.abs()}',
                                      style: tabularStyle(
                                        const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: DuiliaoColors.miss,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 玩法分布 (record-stats.html lines 135-149)
                    const DesignSectionHeader(title: '玩法分布'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: playEntries.isEmpty
                          ? Text(
                              '暂无玩法投入数据',
                              style: context.texts.labelSmall,
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < playEntries.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        playEntries[i].key,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text.rich(
                                        TextSpan(
                                          style: context.texts.labelSmall
                                              ?.copyWith(fontSize: 12),
                                          children: [
                                            TextSpan(
                                              text: '¥${playEntries[i].value}',
                                              style: tabularStyle(
                                                TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.onSurface,
                                                ),
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  ' · ${totalAllStake > 0 ? (playEntries[i].value / totalAllStake * 100).round() : 0}%',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  GlassLinearProgress(
                                    value: totalAllStake > 0
                                        ? (playEntries[i].value / totalAllStake)
                                              .clamp(0.0, 1.0)
                                        : 0.0,
                                    color: i.isOdd ? DuiliaoColors.hit : null,
                                  ),
                                ],
                              ],
                            ),
                    ),

                    // 常中号码 (record-stats.html lines 152-182)
                    const DesignSectionHeader(title: '常中号码'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: frequentHits.isEmpty
                          ? [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  '暂无已命中号码统计',
                                  style: context.texts.labelSmall,
                                ),
                              ),
                            ]
                          : [
                              for (final item in frequentHits.take(5))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 11,
                                  ),
                                  child: Row(
                                    children: [
                                      NumberBall(
                                        number: item.numStr,
                                        bose: Lottery2026Lookup.boseForNumber(
                                          item.numStr,
                                        ),
                                        size: 28,
                                        showColorName: false,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${item.numStr} 码 · ${item.boseLabel}',
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text.rich(
                                              TextSpan(
                                                style: context.texts.labelSmall
                                                    ?.copyWith(fontSize: 11.5),
                                                children: [
                                                  TextSpan(
                                                    text:
                                                        '累计中 ${item.count} 次 · 贡献 ',
                                                  ),
                                                  TextSpan(
                                                    text: '+¥${item.profit}',
                                                    style: tabularStyle(
                                                      const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            DuiliaoColors.hit,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 22,
                                        height: 22,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: DuiliaoColors.hit.withValues(
                                            alpha: 0.16,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: DuiliaoColors.hit.withValues(
                                              alpha: 0.38,
                                            ),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          size: 13,
                                          color: DuiliaoColors.hit,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                    ),

                    // 月度小结 (record-stats.html lines 185-190)
                    const DesignSectionHeader(title: '月度小结'),
                    GlassSubtleBox(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Text.rich(
                        TextSpan(
                          style: context.texts.labelSmall?.copyWith(
                            fontSize: 12,
                            height: 1.8,
                          ),
                          children: [
                            TextSpan(
                              text:
                                  '累计共 ${all.length} 单（已结 ${settled.length} 单、$totalNotes 注）；已结投入 $investStr，派彩 $payoutStr，净盈亏 ',
                            ),
                            TextSpan(
                              text: netStr,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: netProfit >= 0
                                    ? DuiliaoColors.hit
                                    : DuiliaoColors.miss,
                              ),
                            ),
                            const TextSpan(text: '。理性记录，量力而行。'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatKpiCard extends StatelessWidget {
  const _StatKpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.delta,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final String delta;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(label, style: context.texts.labelSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: tabularStyle(
              TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(delta, style: context.texts.labelSmall),
        ],
      ),
    );
  }
}
