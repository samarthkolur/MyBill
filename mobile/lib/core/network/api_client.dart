import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/core/constants/app_constants.dart';
import 'package:mybill/features/auth/data/auth_repository.dart';

/// Error surfaced by the API layer, carrying the backend's machine-readable code.
///
/// The backend answers every route with the same envelope (`MyBill.md` §5), so failures
/// arrive as `error.code` / `error.message` rather than bare HTTP statuses. Callers
/// switch on [code]; [message] is already human-readable.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  /// True when retrying later could plausibly succeed — no network, a timeout, or a
  /// server-side fault. Client mistakes (415, 413, 401) are not retryable, so the
  /// upload queue must not spin on them.
  bool get isRetryable =>
      code == 'network_error' ||
      code == 'timeout' ||
      (statusCode != null && statusCode! >= 500);

  @override
  String toString() => 'ApiException($code): $message';
}

/// Builds the [Dio] used for all backend calls.
///
/// Attaches the caller's Supabase access token to every request. The token is read per
/// request rather than captured once, so a background refresh is picked up automatically
/// instead of pinning a stale JWT for the process lifetime.
Dio buildApiClient(AuthRepository auth) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      // Generous: an upload on a weak connection is slow but still worth finishing.
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = auth.currentSession?.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) => handler.reject(_toApiError(error)),
    ),
  );

  return dio;
}

/// Translates Dio's transport-level failures into the envelope's error vocabulary, so
/// callers handle one error type instead of both `DioException` and `ApiException`.
DioException _toApiError(DioException error) {
  final response = error.response;
  final data = response?.data;

  // The backend's envelope, when we got far enough to receive one.
  if (data is Map && data['error'] is Map) {
    final detail = data['error'] as Map;
    return error.copyWith(
      error: ApiException(
        code: (detail['code'] ?? 'unknown').toString(),
        message: (detail['message'] ?? 'Something went wrong.').toString(),
        statusCode: response?.statusCode,
      ),
    );
  }

  final (code, message) = switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => ('timeout', 'The request timed out.'),
    DioExceptionType.connectionError => (
      'network_error',
      'No connection. Check your network.',
    ),
    DioExceptionType.cancel => ('cancelled', 'The request was cancelled.'),
    _ => ('unknown', 'Something went wrong. Please try again.'),
  };

  return error.copyWith(
    error: ApiException(
      code: code,
      message: message,
      statusCode: response?.statusCode,
    ),
  );
}

final apiClientProvider = Provider<Dio>((ref) {
  return buildApiClient(ref.watch(authRepositoryProvider));
});
