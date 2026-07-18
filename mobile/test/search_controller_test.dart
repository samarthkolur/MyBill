import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybill/core/network/api_client.dart';
import 'package:mybill/features/scan/data/receipts_repository.dart';
import 'package:mybill/features/scan/domain/receipt.dart';
import 'package:mybill/features/search/application/search_controller.dart';

class _FakeRepository implements ReceiptsRepository {
  _FakeRepository({this.results = const [], this.throws = false});

  final List<ItemSearchResult> results;
  final bool throws;
  String? lastQuery;

  @override
  Future<List<ItemSearchResult>> searchItems(
    String query, {
    int limit = 50,
  }) async {
    lastQuery = query;
    if (throws) throw const ApiException(code: 'network_error', message: 'x');
    return results;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ItemSearchResult _result(String name) => ItemSearchResult(
  id: name,
  receiptId: 'r1',
  name: name,
  quantity: 1,
  totalPrice: 10,
);

void main() {
  test('a query returns results', () async {
    final repo = _FakeRepository(results: [_result('Amul Milk')]);
    final controller = SearchController(repo);

    await controller.runSearch('milk');

    expect(controller.state.value, isNotNull);
    expect(controller.state.value!.single.name, 'Amul Milk');
    expect(repo.lastQuery, 'milk');
  });

  test(
    'a blank query resets to empty without hitting the repository',
    () async {
      final repo = _FakeRepository(results: [_result('X')]);
      final controller = SearchController(repo);

      await controller.runSearch('   ');

      expect(controller.state.value, isEmpty);
      expect(repo.lastQuery, isNull);
    },
  );

  test('a failure surfaces as an error state', () async {
    final controller = SearchController(_FakeRepository(throws: true));

    await controller.runSearch('milk');

    expect(controller.state.hasError, isTrue);
  });
}
