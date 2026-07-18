import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import 'package:mybill/core/network/api_client.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Uploads receipt images to the backend (task 1.3.5).
class ReceiptsRepository {
  const ReceiptsRepository(this._dio);

  final Dio _dio;

  /// Uploads [image] as a **new** bill and returns the created `pending` receipt.
  ///
  /// [onProgress] reports 0.0–1.0 for the progress UI. The pipeline always hands us
  /// JPEG, and the content type is stated explicitly because the backend validates it
  /// (415 on anything outside JPEG/PNG/WebP) rather than sniffing the bytes.
  Future<Receipt> upload(
    File image, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) => _post('/receipts/upload', image, onProgress, cancelToken);

  /// Appends [image] to an existing bill as its next page (decision 24).
  ///
  /// The server assigns the page number. Returns the receipt with all of its pages.
  Future<Receipt> addImage(
    String receiptId,
    File image, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) => _post('/receipts/$receiptId/images', image, onProgress, cancelToken);

  /// Fetch a single receipt by id — the processing-status poll.
  ///
  /// The processing screen calls this on an interval, reading [Receipt.status] until it
  /// settles on `done` or `failed`.
  Future<Receipt> get(String receiptId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/receipts/$receiptId',
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException(
        code: 'bad_response',
        message: 'The server returned an unexpected response.',
      );
    }
    return Receipt.fromJson(data);
  }

  /// The parsed line items of a receipt (bill detail).
  Future<List<ReceiptItem>> items(String receiptId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/receipts/$receiptId/items',
    );
    final data = response.data?['data'];
    if (data is! List) {
      throw const ApiException(
        code: 'bad_response',
        message: 'The server returned an unexpected response.',
      );
    }
    return data
        .map((i) => ReceiptItem.fromJson(i as Map<String, dynamic>))
        .toList();
  }

  /// The caller's receipts, newest first — the choices for "add to an existing bill".
  Future<List<Receipt>> list({int limit = 20}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/receipts',
      queryParameters: {'limit': limit},
    );
    final data = response.data?['data'];
    if (data is! List) {
      throw const ApiException(
        code: 'bad_response',
        message: 'The server returned an unexpected response.',
      );
    }
    return data
        .map((r) => Receipt.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Shared multipart POST — upload and add-page differ only by path.
  Future<Receipt> _post(
    String path,
    File image,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  ) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        image.path,
        filename: image.uri.pathSegments.last,
        contentType: MediaType('image', 'jpeg'),
      ),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: form,
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        // total is -1 when the length isn't known; report nothing rather than divide.
        if (total > 0) onProgress?.call(sent / total);
      },
    );

    final data = response.data?['data'];
    if (data is! Map<String, dynamic>) {
      throw const ApiException(
        code: 'bad_response',
        message: 'The server returned an unexpected response.',
      );
    }
    return Receipt.fromJson(data);
  }
}

final receiptsRepositoryProvider = Provider<ReceiptsRepository>((ref) {
  return ReceiptsRepository(ref.watch(apiClientProvider));
});
