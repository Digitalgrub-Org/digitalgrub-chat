import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand colors sampled from digitalgrub.in.
  static const gold = Color(0xFFFFBE00);
  static const goldPressed = Color(0xFFF0A500);
  static const deepTeal = Color(0xFF0B2322);
  static const slate = Color(0xFF364E52);
  static const muted = Color(0xFF67787A);
  static const cloud = Color(0xFFF5F7F6);
  static const night = Color(0xFF071918);
  static const nightSurface = Color(0xFF102B2A);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  /// Theme for the navigation rail and conversation list on a wide window.
  ///
  /// Both stay dark whichever theme the app is in, so the conversation reads
  /// as the primary surface and the list beside it recedes. Handing the whole
  /// subtree a dark scheme — rather than recolouring widget by widget — is
  /// what keeps the list's own text, dividers and badges legible on it.
  static ThemeData get sidebar {
    final base = dark;
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.deepTeal,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: AppColors.deepTeal,
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: AppColors.night,
      ),
      dividerTheme: const DividerThemeData(color: Color(0x1AFFFFFF), space: 1),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.gold,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.gold,
          onPrimary: AppColors.deepTeal,
          primaryContainer: isDark
              ? const Color(0xFF594500)
              : const Color(0xFFFFE6A0),
          onPrimaryContainer: isDark
              ? const Color(0xFFFFE08A)
              : AppColors.deepTeal,
          secondary: isDark ? const Color(0xFFA8C7C5) : AppColors.slate,
          onSecondary: isDark ? AppColors.deepTeal : Colors.white,
          secondaryContainer: isDark
              ? const Color(0xFF284846)
              : const Color(0xFFDDE9E7),
          onSecondaryContainer: isDark
              ? const Color(0xFFDDE9E7)
              : AppColors.deepTeal,
          surface: isDark ? AppColors.nightSurface : Colors.white,
          onSurface: isDark ? const Color(0xFFF2F6F5) : AppColors.deepTeal,
          onSurfaceVariant: isDark ? const Color(0xFFB7C7C5) : AppColors.slate,
          outline: isDark ? const Color(0xFF718B89) : AppColors.muted,
          outlineVariant: isDark
              ? const Color(0xFF284441)
              : const Color(0xFFDCE4E2),
          surfaceContainerHighest: isDark
              ? const Color(0xFF193735)
              : const Color(0xFFE8EEEC),
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? AppColors.night : AppColors.cloud,
      visualDensity: VisualDensity.standard,
    );

    final textTheme = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        height: 1.45,
        letterSpacing: 0,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        height: 1.4,
        letterSpacing: 0,
      ),
    );

    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: isDark ? AppColors.night : AppColors.cloud,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
        color: scheme.surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: shape,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: shape,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    );
  }
}
