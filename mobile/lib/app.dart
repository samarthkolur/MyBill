import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/core/constants/app_constants.dart';
import 'package:mybill/core/router/app_router.dart';
import 'package:mybill/core/theme/app_theme.dart';

/// Root application widget.
///
/// Wires the [GoRouter] (from [routerProvider]) into a [MaterialApp.router] and
/// applies the app theme. Kept thin — navigation and theming are the only concerns
/// here; feature logic lives under `lib/features/`.
class MyBillApp extends ConsumerWidget {
  const MyBillApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
