import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_colors.dart';
import 'package:timebuddy/app/theme/app_spacing.dart';
import 'package:timebuddy/app/theme/app_typography.dart';

/// Height of the full-width primary action.
///
/// Above the 48px touch-target minimum on purpose: the submit bar is the only
/// affordance on its row, and 48 makes it read as just another list item.
const double _primaryButtonHeight = 52;

/// Vertical padding inside a filled input.
///
/// Sits between [AppSpacing.md] and [AppSpacing.lg] because neither works:
/// 12 crowds the label against the field edge, 16 makes the field taller than
/// the button below it. This is the one spacing value the scale does not own.
const double _inputVerticalPadding = 14;

/// Builds the Material 3 [ThemeData] for each brightness from the active
/// palette in [AppColors].
///
/// Reads `AppColors.light` / `AppColors.dark` at call time, not at import
/// time, so a runtime palette switch only has to reassign those statics and
/// rebuild `MaterialApp` with a freshly built theme.
///
/// Example:
/// ```dart
/// MaterialApp(theme: AppTheme.light(), darkTheme: AppTheme.dark());
/// ```
abstract class AppTheme {
  /// Light theme built from the currently selected light palette.
  static ThemeData light() => _buildTheme(
    brightness: Brightness.light,
    colors: AppColors.light,
  );

  /// Dark theme built from the currently selected dark palette.
  static ThemeData dark() => _buildTheme(
    brightness: Brightness.dark,
    colors: AppColors.dark,
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required AppColorsData colors,
  }) {
    final textTheme = AppTypography.textTheme.apply(
      bodyColor: colors.onBackground,
      displayColor: colors.onBackground,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      // Foregrounds are derived with foregroundOn / onPrimary rather than
      // hardcoded white: a catalog palette is free to ship a light primary,
      // and white-on-amber is unreadable long before anyone reports it.
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        secondary: colors.secondary,
        onSecondary: foregroundOn(colors.secondary),
        error: colors.error,
        onError: foregroundOn(colors.error),
        surface: colors.surface,
        onSurface: colors.onBackground,
        surfaceContainerHighest: colors.surfaceVariant,
      ),
      scaffoldBackgroundColor: colors.background,
      textTheme: textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: colors.surface,
        foregroundColor: colors.onBackground,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.surfaceVariant,
        // No resting border: the fill alone carries the field's shape, so a
        // form of six inputs does not read as a stack of boxes.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: _inputVerticalPadding,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size(double.infinity, _primaryButtonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          minimumSize: const Size(double.infinity, _primaryButtonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          side: BorderSide(color: colors.primary),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // The shell renders the custom floating TimeBuddyBottomBar; this only
      // keeps a raw BottomNavigationBar on-brand if one ever appears.
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.surface,
        selectedItemColor: colors.primary,
        unselectedItemColor: colors.onBackgroundLight,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceVariant,
        selectedColor: colors.primary,
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.surfaceVariant,
        thickness: 1,
      ),
    );
  }
}
