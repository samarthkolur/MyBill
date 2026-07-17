import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/core/constants/app_constants.dart';
import 'package:mybill/features/auth/application/auth_controller.dart';
import 'package:mybill/features/auth/data/auth_repository.dart';

/// Temporary landing screen for the app shell (task 1.1.3), now behind the auth guard.
///
/// Replaced by the real authenticated Dashboard (MyBill.md §7) once the bills/analytics
/// features land. Exists so the app is runnable and testable now.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Logout (task 1.2.9). Clears the token, revokes the Supabase session, and lets the
  /// router's guard redirect — no manual navigation here.
  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not sign out. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final email = ref.watch(authRepositoryProvider).currentSession?.user.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('MyBill', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Grocery Bill Intelligence',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (email != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Signed in as $email',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
