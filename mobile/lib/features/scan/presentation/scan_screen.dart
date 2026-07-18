import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mybill/core/router/app_router.dart';
import 'package:mybill/features/auth/presentation/widgets/auth_error_banner.dart';
import 'package:mybill/features/scan/application/scan_controller.dart';
import 'package:mybill/features/scan/data/image_pipeline.dart';
import 'package:mybill/features/scan/presentation/widgets/bill_target_sheet.dart';

/// Scan screen — capture or pick a receipt, review it, upload (tasks 1.3.1, 1.3.5).
///
/// Capture uses the OS camera/gallery via `image_picker` rather than an in-app
/// viewfinder (design decision 23).
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);

    ref.listen<ScanState>(scanControllerProvider, (previous, next) {
      if (previous?.stage == ScanStage.success ||
          next.stage != ScanStage.success) {
        return;
      }
      final receipt = next.receipt;
      if (receipt == null) return;
      // Whether this started a new bill or added a page to an existing one, the receipt is
      // now (re)processing — go watch it. pushReplacement so back from processing (or the
      // bill) lands on home, not this capture screen.
      context.pushReplacement(AppRoutes.processingFor(receipt.id));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan receipt'),
        actions: [
          if (state.image != null && !state.isBusy)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Discard',
              onPressed: controller.reset,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _Preview(state: state)),
            _Actions(state: state, controller: controller),
          ],
        ),
      ),
    );
  }
}

/// The image under review, or the empty-state prompt.
class _Preview extends StatelessWidget {
  const _Preview({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.stage == ScanStage.preparing && state.image == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.image == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Photograph your receipt',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Lay it flat in good light. You can crop it on the next screen.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // Receipts are tall and thin — contain, so nothing is cropped out of view.
        child: Image.file(
          state.image!,
          fit: BoxFit.contain,
          width: double.infinity,
        ),
      ),
    );
  }
}

/// Bottom action area: source buttons, or review + upload controls.
class _Actions extends StatelessWidget {
  const _Actions({required this.state, required this.controller});

  final ScanState state;
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.error != null) ...[
            AuthErrorBanner(message: state.error!),
            const SizedBox(height: 12),
          ],
          if (state.stage == ScanStage.uploading) ...[
            LinearProgressIndicator(
              // Indeterminate until the first byte, so the bar never sits dead at 0.
              value: state.progress > 0 ? state.progress : null,
            ),
            const SizedBox(height: 8),
            Text('Uploading… ${(state.progress * 100).round()}%'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: controller.cancelUpload,
              child: const Text('Cancel'),
            ),
          ] else if (state.image == null)
            _SourceButtons(state: state, controller: controller)
          else ...[
            if (state.stage != ScanStage.success)
              _TargetPicker(state: state, controller: controller),
            _ReviewButtons(state: state, controller: controller),
          ],
        ],
      ),
    );
  }
}

/// Shows where the page will go and lets the user change it (decision 24).
///
/// Defaults to a new bill, so the common case is one tap — choosing an existing bill is
/// opt-in rather than a prompt on every scan.
class _TargetPicker extends StatelessWidget {
  const _TargetPicker({required this.state, required this.controller});

  final ScanState state;
  final ScanController controller;

  Future<void> _choose(BuildContext context) async {
    final target = await showBillTargetSheet(context);
    if (target != null) controller.setTarget(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = state.target;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: state.isBusy ? null : () => _choose(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(
                target.isNewBill
                    ? Icons.add_circle_outline
                    : Icons.playlist_add_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  target.isNewBill
                      ? 'New bill'
                      : 'Adding to ${target.label ?? 'an existing bill'}',
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: state.isBusy ? null : () => _choose(context),
                child: const Text('Change'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceButtons extends StatelessWidget {
  const _SourceButtons({required this.state, required this.controller});

  final ScanState state;
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: state.isBusy
                ? null
                : () => controller.pick(ImageSourceKind.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take photo'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: state.isBusy
                ? null
                : () => controller.pick(ImageSourceKind.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Gallery'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewButtons extends StatelessWidget {
  const _ReviewButtons({required this.state, required this.controller});

  final ScanState state;
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    if (state.stage == ScanStage.success) {
      return FilledButton.icon(
        onPressed: controller.reset,
        icon: const Icon(Icons.add),
        label: const Text('Scan another'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: state.isBusy
                ? null
                : () => controller.pick(ImageSourceKind.camera),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Retake'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: state.isBusy ? null : controller.upload,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(state.error != null ? 'Try again' : 'Upload'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}
