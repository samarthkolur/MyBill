import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mybill/core/network/api_client.dart';
import 'package:mybill/features/scan/application/scan_controller.dart';
import 'package:mybill/features/scan/data/image_pipeline.dart';
import 'package:mybill/features/scan/data/receipts_repository.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Returns a canned image (or null to simulate the user backing out of the picker).
class _FakePipeline implements ImagePipeline {
  _FakePipeline({this.result, this.throws = false});

  final File? result;
  final bool throws;

  @override
  Future<File?> capture(ImageSourceKind source) async {
    if (throws) throw Exception('picker exploded');
    return result;
  }

  @override
  Future<File> compress(File source) async => source;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepository implements ReceiptsRepository {
  _FakeRepository({this.error, this.emitProgress = const []});

  final Object? error;
  final List<double> emitProgress;

  @override
  Future<Receipt> upload(
    File image, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    for (final p in emitProgress) {
      onProgress?.call(p);
    }
    if (error != null) throw error!;
    return Receipt(
      id: 'r1',
      status: ReceiptStatus.pending,
      imageUrl: 'user/r1/original.jpg',
      createdAt: DateTime.utc(2026),
    );
  }
}

ScanController buildController({
  File? picked,
  bool pickerThrows = false,
  Object? uploadError,
  List<double> progress = const [],
}) => ScanController(
  _FakePipeline(result: picked, throws: pickerThrows),
  _FakeRepository(error: uploadError, emitProgress: progress),
);

DioException apiError(String code, String message, {int? status}) =>
    DioException(
      requestOptions: RequestOptions(path: '/receipts/upload'),
      error: ApiException(code: code, message: message, statusCode: status),
    );

void main() {
  late File image;

  setUp(() async {
    image = File(
      '${Directory.systemTemp.path}/scan_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await image.writeAsBytes(List.filled(16, 0));
  });

  tearDown(() async {
    if (image.existsSync()) await image.delete();
  });

  test('starts idle', () {
    expect(buildController().state.stage, ScanStage.idle);
  });

  test('picking an image moves to ready', () async {
    final controller = buildController(picked: image);
    await controller.pick(ImageSourceKind.camera);

    expect(controller.state.stage, ScanStage.ready);
    expect(controller.state.image, isNotNull);
    expect(controller.state.error, isNull);
  });

  test('backing out of the picker returns to idle without an error', () async {
    final controller = buildController(picked: null);
    await controller.pick(ImageSourceKind.camera);

    // A cancellation is not a failure — the user should see no error surface.
    expect(controller.state.stage, ScanStage.idle);
    expect(controller.state.error, isNull);
  });

  test('a picker crash surfaces a permissions hint', () async {
    final controller = buildController(pickerThrows: true);
    await controller.pick(ImageSourceKind.camera);

    expect(controller.state.stage, ScanStage.idle);
    expect(controller.state.error, contains('permission'));
  });

  test('successful upload reports progress then success', () async {
    final controller = buildController(picked: image, progress: [0.5, 1.0]);
    await controller.pick(ImageSourceKind.camera);
    await controller.upload();

    expect(controller.state.stage, ScanStage.success);
    expect(controller.state.receipt?.status, ReceiptStatus.pending);
    expect(controller.state.progress, 1.0);
  });

  test('a 415 is surfaced as non-retryable', () async {
    final controller = buildController(
      picked: image,
      uploadError: apiError(
        'unsupported_media_type',
        'That file type is not supported.',
        status: 415,
      ),
    );
    await controller.pick(ImageSourceKind.camera);
    await controller.upload();

    // Returns to ready (image kept) so the user can retake rather than lose the photo.
    expect(controller.state.stage, ScanStage.ready);
    expect(controller.state.error, 'That file type is not supported.');
    expect(controller.state.isRetryable, isFalse);
  });

  test('a network error is retryable and keeps the image', () async {
    final controller = buildController(
      picked: image,
      uploadError: apiError(
        'network_error',
        'No connection. Check your network.',
      ),
    );
    await controller.pick(ImageSourceKind.camera);
    await controller.upload();

    expect(controller.state.stage, ScanStage.ready);
    expect(controller.state.isRetryable, isTrue);
    expect(controller.state.image, isNotNull);
  });

  test('reset clears everything for the next receipt', () async {
    final controller = buildController(picked: image);
    await controller.pick(ImageSourceKind.camera);
    controller.reset();

    expect(controller.state.stage, ScanStage.idle);
    expect(controller.state.image, isNull);
    expect(controller.state.receipt, isNull);
  });
}
