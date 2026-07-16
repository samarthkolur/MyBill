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
}
