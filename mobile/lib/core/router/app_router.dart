import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mybill/features/home/presentation/home_screen.dart';

/// Route path constants — referenced by name so navigation call-sites don't hard-code
/// string literals. Auth/scan/bills/etc. routes are added as their features land.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
}

/// The app's [GoRouter], exposed as a provider so route guards (task 1.2.8) can later
/// depend on auth state via `ref`.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
});
