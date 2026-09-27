import 'dart:async';

import 'package:dg_chat/core/storage/outgoing_message_store.dart';

enum MessagingConnectionState {
  connecting,
  online,
  offline,
  synchronizing,
  sessionExpired,
  serverUnavailable,
}

abstract interface class MessagingRuntime {
  MessagingConnectionState get currentStatus;

  Stream<MessagingConnectionState> get statuses;

  Stream<List<OutgoingMessage>> watchRoomOutbox(String roomId);

  Future<List<OutgoingMessage>> loadRoomOutbox(String roomId);

  Future<String> enqueueText(
    String roomId,
    String body, {
    String? replyToEventId,
    String? editEventId,
  });

  Future<void> retry(String transactionId);

  Future<void> pause();

  Future<void> resume();

  Future<void> dispose();
}
