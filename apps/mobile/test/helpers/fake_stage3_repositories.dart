import 'dart:async';

import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({List<ChatSummary> chats = const []}) : _chats = chats;

  List<ChatSummary> _chats;
  final _updates = StreamController<List<ChatSummary>>.broadcast();
  int refreshCount = 0;
  final List<String> acceptedInvites = [];
  final List<String> declinedInvites = [];
  ChatFailure? inviteFailure;

  @override
  Stream<List<ChatSummary>> watchChats() async* {
    yield _chats;
    yield* _updates.stream;
  }

  void emit(List<ChatSummary> chats) {
    _chats = chats;
    _updates.add(chats);
  }

  @override
  Future<void> refresh() async {
    refreshCount++;
  }

  @override
  Future<void> acceptInvite(String roomId) async {
    if (inviteFailure != null) throw inviteFailure!;
    acceptedInvites.add(roomId);
  }

  @override
  Future<void> declineInvite(String roomId) async {
    if (inviteFailure != null) throw inviteFailure!;
    declinedInvites.add(roomId);
  }

  Future<void> dispose() => _updates.close();
}

class FakeUserRepository implements UserRepository {
  FakeUserRepository({this.results = const [], Map<String, String>? roomIds})
    : roomIds = roomIds ?? {};

  final List<UserSearchResult> results;
  final Map<String, String> roomIds;
  final List<String> queries = [];
  final List<String> startedUsers = [];

  @override
  Future<List<UserSearchResult>> listServerUsers() async => search('');

  @override
  Future<List<UserSearchResult>> search(String query) async {
    queries.add(query);
    return results;
  }

  @override
  Future<String> startDirectConversation(String userId) async {
    startedUsers.add(userId);
    return roomIds[userId] ?? '!direct:test';
  }
}

class FakeMessageRepository implements MessageRepository {
  FakeMessageRepository(this.sessions);

  final Map<String, FakeConversationSession> sessions;
  final List<String> openedRooms = [];

  @override
  Future<ConversationSession> openConversation(String roomId) async {
    openedRooms.add(roomId);
    final session = sessions[roomId];
    if (session == null) {
      throw const MessageFailure(MessageFailureCode.roomNotFound);
    }
    return session;
  }
}

class FakeConversationSession implements ConversationSession {
  FakeConversationSession(this._snapshot);

  ConversationSnapshot _snapshot;
  final _updates = StreamController<ConversationSnapshot>.broadcast();
  final List<String> sentTexts = [];
  final List<AttachmentDraft> sentAttachments = [];
  final List<(String, String?)> sentMessages = [];
  final List<String> retriedTransactionIds = [];
  final List<(String, String)> editedMessages = [];
  final List<(String, String)> toggledReactions = [];
  final List<String> hiddenEventIds = [];
  final List<String> redactedEventIds = [];
  final List<(String, bool)> pinChanges = [];
  final List<bool> typingUpdates = [];
  int loadOlderCount = 0;

  @override
  Stream<ConversationSnapshot> get changes async* {
    yield _snapshot;
    yield* _updates.stream;
  }

  /// The snapshot the session is currently serving, for tests that emit a
  /// changed copy of it.
  ConversationSnapshot get snapshot => _snapshot;

  void emit(ConversationSnapshot snapshot) {
    _snapshot = snapshot;
    _updates.add(snapshot);
  }

  @override
  Future<void> loadOlder() async {
    loadOlderCount++;
  }

  @override
  Future<void> sendText(String text, {String? replyToEventId}) async {
    sentTexts.add(text);
    sentMessages.add((text, replyToEventId));
  }

  @override
  Future<void> sendAttachment(AttachmentDraft draft) async {
    sentAttachments.add(draft);
  }

  @override
  Future<void> editMessage(String eventId, String text) async {
    editedMessages.add((eventId, text));
  }

  @override
  Future<void> toggleReaction(String eventId, String key) async {
    toggledReactions.add((eventId, key));
  }

  @override
  Future<void> deleteForMe(String eventId) async {
    hiddenEventIds.add(eventId);
  }

  @override
  Future<void> deleteForEveryone(String eventId) async {
    redactedEventIds.add(eventId);
  }

  @override
  Future<void> updateTyping(bool isTyping) async {
    typingUpdates.add(isTyping);
  }

  @override
  Future<void> setPinned(String eventId, {required bool pinned}) async {
    pinChanges.add((eventId, pinned));
  }

  @override
  Future<void> forwardTo(String roomId, ChatMessage message) async {}

  @override
  Future<List<MentionCandidate>> mentionCandidates(String query) async =>
      const [];

  @override
  Future<void> retryMessage(String transactionId) async {
    retriedTransactionIds.add(transactionId);
  }

  @override
  void dispose() {
    if (!_updates.isClosed) unawaited(_updates.close());
  }
}
