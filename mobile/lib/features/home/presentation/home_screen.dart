import 'package:flutter/material.dart';

import 'package:mybill/core/constants/app_constants.dart';

/// Temporary landing screen for the app shell (task 1.1.3).
///
/// Replaced by the real authenticated Dashboard (MyBill.md §7) once auth (1.2.x) and
/// the bills/analytics features land. Exists so the app is runnable and testable now.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.appName)),
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
            ],
          ),
        ),
      ),
    );
  }
}
