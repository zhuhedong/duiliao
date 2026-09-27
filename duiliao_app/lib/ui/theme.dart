/// Mobile design system for Duiliao.
///
/// The mobile client uses a calm, high-contrast operations UI: solid surfaces,
/// clear status colours, generous touch targets and a restrained violet accent.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class DuiliaoColors {
  static const Color primary = Color(0xFF5B4BDB);
  static const Color primaryDark = Color(0xFFB8AEFF);

  static const Color auroraIndigo = Color(0xFF4F46E5);
  static const Color auroraViolet = Color(0xFF7C3AED);
  static const Color auroraFuchsia = Color(0xFFC026D3);
  static const Color auroraSky = Color(0xFF0284C7);
  static const LinearGradient auroraGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [auroraIndigo, auroraViolet, auroraFuchsia],
  );

  static const Color backgroundDark = Color(0xFF101116);
  static const Color backgroundLight = Color(0xFFF7F7FA);

  static const Color boseRed = Color(0xFFE53935);
  static const Color boseBlue = Color(0xFF1E88E5);
  static const Color boseGreen = Color(0xFF2E7D32);
  static const Color boseUnknown = Color(0xFF757575);

  static const Color hit = Color(0xFF0F9D69);
  static const Color miss = Color(0xFFD64545);
  static const Color pending = Color(0xFF667085);
  static const Color conflict = Color(0xFFB54708);
  static const Color warning = Color(0xFFB7791F);
  static const Color offline = Color(0xFF667085);

  static Color forBose(String? bose) {
    if (bose == null || bose.isEmpty) return boseUnknown;
    if (bose.startsWith('红')) return boseRed;
    if (bose.startsWith('蓝')) return boseBlue;
    if (bose.startsWith('绿')) return boseGreen;
    return boseUnknown;
  }
}

abstract final class DuiliaoTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: DuiliaoColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: dark ? DuiliaoColors.primaryDark : DuiliaoColors.primary,
      onPrimary: dark ? const Color(0xFF211A45) : Colors.white,
      primaryContainer: dark ? const Color(0xFF352B70) : const Color(0xFFE9E7FF),
      onPrimaryContainer: dark ? const Color(0xFFEAE7FF) : const Color(0xFF211A45),
      secondary: dark ? const Color(0xFF9A8CFF) : const Color(0xFF6D5CE7),
      surface: dark ? DuiliaoColors.backgroundDark : DuiliaoColors.backgroundLight,
      onSurface: dark ? const Color(0xFFF4F4F5) : const Color(0xFF1D1D24),
      onSurfaceVariant: dark ? const Color(0xFFB7B8C2) : const Color(0xFF62636D),
      outline: dark ? const Color(0xFF3B3D48) : const Color(0xFFD7D7DF),
      outlineVariant: dark ? const Color(0xFF282A33) : const Color(0xFFE8E8EE),
      surfaceContainerHighest: dark ? const Color(0xFF20222A) : const Color(0xFFEFEFF3),
      error: dark ? const Color(0xFFFF8A8A) : const Color(0xFFB42318),
    );

    final baseText = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
    ).textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: baseText.copyWith(
        displaySmall: baseText.displaySmall?.copyWith(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.0,
        ),
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: baseText.titleSmall?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 15, height: 1.35),
        bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 13, height: 1.35),
        bodySmall: baseText.bodySmall?.copyWith(fontSize: 12, height: 1.35),
        labelLarge: baseText.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
        labelMedium: baseText.labelMedium?.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
        labelSmall: baseText.labelSmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      fontFamilyFallback: const [
        'SF Pro Display',
        'PingFang SC',
        'Heiti SC',
        'Noto Sans CJK SC',
        'sans-serif',
      ],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark ? const Color(0xFF191B22) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DuiliaoTokens.radiusLarge),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: dark ? const Color(0xFF17181E) : Colors.white,
        indicatorColor: dark ? const Color(0xFF3A3271) : const Color(0xFFEAE8FF),
        labelTextStyle: MaterialStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF1B1D24) : const Color(0xFFF1F1F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DuiliaoTokens.radiusMedium),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DuiliaoTokens.radiusMedium),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DuiliaoTokens.radiusMedium),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        isDense: true,
      ),
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DuiliaoTokens.radiusSmall)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DuiliaoTokens.radiusMedium)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DuiliaoTokens.radiusMedium)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(DuiliaoTokens.minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DuiliaoTokens.radiusMedium)),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

extension ThemeContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
