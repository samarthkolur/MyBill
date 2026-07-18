import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybill/features/bills/presentation/bill_detail_screen.dart';
import 'package:mybill/features/scan/data/receipts_repository.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// A repository stub returning a fixed bill + items.
class _FakeRepository implements ReceiptsRepository {
  _FakeRepository({required this.receipt, required this.lineItems});

  final Receipt receipt;
  final List<ReceiptItem> lineItems;

  @override
  Future<Receipt> get(String receiptId) async => receipt;

  @override
  Future<List<ReceiptItem>> items(String receiptId) async => lineItems;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [receiptsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: BillDetailScreen(receiptId: 'r1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the store header, total and line items', (tester) async {
    final repo = _FakeRepository(
      receipt: Receipt(
        id: 'r1',
        status: ReceiptStatus.done,
        createdAt: DateTime.utc(2026, 7, 4),
        storeName: 'DMart',
        date: DateTime.utc(2026, 7, 4),
        total: 438,
      ),
      lineItems: const [
        ReceiptItem(
          id: 'i1',
          name: 'Amul Milk',
          category: 'Dairy',
          quantity: 1,
          unitPrice: 62,
          totalPrice: 62,
        ),
        ReceiptItem(
          id: 'i2',
          name: 'Brown Bread',
          quantity: 1,
          unitPrice: 40,
          totalPrice: 40,
        ),
      ],
    );

    await _pump(tester, repo);

    expect(find.text('DMart'), findsOneWidget);
    expect(find.text('₹438.00'), findsOneWidget); // header total
    expect(find.text('Amul Milk'), findsOneWidget);
    expect(find.text('Brown Bread'), findsOneWidget);
    expect(find.text('₹62.00'), findsOneWidget); // an item total
  });

  testWidgets('flags a low-confidence item for review', (tester) async {
    final repo = _FakeRepository(
      receipt: Receipt(
        id: 'r1',
        status: ReceiptStatus.done,
        createdAt: DateTime.utc(2026),
        storeName: 'DMart',
      ),
      lineItems: const [
        ReceiptItem(
          id: 'i1',
          name: 'Smudged',
          quantity: 1,
          unitPrice: 10,
          totalPrice: 10,
          needsReview: true,
        ),
      ],
    );

    await _pump(tester, repo);

    expect(find.text('Smudged'), findsOneWidget);
    // The review flag icon is shown.
    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  testWidgets('shows an empty-state when there are no items yet', (
    tester,
  ) async {
    final repo = _FakeRepository(
      receipt: Receipt(
        id: 'r1',
        status: ReceiptStatus.processing,
        createdAt: DateTime.utc(2026),
      ),
      lineItems: const [],
    );

    await _pump(tester, repo);

    expect(find.textContaining('still be processing'), findsOneWidget);
  });
}
