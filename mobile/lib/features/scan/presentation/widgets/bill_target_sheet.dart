import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/features/scan/application/scan_controller.dart';
import 'package:mybill/features/scan/data/receipts_repository.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// The caller's recent receipts, for the "add to an existing bill" picker.
///
/// autoDispose so the list is re-fetched each time the sheet opens — a bill created
/// moments ago must appear, and a cached list would hide it.
final recentReceiptsProvider = FutureProvider.autoDispose<List<Receipt>>((ref) {
  return ref.watch(receiptsRepositoryProvider).list();
});

/// Lets the user send the captured page to a new bill or an existing one (decision 24).
///
/// Returns the chosen [ScanTarget], or null if dismissed.
Future<ScanTarget?> showBillTargetSheet(BuildContext context) {
  return showModalBottomSheet<ScanTarget>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _BillTargetSheet(),
  );
}

class _BillTargetSheet extends ConsumerWidget {
  const _BillTargetSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final receipts = ref.watch(recentReceiptsProvider);

    return SafeArea(
      child: ConstrainedBox(
        // Half-height: the sheet is a chooser, not a full browser.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Where should this page go?',
                style: theme.textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.add,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              title: const Text('New bill'),
              subtitle: const Text('Start a separate receipt'),
              onTap: () => Navigator.pop(context, const ScanTarget.newBill()),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                'Or add to an existing bill',
                style: theme.textTheme.labelLarge,
              ),
            ),
            Flexible(
              child: receipts.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                // The sheet is still usable when the list fails — "New bill" above always
                // works, so this degrades rather than blocking the upload.
                error: (_, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Couldn't load your bills. You can still start a new one.",
                    textAlign: TextAlign.center,
                  ),
                ),
                data: (items) => items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No bills yet — this will be your first.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _ReceiptTile(receipt: items[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    // Until OCR runs (Phase 2) there's no store or total to show, so a bill is
    // identified by when it was created and how many pages it already has.
    final created = receipt.createdAt.toLocal();
    final label =
        'Bill from ${created.day}/${created.month}/${created.year} '
        '${created.hour.toString().padLeft(2, '0')}:'
        '${created.minute.toString().padLeft(2, '0')}';
    final pages = receipt.pageCount == 1
        ? '1 page'
        : '${receipt.pageCount} pages';

    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
      title: Text(label),
      subtitle: Text('$pages · ${receipt.status.name}'),
      onTap: () => Navigator.pop(
        context,
        ScanTarget.existing(receiptId: receipt.id, label: label),
      ),
    );
  }
}
