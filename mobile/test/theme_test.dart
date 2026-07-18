import 'package:flutter_test/flutter_test.dart';
import 'package:mybill/core/theme/app_theme.dart';

/// The typography contract: Oswald on the title tiers, Poppins everywhere else.
/// Both families are bundled app assets (pubspec `fonts:`), so this also guards
/// against the theme silently falling back to the platform default.
void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
  }.entries) {
    group('${entry.key} theme typography', () {
      final text = entry.value.textTheme;

      test('title tiers use Oswald', () {
        expect(text.displayLarge?.fontFamily, 'Oswald');
        expect(text.headlineMedium?.fontFamily, 'Oswald');
        expect(text.titleLarge?.fontFamily, 'Oswald');
        expect(text.titleSmall?.fontFamily, 'Oswald');
      });

      test('body and label text use Poppins', () {
        expect(text.bodyLarge?.fontFamily, 'Poppins');
        expect(text.bodyMedium?.fontFamily, 'Poppins');
        expect(text.labelLarge?.fontFamily, 'Poppins');
      });
    });
  }
}
