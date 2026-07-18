import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mybill/core/router/app_router.dart';
import 'package:mybill/features/bills/application/bills_providers.dart';
import 'package:mybill/features/processing/application/processing_controller.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Shown after an upload while the OCR pipeline reads the receipt (MyBill.md §6).
///
/// Polls the status endpoint (via [ProcessingController]) and animates a "reading" state
/// until the receipt settles on done/failed, then offers the next step. Bill detail is
/// Phase 3, so a successful parse currently returns the user home.
class ProcessingScreen extends ConsumerWidget {
  const ProcessingScreen({required this.receiptId, super.key});

  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(processingControllerProvider(receiptId));
    final controller = ref.read(
      processingControllerProvider(receiptId).notifier,
    );

    // Refresh the bills list so the just-finished receipt appears, then navigate. Both
    // paths invalidate: home is still mounted under this screen, so its cached list would
    // otherwise miss the new bill.
    void goToBills() {
      ref.invalidate(receiptsListProvider);
      context.go(AppRoutes.home);
    }

    void viewBill() {
      ref.invalidate(receiptsListProvider);
      context.pushReplacement(AppRoutes.billFor(receiptId));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reading receipt')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: switch (state.phase) {
              ProcessingPhase.working => _Working(status: state.status),
              ProcessingPhase.done => _Done(
                onContinue: viewBill,
                onHome: goToBills,
              ),
              ProcessingPhase.failed => _Failed(
                message: state.error,
                onRescan: () => context.go(AppRoutes.scan),
                onHome: goToBills,
              ),
              ProcessingPhase.timedOut || ProcessingPhase.error => _Stalled(
                message: state.error,
                onRetry: controller.retry,
                onHome: goToBills,
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// The animated "reading…" state: a receipt icon pulsing behind an indeterminate ring.
class _Working extends StatefulWidget {
  const _Working({required this.status});

  final ReceiptStatus status;

  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.status == ReceiptStatus.processing
        ? 'Reading the items…'
        : 'Queued for processing…';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 120,
          width: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                height: 120,
                width: 120,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              // Gentle scale/fade pulse on the icon, tied to the same controller.
              ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.1).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: FadeTransition(
                  opacity: Tween(begin: 0.55, end: 1.0).animate(_pulse),
                  child: Icon(
                    Icons.receipt_long,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text('Reading your receipt', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This usually takes a few seconds. You can leave this screen — it keeps going.',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.onContinue, required this.onHome});

  final VoidCallback onContinue;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text('Receipt ready', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'We pulled out the items and totals.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.receipt_long),
          label: const Text('View bill'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          ),
        ),
        TextButton(onPressed: onHome, child: const Text('Back to home')),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.onRescan,
    required this.onHome,
  });

  final String? message;
  final VoidCallback onRescan;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 72, color: theme.colorScheme.error),
        const SizedBox(height: 24),
        Text("Couldn't read it", style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          message ?? 'Something went wrong reading this receipt.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: onRescan,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Scan again'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          ),
        ),
        TextButton(onPressed: onHome, child: const Text('Back to home')),
      ],
    );
  }
}

class _Stalled extends StatelessWidget {
  const _Stalled({
    required this.message,
    required this.onRetry,
    required this.onHome,
  });

  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.hourglass_empty, size: 72, color: theme.colorScheme.outline),
        const SizedBox(height: 24),
        Text('Still working', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          message ?? 'This is taking longer than usual.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: onRetry,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
          child: const Text('Keep checking'),
        ),
        TextButton(onPressed: onHome, child: const Text('Back to home')),
      ],
    );
  }
}
