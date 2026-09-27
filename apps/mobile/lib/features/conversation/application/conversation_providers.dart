import 'package:dg_chat/features/conversation/data/matrix_message_repository.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/core/storage/hidden_event_store.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final messageRepositoryProvider = FutureProvider.autoDispose<MessageRepository>(
  (ref) async {
    return MatrixMessageRepository(
      await ref.watch(matrixClientProvider.future),
      await ref.watch(messagingRuntimeProvider.future),
      ref.watch(hiddenEventStoreProvider),
    );
  },
);

final conversationSessionProvider = FutureProvider.autoDispose
    .family<ConversationSession, String>((ref, roomId) async {
      final repository = await ref.watch(messageRepositoryProvider.future);
      final session = await repository.openConversation(roomId);
      ref.onDispose(session.dispose);
      return session;
    });

final conversationProvider = StreamProvider.autoDispose
    .family<ConversationSnapshot, String>((ref, roomId) async* {
      final session = await ref.watch(
        conversationSessionProvider(roomId).future,
      );
      yield* session.changes;
    });
