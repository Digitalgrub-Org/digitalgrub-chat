import 'package:dg_chat/features/chats/data/matrix_chat_repository.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/chats/domain/unread_tally.dart';
import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final chatRepositoryProvider = FutureProvider.autoDispose<ChatRepository>((
  ref,
) async {
  return MatrixChatRepository(
    await ref.watch(matrixClientProvider.future),
    await ref.watch(outgoingMessageStoreProvider.future),
  );
});

final chatListProvider = StreamProvider.autoDispose<List<ChatSummary>>((
  ref,
) async* {
  final repository = await ref.watch(chatRepositoryProvider.future);
  yield* repository.watchChats();
});

/// How much is unread across every chat.
///
/// Derived from the list the app is already watching rather than asking the
/// server for its own count, so the tab and the chat rows can never disagree
/// about what is unread.
///
/// Invites are excluded on purpose: an unanswered invite is a standing state,
/// not a message, and it would leave the tab dotted permanently for anyone
/// who has one waiting.
final unreadTallyProvider = Provider.autoDispose<UnreadTally>((ref) {
  final chats = ref.watch(chatListProvider).valueOrNull;
  if (chats == null) return UnreadTally.none;
  var rooms = 0;
  var highlights = 0;
  for (final chat in chats) {
    if (chat.isInvite) continue;
    if (chat.unreadCount > 0) rooms++;
    highlights += chat.highlightCount;
  }
  return UnreadTally(rooms: rooms, highlights: highlights);
});
