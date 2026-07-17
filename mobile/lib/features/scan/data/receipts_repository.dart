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

  /// Uploads [image] and returns the created `pending` receipt.
  ///
  /// [onProgress] reports 0.0–1.0 for the progress UI. The pipeline always hands us
  /// JPEG, and the content type is stated explicitly because the backend validates it
  /// (415 on anything outside JPEG/PNG/WebP) rather than sniffing the bytes.
  Future<Receipt> upload(
    File image, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        image.path,
        filename: image.uri.pathSegments.last,
        contentType: MediaType('image', 'jpeg'),
      ),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/receipts/upload',
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
