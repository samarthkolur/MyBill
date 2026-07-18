// Small display formatters for bills. Kept dependency-free (no `intl`) — the app only
// needs rupee amounts and short dates.

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `₹1,234.50`. Thousands grouped Indian-style would be nicer, but plain grouping reads
/// fine for grocery totals.
String formatMoney(double? amount) {
  if (amount == null) return '—';
  return '₹${amount.toStringAsFixed(2)}';
}

/// `4 Jul 2026`.
String formatDate(DateTime? date) {
  if (date == null) return '';
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

/// A compact quantity + unit, e.g. `2 × ` prefix or `1.5 kg`. Returns an empty string for
/// a plain single unit so the UI can omit it.
String formatQuantity(double quantity, String? unit) {
  final qty = quantity == quantity.roundToDouble()
      ? quantity.toStringAsFixed(0)
      : quantity.toString();
  if (unit != null && unit.isNotEmpty) return '$qty $unit';
  if (quantity != 1) return '$qty ×';
  return '';
}
