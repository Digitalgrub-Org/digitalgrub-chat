import 'dart:async';

import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:matrix/matrix.dart';

class MatrixChatRepository implements ChatRepository {
  MatrixChatRepository(this._client, this._outgoingMessageStore);

  final Client _client;
  final OutgoingMessageStore _outgoingMessageStore;

  @override
  Stream<List<ChatSummary>> watchChats() async* {
    await _client.roomsLoading;
    yield await _readChats();

    final updates = StreamController<void>();
    final syncSubscription = _client.onSync.stream.listen((_) {
      if (!updates.isClosed) updates.add(null);
    });
    final outboxSubscription = _outgoingMessageStore.changes.listen((_) {
      if (!updates.isClosed) updates.add(null);
    });
    // Presence arrives in sync but the SDK surfaces it on its own stream,
    // after the sync event has already fired; without this the dot would
    // trail one sync behind the truth.
    final presenceSubscription = _client.onPresenceChanged.stream.listen((_) {
      if (!updates.isClosed) updates.add(null);
    });
    try {
      await for (final _ in updates.stream) {
        yield await _readChats();
      }
    } finally {
      await syncSubscription.cancel();
      await outboxSubscription.cancel();
      await presenceSubscription.cancel();
      await updates.close();
    }
  }

  @override
  Future<void> refresh() async {
    try {
      await _client
          .oneShotSync(timeout: Duration.zero)
          .timeout(const Duration(seconds: 20));
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } on ChatFailure {
      rethrow;
    } catch (_) {
      throw const ChatFailure(ChatFailureCode.serverUnavailable);
    }
  }

  Future<List<ChatSummary>> _readChats() async {
    final userId = _client.userID;
    final outgoingMessages = userId == null
        ? const <OutgoingMessage>[]
        : await _outgoingMessageStore.readForUser(userId);
    final rooms =
        _client.rooms
            .where(
              (room) =>
                  room.membership == Membership.join ||
                  room.membership == Membership.invite,
            )
            .toList()
          ..sort(
            (a, b) =>
                b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
          );

    return Future.wait(
      rooms.map(
        (room) => _mapRoom(
          room,
          outgoingMessages
              .where((message) => message.roomId == room.id)
              .toList(),
        ),
      ),
    );
  }

  @override
  Future<void> acceptInvite(String roomId) async {
    final room = _requireRoom(roomId);
    try {
      await room.join();
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } on ChatFailure {
      rethrow;
    } catch (_) {
      throw const ChatFailure(ChatFailureCode.serverUnavailable);
    }
  }

  @override
  Future<void> declineInvite(String roomId) async {
    final room = _requireRoom(roomId);
    try {
      await room.leave();
      await room.forget().catchError((_) => '');
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } on ChatFailure {
      rethrow;
    } catch (_) {
      throw const ChatFailure(ChatFailureCode.serverUnavailable);
    }
  }

  Room _requireRoom(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) throw const ChatFailure(ChatFailureCode.unknown);
    return room;
  }

  Future<ChatSummary> _mapRoom(
    Room room,
    List<OutgoingMessage> outgoingMessages,
  ) async {
    Uri? avatarUrl;
    final avatar = room.avatar;
    if (avatar != null) {
      final thumbnail = await avatar.getThumbnailUri(
        _client,
        width: 96,
        height: 96,
      );
      if (thumbnail.hasScheme) avatarUrl = thumbnail;
    }

    final event = room.lastEvent;
    var preview = event?.type == EventTypes.Message
        ? event!.plaintextBody.trim()
        : '';
    var previewKind = event?.type == EventTypes.Message
        ? switch (event!.messageType) {
            MessageTypes.Image => ChatPreviewKind.image,
            MessageTypes.Video => ChatPreviewKind.video,
            MessageTypes.Audio => ChatPreviewKind.audio,
            MessageTypes.File => ChatPreviewKind.file,
            _ => ChatPreviewKind.text,
          }
        : ChatPreviewKind.text;
    var lastActivity = event?.originServerTs;
    if (outgoingMessages.isNotEmpty) {
      outgoingMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final newest = outgoingMessages.first;
      if (lastActivity == null || newest.createdAt.isAfter(lastActivity)) {
        preview = newest.body;
        // Only text goes through the outbox, so a queued message is text.
        previewKind = ChatPreviewKind.text;
        lastActivity = newest.createdAt;
      }
    }

    final isInvite = room.membership == Membership.invite;

    return ChatSummary(
      roomId: room.id,
      name: room.getLocalizedDisplayname(),
      lastMessage: preview,
      lastActivity: lastActivity,
      unreadCount: room.notificationCount,
      highlightCount: room.highlightCount,
      presence: await _partnerPresence(room),
      previewKind: previewKind,
      isDirect: room.isDirectChat,
      isInvite: isInvite,
      invitedBy: isInvite ? _inviterName(room) : null,
      pendingCount: outgoingMessages.length,
      hasFailedMessages: outgoingMessages.any(
        (message) => message.status == OutgoingMessageStatus.failed,
      ),
      avatarUrl: avatarUrl,
      avatarHeaders: avatarUrl == null ? const {} : _mediaHeaders,
    );
  }

  /// The other person's presence in a direct chat, or null for a group.
  ///
  /// Cached by the SDK after the first look, so this costs one request per
  /// direct chat for the life of the session and nothing per sync. Never
  /// throws: a server with presence switched off must not blank the list.
  Future<UserPresence?> _partnerPresence(Room room) async {
    if (!room.isDirectChat) return null;
    final partner = room.directChatMatrixID;
    if (partner == null) return null;
    try {
      final cached = await _client.fetchCurrentPresence(partner);
      return UserPresence(
        online:
            cached.presence == PresenceType.online ||
            cached.currentlyActive == true,
        lastActive: cached.lastActiveTimestamp,
      );
    } catch (_) {
      return null;
    }
  }

  /// Resolves who sent the invite from the account's own membership event,
  /// whose sender is the inviter. Returns null rather than guessing when the
  /// state is not cached.
  String? _inviterName(Room room) {
    final userId = _client.userID;
    if (userId == null) return null;
    final membershipEvent = room.getState(EventTypes.RoomMember, userId);
    final inviterId = membershipEvent?.senderId;
    if (inviterId == null || inviterId == userId) return null;
    return room.unsafeGetUserFromMemoryOrFallback(inviterId).calcDisplayname();
  }

  Map<String, String> get _mediaHeaders {
    final token = _client.accessToken;
    return token == null ? const {} : {'authorization': 'Bearer $token'};
  }

  ChatFailure _mapFailure(MatrixException error) {
    if (error.error == MatrixError.M_UNKNOWN_TOKEN) {
      return const ChatFailure(ChatFailureCode.sessionExpired);
    }
    return const ChatFailure(ChatFailureCode.serverUnavailable);
  }
}
