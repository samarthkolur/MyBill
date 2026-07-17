/// App-wide constants and build-time configuration.
class AppConstants {
  const AppConstants._();

  static const String appName = 'MyBill';

  /// Base URL of the FastAPI backend. Overridable at build/run time with
  /// `--dart-define=API_BASE_URL=https://api.example.com/v1`. The default targets
  /// a locally-running backend (see `infra/docker-compose.yml`).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/v1',
  );

  /// Supabase project URL — the client authenticates directly against Supabase Auth
  /// and sends the resulting JWT to our backend, which only *verifies* it
  /// (`backend/app/core/security.py`). Supply with
  /// `--dart-define=SUPABASE_URL=https://<project>.supabase.co`.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon/publishable key. Safe to ship in a client (it grants nothing on its
  /// own — row-level security is the authority, `MyBill.md` §11), but it is still
  /// injected at build time rather than committed. Supply with
  /// `--dart-define=SUPABASE_ANON_KEY=<key>`.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Whether Supabase credentials were supplied at build time. Mirrors the backend's
  /// `Settings.supabase_configured` so the app can fail loudly with a useful message
  /// instead of throwing deep inside the SDK.
  static bool get supabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Deep link that Supabase redirects to after a password-reset email (task 1.2.7).
  /// Must match the scheme registered in the Android manifest / iOS Info.plist and be
  /// listed as an allowed redirect URL in the Supabase dashboard.
  static const String passwordResetRedirect = 'io.mybill.app://reset-password';
}
