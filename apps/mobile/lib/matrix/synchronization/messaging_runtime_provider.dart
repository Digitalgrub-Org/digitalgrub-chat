import 'dart:async';

import 'package:dg_chat/core/network/connectivity_monitor.dart';
import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:dg_chat/matrix/synchronization/matrix_messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final messagingRuntimeProvider = FutureProvider.autoDispose<MessagingRuntime>((
  ref,
) async {
  final client = await ref.watch(matrixClientProvider.future);
  final store = await ref.watch(outgoingMessageStoreProvider.future);
  final runtime = MatrixMessagingRuntime(
    client: client,
    store: store,
    connectivity: ref.watch(connectivityMonitorProvider),
  );
  await runtime.start();
  ref.onDispose(() => unawaited(runtime.dispose()));
  return runtime;
});

final messagingStatusProvider =
    StreamProvider.autoDispose<MessagingConnectionState>((ref) async* {
      final runtime = await ref.watch(messagingRuntimeProvider.future);
      yield* runtime.statuses;
    });
