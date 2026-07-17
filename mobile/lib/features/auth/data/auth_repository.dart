import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mybill/core/constants/app_constants.dart';

/// Thin wrapper over Supabase Auth (tasks 1.2.5–1.2.7, 1.2.9).
///
/// Auth is client-to-Supabase: the backend issues no credentials, it only verifies the
/// resulting JWT (`backend/app/core/security.py`). Keeping the SDK behind this class
/// means screens/controllers never import `supabase_flutter`, and the session (including
/// refresh) stays the SDK's concern.
class AuthRepository {
  const AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// The current session, or null when signed out.
  Session? get currentSession => _auth.currentSession;

  /// Emits on sign-in, sign-out, and token refresh — the source of truth for
  /// [authStateProvider] and the router's guard (task 1.2.8).
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  /// Sign in with email + password. Throws [AuthException] on bad credentials.
  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithPassword(email: email.trim(), password: password);
  }

  /// Register a new account (task 1.2.6).
  ///
  /// `full_name` goes into user metadata, which the DB signup trigger copies into
  /// `public.users` (task 1.2.3). When the project has email confirmation enabled the
  /// returned session is null — the caller surfaces a "check your inbox" message.
  Future<bool> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final response = await _auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        if (fullName != null && fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
      },
    );
    return response.session != null;
  }

  /// Send a password-reset email (task 1.2.7).
  Future<void> sendPasswordReset(String email) async {
    await _auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: AppConstants.passwordResetRedirect,
    );
  }

  /// Sign out and clear the persisted session (task 1.2.9).
  Future<void> signOut() => _auth.signOut();
}

/// The Supabase client. Overridden in tests; throws if read before
/// `Supabase.initialize` has run in `main`.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
