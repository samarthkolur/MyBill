import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/core/network/api_client.dart';
import 'package:mybill/features/scan/data/image_pipeline.dart';
import 'package:mybill/features/scan/data/receipts_repository.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Where the scan flow currently is (tasks 1.3.1–1.3.5).
enum ScanStage {
  /// Nothing picked yet — the screen offers camera/gallery.
  idle,

  /// Picker/cropper is open, or the image is being compressed.
  preparing,

  /// An image is ready and shown for review before upload.
  ready,

  /// Upload in flight; [ScanState.progress] drives the bar.
  uploading,

  /// Upload accepted — the backend created a pending receipt.
  success,
}

/// Where the captured page should go (decision 24).
///
/// Null [receiptId] means "create a new bill"; a non-null id appends the page to that
/// existing bill — the case for a receipt too long to photograph in one shot.
class ScanTarget {
  const ScanTarget.newBill() : receiptId = null, label = null;
  const ScanTarget.existing({required String this.receiptId, this.label});

  final String? receiptId;

  /// How the target reads in the UI ("New bill" vs a description of the chosen bill).
  final String? label;

  bool get isNewBill => receiptId == null;
}

/// Immutable state of the scan screen.
class ScanState {
  const ScanState({
    this.stage = ScanStage.idle,
    this.image,
    this.progress = 0,
    this.receipt,
    this.error,
    this.isRetryable = false,
    this.target = const ScanTarget.newBill(),
  });

  final ScanStage stage;
  final File? image;
  final double progress;
  final Receipt? receipt;
  final String? error;

  /// Whether [error] is worth offering a retry for. A 415/413 is the user's problem to
  /// fix, not something a retry button can help with.
  final bool isRetryable;

  /// New bill, or an existing one to append to.
  final ScanTarget target;

  bool get isBusy =>
      stage == ScanStage.preparing || stage == ScanStage.uploading;

  ScanState copyWith({
    ScanStage? stage,
    File? image,
    double? progress,
    Receipt? receipt,
    String? error,
    bool? isRetryable,
    ScanTarget? target,
    bool clearError = false,
    bool clearImage = false,
  }) => ScanState(
    stage: stage ?? this.stage,
    image: clearImage ? null : (image ?? this.image),
    progress: progress ?? this.progress,
    receipt: receipt ?? this.receipt,
    error: clearError ? null : (error ?? this.error),
    isRetryable: isRetryable ?? this.isRetryable,
    target: target ?? this.target,
  );
}

/// Drives capture → crop → compress → upload (tasks 1.3.1, 1.3.2, 1.3.5).
class ScanController extends StateNotifier<ScanState> {
  ScanController(this._pipeline, this._repository) : super(const ScanState());

  final ImagePipeline _pipeline;
  final ReceiptsRepository _repository;
  CancelToken? _cancelToken;

  /// Pick from camera or gallery, then crop and compress (tasks 1.3.1–1.3.2).
  Future<void> pick(ImageSourceKind source) async {
    state = state.copyWith(stage: ScanStage.preparing, clearError: true);
    try {
      final image = await _pipeline.capture(source);
      // Null means the user backed out of the picker or cropper — not an error.
      if (image == null) {
        state = state.copyWith(
          stage: state.image == null ? ScanStage.idle : ScanStage.ready,
        );
        return;
      }
      state = state.copyWith(stage: ScanStage.ready, image: image, progress: 0);
    } catch (_) {
      state = state.copyWith(
        stage: ScanStage.idle,
        error: 'Could not open the image. Check camera/photo permissions.',
        isRetryable: true,
      );
    }
  }

  /// Choose whether this page starts a new bill or joins an existing one (decision 24).
  void setTarget(ScanTarget target) =>
      state = state.copyWith(target: target, clearError: true);

  /// Upload the prepared image to the chosen target (task 1.3.5).
  Future<void> upload() async {
    final image = state.image;
    if (image == null || state.stage == ScanStage.uploading) return;

    _cancelToken = CancelToken();
    state = state.copyWith(
      stage: ScanStage.uploading,
      progress: 0,
      clearError: true,
    );

    void reportProgress(double progress) {
      // A late callback after cancel/success must not resurrect the progress bar.
      if (state.stage == ScanStage.uploading) {
        state = state.copyWith(progress: progress);
      }
    }

    try {
      final target = state.target;
      final receipt = target.isNewBill
          ? await _repository.upload(
              image,
              cancelToken: _cancelToken,
              onProgress: reportProgress,
            )
          : await _repository.addImage(
              target.receiptId!,
              image,
              cancelToken: _cancelToken,
              onProgress: reportProgress,
            );
      state = state.copyWith(
        stage: ScanStage.success,
        receipt: receipt,
        progress: 1,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        state = state.copyWith(stage: ScanStage.ready, progress: 0);
        return;
      }
      final error = e.error;
      state = state.copyWith(
        stage: ScanStage.ready,
        progress: 0,
        error: error is ApiException
            ? error.message
            : 'Upload failed. Please try again.',
        isRetryable: error is ApiException ? error.isRetryable : true,
      );
    } catch (_) {
      state = state.copyWith(
        stage: ScanStage.ready,
        progress: 0,
        error: 'Upload failed. Please try again.',
        isRetryable: true,
      );
    }
  }

  void cancelUpload() => _cancelToken?.cancel('cancelled by user');

  /// Clear everything for the next receipt.
  void reset() {
    _cancelToken = null;
    state = const ScanState();
  }

  @override
  void dispose() {
    _cancelToken?.cancel('screen disposed');
    super.dispose();
  }
}

final scanControllerProvider =
    StateNotifierProvider.autoDispose<ScanController, ScanState>((ref) {
      return ScanController(
        ref.watch(imagePipelineProvider),
        ref.watch(receiptsRepositoryProvider),
      );
    });
