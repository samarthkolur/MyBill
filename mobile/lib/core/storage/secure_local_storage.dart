import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session in the platform keystore (task 1.2.4).
///
/// The SDK defaults to `SharedPreferences`, which is plain-text on disk — a session
/// string contains a live access token *and* a long-lived refresh token, so it is
/// stored via `flutter_secure_storage` instead (Keychain on iOS, EncryptedSharedPrefs
/// backed by the Android Keystore).
///
/// Wired in through `FlutterAuthClientOptions.localStorage` at `Supabase.initialize`;
/// the SDK calls these methods itself on sign-in/refresh/sign-out, so nothing else in
/// the app touches tokens directly.
class SecureLocalStorage extends LocalStorage {
  const SecureLocalStorage();

  /// Single key holding the SDK's serialised session JSON.
  static const String _sessionKey = 'supabase.session';

  // Android encrypts via the plugin's default ciphers (Keystore-backed); iOS pins the
  // item to `first_unlock` so a background token refresh can still read it after a
  // reboot, while it stays unreadable on a locked, powered-off device.
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _sessionKey);

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _sessionKey, value: persistSessionString);
}
