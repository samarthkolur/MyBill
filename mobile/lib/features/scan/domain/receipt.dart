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

/// A receipt as returned right after upload (task 1.3.5).
///
/// Parsed fields (store, date, totals, line items) don't exist until OCR completes in
/// Phase 2, so this deliberately mirrors only what `POST /v1/receipts/upload` returns.
class Receipt {
  const Receipt({
    required this.id,
    required this.status,
    required this.imageUrl,
    required this.createdAt,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
    id: json['id'] as String,
    status: ReceiptStatus.parse(json['status'] as String?),
    // The storage object key, not a fetchable URL — signed URLs are minted on read
    // in Phase 3 (design decision 19).
    imageUrl: json['image_url'] as String,
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
  );

  final String id;
  final ReceiptStatus status;
  final String imageUrl;
  final DateTime createdAt;
}
