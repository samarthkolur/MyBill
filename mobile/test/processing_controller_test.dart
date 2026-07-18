import 'package:flutter_test/flutter_test.dart';

import 'package:mybill/core/network/api_client.dart';
import 'package:mybill/features/processing/application/processing_controller.dart';
import 'package:mybill/features/scan/data/receipts_repository.dart';
import 'package:mybill/features/scan/domain/receipt.dart';

/// Returns a scripted sequence of statuses for successive `get` calls (clamping to the
/// last once exhausted), or throws to simulate an unreachable server.
class _FakeRepository implements ReceiptsRepository {
  _FakeRepository(this._statuses, {this.alwaysThrows = false});

  final List<ReceiptStatus> _statuses;
  final bool alwaysThrows;
  int calls = 0;

  @override
  Future<Receipt> get(String receiptId) async {
    calls++;
    if (alwaysThrows) {
      throw const ApiException(code: 'network_error', message: 'no connection');
    }
    final status = _statuses[(calls - 1).clamp(0, _statuses.length - 1)];
    return Receipt(
      id: receiptId,
      status: status,
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProcessingController _controller(_FakeRepository repo, {int maxAttempts = 5}) =>
    ProcessingController(
      repo,
      'r1',
      interval: Duration.zero,
      maxAttempts: maxAttempts,
    );

void main() {
  test('polls until done', () async {
    final repo = _FakeRepository([
      ReceiptStatus.pending,
      ReceiptStatus.processing,
      ReceiptStatus.done,
    ]);
    final controller = _controller(repo);

    await controller.settled;

    expect(controller.state.phase, ProcessingPhase.done);
    expect(repo.calls, 3);
  });

  test('settles immediately when already done', () async {
    final repo = _FakeRepository([ReceiptStatus.done]);
    final controller = _controller(repo);

    await controller.settled;

    expect(controller.state.phase, ProcessingPhase.done);
    expect(repo.calls, 1);
  });

  test('a failed receipt is terminal and not retryable', () async {
    final repo = _FakeRepository([
      ReceiptStatus.processing,
      ReceiptStatus.failed,
    ]);
    final controller = _controller(repo);

    await controller.settled;

    expect(controller.state.phase, ProcessingPhase.failed);
    expect(controller.state.isRetryable, isFalse);
    expect(controller.state.error, isNotNull);
  });

  test(
    'exhausting the attempt budget while still processing is a retryable timeout',
    () async {
      final repo = _FakeRepository([ReceiptStatus.processing]);
      final controller = _controller(repo, maxAttempts: 3);

      await controller.settled;

      expect(controller.state.phase, ProcessingPhase.timedOut);
      expect(controller.state.isRetryable, isTrue);
      expect(repo.calls, 3);
    },
  );

  test('never reaching the server is a retryable connection error', () async {
    final repo = _FakeRepository([
      ReceiptStatus.processing,
    ], alwaysThrows: true);
    final controller = _controller(repo, maxAttempts: 3);

    await controller.settled;

    expect(controller.state.phase, ProcessingPhase.error);
    expect(controller.state.isRetryable, isTrue);
  });

  test('a transient error mid-poll does not end polling', () async {
    // First call throws, later calls succeed — the poll should ride through the blip.
    final repo = _FlakyRepository();
    final controller = ProcessingController(
      repo,
      'r1',
      interval: Duration.zero,
      maxAttempts: 5,
    );

    await controller.settled;

    expect(controller.state.phase, ProcessingPhase.done);
  });

  test('retry restarts polling after a timeout', () async {
    final repo = _FakeRepository([
      ReceiptStatus.processing,
      ReceiptStatus.processing,
      ReceiptStatus.done,
    ]);
    final controller = _controller(repo, maxAttempts: 2);

    await controller.settled;
    expect(controller.state.phase, ProcessingPhase.timedOut);

    controller.retry();
    await controller.settled;

    expect(controller.state.phase, ProcessingPhase.done);
  });
}

/// Throws once, then reports done.
class _FlakyRepository implements ReceiptsRepository {
  int calls = 0;

  @override
  Future<Receipt> get(String receiptId) async {
    calls++;
    if (calls == 1) {
      throw const ApiException(code: 'timeout', message: 'slow');
    }
    return Receipt(
      id: receiptId,
      status: ReceiptStatus.done,
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
