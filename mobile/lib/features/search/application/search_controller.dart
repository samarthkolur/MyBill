import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/features/scan/data/receipts_repository.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Drives item search. Holds the results as an [AsyncValue]; the screen debounces the
/// keystrokes and calls [runSearch]. A blank query resets to an empty result set.
class SearchController
    extends StateNotifier<AsyncValue<List<ItemSearchResult>>> {
  SearchController(this._repository) : super(const AsyncValue.data([]));

  final ReceiptsRepository _repository;

  Future<void> runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _repository.searchItems(trimmed));
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }
}

final searchControllerProvider =
    StateNotifierProvider.autoDispose<
      SearchController,
      AsyncValue<List<ItemSearchResult>>
    >((ref) => SearchController(ref.watch(receiptsRepositoryProvider)));
