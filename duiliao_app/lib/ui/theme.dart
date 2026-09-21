/// App theme, and the semantic colours the domain needs.
library;

import 'package:flutter/material.dart';

/// Domain colours that must stay consistent between light and dark mode.
///
/// 波色 (ball colour) is part of the data, not decoration: a red ball must read
/// as red in both themes. These are therefore fixed values, chosen to stay
/// legible on both backgrounds, rather than being derived from the colour scheme.
abstract final class DuiliaoColors {
  /// 红波.
  static const Color boseRed = Color(0xFFD32F2F);

  /// 蓝波.
  static const Color boseBlue = Color(0xFF1976D2);

  /// 绿波.
  static const Color boseGreen = Color(0xFF388E3C);

  /// Unknown 波色, so an unexpected value is visibly neutral rather than
  /// silently rendered as one of the three.
  static const Color boseUnknown = Color(0xFF757575);

  static const Color hit = Color(0xFF2E7D32);
  static const Color miss = Color(0xFFC62828);
  static const Color pending = Color(0xFF757575);

  /// Conflict: a source claiming a hit the judge scored as a miss. Deliberately
  /// the most alarming colour in the palette — it is evidence of dishonesty.
  static const Color conflict = Color(0xFFE65100);

  static const Color warning = Color(0xFFEF6C00);
  static const Color offline = Color(0xFF616161);

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
  static const Color _seed = Color(0xFF1565C0);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Tabular figures keep number columns aligned in the ratings table.
      fontFamilyFallback: const ['PingFang SC', 'Heiti SC', 'Noto Sans CJK SC'],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
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
