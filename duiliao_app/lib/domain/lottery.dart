/// Lottery codes and period handling.
///
/// The codes are fixed by `backend/collector/common/period.py::LOTTERIES`.
library;

enum Lottery {
  hk('hk', '香港'),
  macau('macau', '澳门'),
  taiwan('taiwan', '台湾'),
  neu('new', '新彩');

  const Lottery(this.code, this.label);

  /// Wire value, e.g. `macau`.
  final String code;

  /// Chinese display name.
  final String label;

  static const List<Lottery> all = [Lottery.hk, Lottery.macau, Lottery.taiwan, Lottery.neu];

  /// Parse a wire code. Returns null for an unknown value rather than guessing.
  static Lottery? tryParse(String? code) {
    if (code == null) return null;
    for (final lottery in values) {
      if (lottery.code == code) return lottery;
    }
    return null;
  }

  /// Parse with a fallback, for display paths that must not fail.
  static Lottery parse(String? code, {Lottery fallback = Lottery.macau}) =>
      tryParse(code) ?? fallback;

  /// Label for an arbitrary code, falling back to the code itself so an
  /// unrecognised lottery is still identifiable on screen.
  static String labelFor(String? code) => tryParse(code)?.label ?? (code ?? '—');
}

/// Helpers for the canonical `YYYYNNN` period format.
///
/// The backend normalises loose input (`248`, `第248期`, `26/248`) server-side via
/// `common.period.normalize`, so the client may send what the user typed and only
/// needs to *display* canonical values it receives.
abstract final class Period {
  /// Strip the year and leading zeros: `2026248` -> `248`.
  ///
  /// Responses usually include `period_raw` already; this is for the cases that
  /// do not.
  static String short(String? period) {
    if (period == null || period.isEmpty) return '';
    if (period.length <= 4) return period;
    final sequence = period.substring(4);
    final trimmed = sequence.replaceFirst(RegExp(r'^0+'), '');
    return trimmed.isEmpty ? '0' : trimmed;
  }

  /// Extract the 4-digit year, or null when the period is not canonical.
  static int? year(String? period) {
    if (period == null || period.length < 5) return null;
    return int.tryParse(period.substring(0, 4));
  }

  /// `2026248` -> `2026 年 248 期`.
  static String display(String? period) {
    if (period == null || period.isEmpty) return '—';
    final y = year(period);
    if (y == null) return period;
    return '$y 年 ${short(period)} 期';
  }

  /// `2026248` -> `第248期`, the compact form used in list rows.
  static String compact(String? period) {
    if (period == null || period.isEmpty) return '—';
    return '第${short(period)}期';
  }

  /// True when [input] could be a period the backend will accept.
  ///
  /// Deliberately permissive — the server is the authority — but it catches
  /// obvious typos before a round trip.
  static bool looksValid(String input) {
    final trimmed = input.trim().replaceAll('第', '').replaceAll('期', '');
    if (trimmed.isEmpty) return false;
    return RegExp(r'^\d{1,7}$').hasMatch(trimmed) ||
        RegExp(r'^\d{2,4}[/_-]\d{1,3}$').hasMatch(trimmed);
  }
}
