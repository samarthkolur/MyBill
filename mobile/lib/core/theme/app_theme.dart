import 'package:flutter/material.dart';

/// Central Material 3 theme, seeded from a single brand colour so light and dark
/// stay in sync. Widgets should read colours/text styles from `Theme.of(context)`
/// rather than hard-coding values.
class AppTheme {
  const AppTheme._();

  /// Grocery-green brand seed.
  static const Color _seed = Color(0xFF2E7D32);

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _seed),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
  );
}
