import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mybill/core/constants/app_constants.dart';
import 'package:mybill/core/router/app_router.dart';
import 'package:mybill/features/auth/application/auth_controller.dart';
import 'package:mybill/features/bills/application/bills_providers.dart';
import 'package:mybill/features/bills/presentation/bill_format.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Home: the caller's bills grouped by store (MyBill.md §7). Tap a bill for its parsed
/// items, search across items, or scan a new receipt.
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
            icon: const Icon(Icons.search),
            tooltip: 'Search items',
            onPressed: () => context.push(AppRoutes.search),
          ),
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
              : _GroupedBills(receipts: receipts),
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

/// Bills grouped under a header per store, stores ordered by their most recent bill.
class _GroupedBills extends StatelessWidget {
  const _GroupedBills({required this.receipts});

  final List<Receipt> receipts;

  @override
  Widget build(BuildContext context) {
    // Receipts arrive newest-first; preserve that within each group.
    final groups = <String, List<Receipt>>{};
    for (final receipt in receipts) {
      // A receipt with no store yet (still processing, or store unread) collects under a
      // neutral heading rather than a misleading store name.
      final key = receipt.storeName ?? 'Not yet sorted';
      groups.putIfAbsent(key, () => []).add(receipt);
    }
    final sections = groups.entries.toList()
      ..sort(
        (a, b) => b.value.first.createdAt.compareTo(a.value.first.createdAt),
      );

    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final section in sections) ...[
          _StoreHeader(store: section.key, bills: section.value),
          for (final receipt in section.value) _BillTile(receipt: receipt),
        ],
      ],
    );
  }
}

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.store, required this.bills});

  final String store;
  final List<Receipt> bills;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spent = bills.fold<double>(0, (sum, b) => sum + (b.total ?? 0));
    final count = bills.length == 1 ? '1 bill' : '${bills.length} bills';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: [
          Icon(Icons.storefront, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              store.toUpperCase(),
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            spent > 0 ? '$count · ${formatMoney(spent)}' : count,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// One bill within a store section: its date, item count, and total (or a status hint).
class _BillTile extends StatelessWidget {
  const _BillTile({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = receipt.date ?? receipt.createdAt;
    final count = receipt.itemCount ?? 0;
    final subtitle = switch (receipt.status) {
      ReceiptStatus.done =>
        count > 0 ? '$count item${count == 1 ? '' : 's'}' : 'No items found',
      ReceiptStatus.failed => "Couldn't read this receipt",
      _ => 'Processing…',
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.receipt_long,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(formatDate(date)),
      subtitle: Text(subtitle),
      trailing: _Trailing(receipt: receipt),
      onTap: () => context.push(AppRoutes.billFor(receipt.id)),
    );
  }
}

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
