import 'package:flutter/material.dart';

const _teal = Color(0xFF176B60);

ThemeData buildTheme(Brightness brightness) {
  var scheme = ColorScheme.fromSeed(
    seedColor: _teal,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  if (brightness == Brightness.light) {
    scheme = scheme.copyWith(primary: _teal, surface: const Color(0xFFFAFAF6));
  }
  final base = ThemeData(colorScheme: scheme);
  return base.copyWith(
    appBarTheme: const AppBarTheme(centerTitle: false),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: base.textTheme.titleMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
      minVerticalPadding: 10,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );
}

/// Digits that line up in columns, for money.
const tabular = [FontFeature.tabularFigures()];

extension BalanceColors on ColorScheme {
  /// Teal when someone owes you, amber when you owe, muted when even.
  ///
  /// Owing money is not an error, so it never uses the error red.
  Color forSign(int sign) => switch (sign) {
    > 0 => primary,
    < 0 =>
      brightness == Brightness.light
          ? const Color(0xFF8A5A00)
          : const Color(0xFFF2B866),
    _ => onSurfaceVariant,
  };
}

extension ChartColors on ColorScheme {
  /// A step brighter than [primary], so thin bars still read as colour.
  Color get bar => brightness == Brightness.light
      ? const Color(0xFF00897B)
      : const Color(0xFF1E9E8C);
}
