import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mybill/app.dart';
import 'package:mybill/features/auth/data/auth_repository.dart';
import 'package:mybill/features/bills/application/bills_providers.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Stands in for [AuthRepository] so these tests never touch the network or need
/// `Supabase.initialize`. Implements the class's implicit interface — the real one
/// keeps its `SupabaseClient` private, so only the public surface matters here.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({Session? session}) : _session = session;

  Session? _session;
  final StreamController<AuthState> _controller =
      StreamController<AuthState>.broadcast();

  @override
  Session? get currentSession => _session;

  @override
  Stream<AuthState> get onAuthStateChange => _controller.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    _session = _fakeSession();
    _controller.add(AuthState(AuthChangeEvent.signedIn, _session));
  }

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async => false;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    _session = null;
    _controller.add(AuthState(AuthChangeEvent.signedOut, null));
  }

  void dispose() => _controller.close();
}

Session _fakeSession() => Session(
  accessToken: 'fake-access-token',
  tokenType: 'bearer',
  user: User(
    id: '00000000-0000-0000-0000-000000000001',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    email: 'shopper@example.com',
    createdAt: DateTime.utc(2026).toIso8601String(),
  ),
);

Future<void> _pumpApp(
  WidgetTester tester,
  _FakeAuthRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        // Home fetches the bills list; stub it so these auth/navigation tests never hit
        // the network. An empty list renders the home empty-state.
        receiptsListProvider.overrideWith((ref) async => <Receipt>[]),
      ],
      child: const MyBillApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed-out user is redirected to the login screen', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);

    await _pumpApp(tester, repository);

    // The guard (task 1.2.8) sends an unauthenticated user to login, not home.
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Scan receipt'), findsNothing);
  });

  testWidgets('signed-in user lands on the home screen', (tester) async {
    final repository = _FakeAuthRepository(session: _fakeSession());
    addTearDown(repository.dispose);

    await _pumpApp(tester, repository);

    expect(find.text('Scan receipt'), findsOneWidget);
  });

  testWidgets('signing in from the login screen navigates to home', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);

    await _pumpApp(tester, repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'shopper@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct-horse',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // No navigation happens in the screen — the guard reacts to the session change.
    expect(find.text('Scan receipt'), findsOneWidget);
  });

  testWidgets('signing out returns the user to login (task 1.2.9)', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(session: _fakeSession());
    addTearDown(repository.dispose);

    await _pumpApp(tester, repository);
    expect(find.text('Scan receipt'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('login rejects an invalid email before submitting', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);

    await _pumpApp(tester, repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'not-an-email',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Scan receipt'), findsNothing);
  });
}
