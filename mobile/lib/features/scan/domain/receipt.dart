/// Processing lifecycle of a receipt. Mirrors the backend's `ReceiptStatus` and the
/// database CHECK constraint.
enum ReceiptStatus {
  pending,
  processing,
  done,
  failed;

  /// Unknown values map to [pending] rather than throwing: the backend may add a state
  /// (Phase 2 OCR) before the app ships an update, and a new status is not a reason to
  /// fail an upload the server already accepted.
  static ReceiptStatus parse(String? value) => ReceiptStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ReceiptStatus.pending,
  );
}

/// One page of a receipt.
class ReceiptImage {
  const ReceiptImage({
    required this.id,
    required this.imageUrl,
    required this.pageNumber,
  });

  factory ReceiptImage.fromJson(Map<String, dynamic> json) => ReceiptImage(
    id: json['id'] as String,
    // The storage object key, not a fetchable URL — signed URLs are minted on read
    // in Phase 3 (design decision 19).
    imageUrl: json['image_url'] as String,
    pageNumber: json['page_number'] as int? ?? 1,
  );

  final String id;
  final String imageUrl;
  final int pageNumber;
}

/// A parsed line item on a receipt (`GET /receipts/{id}/items`).
class ReceiptItem {
  const ReceiptItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.brand,
    this.category,
    this.unit,
    this.needsReview = false,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) => ReceiptItem(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    brand: json['brand'] as String?,
    category: json['category'] as String?,
    quantity: _toDouble(json['quantity']) ?? 1,
    unit: json['unit'] as String?,
    unitPrice: _toDouble(json['unit_price']) ?? 0,
    totalPrice: _toDouble(json['total_price']) ?? 0,
    needsReview: json['needs_review'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String? brand;
  final String? category;
  final double quantity;
  final String? unit;
  final double unitPrice;
  final double totalPrice;

  /// True for a low-confidence parse the UI should highlight for correction.
  final bool needsReview;
}

/// A receipt: its pages and, once OCR completes, its parsed summary (task 1.3.5,
/// decision 24; Phase 3 bill viewer).
///
/// A receipt holds 1..N pages — a long receipt is photographed in several shots and the
/// pages are appended to the same bill. The parsed summary fields are null until the
/// pipeline settles the receipt on `done`; line items are fetched separately.
class Receipt {
  const Receipt({
    required this.id,
    required this.status,
    required this.createdAt,
    this.storeName,
    this.date,
    this.time,
    this.total,
    this.tax,
    this.discount,
    this.paymentMethod,
    this.images = const [],
  });

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
    id: json['id'] as String,
    status: ReceiptStatus.parse(json['status'] as String?),
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
    storeName: json['store_name'] as String?,
    date: DateTime.tryParse(json['date'] as String? ?? ''),
    // Backend sends "HH:MM:SS"; keep just HH:MM for display.
    time: _shortTime(json['time'] as String?),
    total: _toDouble(json['total']),
    tax: _toDouble(json['tax']),
    discount: _toDouble(json['discount']),
    paymentMethod: json['payment_method'] as String?,
    images: ((json['images'] as List<dynamic>?) ?? const [])
        .map((i) => ReceiptImage.fromJson(i as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final ReceiptStatus status;
  final DateTime createdAt;

  /// Parsed summary — null until OCR completes.
  final String? storeName;
  final DateTime? date;
  final String? time;
  final double? total;
  final double? tax;
  final double? discount;
  final String? paymentMethod;

  final List<ReceiptImage> images;

  int get pageCount => images.length;
}

/// Parse a numeric field that the backend may serialise as either a JSON number or a
/// string (pydantic renders Decimal as a string).
double? _toDouble(Object? value) => switch (value) {
  null => null,
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

/// "18:42:00" → "18:42"; null/blank stays null.
String? _shortTime(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split(':');
  return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : value;
}
