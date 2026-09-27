import 'dart:async';
import 'dart:math';

import 'package:dg_chat/core/storage/outgoing_message_store.dart';

typedef OutgoingMessageSender = Future<bool> Function(OutgoingMessage message);

class OutgoingMessageQueue {
  OutgoingMessageQueue({
    required OutgoingMessageStore store,
    required String ownerUserId,
    required OutgoingMessageSender sender,
    required String Function() generateTransactionId,
    DateTime Function()? now,
    Random? random,
    this.onRetryDue,
  }) : _store = store,
       _ownerUserId = ownerUserId,
       _sender = sender,
       _generateTransactionId = generateTransactionId,
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  static const _minimumRetryDelay = Duration(seconds: 2);
  static const _maximumRetryDelay = Duration(minutes: 5);

  final OutgoingMessageStore _store;
  final String _ownerUserId;
  final OutgoingMessageSender _sender;
  final String Function() _generateTransactionId;
  final DateTime Function() _now;
  final Random _random;
  final void Function()? onRetryDue;

  Future<void>? _flushFuture;
  bool _flushAgain = false;
  bool _forceNextFlush = false;
  Timer? _retryTimer;

  Future<void> restore() => _store.resetSending(_ownerUserId, _now());

  Stream<List<OutgoingMessage>> watchRoom(String roomId) async* {
    yield await _store.readForRoom(_ownerUserId, roomId);
    yield* _store.changes.asyncMap(
      (_) => _store.readForRoom(_ownerUserId, roomId),
    );
  }

  Future<List<OutgoingMessage>> readRoom(String roomId) =>
      _store.readForRoom(_ownerUserId, roomId);

  Future<String> enqueue(
    String roomId,
    String body, {
    String? replyToEventId,
    String? editEventId,
  }) async {
    final transactionId = _generateTransactionId();
    final createdAt = _now();
    await _store.put(
      OutgoingMessage(
        transactionId: transactionId,
        ownerUserId: _ownerUserId,
        roomId: roomId,
        body: body,
        createdAt: createdAt,
        status: OutgoingMessageStatus.pending,
        attemptCount: 0,
        nextAttemptAt: createdAt,
        replyToEventId: replyToEventId,
        editEventId: editEventId,
      ),
    );
    return transactionId;
  }

  Future<void> retry(String transactionId) async {
    final messages = await _store.readForUser(_ownerUserId);
    final message = messages
        .where((item) => item.transactionId == transactionId)
        .firstOrNull;
    if (message == null || message.status == OutgoingMessageStatus.sending) {
      return;
    }
    await _store.put(
      message.copyWith(
        status: OutgoingMessageStatus.pending,
        nextAttemptAt: _now(),
      ),
    );
    onRetryDue?.call();
  }

  Future<void> flush({bool force = false}) {
    _flushAgain = true;
    _forceNextFlush = _forceNextFlush || force;
    return _flushFuture ??= _drain().whenComplete(() {
      _flushFuture = null;
    });
  }

  Future<void> _drain() async {
    do {
      _flushAgain = false;
      final force = _forceNextFlush;
      _forceNextFlush = false;
      final now = _now();
      final messages = force
          ? (await _store.readForUser(
              _ownerUserId,
            )).where((item) => item.status != OutgoingMessageStatus.sending)
          : await _store.readReady(_ownerUserId, now);

      for (final message in messages) {
        final sending = message.copyWith(status: OutgoingMessageStatus.sending);
        await _store.put(sending);
        var sent = false;
        try {
          sent = await _sender(sending);
        } catch (_) {
          sent = false;
        }
        if (sent) {
          await _store.remove(message.transactionId);
          continue;
        }

        final attemptCount = message.attemptCount + 1;
        await _store.put(
          message.copyWith(
            status: OutgoingMessageStatus.failed,
            attemptCount: attemptCount,
            nextAttemptAt: _now().add(_retryDelay(attemptCount)),
          ),
        );
      }
    } while (_flushAgain);
    await _scheduleRetry();
  }

  Duration _retryDelay(int attemptCount) {
    final exponent = min(attemptCount - 1, 7);
    final baseMilliseconds = min(
      _minimumRetryDelay.inMilliseconds * pow(2, exponent).toInt(),
      _maximumRetryDelay.inMilliseconds,
    );
    final jitter = _random.nextInt(max(1, baseMilliseconds ~/ 5));
    return Duration(
      milliseconds: min(
        baseMilliseconds + jitter,
        _maximumRetryDelay.inMilliseconds,
      ),
    );
  }

  Future<void> _scheduleRetry() async {
    _retryTimer?.cancel();
    final messages = await _store.readForUser(_ownerUserId);
    final retryable = messages
        .where((message) => message.status != OutgoingMessageStatus.sending)
        .toList();
    if (retryable.isEmpty) return;
    retryable.sort((a, b) => a.nextAttemptAt.compareTo(b.nextAttemptAt));
    final delay = retryable.first.nextAttemptAt.difference(_now());
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      onRetryDue?.call();
    });
  }

  void dispose() {
    _retryTimer?.cancel();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
