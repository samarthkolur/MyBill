import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mybill/app.dart';
import 'package:mybill/core/constants/app_constants.dart';
import 'package:mybill/core/storage/secure_local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail with an actionable message rather than an opaque SDK error deeper in the app.
  if (!AppConstants.supabaseConfigured) {
    throw StateError(
      'Supabase is not configured. Run with '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... '
      '(see mobile/README.md).',
    );
  }

  // Rehydrates any persisted session before the first frame, so AuthController's
  // initial read is authoritative and the splash resolves without a login flash.
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      // Tokens live in the platform keystore, not plain-text SharedPreferences.
      localStorage: SecureLocalStorage(),
    ),
  );

  // ProviderScope is the root of Riverpod's state — every provider lives under it.
  runApp(const ProviderScope(child: MyBillApp()));
}
