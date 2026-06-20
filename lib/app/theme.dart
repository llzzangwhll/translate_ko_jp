import 'package:flutter/material.dart';

/// Brand palette, derived from the app icon / splash (white background with a
/// blue family). Reuse these instead of hard-coding hex values in widgets.
class AppColors {
  AppColors._();

  /// Primary action blue (buttons, active accents).
  static const Color primary = Color(0xFF2563EB);

  /// Lighter blue used in the icon's first speech bubble.
  static const Color primaryLight = Color(0xFF378ADD);

  /// Deeper blue used in the icon's second bubble and on-light text.
  static const Color primaryDark = Color(0xFF185FA5);

  /// Very light blue tint for containers, borders and surfaces.
  static const Color tint = Color(0xFFE6F1FB);

  /// Text color to sit on [tint] / light-blue containers.
  static const Color onTint = Color(0xFF0C447C);
}

/// Centralized light/dark themes so every screen shares one white + blue look.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.tint,
      onPrimaryContainer: AppColors.onTint,
      surface: Colors.white,
      surfaceTint: AppColors.primary,
    );
    return _base(scheme, Colors.white);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    );
    return _base(scheme, scheme.surface);
  }

  static ThemeData _base(ColorScheme scheme, Color scaffold) {
    final isLight = scheme.brightness == Brightness.light;
    final appBarFg = isLight ? AppColors.primaryDark : scheme.onSurface;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: appBarFg,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: scheme.primary,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: appBarFg,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : null,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
