/// App theme, and the semantic colours the domain needs — iOS 27 Liquid Glass Edition.
library;

import 'package:flutter/material.dart';

/// Domain colours that must stay consistent between light and dark mode.
///
/// 波色 (ball colour) is part of the data, not decoration: a red ball must read
/// as red in both themes. These are therefore fixed values, chosen to stay
/// legible on both backgrounds, rather than being derived from the colour scheme.
abstract final class DuiliaoColors {
  /// 红波 — 晶莹红宝石.
  static const Color boseRed = Color(0xFFE53935);

  /// 蓝波 — 蔚蓝水晶.
  static const Color boseBlue = Color(0xFF1E88E5);

  /// 绿波 — 极光翡翠.
  static const Color boseGreen = Color(0xFF2E7D32);

  /// Unknown 波色, visibly neutral.
  static const Color boseUnknown = Color(0xFF757575);

  static const Color hit = Color(0xFF10B981);
  static const Color miss = Color(0xFFEF4444);
  static const Color pending = Color(0xFF64748B);

  /// Conflict: a source claiming a hit the judge scored as a miss.
  static const Color conflict = Color(0xFFF97316);

  static const Color warning = Color(0xFFF59E0B);
  static const Color offline = Color(0xFF64748B);

  /// Colour for a 波色 string, tolerating both `红` and `红波`.
  static Color forBose(String? bose) {
    if (bose == null || bose.isEmpty) return boseUnknown;
    if (bose.startsWith('红')) return boseRed;
    if (bose.startsWith('蓝')) return boseBlue;
    if (bose.startsWith('绿')) return boseGreen;
    return boseUnknown;
  }
}

abstract final class DuiliaoTheme {
  /// iOS 27 Electric Azure / Indigo seed.
  static const Color _seed = Color(0xFF007AFF);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      surface: isDark ? const Color(0xFF0F1522) : const Color(0xFFF6F8FD),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF3F6FD),
      fontFamilyFallback: const [
        'SF Pro Display',
        'PingFang SC',
        'Heiti SC',
        'Noto Sans CJK SC',
        'sans-serif',
      ],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark
            ? const Color(0xFF0F1522).withValues(alpha: 0.75)
            : Colors.white.withValues(alpha: 0.75),
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        color: isDark
            ? const Color(0xFF141B2A).withValues(alpha: 0.68)
            : Colors.white.withValues(alpha: 0.78),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.85),
            width: 1.0,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.15) : scheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.65),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.80),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF007AFF), width: 1.5),
        ),
        isDense: true,
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 0.8,
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFE2E8F0).withValues(alpha: 0.6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

/// Convenience accessors used across screens.
extension ThemeContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
