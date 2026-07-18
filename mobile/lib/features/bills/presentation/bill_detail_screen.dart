import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/features/bills/application/bills_providers.dart';
import 'package:mybill/features/bills/presentation/bill_format.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// The parsed bill: store/date/total header and the line items (MyBill.md §7).
class BillDetailScreen extends ConsumerWidget {
  const BillDetailScreen({required this.receiptId, super.key});

  final String receiptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(billDetailProvider(receiptId));

    return Scaffold(
      appBar: AppBar(title: const Text('Bill')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Message(
          icon: Icons.error_outline,
          text: "Couldn't load this bill.",
          onRetry: () => ref.invalidate(billDetailProvider(receiptId)),
        ),
        data: (bill) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(billDetailProvider(receiptId)),
          child: _BillBody(bill: bill),
        ),
      ),
    );
  }
}

class _BillBody extends StatelessWidget {
  const _BillBody({required this.bill});

  final BillDetail bill;

  @override
  Widget build(BuildContext context) {
    final receipt = bill.receipt;
    final items = bill.items;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Header(receipt: receipt, itemCount: items.length),
        const SizedBox(height: 16),
        if (receipt.status == ReceiptStatus.failed)
          const _Message(
            icon: Icons.error_outline,
            text: "We couldn't read this receipt.",
          )
        else if (items.isEmpty)
          const _Message(
            icon: Icons.hourglass_empty,
            text: 'No items yet — this bill may still be processing.',
          )
        else
          ...items.map((item) => _ItemTile(item: item)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.receipt, required this.itemCount});

  final Receipt receipt;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (receipt.date != null) formatDate(receipt.date),
      if (itemCount > 0) '$itemCount item${itemCount == 1 ? '' : 's'}',
      if (receipt.paymentMethod != null) receipt.paymentMethod!,
    ].join('  ·  ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    receipt.storeName ?? 'Receipt',
                    style: theme.textTheme.titleLarge,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (receipt.total != null)
              Text(
                formatMoney(receipt.total),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final ReceiptItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantity = formatQuantity(item.quantity, item.unit);
    final meta = [
      if (quantity.isNotEmpty) quantity,
      if (item.category != null) item.category!,
    ].join('  ·  ');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(item.name),
      subtitle: meta.isEmpty ? null : Text(meta),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A low-confidence line is flagged so the user knows to double-check it.
          if (item.needsReview)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                Icons.help_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
            ),
          Text(formatMoney(item.totalPrice), style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.onRetry});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}
