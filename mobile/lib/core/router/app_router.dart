import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mybill/features/auth/application/auth_controller.dart';
import 'package:mybill/features/auth/presentation/forgot_password_screen.dart';
import 'package:mybill/features/auth/presentation/login_screen.dart';
import 'package:mybill/features/auth/presentation/signup_screen.dart';
import 'package:mybill/features/home/presentation/home_screen.dart';
import 'package:mybill/features/processing/presentation/processing_screen.dart';
import 'package:mybill/features/scan/presentation/scan_screen.dart';
import 'package:mybill/features/splash/presentation/splash_screen.dart';

/// Route path constants — referenced by name so navigation call-sites don't hard-code
/// string literals. Scan/bills/etc. routes are added as their features land.
class AppRoutes {
  const AppRoutes._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String signUp = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String home = '/';
  static const String scan = '/scan';
  static const String processing = '/processing';

  /// Build the processing route for a specific receipt.
  static String processingFor(String receiptId) => '$processing/$receiptId';

  /// Routes reachable while signed out. Everything else requires a session.
  static const Set<String> unauthenticated = {login, signUp, forgotPassword};
}

/// The app's [GoRouter], including the auth guard (task 1.2.8).
///
/// The guard is one `redirect` rule rather than checks scattered across screens, so a
/// newly added route is protected by default — exposing it means opting into
/// [AppRoutes.unauthenticated]. Screens therefore never navigate on sign-in/sign-out
/// themselves; they change auth state and the guard reacts.
final routerProvider = Provider<GoRouter>((ref) {
  // Bridges auth state into a Listenable so go_router re-evaluates `redirect` when the
  // session changes. The router is built once — `ref.watch` here would rebuild it on
  // every auth change and throw away navigation state.
  final refresh = ValueNotifier<AuthStatus>(ref.read(authControllerProvider));
  ref.listen<AuthStatus>(
    authControllerProvider,
    (_, next) => refresh.value = next,
  );
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final onSplash = location == AppRoutes.splash;
      final onAuthRoute = AppRoutes.unauthenticated.contains(location);

      switch (status) {
        // Session restore still in flight — hold on the splash rather than guess and
        // flash the login screen at a user who is already signed in.
        case AuthStatus.unknown:
          return onSplash ? null : AppRoutes.splash;
        case AuthStatus.unauthenticated:
          return onAuthRoute ? null : AppRoutes.login;
        case AuthStatus.authenticated:
          // Signed-in users have no business on the splash or the auth screens.
          return (onSplash || onAuthRoute) ? AppRoutes.home : null;
      }
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        name: 'signup',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.scan,
        name: 'scan',
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.processing}/:receiptId',
        name: 'processing',
        builder: (context, state) =>
            ProcessingScreen(receiptId: state.pathParameters['receiptId']!),
      ),
    ],
  );
});
