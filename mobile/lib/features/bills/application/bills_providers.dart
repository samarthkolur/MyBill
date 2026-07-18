import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/features/scan/data/receipts_repository.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// The caller's receipts, newest first — the home bills list. Auto-disposed so it refetches
/// when the user returns to home (e.g. after a new scan finishes).
final receiptsListProvider = FutureProvider.autoDispose<List<Receipt>>((ref) {
  return ref.watch(receiptsRepositoryProvider).list();
});

/// A bill and its parsed line items, for the detail screen.
class BillDetail {
  const BillDetail(this.receipt, this.items);

  final Receipt receipt;
  final List<ReceiptItem> items;
}

/// One bill's detail, keyed by receipt id. Fetches the receipt (parsed summary) and its
/// line items.
final billDetailProvider = FutureProvider.autoDispose
    .family<BillDetail, String>((ref, receiptId) async {
      final repo = ref.watch(receiptsRepositoryProvider);
      final receipt = await repo.get(receiptId);
      final items = await repo.items(receiptId);
      return BillDetail(receipt, items);
    });
