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

/// A receipt and its pages (task 1.3.5, decision 24).
///
/// A receipt holds 1..N pages — a long receipt is photographed in several shots and the
/// pages are appended to the same bill. Parsed fields (store, date, totals, line items)
/// don't exist until OCR completes in Phase 2, so this mirrors only what the upload and
/// list endpoints return.
class Receipt {
  const Receipt({
    required this.id,
    required this.status,
    required this.createdAt,
    this.images = const [],
  });

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
    id: json['id'] as String,
    status: ReceiptStatus.parse(json['status'] as String?),
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
    images: ((json['images'] as List<dynamic>?) ?? const [])
        .map((i) => ReceiptImage.fromJson(i as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final ReceiptStatus status;
  final DateTime createdAt;
  final List<ReceiptImage> images;

  int get pageCount => images.length;
}
