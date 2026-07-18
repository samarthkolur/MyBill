import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central Material 3 theme, seeded from a single brand colour so light and dark
/// stay in sync. Widgets should read colours/text styles from `Theme.of(context)`
/// rather than hard-coding values.
///
/// Typography pairs two Google Fonts: **Oswald** for titles (the display,
/// headline, and title styles — app-bar titles, section headers) and **Poppins**
/// for everything else (body and label text). The pairing is applied once here so
/// screens never name a font directly.
class AppTheme {
  const AppTheme._();

  /// Grocery-green brand seed.
  static const Color _seed = Color(0xFF2E7D32);

  static ThemeData get light => _themeFor(Brightness.light);

  static ThemeData get dark => _themeFor(Brightness.dark);

  static ThemeData _themeFor(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
    );
    return base.copyWith(textTheme: _textTheme(base.textTheme));
  }

  /// Oswald for the title tiers, Poppins for the rest. Each Oswald style is
  /// derived from the Poppins one so colour, size, and spacing from the base
  /// Material text theme carry through — only the family changes.
  static TextTheme _textTheme(TextTheme base) {
    final body = GoogleFonts.poppinsTextTheme(base);
    TextStyle? title(TextStyle? style) => GoogleFonts.oswald(textStyle: style);
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
