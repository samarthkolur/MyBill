import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/app.dart';

void main() {
  // ProviderScope is the root of Riverpod's state — every provider lives under it.
  runApp(const ProviderScope(child: MyBillApp()));
}
