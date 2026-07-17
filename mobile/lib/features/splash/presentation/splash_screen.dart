import 'package:flutter/material.dart';

import 'package:mybill/core/constants/app_constants.dart';

/// Shown while a persisted session is restored from secure storage (task 1.2.4).
///
/// The router parks here on [AuthStatus.unknown] and redirects once auth state
/// resolves, so this screen never navigates on its own.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(AppConstants.appName, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 32),
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
