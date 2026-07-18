import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mybill/core/router/app_router.dart';
import 'package:mybill/features/bills/presentation/bill_format.dart';
import 'package:mybill/features/scan/domain/receipt.dart';
import 'package:mybill/features/search/application/search_controller.dart';

/// Search purchased items across all bills (MyBill.md §5). The app-bar field drives a
/// debounced query; tapping a result opens the bill it came from.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Debounce so we don't fire a request on every keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchControllerProvider.notifier).runSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _field,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Search items…',
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_field.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _field.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const _Centered('Something went wrong. Try again.'),
        data: (items) {
          if (_field.text.trim().isEmpty) {
            return const _Centered('Search for milk, rice, a brand…');
          }
          if (items.isEmpty) {
            return _Centered('No items match "${_field.text.trim()}".');
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _ResultTile(result: items[i]),
          );
        },
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final ItemSearchResult result;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (result.storeName != null) result.storeName!,
      if (result.date != null) formatDate(result.date),
      if (result.quantity != 1 || result.unit != null)
        formatQuantity(result.quantity, result.unit),
    ].where((s) => s.isNotEmpty).join('  ·  ');

    return ListTile(
      title: Text(result.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Text(formatMoney(result.totalPrice)),
      onTap: () => context.push(AppRoutes.billFor(result.receiptId)),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
