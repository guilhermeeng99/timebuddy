import 'package:flutter/material.dart';
import 'package:timebuddy/app/theme/app_colors.dart';

/// The sanctioned way to read theme values inside a widget.
///
/// Screens never touch [AppColors] or [Theme] directly. Two reasons: the active
/// palette is a mutable static that only these getters know how to pick between
/// (light vs dark), and a widget that reaches for `AppColors.light` hardcodes a
/// brightness that survives a theme switch and only shows up in dark mode.
///
/// ```dart
/// final colors = context.appColors;
/// Text(city.label, style: context.textTheme.titleLarge);
/// context.showSnack(t.locations.added);
/// ```
extension ContextExtensions on BuildContext {
  /// Semantic color tokens of the brightness currently rendering.
  AppColorsData get appColors => isDarkMode ? AppColors.dark : AppColors.light;

  /// The app's type scale, already colored by [ThemeData].
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Whether the dark palette is the one in effect.
  ///
  /// Read from the resolved [ThemeData], not from the platform brightness: a
  /// user who forced `ThemeMode.light` on a dark phone must still get the light
  /// tokens, and `MediaQuery.platformBrightnessOf` would say otherwise.
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Logical size of the window.
  ///
  /// Uses `MediaQuery.sizeOf` so the widget rebuilds on a resize (constant on
  /// phones, constant only until the next drag on web) without subscribing to
  /// every other `MediaQueryData` field.
  Size get screenSize => MediaQuery.sizeOf(this);

  /// Shows a plain-text snackbar, the app's default feedback channel.
  ///
  /// The current bar is dismissed first so a burst of feedback (add a city,
  /// then hit the board limit) shows the newest message instead of queueing
  /// behind a stale one for four seconds.
  ///
  /// Snackbars that need an action or a custom duration call
  /// [ScaffoldMessenger] directly; this helper deliberately stays one-shape.
  void showSnack(String message) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
