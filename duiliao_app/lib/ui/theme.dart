/// App theme, and the semantic colours the domain needs — Aurora Glass Edition.
library;

import 'package:flutter/material.dart';

/// Domain colours that must stay consistent between light and dark mode.
///
/// 波色 (ball colour) is part of the data, not decoration: a red ball must read
/// as red in both themes. These are therefore fixed values, chosen to stay
/// legible on both backgrounds, rather than being derived from the colour scheme.
abstract final class DuiliaoColors {
  /// Aurora brand violet (primary).
  static const Color primary = Color(0xFF8B5CF6);

  /// Aurora brand violet, lightened for dark-mode legibility.
  static const Color primaryDark = Color(0xFFA78BFA);

  /// Aurora gradient stops: 靛蓝 → 紫罗兰 → 品红.
  static const Color auroraIndigo = Color(0xFF6366F1);
  static const Color auroraViolet = Color(0xFF8B5CF6);
  static const Color auroraFuchsia = Color(0xFFD946EF);

  /// Aurora ambient sky glow (used for background orbs and accents).
  static const Color auroraSky = Color(0xFF38BDF8);

  /// The signature brand gradient.
  static const LinearGradient auroraGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [auroraIndigo, auroraViolet, auroraFuchsia],
  );

  /// Deep-space indigo app background (dark theme).
  static const Color backgroundDark = Color(0xFF12121F);

  /// Cool violet-white app background (light theme).
  static const Color backgroundLight = Color(0xFFF5F4FB);

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
  /// Aurora violet seed.
  static const Color _seed = DuiliaoColors.auroraViolet;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    ).copyWith(
      // violet primary — lightened in dark mode for legibility on glass
      primary: isDark ? DuiliaoColors.primaryDark : DuiliaoColors.primary,
      onPrimary: isDark ? const Color(0xFF2A1A52) : Colors.white,
      primaryContainer: isDark ? const Color(0xFF4C2E8C) : const Color(0xFFE9E4FD),
      onPrimaryContainer: isDark ? const Color(0xFFEDE9FE) : const Color(0xFF3B1470),
      secondary: isDark ? const Color(0xFF818CF8) : DuiliaoColors.auroraIndigo,
      onSecondary: isDark ? const Color(0xFF1E1B4B) : Colors.white,
      secondaryContainer: isDark ? const Color(0xFF3730A3) : const Color(0xFFE0E7FF),
      onSecondaryContainer: isDark ? const Color(0xFFE0E7FF) : const Color(0xFF1E1B4B),
      tertiary: isDark ? const Color(0xFFE879F9) : DuiliaoColors.auroraFuchsia,
      onTertiary: isDark ? const Color(0xFF4A044E) : Colors.white,
      tertiaryContainer: isDark ? const Color(0xFF86198F) : const Color(0xFFFAE8FF),
      onTertiaryContainer: isDark ? const Color(0xFFFAE8FF) : const Color(0xFF701A75),
      surface: isDark ? DuiliaoColors.backgroundDark : DuiliaoColors.backgroundLight,
      onSurface: isDark ? const Color(0xFFE6E4F2) : const Color(0xFF1E1B2E),
      onSurfaceVariant: isDark ? const Color(0xFFA9A4C0) : const Color(0xFF5A5670),
      outline: isDark ? const Color(0xFF4A4767) : const Color(0xFF8F8AAC),
      outlineVariant: isDark ? const Color(0xFF2C2B44) : const Color(0xFFE3E0F0),
      surfaceContainerHighest:
          isDark ? const Color(0xFF23233A) : const Color(0xFFEBE9F6),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? DuiliaoColors.backgroundDark : DuiliaoColors.backgroundLight,
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
            ? const Color(0xFF16162A).withValues(alpha: 0.75)
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
            ? const Color(0xFF1C1C2E).withValues(alpha: 0.62)
            : Colors.white.withValues(alpha: 0.72),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.75),
            width: 1.0,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.15) : scheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.62),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.12) : scheme.outlineVariant,
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
          borderSide: const BorderSide(color: DuiliaoColors.primary, width: 1.5),
        ),
        isDense: true,
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 0.8,
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : scheme.outlineVariant.withValues(alpha: 0.7),
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
