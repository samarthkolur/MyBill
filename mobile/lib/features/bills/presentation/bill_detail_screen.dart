import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/features/bills/application/bills_providers.dart';
import 'package:mybill/features/bills/presentation/bill_format.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

// Tabular figures keep the price column aligned like a printed receipt.
const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// The parsed bill, styled like an actual paper receipt (MyBill.md §7).
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
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _Receipt(bill: bill),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.bill});

  final BillDetail bill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receipt = bill.receipt;
    final items = bill.items;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(receipt: receipt),
            const SizedBox(height: 16),
            const _DashedLine(),
            const SizedBox(height: 12),
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
            else ...[
              for (final item in items) _ItemRow(item: item),
              const SizedBox(height: 12),
              const _DashedLine(),
              const SizedBox(height: 12),
              _Totals(receipt: receipt, items: items),
            ],
            const SizedBox(height: 16),
            const _DashedLine(),
            const SizedBox(height: 12),
            _Footer(receipt: receipt, itemCount: items.length),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final when = [
      if (receipt.date != null) formatDate(receipt.date),
      if (receipt.time != null) receipt.time,
    ].whereType<String>().join('  ');

    return Column(
      children: [
        Text(
          (receipt.storeName ?? 'Receipt').toUpperCase(),
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (when.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            when,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final ReceiptItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A per-unit breakdown only when it adds information (a real quantity or unit).
    final breakdown = (item.quantity != 1 || item.unit != null)
        ? '${formatQuantity(item.quantity, item.unit)} × ${formatMoney(item.unitPrice)}'
        : null;
    final meta = [
      if (breakdown != null) breakdown,
      if (item.category != null) item.category!,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(item.name, style: theme.textTheme.bodyLarge),
                    ),
                    if (item.needsReview)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.help_outline,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                      ),
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatMoney(item.totalPrice),
            style: theme.textTheme.bodyLarge?.merge(_tabular),
          ),
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.receipt, required this.items});

  final Receipt receipt;
  final List<ReceiptItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsSum = items.fold<double>(0, (sum, i) => sum + i.totalPrice);
    // The printed total when OCR found one, else the sum of the lines.
    final total = receipt.total ?? itemsSum;

    return Column(
      children: [
        _TotalRow(label: 'Subtotal', value: itemsSum),
        if (receipt.tax != null && receipt.tax! > 0)
          _TotalRow(label: 'Tax', value: receipt.tax),
        if (receipt.discount != null && receipt.discount! > 0)
          _TotalRow(label: 'Discount', value: receipt.discount),
        const SizedBox(height: 4),
        _TotalRow(
          label: 'TOTAL',
          value: total,
          style: theme.textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.style});

  final String label;
  final double? value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: base),
          Text(formatMoney(value), style: base?.merge(_tabular)),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.receipt, required this.itemCount});

  final Receipt receipt;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = [
      '$itemCount item${itemCount == 1 ? '' : 's'}',
      if (receipt.paymentMethod != null) 'Paid via ${receipt.paymentMethod}',
    ].join('  ·  ');

    return Column(
      children: [
        Text(
          line,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'via MyBill',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

/// A dashed horizontal rule, for the perforated-receipt look.
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashedLinePainter(Theme.of(context).colorScheme.outlineVariant),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
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
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.outline),
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
