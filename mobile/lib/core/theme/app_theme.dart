import 'package:flutter/material.dart';

/// Central Material 3 theme, seeded from a single brand colour so light and dark
/// stay in sync. Widgets should read colours/text styles from `Theme.of(context)`
/// rather than hard-coding values.
///
/// Typography pairs two bundled Google Fonts: **Oswald** for titles (the display,
/// headline, and title styles — app-bar titles, section headers) and **Poppins**
/// for everything else (body and label text). Both are shipped as app assets (see
/// pubspec `fonts:`), so no font is fetched at runtime. The pairing is applied once
/// here so screens never name a font directly.
class AppTheme {
  const AppTheme._();

  /// Grocery-green brand seed.
  static const Color _seed = Color(0xFF2E7D32);

  /// Bundled font families (declared in pubspec `fonts:`).
  static const String _titleFont = 'Oswald';
  static const String _bodyFont = 'Poppins';

  static ThemeData get light => _themeFor(Brightness.light);

  static ThemeData get dark => _themeFor(Brightness.dark);

  static ThemeData _themeFor(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
    );
    return base.copyWith(textTheme: _textTheme(base.textTheme));
  }

  /// Poppins across the board, then Oswald over the title tiers. Each style keeps
  /// its Material size, colour, and spacing — only the family changes.
  static TextTheme _textTheme(TextTheme base) {
    final body = base.apply(fontFamily: _bodyFont);
    TextStyle? title(TextStyle? style) =>
        style?.copyWith(fontFamily: _titleFont);
    return body.copyWith(
      displayLarge: title(body.displayLarge),
      displayMedium: title(body.displayMedium),
      displaySmall: title(body.displaySmall),
      headlineLarge: title(body.headlineLarge),
      headlineMedium: title(body.headlineMedium),
      headlineSmall: title(body.headlineSmall),
      titleLarge: title(body.titleLarge),
      titleMedium: title(body.titleMedium),
      titleSmall: title(body.titleSmall),
    );
  }
}
