import 'dart:async';
import 'dart:math';

import 'package:dg_chat/core/network/connectivity_monitor.dart';
import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/outgoing_message_queue.dart';
import 'package:matrix/matrix.dart';

class MatrixMessagingRuntime implements MessagingRuntime {
  MatrixMessagingRuntime({
    required Client client,
    required OutgoingMessageStore store,
    required ConnectivityMonitor connectivity,
    Random? random,
  }) : _client = client,
       _connectivity = connectivity,
       _random = random ?? Random.secure() {
    _queue = OutgoingMessageQueue(
      store: store,
      ownerUserId: client.userID!,
      sender: (message) => _send(client, message),
      generateTransactionId: client.generateUniqueTransactionId,
      random: random,
      onRetryDue: () => _flushOutbox(),
    );
  }

  static const _minimumSyncRetry = Duration(seconds: 2);
  static const _maximumSyncRetry = Duration(minutes: 1);

  final Client _client;
  final ConnectivityMonitor _connectivity;
  final Random _random;
  late final OutgoingMessageQueue _queue;
  final _statuses = StreamController<MessagingConnectionState>.broadcast();
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<SyncStatusUpdate>? _syncStatusSubscription;
  MessagingConnectionState _status = MessagingConnectionState.connecting;
  bool _connected = false;
  bool _foreground = true;
  bool _started = false;
  bool _disposed = false;
  bool _syncFailed = false;
  bool _hasCompletedSync = false;
  int _syncGeneration = 0;
  Future<void>? _syncLoop;
  Completer<void>? _backoffWait;

  static Future<bool> _send(Client client, OutgoingMessage message) async {
    final room = client.getRoomById(message.roomId);
    if (room == null || room.membership != Membership.join) return false;
    final replyEvent = message.replyToEventId == null
        ? null
        : await room.getEventById(message.replyToEventId!);
    final eventId = await room.sendTextEvent(
      message.body,
      txid: message.transactionId,
      inReplyTo: replyEvent,
      editEventId: message.editEventId,
      // The composer writes markdown markers when the user formats a
      // selection, and people type them by hand regardless. The SDK converts
      // them to a formatted_body and leaves `body` as the plaintext fallback,
      // so a client that cannot render markup still shows the message.
      parseMarkdown: true,
      // Commands stay off: `/me` and friends are not features this app
      // offers, and silently reinterpreting a line that merely starts with a
      // slash would lose whatever the user actually meant to say.
      parseCommands: false,
      displayPendingEvent: true,
    );
    return eventId != null;
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _connected = await _connectivity.isConnected;
    await _queue.restore();
    _connectivitySubscription = _connectivity.changes.listen(
      _onConnectivityChanged,
    );
    _syncStatusSubscription = _client.onSyncStatus.stream.listen(_onSyncStatus);

    // Client.init starts the SDK loop. Stop it once, then this runtime owns all
    // subsequent one-shot sync calls so only one loop can exist.
    await _client.abortSync();
    if (_connected) {
      _setStatus(MessagingConnectionState.connecting);
      _startSyncLoop();
      _flushOutbox(force: true);
    } else {
      _setStatus(MessagingConnectionState.offline);
    }
  }

  @override
  MessagingConnectionState get currentStatus => _status;

  @override
  Stream<MessagingConnectionState> get statuses async* {
    yield _status;
    yield* _statuses.stream;
  }

  @override
  Stream<List<OutgoingMessage>> watchRoomOutbox(String roomId) =>
      _queue.watchRoom(roomId);

  @override
  Future<List<OutgoingMessage>> loadRoomOutbox(String roomId) =>
      _queue.readRoom(roomId);

  @override
  Future<String> enqueueText(
    String roomId,
    String body, {
    String? replyToEventId,
    String? editEventId,
  }) async {
    final transactionId = await _queue.enqueue(
      roomId,
      body,
      replyToEventId: replyToEventId,
      editEventId: editEventId,
    );
    _flushOutbox();
    return transactionId;
  }

  @override
  Future<void> retry(String transactionId) async {
    await _queue.retry(transactionId);
    _flushOutbox(force: true);
  }

  void _onConnectivityChanged(bool connected) {
    if (_disposed) return;
    final reconnected = !_connected && connected;
    _connected = connected;
    if (!connected) {
      _setStatus(MessagingConnectionState.offline);
      return;
    }
    _releaseBackoff();
    if (_foreground) _startSyncLoop();
    if (reconnected) _flushOutbox(force: true);
  }

  void _onSyncStatus(SyncStatusUpdate update) {
    if (_disposed || !_connected) return;
    switch (update.status) {
      case SyncStatus.waitingForResponse:
        _setStatus(
          _hasCompletedSync
              ? MessagingConnectionState.online
              : MessagingConnectionState.connecting,
        );
      case SyncStatus.processing:
      case SyncStatus.cleaningUp:
        _setStatus(MessagingConnectionState.synchronizing);
      case SyncStatus.finished:
        _syncFailed = false;
        _hasCompletedSync = true;
        _setStatus(MessagingConnectionState.online);
        _flushOutbox();
      case SyncStatus.error:
        _syncFailed = true;
        final exception = update.error?.exception;
        if (exception is MatrixException &&
            exception.error == MatrixError.M_UNKNOWN_TOKEN) {
          _setStatus(MessagingConnectionState.sessionExpired);
        } else {
          _setStatus(MessagingConnectionState.serverUnavailable);
        }
    }
  }

  void _startSyncLoop() {
    if (_disposed || !_started || !_foreground || !_connected) return;
    if (_syncLoop != null) return;
    final generation = _syncGeneration;
    final loop = _runSyncLoop(generation);
    _syncLoop = loop;
    unawaited(
      loop.whenComplete(() {
        if (!identical(_syncLoop, loop)) return;
        _syncLoop = null;
        if (!_disposed &&
            generation == _syncGeneration &&
            _foreground &&
            _connected &&
            _client.isLogged()) {
          _startSyncLoop();
        }
      }),
    );
  }

  Future<void> _runSyncLoop(int generation) async {
    var failedAttempts = 0;
    while (!_disposed &&
        generation == _syncGeneration &&
        _foreground &&
        _connected &&
        _client.isLogged()) {
      _syncFailed = false;
      await _client.oneShotSync();
      if (_disposed || generation != _syncGeneration) return;
      if (!_syncFailed) {
        failedAttempts = 0;
        continue;
      }
      failedAttempts++;
      await _waitForRetry(_syncRetryDelay(failedAttempts));
    }
  }

  Duration _syncRetryDelay(int attemptCount) {
    final exponent = min(attemptCount - 1, 6);
    final baseMilliseconds = min(
      _minimumSyncRetry.inMilliseconds * pow(2, exponent).toInt(),
      _maximumSyncRetry.inMilliseconds,
    );
    final jitter = _random.nextInt(max(1, baseMilliseconds ~/ 5));
    return Duration(
      milliseconds: min(
        baseMilliseconds + jitter,
        _maximumSyncRetry.inMilliseconds,
      ),
    );
  }

  Future<void> _waitForRetry(Duration duration) async {
    final completer = _backoffWait = Completer<void>();
    final timer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    timer.cancel();
    if (identical(_backoffWait, completer)) _backoffWait = null;
  }

  void _releaseBackoff() {
    final wait = _backoffWait;
    if (wait != null && !wait.isCompleted) wait.complete();
  }

  void _flushOutbox({bool force = false}) {
    if (_disposed || !_started || !_foreground || !_connected) return;
    unawaited(_queue.flush(force: force));
  }

  void _setStatus(MessagingConnectionState status) {
    if (_status == status || _disposed) return;
    _status = status;
    _statuses.add(status);
  }

  @override
  Future<void> pause() async {
    if (!_foreground || _disposed) return;
    _foreground = false;
    _syncGeneration++;
    _releaseBackoff();
    await _client.abortSync();
    _syncLoop = null;
  }

  @override
  Future<void> resume() async {
    if (_foreground || _disposed) return;
    _foreground = true;
    if (_connected) {
      _startSyncLoop();
      _flushOutbox(force: true);
    } else {
      _setStatus(MessagingConnectionState.offline);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _syncGeneration++;
    _releaseBackoff();
    _queue.dispose();
    await _connectivitySubscription?.cancel();
    await _syncStatusSubscription?.cancel();
    await _client.abortSync();
    await _statuses.close();
  }
}
