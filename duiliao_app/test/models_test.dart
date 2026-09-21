/// Domain model tests against **real** backend responses.
///
/// The fixtures in `assets/fixtures/api/` were captured from a live FastAPI app
/// by `backend/scripts/dump_api_fixtures.py`, so these assert the hand-written
/// port against payloads the server actually produces rather than against
/// payloads written to match the port.
///
/// Regenerate with:
///   cd backend && .venv/bin/python scripts/dump_api_fixtures.py \
///       ../duiliao_app/assets/fixtures/api
library;

import 'dart:convert';
import 'dart:io';

import 'package:duiliao_app/domain/json.dart';
import 'package:duiliao_app/domain/lottery.dart';
import 'package:duiliao_app/domain/models/app_event.dart';
import 'package:duiliao_app/domain/models/collect_job.dart';
import 'package:duiliao_app/domain/models/consensus.dart';
import 'package:duiliao_app/domain/models/draw.dart';
import 'package:duiliao_app/domain/models/prediction.dart';
import 'package:duiliao_app/domain/models/ratings.dart';
import 'package:duiliao_app/domain/models/source.dart';
import 'package:duiliao_app/domain/models/user.dart';
import 'package:duiliao_app/domain/play_type.dart';
import 'package:duiliao_app/features/numbers/numbers_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Object? _fixture(String name) {
  final file = File('assets/fixtures/api/$name.json');
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync());
}

Map<String, dynamic> _map(String name) => asMap(_fixture(name));
List<dynamic> _list(String name) => asList(_fixture(name));

void main() {
  group('coercion helpers', () {
    test('null and absent are preserved, never zeroed', () {
      // The central invariant: a null rate means "no data", which is a different
      // claim from 0% and must not be rendered as one.
      expect(asDoubleOrNull(null), isNull);
      expect(asIntOrNull(null), isNull);
      expect(asStringOrNull(null), isNull);
      expect(asBoolOrNull(null), isNull);
      expect(asMapOrNull(null), isNull);
    });

    test('numeric strings and cross-type numbers are accepted', () {
      expect(asIntOrNull('42'), 42);
      expect(asIntOrNull(42.9), 42);
      expect(asDoubleOrNull('0.35'), 0.35);
      expect(asDoubleOrNull(1), 1.0);
      expect(asIntOrNull('not a number'), isNull);
    });

    test('0/1 ints decode as booleans, matching official_hit', () {
      expect(asBoolOrNull(1), isTrue);
      expect(asBoolOrNull(0), isFalse);
      expect(asBoolOrNull('true'), isTrue);
      expect(asBoolOrNull(''), isNull);
    });

    test('malformed list entries are skipped, not fatal', () {
      final parsed = asModelList<PredAtom>(
        [
          {'kind': 'xiao', 'value': '猪'},
          'not an object',
          null,
          {'kind': 'xiao', 'value': '兔'},
        ],
        PredAtom.fromJson,
      );
      expect(parsed, hasLength(2), reason: 'one bad row must not blank the list');
    });

    test('timestamps parse in both backend formats', () {
      expect(asDateTimeOrNull('2026-09-05 21:33:30'), isNotNull);
      expect(asDateTimeOrNull('2026-09-05T21:33:30'), isNotNull);
      expect(asDateTimeOrNull('2026-09-05T21:33:30+08:00'), isNotNull);
      expect(asDateTimeOrNull(''), isNull);
      expect(asDateTimeOrNull('rubbish'), isNull);
    });

    test('formatRate shows a dash for absent, not 0%', () {
      expect(formatRate(null), '—');
      expect(formatRate(0), '0.0%');
      expect(formatRate(0.523), '52.3%');
    });
  });

  group('lottery and period', () {
    test('all four codes parse to their Chinese labels', () {
      expect(Lottery.tryParse('hk')!.label, '香港');
      expect(Lottery.tryParse('macau')!.label, '澳门');
      expect(Lottery.tryParse('taiwan')!.label, '台湾');
      expect(Lottery.tryParse('new')!.label, '新彩');
      expect(Lottery.all, hasLength(4));
    });

    test('an unknown code is not silently mapped to macau', () {
      expect(Lottery.tryParse('atlantis'), isNull);
      expect(Lottery.labelFor('atlantis'), 'atlantis');
    });

    test('canonical periods render correctly', () {
      expect(Period.short('2026248'), '248');
      expect(Period.short('2026096'), '96');
      expect(Period.year('2026248'), 2026);
      expect(Period.display('2026248'), '2026 年 248 期');
      expect(Period.compact('2026248'), '第248期');
      expect(Period.compact(null), '—');
    });

    test('loose user input is accepted for submission', () {
      expect(Period.looksValid('248'), isTrue);
      expect(Period.looksValid('第248期'), isTrue);
      expect(Period.looksValid('26/248'), isTrue);
      expect(Period.looksValid(''), isFalse);
      expect(Period.looksValid('abc'), isFalse);
    });
  });

  group('play types', () {
    test('there are exactly 21, matching rules.py', () {
      expect(kPlayTypes, hasLength(21));
    });

    test('scope counts match rules.py: 8 / 7 / 5 / 1', () {
      final grouped = PlayTypes.grouped;
      expect(grouped[PlayScope.tema], hasLength(8));
      expect(grouped[PlayScope.sevenBalls], hasLength(7));
      expect(grouped[PlayScope.sixZheng], hasLength(5));
      expect(grouped[PlayScope.zhengAndTema], hasLength(1));
    });

    test('keys are unique', () {
      final keys = kPlayTypes.map((p) => p.key).toSet();
      expect(keys, hasLength(21));
    });

    test('the local table matches the server rule catalogue exactly', () {
      final rules = _list('rules');
      if (rules.isEmpty) {
        markTestSkipped('rules fixture missing');
        return;
      }
      final serverKeys = rules.map((r) => asMap(r)['play_type'] as String).toSet();
      final localKeys = kPlayTypes.map((p) => p.key).toSet();
      expect(
        localKeys,
        equals(serverKeys),
        reason: 'the transcribed play-type table has drifted from rules.py',
      );

      // Names must match too, or pickers and the encyclopaedia disagree.
      for (final row in rules) {
        final map = asMap(row);
        final key = map['play_type'] as String;
        expect(PlayTypes.labelFor(key), map['name'], reason: 'name mismatch for $key');
      }
    });

    test('the transcribed rule version matches the server', () {
      final rules = _list('rules');
      if (rules.isEmpty) return;
      final versions = rules.map((r) => asMap(r)['version']).toSet();
      expect(versions, hasLength(1));
      expect(versions.first, kTranscribedRuleVersion);
    });
  });

  group('RuleRow', () {
    test('parses the real catalogue', () {
      final rows = _list('rules').map((r) => RuleRow.fromJson(asMap(r))).toList();
      expect(rows, hasLength(21));
      expect(rows.every((r) => r.playType.isNotEmpty), isTrue);
      expect(rows.every((r) => r.name.isNotEmpty), isTrue);
      expect(rows.every((r) => r.condition.isNotEmpty), isTrue);
      expect(rows.every((r) => r.scope.isNotEmpty), isTrue);
      // Exactly two plays are configurable any/all.
      final configurable = rows.where((r) => r.modes.contains('任一或全部')).toList();
      expect(configurable.map((r) => r.playType).toSet(), {'zhengma_n', 'tema_twoface'});
    });
  });

  group('DrawRow', () {
    test('parses the real draw list', () {
      final result = DrawListResult.fromJson(_map('draws'));
      expect(result.ok, isTrue);
      expect(result.items, isNotEmpty);

      final draw = result.items.first;
      expect(draw.lottery, 'macau');
      expect(draw.period, hasLength(7));
      expect(draw.balls, hasLength(6), reason: 'z1..z6 are the six 正码');
      expect(draw.tema, isNotEmpty, reason: '特码 is separate from balls');
      expect(draw.allNumbers, hasLength(7));
    });

    test('per-ball attributes carry the full fixed attribute set', () {
      final result = DrawListResult.fromJson(_map('draws'));
      final enriched = result.items.where((d) => d.isEnriched).toList();
      if (enriched.isEmpty) {
        markTestSkipped('no enriched draw in the fixture');
        return;
      }
      final attr = enriched.first.ballsDetail.first;
      for (final value in [
        attr.num,
        attr.xiao,
        attr.jiaye,
        attr.bose,
        attr.size,
        attr.odd,
        attr.head,
        attr.wei,
        attr.sum,
      ]) {
        expect(value, isNotEmpty);
      }
      expect(['红', '蓝', '绿'], contains(attr.bose));
      expect(['大', '小'], contains(attr.size));
      expect(['单', '双'], contains(attr.odd));
    });

    test('the semantic label names the colour, not just the fill', () {
      final result = DrawListResult.fromJson(_map('draws'));
      final enriched = result.items.firstWhere(
        (d) => d.isEnriched,
        orElse: () => result.items.first,
      );
      if (!enriched.isEnriched) return;
      final label = enriched.ballsDetail.first.semanticLabel;
      expect(label, contains('号码'));
      expect(label, contains('生肖'));
      // Accessibility: colour must also be conveyed as text.
      expect(RegExp('[红蓝绿]').hasMatch(label), isTrue);
    });

    test('summary parses with its derived fields', () {
      final result = DrawListResult.fromJson(_map('draws'));
      final withSummary = result.items.where((d) => d.summary != null).toList();
      if (withSummary.isEmpty) {
        markTestSkipped('no summary in the fixture');
        return;
      }
      final summary = withSummary.first.summary!;
      expect(summary.sum7, greaterThan(0));
      expect(['大', '小'], contains(summary.sum7Size));
      expect(['单', '双'], contains(summary.sum7Odd));
      expect(summary.temaXiao, isNotEmpty);
      expect(summary.temaHalfwave, isNotEmpty);
    });

    test('a row with no summary or details degrades instead of throwing', () {
      final draw = DrawRow.fromJson({
        'lottery': 'macau',
        'period': '2026248',
        'period_raw': '248',
        'balls': ['01', '02', '03', '04', '05', '06'],
        'tema': '07',
        'source': 'test',
      });
      expect(draw.summary, isNull);
      expect(draw.isEnriched, isFalse);
      expect(draw.temaDetail, isNull);
      expect(draw.drawDate, isNull);
      expect(draw.tag, isEmpty);
    });

    test('an entirely empty object does not throw', () {
      expect(() => DrawRow.fromJson(const {}), returnsNormally);
      expect(DrawRow.fromJson(const {}).balls, isEmpty);
    });
  });

  group('NumberAttr / NumbersResult', () {
    test('the real table has all 49 numbers', () {
      final result = NumbersResult.fromJson(_map('numbers'));
      expect(result.ok, isTrue);
      expect(result.items, hasLength(49));
      expect(result.items.first.num, '01');
      expect(result.items.last.num, '49');
    });

    test('wuxing availability is reported explicitly', () {
      final result = NumbersResult.fromJson(_map('numbers'));
      // Either a table exists and values are populated, or the flag says it does
      // not — the UI must never render a blank without explanation.
      if (result.wuxingAvailable) {
        expect(result.items.any((n) => n.wuxing != null), isTrue);
      } else {
        expect(result.items.every((n) => n.wuxingMissing), isTrue);
      }
      expect(result.wuxingYears, isNotNull);
    });

    test('a null wuxing is preserved as missing', () {
      final attr = NumberAttr.fromJson({
        'num': '01',
        'xiao': '猪',
        'jiaye': '家',
        'bose': '红',
        'size': '小',
        'odd': '单',
        'head': '0',
        'wei': '1',
        'sum': '单',
        'wuxing': null,
      });
      expect(attr.wuxing, isNull);
      expect(attr.wuxingMissing, isTrue);
    });

    test('zodiac classification fields parse when present', () {
      final result = NumbersResult.fromJson(_map('numbers'));
      final withMeta = result.items.where((n) => n.role != null).toList();
      if (withMeta.isEmpty) {
        markTestSkipped('no 灵码 metadata in the fixture');
        return;
      }
      final attr = withMeta.first;
      expect(attr.role, isNotNull);
      // At least some classification is populated for the reverse-lookup filters.
      expect(
        [attr.tianDi, attr.yinYang, attr.gender, attr.luck, attr.season, attr.direction]
            .any((v) => v != null),
        isTrue,
      );
    });

    test('NumberFilters matches on gender and tianDi', () {
      final result = NumbersResult.fromJson(_map('numbers'));
      const filters = NumberFilters(selections: {
        'gender': {'女肖'},
      });
      final nvItems = result.items.where(filters.matches).toList();
      expect(nvItems, isNotEmpty);
      expect(nvItems.every((n) => n.gender == '女肖'), isTrue);

      const multiFilters = NumberFilters(selections: {
        'gender': {'女肖'},
        'bose': {'红'},
      });
      final redNvItems = result.items.where(multiFilters.matches).toList();
      expect(redNvItems, isNotEmpty);
      expect(redNvItems.every((n) => n.gender == '女肖' && n.bose == '红'), isTrue);
    });
  });

  group('ConsensusResult', () {
    test('parses the real consensus payload', () {
      final result = ConsensusResult.fromJson(_map('consensus'));
      expect(result.ok, isTrue);
      expect(result.period, isNotEmpty);
      for (final group in result.groups) {
        expect(group.playType, isNotEmpty);
        expect(group.leaderVotes, greaterThanOrEqualTo(0));
        expect(group.tally, isNotNull);
      }
    });

    test('groups sort by leader votes descending', () {
      // Synthetic input so the assertion holds regardless of how rich the
      // captured fixture happens to be.
      final synthetic = ConsensusResult.fromJson({
        'ok': true,
        'lottery': 'macau',
        'period': '2026248',
        'groups': [
          {'play_type': 'a', 'n_sources': 1, 'n_votes': 2, 'leader_votes': 2, 'tally': []},
          {'play_type': 'b', 'n_sources': 5, 'n_votes': 9, 'leader_votes': 7, 'tally': []},
          {'play_type': 'c', 'n_sources': 3, 'n_votes': 5, 'leader_votes': 4, 'tally': []},
        ],
      });
      expect(
        synthetic.sortedGroups.map((g) => g.playType).toList(),
        ['b', 'c', 'a'],
      );

      // And the invariant holds on the real payload too.
      final real = ConsensusResult.fromJson(_map('consensus'));
      final sorted = real.sortedGroups;
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i - 1].leaderVotes, greaterThanOrEqualTo(sorted[i].leaderVotes));
      }
    });

    test('tally sorts by votes descending', () {
      final result = ConsensusResult.fromJson(_map('consensus'));
      for (final group in result.groups) {
        final sorted = group.sortedTally;
        for (var i = 1; i < sorted.length; i++) {
          expect(sorted[i - 1].votes, greaterThanOrEqualTo(sorted[i].votes));
        }
      }
    });

    test('an empty groups array yields an empty board, not a crash', () {
      final result = ConsensusResult.fromJson({
        'ok': true,
        'lottery': 'macau',
        'period': '2026999',
        'groups': [],
      });
      expect(result.groups, isEmpty);
      expect(result.hasAtomTallies, isFalse);
      expect(result.isDrawn, isFalse);
    });

    test('absent atom_tallies hides the heat section', () {
      final result = ConsensusResult.fromJson({
        'ok': true,
        'lottery': 'macau',
        'period': '2026248',
        'groups': [],
      });
      expect(result.temaTallies, isEmpty);
      expect(result.texiaoTallies, isEmpty);
      expect(result.hasAtomTallies, isFalse);
    });

    test('a null leaderHit means not yet drawn, not a miss', () {
      final group = ConsensusGroup.fromJson({
        'play_type': 'pingte_xiao',
        'n_sources': 3,
        'n_votes': 5,
        'leader': [{'kind': 'xiao', 'value': '猪'}],
        'leader_votes': 3,
        'leader_hit': null,
        'tally': [],
      });
      expect(group.leaderHit, isNull);
      expect(group.leaderShare, closeTo(0.6, 0.001));
    });

    test('leaderShare is null rather than NaN with no votes', () {
      final group = ConsensusGroup.fromJson({
        'play_type': 'texiao',
        'n_sources': 0,
        'n_votes': 0,
        'leader_votes': 0,
        'tally': [],
      });
      expect(group.leaderShare, isNull);
    });

    test('atom heat bars are clamped to 0..1', () {
      final item = AtomTallyItem.fromJson({
        'value': '08',
        'kind': 'num',
        'votes': 9,
        'percentage': 145.0,
        'sources': ['a'],
      });
      expect(item.barFraction, 1.0);
    });
  });

  group('PeriodComparisonResult', () {
    test('parses the real comparison payload', () {
      final result = PeriodComparisonResult.fromJson(_map('comparison'));
      expect(result.ok, isTrue);
      expect(result.period, isNotEmpty);
      expect(result.summary.total, greaterThanOrEqualTo(0));
      for (final item in result.items) {
        expect(item.sourceId, isNotEmpty);
        expect(item.playType, isNotEmpty);
      }
    });

    test('official_hit is an int on the wire, exposed as a bool helper', () {
      final item = ComparisonItem.fromJson({
        'id': 1,
        'source_id': 's',
        'source_name': 'S',
        'lottery': 'macau',
        'play_type': 'pingte_xiao',
        'hit_mode': 'any',
        'period': '2026248',
        'period_raw': '248',
        'group_key': '',
        'preds': [],
        'claimed_status': '准',
        'raw_text': 'x',
        'official_hit': 1,
        'claimed_hit': 0,
        'status': 'hit',
      });
      expect(item.officialHit, 1);
      expect(item.isHit, isTrue);
      expect(item.isJudged, isTrue);
    });

    test('a null hit_detail reads as not yet judged', () {
      final item = ComparisonItem.fromJson({
        'id': 2,
        'source_id': 's',
        'source_name': 'S',
        'lottery': 'macau',
        'play_type': 'texiao',
        'hit_mode': 'any',
        'period': '2026249',
        'period_raw': '249',
        'group_key': '',
        'preds': [],
        'claimed_status': '',
        'raw_text': '',
        'official_hit': null,
        'hit_detail': null,
        'status': 'pending',
      });
      expect(item.isJudged, isFalse);
      expect(item.explanation, isNull);
      expect(item.ruleVersion, isNull);
      expect(item.drawSnapshot, isNull);
      expect(item.status, ComparisonStatus.pending);
    });

    test('all four statuses map, and conflict is filterable', () {
      for (final entry in {
        'hit': ComparisonStatus.hit,
        'miss': ComparisonStatus.miss,
        'pending': ComparisonStatus.pending,
        'conflict': ComparisonStatus.conflict,
      }.entries) {
        expect(ComparisonStatus.tryParse(entry.key), entry.value);
      }
      expect(ComparisonStatus.conflict.label, '冲突');

      final result = PeriodComparisonResult.fromJson(_map('comparison'));
      final conflicts = result.withStatus(ComparisonStatus.conflict);
      expect(conflicts.every((i) => i.isConflict), isTrue);
      expect(result.withStatus(null), hasLength(result.items.length));
    });

    test('evidence fields are read out of hit_detail', () {
      final item = ComparisonItem.fromJson({
        'id': 3,
        'source_id': 's',
        'source_name': 'S',
        'lottery': 'macau',
        'play_type': 'pingte_xiao',
        'hit_mode': 'any',
        'period': '2026248',
        'period_raw': '248',
        'group_key': '',
        'preds': [],
        'claimed_status': '',
        'raw_text': '',
        'official_hit': 0,
        'hit_detail': {
          'explanation': '候选生肖未出现在七球中',
          'rule': 'pingte_xiao',
          'rule_version': '2026-09-06.2',
          'scope_label': '七球（含特码）',
          'draw_snapshot': {'tema': '28'},
          'prediction_snapshot': {'preds': []},
        },
        'status': 'miss',
      });
      expect(item.explanation, '候选生肖未出现在七球中');
      expect(item.rule, 'pingte_xiao');
      expect(item.ruleVersion, '2026-09-06.2');
      expect(item.scopeLabel, '七球（含特码）');
      expect(item.drawSnapshot, isNotNull);
      expect(item.predictionSnapshot, isNotNull);
    });

    test('a null draw is normal before the result is published', () {
      final result = PeriodComparisonResult.fromJson({
        'ok': true,
        'lottery': 'macau',
        'period': '2026999',
        'draw': null,
        'items': [],
      });
      expect(result.draw, isNull);
      expect(result.summary.total, 0);
    });

    test('group suffix renders only for non-default groups', () {
      ComparisonItem build(String groupKey) => ComparisonItem.fromJson({
            'id': 1,
            'source_id': 's',
            'source_name': 'S',
            'lottery': 'macau',
            'play_type': 'x',
            'hit_mode': 'any',
            'period': '2026248',
            'period_raw': '248',
            'group_key': groupKey,
            'preds': [],
            'claimed_status': '',
            'raw_text': '',
          });
      expect(build('').groupSuffix, '');
      expect(build('default').groupSuffix, '');
      expect(build('第2组').groupSuffix, '／第2组');
    });
  });

  group('RatingRow', () {
    test('parses the real ratings board', () {
      final result = RatingsResult.fromJson(_map('ratings'));
      expect(result.ok, isTrue);
      expect(result.windows, [30, 50, 100]);
      for (final row in result.sources) {
        expect(row.sourceId, isNotEmpty);
      }
    });

    test('a null hit rate stays null instead of becoming zero', () {
      final row = RatingRow.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'n_30': 0,
        'hit_30': null,
      });
      expect(
        row.hitRate(30),
        isNull,
        reason: '0% would falsely claim the source never hits',
      );
      expect(row.sampleSize(30), 0);
    });

    test('an unrequested window reads as null, not zero', () {
      final row = RatingRow.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'n_30': 12,
        'hit_30': 0.5,
      });
      expect(row.hitRate(999), isNull);
      expect(row.sampleSize(999), isNull);
    });

    test('dynamic per-window keys are all readable', () {
      final row = RatingRow.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'n_30': 30,
        'hit_30': 0.4,
        'n_50': 50,
        'hit_50': 0.44,
        'n_100': 100,
        'hit_100': 0.41,
      });
      expect(row.hitRate(30), 0.4);
      expect(row.hitRate(50), 0.44);
      expect(row.hitRate(100), 0.41);
      expect(row.sampleSize(100), 100);
    });

    test('a small sample is flagged', () {
      final small = RatingRow.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'n_30': 3,
        'hit_30': 1.0,
      });
      expect(small.isSmallSample(30), isTrue,
          reason: '100% on three samples must not look authoritative');
      final big = RatingRow.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'n_30': 30,
        'hit_30': 0.5,
      });
      expect(big.isSmallSample(30), isFalse);
    });

    test('post-draw editing is inferred from the before/after gap', () {
      final suspicious = RatingRow.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'before_n': 20,
        'before_rate': 0.21,
        'after_n': 15,
        'after_rate': 0.52,
        'after_edits': 12,
      });
      expect(suspicious.suspectedPostDrawEditing, isTrue);
      expect(suspicious.hasPostDrawEdits, isTrue);
      expect(suspicious.hasIntegrityWarning, isTrue);

      final honest = RatingRow.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'before_n': 20,
        'before_rate': 0.42,
        'after_n': 15,
        'after_rate': 0.44,
        'after_edits': 0,
      });
      expect(honest.suspectedPostDrawEditing, isFalse);
      expect(honest.hasIntegrityWarning, isFalse);
    });

    test('a tiny before-sample does not raise a false editing alarm', () {
      final row = RatingRow.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'before_n': 2,
        'before_rate': 0.0,
        'after_n': 10,
        'after_rate': 1.0,
      });
      expect(row.suspectedPostDrawEditing, isFalse);
    });

    test('a null before_rate does not raise an alarm', () {
      final row = RatingRow.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'before_n': 0,
        'before_rate': null,
        'after_n': 10,
        'after_rate': 0.9,
      });
      expect(row.beforeRate, isNull);
      expect(row.suspectedPostDrawEditing, isFalse);
    });

    test('streaks render in Chinese and expose a miss count', () {
      expect(
        RatingRow.fromJson({'source_id': 's', 'source_name': 'S', 'current_streak': 4})
            .streakLabel,
        '连中 4',
      );
      final miss = RatingRow.fromJson(
        {'source_id': 's', 'source_name': 'S', 'current_streak': -3},
      );
      expect(miss.streakLabel, '连挂 3');
      expect(miss.missStreak, 3);
      expect(
        RatingRow.fromJson({'source_id': 's', 'source_name': 'S', 'current_streak': 0})
            .streakLabel,
        '—',
      );
    });

    test('sorting puts null hit rates last, matching the backend', () {
      final result = RatingsResult.fromJson({
        'ok': true,
        'lottery': 'macau',
        'play_type': 'pingte_xiao',
        'windows': [30],
        'periods': [],
        'sources': [
          {'source_id': 'a', 'source_name': 'A', 'hit_30': null, 'n_30': 0},
          {'source_id': 'b', 'source_name': 'B', 'hit_30': 0.5, 'n_30': 30},
          {'source_id': 'c', 'source_name': 'C', 'hit_30': 0.8, 'n_30': 30},
        ],
      });
      final sorted = result.sortedBy(30);
      expect(sorted.map((r) => r.sourceId).toList(), ['c', 'b', 'a']);
    });
  });

  group('MonitorRow', () {
    test('parses the real monitor payload', () {
      final payload = _fixture('monitor');
      final items = asModelList(asMap(payload)['items'], MonitorRow.fromJson);
      expect(items, isNotEmpty);
      for (final row in items) {
        expect(row.sourceId, isNotEmpty);
      }
    });

    test('staleness derives from lag', () {
      MonitorRow build(int? lag) => MonitorRow.fromJson({
            'source_id': 's',
            'source_name': 'S',
            'lottery': 'macau',
            'play_type': 'x',
            'enabled': true,
            'lag': lag,
          });
      expect(build(0).isStale, isFalse);
      expect(build(1).isStale, isFalse);
      expect(build(5).isStale, isTrue);
      expect(build(null).isStale, isFalse);
    });
  });

  group('CollectorSource', () {
    test('parses the real source catalogue', () {
      final sources = _list('sources').map((s) => CollectorSource.fromJson(asMap(s))).toList();
      expect(sources, isNotEmpty);
      for (final source in sources) {
        expect(source.sourceId, isNotEmpty);
        expect(source.sourceName, isNotEmpty);
        expect(source.timeoutSec, greaterThan(0));
      }
    });

    test('search matches name, id and site family', () {
      final source = CollectorSource.fromJson({
        'source_id': 'haige_pingte',
        'source_name': '海哥平特',
        'site_family': 'dingjian',
        'lottery': 'macau',
        'play_type': 'pingte_xiao',
        'hit_mode': 'any',
        'script_path': 'sources/haige_pingte.py',
        'timeout_sec': 30,
        'enabled': true,
      });
      expect(source.matches(''), isTrue);
      expect(source.matches('海哥'), isTrue);
      expect(source.matches('HAIGE'), isTrue);
      expect(source.matches('dingjian'), isTrue);
      expect(source.matches('nonsense'), isFalse);
    });

    test('a broken script is detectable', () {
      final broken = CollectorSource.fromJson({
        'source_id': 's',
        'source_name': 'S',
        'site_family': 'f',
        'lottery': 'macau',
        'play_type': 'x',
        'hit_mode': 'any',
        'script_path': 'sources/missing.py',
        'timeout_sec': 30,
        'enabled': true,
        'script_exists': false,
      });
      expect(broken.isBroken, isTrue);
    });
  });

  group('ScriptRunResult', () {
    test('parses a real single-source test run with stdout', () {
      final payload = _fixture('source_test');
      if (payload == null) {
        markTestSkipped('source_test fixture missing');
        return;
      }
      final result = ScriptRunResult.fromJson(asMap(payload));
      expect(result.lottery, 'macau');
      expect(result.elapsedMs, greaterThan(0));
      expect(result.elapsedLabel, isNotEmpty);
      // This payload is the only one carrying raw script output.
      expect(result.stdout, isNotEmpty);
    });

    test('the run_one branches that omit stdout/stderr do not crash', () {
      // bad_script_path and no_script return no stdout/stderr keys at all.
      final result = ScriptRunResult.fromJson({
        'ok': false,
        'source_id': 's',
        'lottery': 'macau',
        'exit_code': null,
        'elapsed_ms': 0,
        'item_count': 0,
        'error_code': 'no_script',
      });
      expect(result.stdout, '');
      expect(result.stderr, '');
      expect(result.errorCode, 'no_script');
      expect(result.hasDiagnostics, isFalse);
    });
  });

  group('CollectJob', () {
    test('parses a real finished job', () {
      final job = CollectJob.fromJson(_map('collect_job'));
      expect(job.id, greaterThan(0));
      expect(job.lottery, 'macau');
      expect(job.status, JobStatus.done);
      expect(job.phase, JobPhase.done);
      expect(job.sourceTotal, 2);
      expect(job.sourceOk, 2);
      expect(job.items, hasLength(2));
      expect(job.items.every((i) => i.state == SourceState.ok), isTrue);
      expect(job.progress, 1.0);
      expect(job.isTerminal, isTrue);
      expect(job.runId, isNotNull);
      expect(job.ingestStats, isNotNull);
      expect(job.judgeStats, isNotNull);
      expect(job.duration, isNotNull);
    });

    test('parses the real job history page', () {
      final page = CollectJobPage.fromJson(_map('collect_jobs'));
      expect(page.items, isNotEmpty);
      expect(page.groupedByDay, isNotEmpty);
      expect(page.worker, isNotNull);
    });

    test('all status and phase values map', () {
      for (final entry in {
        'queued': JobStatus.queued,
        'running': JobStatus.running,
        'done': JobStatus.done,
        'failed': JobStatus.failed,
        'cancelled': JobStatus.cancelled,
        'interrupted': JobStatus.interrupted,
      }.entries) {
        expect(JobStatus.tryParse(entry.key), entry.value);
      }
      expect(JobStatus.queued.isActive, isTrue);
      expect(JobStatus.running.isActive, isTrue);
      expect(JobStatus.done.isTerminal, isTrue);
      expect(JobStatus.interrupted.isTerminal, isTrue);

      for (final entry in {
        'collecting': JobPhase.collecting,
        'ingesting': JobPhase.ingesting,
        'judging': JobPhase.judging,
        'done': JobPhase.done,
      }.entries) {
        expect(JobPhase.tryParse(entry.key), entry.value);
      }
    });

    test('per-source error codes get Chinese labels', () {
      CollectJobItem build(String? code) => CollectJobItem.fromJson({
            'source_id': 's',
            'state': 'fail',
            'error_code': code,
          });
      expect(build('timeout').errorLabel, '超时');
      expect(build('no_script').errorLabel, '脚本缺失');
      expect(build('bad_json').errorLabel, '输出格式错误');
      expect(build('cancelled').errorLabel, '已取消');
      expect(build(null).errorLabel, isNull);
      // An unrecognised code still surfaces rather than vanishing.
      expect(build('brand_new_code').errorLabel, 'brand_new_code');
    });

    test('failed sources are listed for the retry action', () {
      final job = CollectJob.fromJson({
        'id': 1,
        'lottery': 'macau',
        'source_ids': ['a', 'b', 'c'],
        'status': 'done',
        'phase': 'done',
        'source_total': 3,
        'source_done': 3,
        'source_ok': 1,
        'items': [
          {'source_id': 'a', 'state': 'ok', 'item_count': 5},
          {'source_id': 'b', 'state': 'fail', 'error_code': 'timeout'},
          {'source_id': 'c', 'state': 'fail', 'error_code': 'bad_json'},
        ],
      });
      expect(job.failedSourceIds, ['b', 'c']);
      expect(job.sourceFailed, 2);
      expect(job.successRatioLabel, '1/3');
    });

    test('progress is zero rather than NaN when nothing matched', () {
      final job = CollectJob.fromJson({
        'id': 1,
        'lottery': 'macau',
        'source_total': 0,
        'source_done': 0,
        'items': [],
      });
      expect(job.progress, 0);
    });

    test('a job with every source failed still parses', () {
      final job = CollectJob.fromJson({
        'id': 9,
        'lottery': 'macau',
        'status': 'done',
        'source_total': 2,
        'source_done': 2,
        'source_ok': 0,
        'items': [
          {'source_id': 'a', 'state': 'fail', 'error_code': 'timeout'},
          {'source_id': 'b', 'state': 'fail', 'error_code': 'timeout'},
        ],
        'result': {'ok': true},
      });
      expect(job.sourceOk, 0);
      expect(job.failedSourceIds, hasLength(2));
      expect(job.ingestStats, isNull);
    });

    test('worker saturation is derived', () {
      final saturated = CollectWorkerStatus.fromJson({
        'running': true,
        'max_concurrent_jobs': 2,
        'active_jobs_count': 2,
      });
      expect(saturated.isSaturated, isTrue);
      final idle = CollectWorkerStatus.fromJson({
        'running': true,
        'max_concurrent_jobs': 2,
        'active_jobs_count': 0,
      });
      expect(idle.isSaturated, isFalse);
    });
  });

  group('HomeSnapshot', () {
    test('parses the real aggregated home payload', () {
      final home = HomeSnapshot.fromJson(_map('home'));
      expect(home.lottery, 'macau');
      expect(home.latestDraw, isNotNull);
      expect(home.latestDraw!.period, '2026248');
      expect(home.ruleVersion, kTranscribedRuleVersion);
      expect(home.worker, isNotNull);
      expect(home.hasAnyData, isTrue);
    });

    test('every block being null still parses', () {
      final home = HomeSnapshot.fromJson({
        'ok': true,
        'lottery': 'taiwan',
        'play_type': 'pingte_xiao',
        'latest_draw': null,
        'consensus': null,
        'comparison_summary': null,
        'ratings_top': null,
        'recent_jobs': null,
      });
      expect(home.latestDraw, isNull);
      expect(home.consensusGroups, isEmpty);
      expect(home.ratingsTop, isEmpty);
      expect(home.hasAnyData, isFalse);
    });
  });

  group('AppEvent', () {
    test('parses the real event feed', () {
      final page = AppEventPage.fromJson(_map('events'));
      expect(page.events, isNotEmpty);
      expect(page.nextCursor, isNotNull);
      for (final event in page.events) {
        expect(event.occurredAt, isNotEmpty);
        expect(event.title, isNotEmpty);
      }
    });

    test('events are ordered oldest first so the cursor advances safely', () {
      final page = AppEventPage.fromJson(_map('events'));
      final stamps = page.events.map((e) => e.occurredAt).toList();
      final sorted = [...stamps]..sort();
      expect(stamps, sorted);
    });

    test('the cursor equals the newest returned event', () {
      final page = AppEventPage.fromJson(_map('events'));
      if (page.events.isEmpty) return;
      expect(page.nextCursor, page.events.last.occurredAt);
    });

    test('all five event types map and produce deep links', () {
      final links = {
        AppEventType.drawPublished: {'lottery': 'macau', 'period': '2026248'},
        AppEventType.sourceHit: {'source_id': 'haige_pingte'},
        AppEventType.sourceMissStreak: {'source_id': 'haige_pingte'},
        AppEventType.consensusLeaderChanged: {'lottery': 'macau', 'period': '2026248'},
        AppEventType.collectJobFinished: {'job_id': 7},
      };
      for (final entry in links.entries) {
        final event = AppEvent.fromJson({
          'type': entry.key.code,
          'occurred_at': '2026-09-05T21:33:30',
          'lottery': 'macau',
          'period': '2026248',
          'title': 't',
          'body': 'b',
          'data': entry.value,
        });
        expect(event.type, entry.key);
        expect(event.deepLink, isNotNull, reason: 'no deep link for ${entry.key.code}');
        expect(event.channelIdIsStable, isTrue);
      }
    });

    test('dedupe keys are distinct per event', () {
      AppEvent build(String at) => AppEvent.fromJson({
            'type': 'draw_published',
            'occurred_at': at,
            'lottery': 'macau',
            'period': '2026248',
            'title': 't',
            'body': 'b',
            'data': const {},
          });
      expect(build('2026-09-05T21:33:30').dedupeKey,
          isNot(build('2026-09-05T21:34:30').dedupeKey));
      expect(build('2026-09-05T21:33:30').dedupeKey,
          build('2026-09-05T21:33:30').dedupeKey);
    });

    test('an unknown event type degrades rather than throwing', () {
      final event = AppEvent.fromJson({
        'type': 'something_new',
        'occurred_at': '2026-09-05T21:33:30',
        'title': 't',
        'body': 'b',
      });
      expect(event.type, isNull);
      expect(event.deepLink, isNull);
    });
  });

  group('VersionInfo', () {
    test('parses the real version payload', () {
      final info = VersionInfo.fromJson(_map('version'));
      expect(info.platform, 'android');
      expect(info.updateRequired, isFalse);
    });

    test('a required update is represented', () {
      final info = VersionInfo.fromJson({
        'platform': 'android',
        'current': '1.0.0',
        'latest': '2.4.0',
        'min_supported': '2.0.0',
        'download_url': 'https://example.test/app.apk',
        'update_available': true,
        'update_required': true,
      });
      expect(info.updateRequired, isTrue);
      expect(info.downloadUrl, isNotNull);
    });
  });

  group('Subscription', () {
    test('parses the real payload with defaults applied', () {
      final sub = Subscription.fromJson(_map('subscriptions'));
      expect(sub.isEnabled('draw_published'), isTrue);
      expect(sub.missStreakThreshold, 3);
    });

    test('toggling a rule and a source is immutable', () {
      const sub = Subscription.empty;
      final withRule = sub.withRule(NotifyRule.sourceHit, true);
      expect(withRule.isEnabled(NotifyRule.sourceHit), isTrue);
      expect(sub.notifyRules, isEmpty, reason: 'the original must be unchanged');

      final followed = sub.withSource('haige_pingte', true);
      expect(followed.sourceIds, ['haige_pingte']);
      expect(followed.withSource('haige_pingte', false).sourceIds, isEmpty);
      // Following twice must not duplicate.
      expect(followed.withSource('haige_pingte', true).sourceIds, hasLength(1));
    });

    test('the five notification toggles are declared', () {
      expect(NotifyRule.toggles, hasLength(5));
      expect(NotifyRule.toggles.keys, contains(NotifyRule.collectJobFinished));
    });
  });

  group('AppUser and roles', () {
    test('parses the real /users/me payload', () {
      final payload = _fixture('me');
      if (payload == null) {
        markTestSkipped('me fixture missing');
        return;
      }
      final user = AppUser.fromJson(asMap(payload));
      expect(user.id, isNotEmpty);
      expect(user.role, UserRole.staff);
      expect(user.canOperate, isTrue);
      expect(user.name, isNotEmpty);
      expect(user.initial, hasLength(1));
    });

    test('only staff and admin may operate', () {
      expect(UserRole.user.canOperate, isFalse);
      expect(UserRole.staff.canOperate, isTrue);
      expect(UserRole.admin.canOperate, isTrue);
    });

    test('an unknown role does not accidentally grant access', () {
      final user = AppUser.fromJson({'id': 'x', 'role': 'superuser'});
      expect(user.role, isNull);
      expect(user.canOperate, isFalse);
    });

    test('display name falls back through the identity fields', () {
      expect(AppUser.fromJson({'id': 'x', 'display_name': 'D'}).name, 'D');
      expect(AppUser.fromJson({'id': 'x', 'username': 'u'}).name, 'u');
      expect(AppUser.fromJson({'id': 'x', 'phone': '139'}).name, '139');
      expect(AppUser.fromJson({'id': 'x'}).name, 'x');
    });

    test('tokens parse and validate', () {
      final tokens = AuthTokens.fromJson({
        'access_token': 'a',
        'refresh_token': 'r',
        'expires_in': 900,
      });
      expect(tokens.isValid, isTrue);
      expect(
        AuthTokens.fromJson({'access_token': '', 'refresh_token': ''}).isValid,
        isFalse,
      );
    });
  });

  group('DeviceSession', () {
    test('the server current flag is not used to identify this device', () {
      final session = DeviceSession.fromJson({
        'id': 'sess1',
        'device_name': 'Pixel 8',
        'platform': 'android',
        'app_version': '1.0.0',
        'current': true,
      });
      // `current` means "not expired" server-side, so it cannot mark this device.
      expect(session.current, isTrue);
      expect(session.isThisDevice(thisDeviceName: 'Pixel 8', thisAppVersion: '1.0.0'),
          isTrue);
      expect(session.isThisDevice(thisDeviceName: 'iPhone 15'), isFalse);
      expect(session.isThisDevice(), isFalse);
    });

    test('platform labels are localised', () {
      DeviceSession build(String? platform) =>
          DeviceSession.fromJson({'id': 's', 'platform': platform, 'current': true});
      expect(build('android').platformLabel, 'Android');
      expect(build('ios').platformLabel, 'iOS');
      expect(build('web').platformLabel, '网页后台');
      expect(build(null).platformLabel, '未知设备');
    });
  });

  group('schedules', () {
    test('parses the real schedules payload', () {
      final response = SchedulesResponse.fromJson(_map('schedules'));
      expect(response.scheduler, isNotNull);
    });

    test('cron and time-window modes render differently', () {
      final cron = CollectionSchedule.fromJson({
        'id': 1,
        'name': 'nightly',
        'lottery': 'macau',
        'cron': '30 20 * * *',
        'interval_minutes': 0,
        'enabled': true,
      });
      expect(cron.isTimeWindow, isFalse);
      expect(cron.scheduleLabel, 'cron 30 20 * * *');

      final window = CollectionSchedule.fromJson({
        'id': 2,
        'name': 'window',
        'lottery': 'macau',
        'interval_minutes': 15,
        'enabled': true,
      });
      expect(window.isTimeWindow, isTrue);
      expect(window.scheduleLabel, '每 15 分钟');
    });

    test('a disabled schedule hides its next run time', () {
      final disabled = CollectionSchedule.fromJson({
        'id': 3,
        'name': 'off',
        'lottery': 'macau',
        'enabled': false,
        'next_run_at': '2026-09-06 20:30:00',
      });
      expect(
        disabled.displayNextRun,
        isNull,
        reason: 'showing a next run for a disabled task would be misleading',
      );
    });

    test('a failed last run is detectable and concurrency comes from spec', () {
      final failed = CollectionSchedule.fromJson({
        'id': 4,
        'name': 'x',
        'lottery': 'macau',
        'enabled': true,
        'last_status': 'error',
        'spec': {'concurrency': 16},
      });
      expect(failed.lastRunFailed, isTrue);
      expect(failed.concurrency, 16);
      // Default when spec is absent.
      expect(
        CollectionSchedule.fromJson({'id': 5, 'name': 'y', 'lottery': 'macau'})
            .concurrency,
        8,
      );
    });

    test('a null source_ids means all enabled sources', () {
      final all = CollectionSchedule.fromJson({
        'id': 6,
        'name': 'all',
        'lottery': 'macau',
        'source_ids': null,
      });
      expect(all.sourceIds, isNull);
      expect(all.sourceCount, isNull);
    });
  });

  group('predictions', () {
    test('parses the real predictions payload', () {
      final payload = _fixture('predictions');
      final items = payload is List
          ? asModelList(payload, PredictionRow.fromJson)
          : asModelList(asMap(payload)['items'], PredictionRow.fromJson);
      for (final row in items) {
        expect(row.sourceId, isNotEmpty);
      }
    });

    test('atoms compare by kind and value, and format compactly', () {
      const a = PredAtom(kind: 'xiao', value: '猪');
      const b = PredAtom(kind: 'xiao', value: '猪', text: '猪猪猪');
      expect(a, b, reason: 'display text must not affect identity');
      expect(
        formatAtoms(const [
          PredAtom(kind: 'xiao', value: '猪'),
          PredAtom(kind: 'xiao', value: '兔'),
        ]),
        '猪 兔',
      );
    });

    test('atom kinds have Chinese labels', () {
      expect(PlayTypes.kindLabel('num'), '号码');
      expect(PlayTypes.kindLabel('xiao'), '生肖');
      expect(PlayTypes.kindLabel('bose'), '波色');
      expect(PlayTypes.kindLabel('mystery'), 'mystery');
    });
  });

  group('AI models', () {
    test('parses the real prompt list', () {
      final prompts = _list('ai_prompts').map((p) => AiPrompt.fromJson(asMap(p))).toList();
      expect(prompts, isNotEmpty);
      for (final prompt in prompts) {
        expect(prompt.id, isNotEmpty);
        expect(prompt.displayName, isNotEmpty);
      }
    });

    test('a report exposes its model attribution', () {
      final report = AiReport.fromJson({
        'lottery': 'macau',
        'period': '2026248',
        'prompt_id': 'macau_analyst_expert',
        'content': '# 分析\n内容',
        'provider': 'openai',
        'model': 'deepseek-chat',
        'generated_at': '2026-09-05 21:40:00',
      });
      expect(report.modelLabel, 'openai · deepseek-chat');
      expect(report.content, contains('分析'));
      expect(
        AiReport.fromJson({'lottery': 'macau', 'period': '1', 'prompt_id': 'p', 'content': ''})
            .modelLabel,
        '未知模型',
      );
    });
  });
}

/// Small helper used by the deep-link test to assert channels are non-empty.
extension on AppEvent {
  bool get channelIdIsStable => (type?.channelId ?? '').startsWith('duiliao_');
}
