import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mybill/features/scan/data/receipts_repository.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Where a receipt is in the OCR pipeline, from the client's point of view.
enum ProcessingPhase {
  /// Still pending/processing on the server — keep polling.
  working,

  /// Parsed successfully.
  done,

  /// The pipeline marked the receipt failed (unreadable image, parse error).
  failed,

  /// Gave up polling before the server settled — the receipt may still finish.
  timedOut,

  /// Couldn't reach the server to check (network/transient).
  error,
}

/// Immutable state of the processing screen.
class ProcessingState {
  const ProcessingState({
    this.phase = ProcessingPhase.working,
    this.status = ReceiptStatus.pending,
    this.error,
    this.isRetryable = false,
  });

  final ProcessingPhase phase;

  /// Last status read from the server, so the UI can say "processing" vs "queued".
  final ReceiptStatus status;
  final String? error;
  final bool isRetryable;

  bool get isWorking => phase == ProcessingPhase.working;

  ProcessingState copyWith({
    ProcessingPhase? phase,
    ReceiptStatus? status,
    String? error,
    bool? isRetryable,
  }) => ProcessingState(
    phase: phase ?? this.phase,
    status: status ?? this.status,
    error: error ?? this.error,
    isRetryable: isRetryable ?? this.isRetryable,
  );
}

/// Polls the status endpoint until a receipt settles on done/failed (MyBill.md §6).
///
/// Polling rather than a push channel keeps the client simple and matches the backend's
/// polling endpoint. A transient fetch error doesn't end the poll — OCR is still running,
/// so it keeps trying until the attempt budget is spent, then reports a retryable state.
class ProcessingController extends StateNotifier<ProcessingState> {
  ProcessingController(
    this._repository,
    this._receiptId, {
    Duration interval = const Duration(seconds: 2),
    int maxAttempts = 45,
  }) : _interval = interval,
       _maxAttempts = maxAttempts,
       super(const ProcessingState()) {
    _polling = _run();
  }

  final ReceiptsRepository _repository;
  final String _receiptId;
  final Duration _interval;

  /// Attempt budget: `maxAttempts * interval` is the effective timeout (~90s by default).
  final int _maxAttempts;

  bool _disposed = false;
  Future<void>? _polling;

  /// The in-flight poll loop — awaited by tests to observe the settled state.
  @visibleForTesting
  Future<void>? get settled => _polling;

  Future<void> _run() async {
    var sawServer = false;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      if (_disposed) return;
      try {
        final receipt = await _repository.get(_receiptId);
        if (_disposed) return;
        sawServer = true;

        switch (receipt.status) {
          case ReceiptStatus.done:
            state = state.copyWith(
              phase: ProcessingPhase.done,
              status: receipt.status,
            );
            return;
          case ReceiptStatus.failed:
            state = state.copyWith(
              phase: ProcessingPhase.failed,
              status: receipt.status,
              error: "We couldn't read this receipt. Try scanning it again.",
            );
            return;
          case ReceiptStatus.pending:
          case ReceiptStatus.processing:
            state = state.copyWith(status: receipt.status);
        }
      } catch (_) {
        // Transient — a dropped request while OCR runs shouldn't end the poll. Keep going
        // and let the attempt budget bound how long we try.
      }

      if (_disposed) return;
      await Future<void>.delayed(_interval);
    }

    if (_disposed) return;
    // Budget spent without a terminal status. If we never reached the server it's a
    // connection problem; otherwise the receipt is just taking longer than expected. Both
    // are retryable and the receipt may yet finish server-side.
    state = state.copyWith(
      phase: sawServer ? ProcessingPhase.timedOut : ProcessingPhase.error,
      isRetryable: true,
      error: sawServer
          ? "This is taking longer than usual. It'll keep processing in the background."
          : "Couldn't check the status. Check your connection and try again.",
    );
  }

  /// Restart polling after a timeout/error.
  void retry() {
    if (state.isWorking) return;
    state = const ProcessingState();
    _polling = _run();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One controller per receipt id, auto-disposed when the screen leaves the tree.
final processingControllerProvider = StateNotifierProvider.autoDispose
    .family<ProcessingController, ProcessingState, String>((ref, receiptId) {
      return ProcessingController(
        ref.watch(receiptsRepositoryProvider),
        receiptId,
      );
    });
