import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/features/auth/data/auth_repository.dart';

/// Whether the app currently has a usable session (task 1.2.4).
enum AuthStatus {
  /// Still restoring a persisted session from secure storage. The router parks on the
  /// splash route while in this state so a returning user never sees a login flash.
  unknown,
  authenticated,
  unauthenticated,
}

/// Tracks session state for the whole app.
///
/// Sole source of truth for the router's guard (task 1.2.8). Rather than tracking
/// sign-in/sign-out call sites by hand it mirrors the SDK's `onAuthStateChange` stream,
/// so a session that expires or is refreshed in the background is reflected here too —
/// and signing out anywhere lands the user back on login.
class AuthController extends StateNotifier<AuthStatus> {
  AuthController(this._repository) : super(AuthStatus.unknown) {
    _restore();
  }

  final AuthRepository _repository;
  StreamSubscription<void>? _subscription;

  void _restore() {
    // `Supabase.initialize` has already rehydrated any persisted session by the time
    // this runs, so the first read is authoritative rather than a guess.
    state = _statusFor(_repository.currentSession != null);
    _subscription = _repository.onAuthStateChange.listen(
      (event) => state = _statusFor(event.session != null),
      // A stream error must not strand the app in `unknown` (an infinite splash);
      // treat it as signed-out so the user can retry from the login screen.
      onError: (_) => state = AuthStatus.unauthenticated,
    );
  }

  AuthStatus _statusFor(bool hasSession) =>
      hasSession ? AuthStatus.authenticated : AuthStatus.unauthenticated;

  /// Sign out (task 1.2.9). The stream listener above flips state and the router
  /// guard redirects — no manual navigation needed at the call site.
  Future<void> signOut() => _repository.signOut();

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthStatus>((ref) {
      return AuthController(ref.watch(authRepositoryProvider));
    });
