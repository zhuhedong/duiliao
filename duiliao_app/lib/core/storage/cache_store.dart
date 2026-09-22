/// On-disk response cache with per-entry TTLs.
///
/// Two jobs:
///
/// 1. **Offline reading.** Draws, number attributes and play rules are stable
///    reference data an operator may need with no signal, so they are persisted
///    and served stale with a visible banner rather than showing an error.
/// 2. **Avoiding redundant round-trips.** Every request costs a handshake-backed
///    encrypted exchange, so short-lived caching of consensus and ratings keeps
///    tab switching responsive.
///
/// Stale data is always *labelled* stale — [CachedValue.isStale] drives an
/// "offline data, updated at HH:mm" banner. Silently showing yesterday's ratings
/// as current would be worse than showing an error.
library;

import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// TTLs by data class, reflecting how fast each actually changes.
abstract final class CacheTtl {
  /// Play rules change only with a `rules.py` release.
  static const Duration rules = Duration(days: 7);

  /// Number attributes change only at the lunar new year.
  static const Duration numbers = Duration(days: 7);

  /// The source catalogue changes when an operator edits it in the console.
  static const Duration sources = Duration(hours: 12);

  /// Draw history is append-only; existing rows never change.
  static const Duration draws = Duration(minutes: 30);

  /// Consensus and ratings shift with every ingest.
  static const Duration consensus = Duration(minutes: 5);
  static const Duration ratings = Duration(minutes: 5);
  static const Duration comparison = Duration(minutes: 5);
  static const Duration home = Duration(minutes: 2);
}

/// A cached payload plus its age.
class CachedValue<T> {
  const CachedValue({
    required this.value,
    required this.storedAt,
    required this.isStale,
  });

  final T value;
  final DateTime storedAt;

  /// True when the TTL has expired, or when this was served as an offline
  /// fallback after a failed request. The UI must show the staleness.
  final bool isStale;

  /// `HH:mm` of when this was fetched, for the offline banner.
  String get storedAtLabel =>
      '${storedAt.hour.toString().padLeft(2, '0')}:${storedAt.minute.toString().padLeft(2, '0')}';
}

abstract class CacheStore {
  Future<void> init();

  /// Read a raw entry, or null when absent.
  Future<CachedValue<Object?>?> read(String key, {required Duration ttl});

  Future<void> write(String key, Object? value);

  Future<void> delete(String key);

  /// Delete all entries whose key starts with [prefix].
  Future<void> deleteByPrefix(String prefix);

  /// Clear everything. Used when the signed-in user changes, so one user's
  /// cached data is never shown to another.
  Future<void> clear();
}

class HiveCacheStore implements CacheStore {
  HiveCacheStore({this.boxName = 'duiliao_cache'});

  final String boxName;
  Box<String>? _box;

  @override
  Future<void> init() async {
    _box ??= await Hive.openBox<String>(boxName);
  }

  Box<String>? get _openBox => _box?.isOpen == true ? _box : null;

  @override
  Future<CachedValue<Object?>?> read(String key, {required Duration ttl}) async {
    final box = _openBox;
    if (box == null) return null;
    final raw = box.get(key);
    if (raw == null) return null;
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      final storedAtMs = envelope['storedAt'];
      if (storedAtMs is! int) return null;
      final storedAt = DateTime.fromMillisecondsSinceEpoch(storedAtMs);
      return CachedValue<Object?>(
        value: envelope['value'],
        storedAt: storedAt,
        isStale: DateTime.now().difference(storedAt) > ttl,
      );
    } on FormatException {
      // A corrupt entry is dropped rather than repeatedly failing to parse.
      await box.delete(key);
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? value) async {
    final box = _openBox;
    if (box == null) return;
    await box.put(
      key,
      jsonEncode({
        'storedAt': DateTime.now().millisecondsSinceEpoch,
        'value': value,
      }),
    );
  }

  @override
  Future<void> delete(String key) async => _openBox?.delete(key);

  @override
  Future<void> deleteByPrefix(String prefix) async {
    final box = _openBox;
    if (box == null) return;
    final keys = box.keys
        .where((key) => key is String && key.startsWith(prefix))
        .toList();
    if (keys.isNotEmpty) await box.deleteAll(keys);
  }

  @override
  Future<void> clear() async => _openBox?.clear();
}

/// In-memory cache for tests and for a build where Hive failed to open.
class MemoryCacheStore implements CacheStore {
  final Map<String, ({Object? value, DateTime storedAt})> entries = {};

  @override
  Future<void> init() async {}

  @override
  Future<CachedValue<Object?>?> read(String key, {required Duration ttl}) async {
    final entry = entries[key];
    if (entry == null) return null;
    return CachedValue<Object?>(
      value: entry.value,
      storedAt: entry.storedAt,
      isStale: DateTime.now().difference(entry.storedAt) > ttl,
    );
  }

  @override
  Future<void> write(String key, Object? value) async {
    entries[key] = (value: value, storedAt: DateTime.now());
  }

  @override
  Future<void> delete(String key) async => entries.remove(key);

  @override
  Future<void> deleteByPrefix(String prefix) async {
    entries.removeWhere((key, _) => key.startsWith(prefix));
  }

  @override
  Future<void> clear() async => entries.clear();
}

/// Keys for cached entries. Centralised so a key is never typo'd into a miss.
abstract final class CacheKeys {
  static const String rules = 'rules';
  static const String sources = 'sources';
  static String numbers(String date) => 'numbers:$date';
  static String draws(String lottery, int limit, int offset) =>
      'draws:$lottery:$limit:$offset';
  static String consensus(String lottery, String period, String? playType) =>
      'consensus:$lottery:$period:${playType ?? 'all'}';
  static String comparison(String lottery, String period) =>
      'comparison:$lottery:$period';
  static String ratings(String lottery, String playType, String windows) =>
      'ratings:$lottery:$playType:$windows';
  static String monitor(String lottery) => 'monitor:$lottery';
  static String home(String lottery, String playType) => 'home:$lottery:$playType';
  static const String eventCursor = 'event_cursor';
  static const String messages = 'messages';
}
