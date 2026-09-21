/// Defensive JSON coercion helpers.
///
/// Responses come from a Python backend with no response models — handlers return
/// bare dicts — so a field can legitimately be absent, null, or a different
/// numeric type than expected (SQLite hands back an int where Postgres hands back
/// a float, and `official_hit` is a 0/1 int rather than a bool).
///
/// The rule throughout: **absent and null are preserved as null, never silently
/// coerced to a zero value.** A hit rate of null means "not enough data to say",
/// which is a different statement from 0%, and showing 0% would misinform an
/// operator deciding whether to trust a source.
library;

/// Read a nullable string, treating an empty string as present.
String? asStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// Read a string with a fallback for absent/null.
String asString(Object? value, {String fallback = ''}) =>
    asStringOrNull(value) ?? fallback;

/// Read a nullable int, accepting numeric strings and doubles.
int? asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
    return double.tryParse(value.trim())?.toInt();
  }
  return null;
}

int asInt(Object? value, {int fallback = 0}) => asIntOrNull(value) ?? fallback;

/// Read a nullable double. Kept nullable because rates are meaningfully absent.
double? asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

double asDouble(Object? value, {double fallback = 0}) =>
    asDoubleOrNull(value) ?? fallback;

/// Read a nullable bool, accepting the 0/1 ints the backend uses for
/// `official_hit` / `claimed_hit` and the SQLite integer booleans.
bool? asBoolOrNull(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lowered = value.trim().toLowerCase();
    if (lowered.isEmpty) return null;
    if (lowered == 'true' || lowered == '1' || lowered == 'yes') return true;
    if (lowered == 'false' || lowered == '0' || lowered == 'no') return false;
  }
  return null;
}

bool asBool(Object? value, {bool fallback = false}) =>
    asBoolOrNull(value) ?? fallback;

/// Read a map, returning an empty map rather than throwing on an unexpected type.
Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return const {};
}

/// Read a nullable map, distinguishing "absent" from "empty".
Map<String, dynamic>? asMapOrNull(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return null;
}

/// Read a list, returning empty rather than throwing.
List<dynamic> asList(Object? value) {
  if (value is List) return value;
  return const [];
}

/// Read a list of strings, dropping nulls.
List<String> asStringList(Object? value) => asList(value)
    .map(asStringOrNull)
    .whereType<String>()
    .toList(growable: false);

/// Map a list of JSON objects through [parse].
///
/// Entries that are not objects are skipped rather than crashing the whole
/// screen, since one malformed row should not blank a list of fifty.
List<T> asModelList<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  final out = <T>[];
  for (final entry in asList(value)) {
    final map = asMapOrNull(entry);
    if (map == null) continue;
    out.add(parse(map));
  }
  return List.unmodifiable(out);
}

/// Parse a nullable object field through [parse].
T? asModelOrNull<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  final map = asMapOrNull(value);
  if (map == null) return null;
  return parse(map);
}

/// Parse a timestamp.
///
/// The backend emits several formats: ISO-8601 with and without a zone, and
/// `"%Y-%m-%d %H:%M:%S"` from the collector's naive CN-local columns. A space
/// separator is normalised to `T` so [DateTime.parse] accepts it.
DateTime? asDateTimeOrNull(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = asStringOrNull(value)?.trim();
  if (text == null || text.isEmpty) return null;
  final normalised = text.contains(' ') && !text.contains('T')
      ? text.replaceFirst(' ', 'T')
      : text;
  return DateTime.tryParse(normalised);
}

/// Format a rate in `0..1` as a percentage string, or a dash when absent.
///
/// A null rate renders as `—`, never `0%`: the two mean different things and
/// conflating them would overstate confidence in a source with no samples.
String formatRate(double? rate, {int decimals = 1, String absent = '—'}) {
  if (rate == null) return absent;
  return '${(rate * 100).toStringAsFixed(decimals)}%';
}
