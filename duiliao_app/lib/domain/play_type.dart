/// The 21 play types, mirroring `backend/collector/rules.py::RULES`.
///
/// Kept as a local table so pickers and labels work offline and before
/// `/collector/rules` has loaded. `rules.py` is still the authority: the rules
/// encyclopaedia renders the server's response, and [ruleVersion] here is only
/// the version this table was transcribed from. A mismatch against the server's
/// `rule_version` is surfaced in the profile screen rather than hidden.
library;

/// The `rules.py` VERSION this table matches.
const String kTranscribedRuleVersion = '2026-09-06.2';

/// Scope groupings, in the insertion order `rules.py` uses.
enum PlayScope {
  tema('特码'),
  sevenBalls('七球（含特码）'),
  sixZheng('六个正码'),
  zhengAndTema('正码与特码');

  const PlayScope(this.label);
  final String label;

  static PlayScope? tryParse(String? label) {
    for (final scope in values) {
      if (scope.label == label) return scope;
    }
    return null;
  }
}

class PlayType {
  const PlayType({
    required this.key,
    required this.name,
    required this.scope,
    required this.allowedKinds,
  });

  /// Wire value, e.g. `pingte_xiao`.
  final String key;

  /// Chinese name, e.g. `平特肖`.
  final String name;

  final PlayScope scope;

  /// Atom kinds this play accepts, from the 4th element of the `RULES` tuple.
  final List<String> allowedKinds;

  @override
  String toString() => '$name ($key)';
}

/// All 21 play types in `rules.py` order.
const List<PlayType> kPlayTypes = [
  // 特码 (8)
  PlayType(key: 'tema_n', name: '特码', scope: PlayScope.tema, allowedKinds: ['num']),
  PlayType(key: 'texiao', name: '特肖', scope: PlayScope.tema, allowedKinds: ['xiao']),
  PlayType(key: 'tema_wei_n', name: '特尾', scope: PlayScope.tema, allowedKinds: ['wei']),
  PlayType(key: 'tema_head_n', name: '特头', scope: PlayScope.tema, allowedKinds: ['head']),
  PlayType(key: 'tema_bose', name: '特波', scope: PlayScope.tema, allowedKinds: ['bose']),
  PlayType(
    key: 'tema_twoface',
    name: '两面',
    scope: PlayScope.tema,
    allowedKinds: ['size', 'odd', 'xiao'],
  ),
  PlayType(key: 'tema_halfwave', name: '半波', scope: PlayScope.tema, allowedKinds: ['bose']),
  PlayType(key: 'hexiao', name: '合肖', scope: PlayScope.tema, allowedKinds: ['xiao']),

  // 七球（含特码）(7)
  PlayType(
    key: 'pingte_xiao',
    name: '平特肖',
    scope: PlayScope.sevenBalls,
    allowedKinds: ['xiao'],
  ),
  PlayType(key: 'pingte_wei', name: '平特尾', scope: PlayScope.sevenBalls, allowedKinds: ['wei']),
  PlayType(key: 'lianxiao_n', name: '连肖', scope: PlayScope.sevenBalls, allowedKinds: ['xiao']),
  PlayType(key: 'lianwei_n', name: '连尾', scope: PlayScope.sevenBalls, allowedKinds: ['wei']),
  PlayType(key: 'buzhong_num', name: '不中码', scope: PlayScope.sevenBalls, allowedKinds: ['num']),
  PlayType(key: 'buzhong_xiao', name: '杀肖', scope: PlayScope.sevenBalls, allowedKinds: ['xiao']),
  PlayType(key: 'buzhong_wei', name: '杀尾', scope: PlayScope.sevenBalls, allowedKinds: ['wei']),

  // 六个正码 (5)
  PlayType(key: 'zhengma_n', name: '正码', scope: PlayScope.sixZheng, allowedKinds: ['num']),
  PlayType(key: 'zhengxiao', name: '正肖', scope: PlayScope.sixZheng, allowedKinds: ['xiao']),
  PlayType(key: 'lianma_2all', name: '二中二', scope: PlayScope.sixZheng, allowedKinds: ['num']),
  PlayType(key: 'lianma_3all', name: '三中三', scope: PlayScope.sixZheng, allowedKinds: ['num']),
  PlayType(key: 'lianma_3z2', name: '三中二', scope: PlayScope.sixZheng, allowedKinds: ['num']),

  // 正码与特码 (1)
  PlayType(
    key: 'lianma_2zt',
    name: '二中特',
    scope: PlayScope.zhengAndTema,
    allowedKinds: ['num'],
  ),
];

final Map<String, PlayType> _byKey = {
  for (final play in kPlayTypes) play.key: play,
};

abstract final class PlayTypes {
  static PlayType? tryParse(String? key) => key == null ? null : _byKey[key];

  /// Chinese name for a play key, falling back to the key so an unrecognised
  /// play added server-side is still identifiable.
  static String labelFor(String? key) => _byKey[key]?.name ?? (key ?? '—');

  /// Play types grouped by scope, in `rules.py` order.
  static Map<PlayScope, List<PlayType>> get grouped {
    final out = <PlayScope, List<PlayType>>{};
    for (final play in kPlayTypes) {
      out.putIfAbsent(play.scope, () => []).add(play);
    }
    return out;
  }

  /// Label for a prediction atom kind.
  static String kindLabel(String? kind) {
    switch (kind) {
      case 'num':
        return '号码';
      case 'xiao':
        return '生肖';
      case 'wei':
        return '尾数';
      case 'head':
        return '头数';
      case 'bose':
        return '波色';
      case 'size':
        return '大小';
      case 'odd':
        return '单双';
      default:
        return kind ?? '—';
    }
  }
}
