import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mybill/core/constants/app_constants.dart';
import 'package:mybill/core/router/app_router.dart';
import 'package:mybill/features/auth/application/auth_controller.dart';
import 'package:mybill/features/bills/application/bills_providers.dart';
import 'package:mybill/features/bills/presentation/bill_format.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Home: the caller's bills, newest first (MyBill.md §7). The list backs the main flow —
/// tap a bill to see its parsed items, or scan a new one.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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
    final bills = ref.watch(receiptsListProvider);

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
      body: bills.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _EmptyOrError(
          icon: Icons.error_outline,
          title: "Couldn't load your bills",
          subtitle: 'Check your connection and try again.',
          onRetry: () => ref.invalidate(receiptsListProvider),
        ),
        data: (receipts) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(receiptsListProvider),
          child: receipts.isEmpty
              ? const _EmptyList()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: receipts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _BillTile(receipt: receipts[i]),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.scan),
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Scan receipt'),
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = receipt.date != null
        ? formatDate(receipt.date)
        : 'Uploaded ${formatDate(receipt.createdAt)}';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.receipt_long,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(receipt.storeName ?? 'Receipt'),
      subtitle: Text(subtitle),
      trailing: _Trailing(receipt: receipt),
      onTap: () => context.push(AppRoutes.billFor(receipt.id)),
    );
  }
}

/// The total once parsed, or a status chip while the receipt is still in the pipeline.
class _Trailing extends StatelessWidget {
  const _Trailing({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (receipt.status) {
      case ReceiptStatus.done:
        return Text(
          formatMoney(receipt.total),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        );
      case ReceiptStatus.failed:
        return Icon(Icons.error_outline, color: theme.colorScheme.error);
      case ReceiptStatus.pending:
      case ReceiptStatus.processing:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
    }
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    // A scroll view so RefreshIndicator still works on the empty state.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: const _EmptyOrError(
            icon: Icons.receipt_long_outlined,
            title: 'No bills yet',
            subtitle: 'Scan your first receipt to get started.',
          ),
        ),
      ),
    );
  }
}

class _EmptyOrError extends StatelessWidget {
  const _EmptyOrError({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
