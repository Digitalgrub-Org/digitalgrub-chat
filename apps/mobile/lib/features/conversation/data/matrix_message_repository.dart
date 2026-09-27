import 'dart:async';

import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/core/storage/hidden_event_store.dart';
import 'package:dg_chat/core/presence.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/groups/data/group_activity_mapper.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:dg_chat/features/notifications/domain/push_repository.dart'
    show rtcNotificationEventType;
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:matrix/matrix.dart';

class MatrixMessageRepository implements MessageRepository {
  MatrixMessageRepository(this._client, this._runtime, this._hiddenEventStore);

  final Client _client;
  final MessagingRuntime _runtime;
  final HiddenEventStore _hiddenEventStore;

  @override
  Future<ConversationSession> openConversation(String roomId) async {
    await _client.roomsLoading;
    final room = _client.getRoomById(roomId);
    // Membership is the read permission. A room you left still sits in the
    // local cache with its whole history, and a stale route or the browser's
    // back button would happily reopen it -- which is exactly how someone
    // "still saw the messages" after leaving a group.
    if (room == null ||
        !{Membership.join, Membership.invite}.contains(room.membership)) {
      throw const MessageFailure(MessageFailureCode.roomNotFound);
    }
    return _MatrixConversationSession.create(
      _client,
      _runtime,
      _hiddenEventStore,
      room,
    );
  }
}

class _MatrixConversationSession implements ConversationSession {
  _MatrixConversationSession({
    required Client client,
    required MessagingRuntime runtime,
    required HiddenEventStore hiddenEventStore,
    required Room room,
    required Timeline timeline,
    required Set<String> hiddenEventIds,
    required Uri? avatarUrl,
    required Map<String, String> avatarHeaders,
    required bool authenticatedMedia,
    required int? uploadLimitBytes,
  }) : _client = client,
       _runtime = runtime,
       _hiddenEventStore = hiddenEventStore,
       _room = room,
       _timeline = timeline,
       _hiddenEventIds = hiddenEventIds,
       _avatarUrl = avatarUrl,
       _avatarHeaders = avatarHeaders,
       _mediaHeaders = avatarHeaders,
       _authenticatedMedia = authenticatedMedia,
       _uploadLimitBytes = uploadLimitBytes;

  final Client _client;
  final MessagingRuntime _runtime;
  final HiddenEventStore _hiddenEventStore;
  final Room _room;
  final Timeline _timeline;
  final Uri? _avatarUrl;
  final Map<String, String> _avatarHeaders;

  /// Same credentials as the avatar fetch: the media repository does not care
  /// which endpoint is asking.
  final Map<String, String> _mediaHeaders;

  /// Settled once when the session opens. A homeserver does not gain or lose
  /// authenticated media while a client is connected to it.
  final bool _authenticatedMedia;

  /// The server's advertised upload ceiling, or null when it does not say.
  /// Checked before uploading so a too-large file fails in milliseconds with
  /// a usable message instead of after a slow doomed upload.
  final int? _uploadLimitBytes;
  final Set<String> _hiddenEventIds;
  final StreamController<ConversationSnapshot> _updates =
      StreamController.broadcast();
  bool _loadingOlder = false;
  bool _disposed = false;
  List<OutgoingMessage> _outbox = const [];
  StreamSubscription<List<OutgoingMessage>>? _outboxSubscription;
  StreamSubscription<SyncUpdate>? _syncSubscription;
  StreamSubscription<CachedPresence>? _presenceSubscription;

  /// The other person's presence, for a direct chat. Held here because the
  /// snapshot is built synchronously on every timeline update and cannot
  /// go and ask; the subscription keeps it current instead.
  CachedPresence? _partnerPresence;
  Timer? _typingStopTimer;

  bool _typingSent = false;
  DateTime? _lastTypingUpdate;
  String? _lastReadEventId;

  static Future<_MatrixConversationSession> create(
    Client client,
    MessagingRuntime runtime,
    HiddenEventStore hiddenEventStore,
    Room room,
  ) async {
    _MatrixConversationSession? session;
    final timeline = await room.getTimeline(onUpdate: () => session?._emit());

    Uri? avatarUrl;
    final avatar = room.avatar;
    if (avatar != null) {
      final thumbnail = await avatar.getThumbnailUri(
        client,
        width: 96,
        height: 96,
      );
      if (thumbnail.hasScheme) avatarUrl = thumbnail;
    }

    session = _MatrixConversationSession(
      client: client,
      runtime: runtime,
      hiddenEventStore: hiddenEventStore,
      room: room,
      timeline: timeline,
      hiddenEventIds: await hiddenEventStore.read(client.userID!, room.id),
      avatarUrl: avatarUrl,
      avatarHeaders: client.accessToken == null
          ? const {}
          : {'authorization': 'Bearer ${client.accessToken}'},
      // Asked once here so the timeline mapper, which is synchronous and runs
      // on every update, does not have to await it per message.
      authenticatedMedia: await client.authenticatedMediaSupported(),
      uploadLimitBytes: await _fetchUploadLimit(client),
    );
    session._outbox = await runtime.loadRoomOutbox(room.id);
    session._outboxSubscription = runtime.watchRoomOutbox(room.id).listen((
      messages,
    ) {
      session?._outbox = messages;
      session?._emit();
    });
    session._syncSubscription = client.onSync.stream.listen((sync) {
      // Blocking a user arrives as global account data rather than a room
      // update, and it changes how this timeline renders.
      if (sync.rooms?.join?.containsKey(room.id) == true ||
          sync.accountData?.isNotEmpty == true) {
        session?._emit();
      }
    });
    final partner = room.isDirectChat ? room.directChatMatrixID : null;
    if (partner != null) {
      try {
        session._partnerPresence = await client.fetchCurrentPresence(partner);
      } catch (_) {
        // Presence off, or the server would not say: the header simply
        // shows nothing about it.
      }
      session._presenceSubscription = client.onPresenceChanged.stream
          .where((presence) => presence.userid == partner)
          .listen((presence) {
            session?._partnerPresence = presence;
            session?._emit();
          });
    }
    session._markLatestRead();
    return session;
  }

  @override
  Stream<ConversationSnapshot> get changes async* {
    yield _snapshot();
    yield* _updates.stream;
  }

  @override
  Future<void> loadOlder() async {
    if (_loadingOlder || !_timeline.canRequestHistory) return;
    _loadingOlder = true;
    _emit();
    try {
      await _timeline.requestHistory(historyCount: 40);
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } finally {
      _loadingOlder = false;
      _emit();
    }
  }

  @override
  Future<void> sendText(String text, {String? replyToEventId}) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw const MessageFailure(MessageFailureCode.emptyMessage);
    }

    try {
      await _runtime.enqueueText(
        _room.id,
        normalized,
        replyToEventId: replyToEventId,
      );
      await updateTyping(false);
    } catch (_) {
      throw const MessageFailure(MessageFailureCode.serverUnavailable);
    }
  }

  @override
  Future<void> sendAttachment(AttachmentDraft draft) async {
    final limit = _uploadLimitBytes;
    if (limit != null && draft.sizeBytes > limit) {
      throw const MessageFailure(MessageFailureCode.attachmentTooLarge);
    }

    // Images go as MatrixImageFile so the event carries the dimensions the
    // picker measured; receivers use them to reserve layout space. Everything
    // else infers its message type from the mime type.
    final width = draft.width;
    final height = draft.height;
    final voiceMs = draft.voiceDurationMs;
    final MatrixFile file;
    if (voiceMs != null) {
      file = MatrixAudioFile(
        bytes: draft.bytes,
        name: draft.fileName,
        mimeType: draft.mimeType,
        duration: voiceMs,
      );
    } else if (width != null && height != null) {
      file = MatrixImageFile(
        bytes: draft.bytes,
        name: draft.fileName,
        mimeType: draft.mimeType,
        width: width.round(),
        height: height.round(),
      );
    } else {
      file = MatrixFile.fromMimeType(
        bytes: draft.bytes,
        name: draft.fileName,
        mimeType: draft.mimeType,
      );
    }

    try {
      final eventId = await _room.sendFileEvent(
        file,
        extraContent: voiceMs == null
            ? null
            : {
                // MSC3245: what turns an audio file into a voice message in
                // every Matrix client that renders them, ours included.
                'org.matrix.msc3245.voice': const <String, Object?>{},
                'org.matrix.msc1767.audio': {'duration': voiceMs},
              },
      );
      if (eventId == null) {
        // The SDK returns null rather than throwing when the room is not
        // joined or the send was dropped; the user still needs to hear no.
        throw const MessageFailure(MessageFailureCode.serverUnavailable);
      }
    } on MessageFailure {
      rethrow;
    } on MatrixException catch (error) {
      if (error.error == MatrixError.M_TOO_LARGE) {
        throw const MessageFailure(MessageFailureCode.attachmentTooLarge);
      }
      throw _mapFailure(error);
    } catch (_) {
      throw const MessageFailure(MessageFailureCode.serverUnavailable);
    }
  }

  /// The server's upload ceiling, or null when it will not say.
  ///
  /// A failure here must not stop the conversation from opening — the check
  /// is an optimisation, and the server still enforces the real limit.
  static Future<int?> _fetchUploadLimit(Client client) async {
    try {
      return (await client.getConfigAuthed()).mUploadSize;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> retryMessage(String transactionId) =>
      _runtime.retry(transactionId);

  @override
  Future<void> editMessage(String eventId, String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw const MessageFailure(MessageFailureCode.emptyMessage);
    }
    await _runtime.enqueueText(_room.id, normalized, editEventId: eventId);
    await updateTyping(false);
  }

  @override
  Future<void> toggleReaction(String eventId, String key) async {
    try {
      final event = await _timeline.getEventById(eventId);
      if (event == null) {
        throw const MessageFailure(MessageFailureCode.roomNotFound);
      }
      Event? ownReaction;
      for (final reaction in event.aggregatedEvents(
        _timeline,
        RelationshipTypes.reaction,
      )) {
        final relation = reaction.content['m.relates_to'];
        final reactionKey = relation is Map ? relation['key'] : null;
        if (reaction.senderId == _client.userID && reactionKey == key) {
          ownReaction = reaction;
          break;
        }
      }
      if (ownReaction != null) {
        await ownReaction.redactEvent();
      } else {
        await _room.sendReaction(eventId, key);
      }
      _emit();
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    }
  }

  @override
  Future<void> deleteForMe(String eventId) async {
    await _hiddenEventStore.hide(_client.userID!, _room.id, eventId);
    _hiddenEventIds.add(eventId);
    _emit();
  }

  @override
  Future<void> deleteForEveryone(String eventId) async {
    try {
      await _room.redactEvent(eventId, redactAllEdits: true);
      _emit();
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    }
  }

  @override
  Future<void> updateTyping(bool isTyping) async {
    if (_disposed) return;
    _typingStopTimer?.cancel();
    if (!isTyping) {
      if (!_typingSent) return;
      _typingSent = false;
      try {
        await _room.setTyping(false);
      } catch (_) {}
      return;
    }

    _typingStopTimer = Timer(
      const Duration(seconds: 4),
      () => unawaited(updateTyping(false)),
    );
    final now = DateTime.now();
    if (_typingSent &&
        _lastTypingUpdate != null &&
        now.difference(_lastTypingUpdate!) < const Duration(seconds: 4)) {
      return;
    }
    _typingSent = true;
    _lastTypingUpdate = now;
    try {
      await _room.setTyping(true, timeout: 8000);
    } catch (_) {}
  }

  ConversationSnapshot _snapshot() {
    final outboxByTransactionId = {
      for (final message in _outbox) message.transactionId: message,
    };
    final eventsById = {
      for (final event in _timeline.events) event.eventId: event,
    };
    final pendingEdits = <String, OutgoingMessage>{};
    for (final message in _outbox.where(
      (message) => message.editEventId != null,
    )) {
      final current = pendingEdits[message.editEventId];
      if (current == null || message.createdAt.isAfter(current.createdAt)) {
        pendingEdits[message.editEventId!] = message;
      }
    }

    // What happened to the group, keyed by the event that says so. Computed
    // once here rather than inside the filter, which would otherwise map every
    // candidate twice.
    final activityByEventId = _activityEntries();

    final messages = _timeline.events
        .where(
          (event) =>
              !_hiddenEventIds.contains(event.eventId) &&
              // A call is not a message, but it belongs in the timeline: it
              // is the record that somebody tried to reach you, and it
              // survives the thirty seconds the ring itself lasts.
              (event.type == rtcNotificationEventType ||
                  // Joins, removals, a new group name: the story of the room
                  // told where it happened, rather than in a screen you have
                  // to go and find.
                  activityByEventId.containsKey(event.eventId) ||
                  (event.type == EventTypes.Message &&
                      event.relationshipType != RelationshipTypes.edit &&
                      (event.redacted ||
                          _renderableMessageTypes.contains(
                            event.messageType,
                          )))),
        )
        .map(
          (event) => _mapEvent(
            event,
            eventsById,
            event.transactionId == null
                ? null
                : outboxByTransactionId[event.transactionId],
            pendingEdits[event.eventId],
            activityByEventId[event.eventId],
          ),
        )
        .toList();
    final matrixTransactionIds = _timeline.events
        .map((event) => event.transactionId)
        .whereType<String>()
        .toSet();
    messages.addAll(
      _outbox
          .where(
            (message) =>
                message.editEventId == null &&
                !matrixTransactionIds.contains(message.transactionId),
          )
          .map((message) => _mapOutgoingMessage(message, eventsById)),
    );
    messages.sort((a, b) => b.sentAt.compareTo(a.sentAt));

    return ConversationSnapshot(
      roomId: _room.id,
      title: _room.getLocalizedDisplayname(),
      messages: messages,
      canLoadOlder: _timeline.canRequestHistory,
      isLoadingOlder: _loadingOlder,
      isDirect: _room.isDirectChat,
      typingUsers: _room.typingUsers
          .where((user) => user.id != _client.userID)
          .map((user) => user.calcDisplayname())
          .toList(growable: false),
      avatarUrl: _avatarUrl,
      avatarHeaders: _avatarHeaders,
      pinnedEventIds: _room.pinnedEventIds,
      canPin: _room.canChangeStateEvent(EventTypes.RoomPinnedEvents),
      partnerPresence: switch (_partnerPresence) {
        null => null,
        final cached => UserPresence(
          online:
              cached.presence == PresenceType.online ||
              cached.currentlyActive == true,
          lastActive: cached.lastActiveTimestamp,
        ),
      },
    );
  }

  /// Marks a forward, and records where it came from. Not a spec field, so
  /// other clients ignore it and simply show the message.
  static const _forwardedFromKey = 'in.digitalgrub.forwarded_from';

  @override
  Future<void> setPinned(String eventId, {required bool pinned}) async {
    // Read, change, write: the pin list is one state event, so pinning is
    // always a rewrite of the whole list rather than an append.
    final current = List<String>.from(_room.pinnedEventIds);
    if (pinned) {
      if (current.contains(eventId)) return;
      current.add(eventId);
    } else {
      if (!current.remove(eventId)) return;
    }
    try {
      await _room.setPinnedEvents(current);
      _emit();
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } catch (_) {
      throw const MessageFailure(MessageFailureCode.serverUnavailable);
    }
  }

  @override
  Future<void> forwardTo(String roomId, ChatMessage message) async {
    final target = _client.getRoomById(roomId);
    if (target == null) {
      throw const MessageFailure(MessageFailureCode.roomNotFound);
    }
    try {
      final source = await _timeline.getEventById(message.eventId);
      if (source == null) {
        throw const MessageFailure(MessageFailureCode.unknown);
      }
      final content = Map<String, Object?>.from(source.content)
        // A reply or edit relation points at an event that does not exist in
        // the destination, where it would render as a reply to nothing.
        ..remove('m.relates_to')
        // Forwarding must not ping the people the original named: they are
        // probably not even in this room, and being pinged by a message you
        // cannot see is alarming.
        ..remove('m.mentions')
        ..[_forwardedFromKey] = {
          'room_id': _room.id,
          'event_id': message.eventId,
        };
      // Sent as content rather than re-uploaded: an attachment keeps its
      // existing mxc URL, so forwarding a video costs one event, not a
      // second copy of the file on the server.
      await target.sendEvent(content);
    } on MessageFailure {
      rethrow;
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } catch (_) {
      throw const MessageFailure(MessageFailureCode.serverUnavailable);
    }
  }

  @override
  Future<List<MentionCandidate>> mentionCandidates(String query) async {
    final needle = query.trim().toLowerCase();
    final me = _client.userID;

    // "Everyone" first, when it is offerable at all. Not in a direct chat,
    // where pinging "the room" means pinging the one other person and is just
    // a noisier way to talk to them; and not for someone whose power level
    // the room does not trust with a room-wide notification, because the
    // homeserver would accept the message and quietly notify nobody.
    final canNotifyRoom =
        !_room.isDirectChat &&
        me != null &&
        _room.canSendNotification(me) &&
        ('everyone'.startsWith(needle) ||
            'room'.startsWith(needle) ||
            'here'.startsWith(needle) ||
            needle.isEmpty);
    final participants = _room.getParticipants().where(
      (user) =>
          user.id != me &&
          user.membership == Membership.join &&
          // Someone whose name the server cannot turn back into a user id is
          // not offerable: inserting it would look like a mention and ping
          // nobody. The SDK refuses names containing [ ] or :.
          user.mentionFragments.isNotEmpty,
    );

    final matches =
        participants
            .where(
              (user) =>
                  needle.isEmpty ||
                  user.calcDisplayname().toLowerCase().contains(needle) ||
                  user.id.toLowerCase().contains(needle),
            )
            .take(_mentionLimit)
            .toList()
          ..sort(
            (a, b) => a.calcDisplayname().toLowerCase().compareTo(
              b.calcDisplayname().toLowerCase(),
            ),
          );

    final people = await Future.wait(
      matches.map((user) async {
        Uri? avatarUrl;
        final avatar = user.avatarUrl;
        if (avatar != null) {
          try {
            final thumbnail = await avatar.getThumbnailUri(
              _client,
              width: 96,
              height: 96,
            );
            if (thumbnail.hasScheme) avatarUrl = thumbnail;
          } catch (_) {
            // An unreachable avatar must not remove the person from the list.
          }
        }
        return MentionCandidate(
          userId: user.id,
          displayName: user.calcDisplayname(),
          insertText: user.mentionFragments.first,
          avatarUrl: avatarUrl,
          avatarHeaders: avatarUrl == null ? const {} : _mediaHeaders,
        );
      }),
    );

    return [
      if (canNotifyRoom)
        const MentionCandidate(
          userId: roomMentionId,
          displayName: 'Everyone',
          // `@room` is the spec's token for a room-wide mention, and the SDK
          // turns exactly this in a body into m.mentions {room: true}. The
          // picker shows "Everyone" because that is what it means; the wire
          // format is not the user's problem.
          insertText: roomMentionId,
        ),
      ...people,
    ];
  }

  /// Message types this client can put on screen.
  ///
  /// Anything outside this set is left out of the timeline entirely, so it has
  /// to stay in step with what the UI can render. Attachments were missing
  /// here for a long time, and the effect was not a broken-looking bubble: a
  /// shared file simply never appeared, while the sender saw it delivered.
  /// The picker is a shortcut, not a directory: a long list is slower to use
  /// than typing the name.
  static const _mentionLimit = 8;

  static const _renderableMessageTypes = {
    MessageTypes.Text,
    MessageTypes.Notice,
    MessageTypes.Emote,
    MessageTypes.Image,
    MessageTypes.Video,
    MessageTypes.Audio,
    MessageTypes.File,
  };

  /// Builds the attachment for a file-bearing message, or null for text.
  MessageAttachment? _attachmentOf(Event event) {
    final kind = switch (event.messageType) {
      MessageTypes.Image => AttachmentKind.image,
      MessageTypes.Video => AttachmentKind.video,
      MessageTypes.Audio => AttachmentKind.audio,
      MessageTypes.File => AttachmentKind.file,
      _ => null,
    };
    if (kind == null) return null;

    final info = event.infoMap;
    final width = info['w'];
    final height = info['h'];
    final size = info['size'];
    final duration = info['duration'];
    return MessageAttachment(
      kind: kind,
      // The body of a file event is its filename by convention.
      fileName: event.body.trim().isEmpty ? event.eventId : event.body,
      mimeType: info['mimetype'] is String ? info['mimetype'] as String : null,
      sizeBytes: size is int ? size : null,
      url: _mediaUri(event.attachmentMxcUrl),
      thumbnailUrl: _mediaUri(event.thumbnailMxcUrl),
      width: width is num ? width.toDouble() : null,
      height: height is num ? height.toDouble() : null,
      headers: _mediaHeaders,
      durationMs: duration is int ? duration : null,
      isVoice: event.content['org.matrix.msc3245.voice'] != null,
    );
  }

  /// Resolves an `mxc://` reference to something an image widget can fetch.
  ///
  /// Built here rather than through the SDK's async helper because mapping a
  /// timeline is synchronous and the only asynchronous part — whether the
  /// homeserver wants authenticated media — is settled once when the session
  /// opens and cannot change under a running client.
  Uri? _mediaUri(Uri? mxc) {
    if (mxc == null || !mxc.isScheme('mxc')) return null;
    final homeserver = _client.homeserver;
    if (homeserver == null) return null;
    final authority = '${mxc.host}${mxc.hasPort ? ':${mxc.port}' : ''}';
    return homeserver.resolve(
      _authenticatedMedia
          ? '_matrix/client/v1/media/download/$authority${mxc.path}'
          : '_matrix/media/v3/download/$authority${mxc.path}',
    );
  }

  /// The sender's HTML body, or null when the message is plain text.
  ///
  /// Only `org.matrix.custom.html` counts. Any other format is a markup
  /// language this client has no renderer for, and guessing at it would be
  /// worse than falling back to the plaintext body.
  static String? _formattedBodyOf(Event event) {
    if (event.content['format'] != 'org.matrix.custom.html') return null;
    final formatted = event.content['formatted_body'];
    if (formatted is! String || formatted.trim().isEmpty) return null;
    return formatted;
  }

  /// What happened to the group, for the events that say so.
  ///
  /// Empty for a direct chat: "you joined" between two people is noise, and
  /// WhatsApp does not show it either. The call notification is left out
  /// because the timeline already gives a call its own row, with a way to
  /// join it.
  Map<String, GroupActivityEntry> _activityEntries() {
    if (_room.isDirectChat) return const {};
    final entries = <String, GroupActivityEntry>{};
    for (final event in _timeline.events) {
      if (!timelineActivityEventTypes.contains(event.type)) continue;
      final entry = activityEntryOf(event, _room);
      if (entry != null) entries[event.eventId] = entry;
    }
    return entries;
  }

  ChatMessage _mapEvent(
    Event event,
    Map<String, Event> eventsById,
    OutgoingMessage? outgoingMessage,
    OutgoingMessage? pendingEdit,
    GroupActivityEntry? activity,
  ) {
    final sender = event.senderFromMemoryOrFallback;
    final displayEvent = event.getDisplayEvent(_timeline);
    final replyTo = _replyPreview(event.inReplyToEventId(), eventsById);
    final reactions = _reactionsFor(event);
    final effectiveOutgoing = pendingEdit ?? outgoingMessage;
    // A ring mentions the whole room -- that is how it reaches everyone -- but
    // the entry it leaves behind is a call, not a message that named you, and
    // lighting it up as a mention would train people to ignore the highlight.
    final isCallStart = event.type == rtcNotificationEventType;
    return ChatMessage(
      eventId: event.eventId,
      senderId: event.senderId,
      senderName: sender.calcDisplayname(),
      body: event.redacted
          ? ''
          : pendingEdit?.body ?? displayEvent.plaintextBody,
      // An edit still in the outbox has no formatting yet, so the old markup
      // is dropped rather than shown alongside the new text.
      formattedBody: event.redacted || pendingEdit != null
          ? null
          : _formattedBodyOf(displayEvent),
      attachment: event.redacted ? null : _attachmentOf(event),
      sentAt: event.originServerTs,
      isOwn: event.senderId == _client.userID,
      deliveryState: pendingEdit == null
          ? switch (event.status) {
              EventStatus.error =>
                outgoingMessage == null
                    ? MessageDeliveryState.failed
                    : _mapOutgoingStatus(outgoingMessage.status),
              EventStatus.sending =>
                outgoingMessage == null
                    ? MessageDeliveryState.sending
                    : _mapOutgoingStatus(outgoingMessage.status),
              EventStatus.sent => MessageDeliveryState.sent,
              EventStatus.synced => MessageDeliveryState.synced,
            }
          : _mapOutgoingStatus(pendingEdit.status),
      transactionId: effectiveOutgoing?.transactionId ?? event.transactionId,
      replyTo: replyTo,
      reactions: reactions,
      isEdited:
          pendingEdit != null ||
          event.hasAggregatedEvents(_timeline, RelationshipTypes.edit),
      isDeleted: event.redacted,
      isRead: event.receipts.any(
        (receipt) => receipt.user.id != _client.userID,
      ),
      readBy: [
        for (final receipt in event.receipts)
          if (receipt.user.id != _client.userID) receipt.user.calcDisplayname(),
      ],
      canDeleteForEveryone: event.canRedact,
      isFromBlockedUser: _client.ignoredUsers.contains(event.senderId),
      isForwarded: event.content.containsKey(_forwardedFromKey),
      // Intentional mentions only: a message that merely contains your name
      // is not a ping, and treating it as one trains people to ignore the
      // highlight.
      mentionsMe:
          !isCallStart &&
          (event.mentions.room ||
              (_client.userID != null &&
                  event.mentions.userIds.contains(_client.userID))),
      isCallStart: isCallStart,
      activity: activity,
    );
  }

  ChatMessage _mapOutgoingMessage(
    OutgoingMessage message,
    Map<String, Event> eventsById,
  ) {
    final sender = _room.unsafeGetUserFromMemoryOrFallback(_client.userID!);
    return ChatMessage(
      eventId: message.transactionId,
      senderId: _client.userID!,
      senderName: sender.calcDisplayname(),
      body: message.body,
      sentAt: message.createdAt,
      isOwn: true,
      deliveryState: _mapOutgoingStatus(message.status),
      transactionId: message.transactionId,
      replyTo: _replyPreview(message.replyToEventId, eventsById),
    );
  }

  MessageReplyPreview? _replyPreview(
    String? eventId,
    Map<String, Event> eventsById,
  ) {
    if (eventId == null) return null;
    final event = eventsById[eventId];
    if (event == null) return null;
    return MessageReplyPreview(
      eventId: eventId,
      senderName: event.senderFromMemoryOrFallback.calcDisplayname(),
      body: event.getDisplayEvent(_timeline).plaintextBody,
    );
  }

  List<MessageReaction> _reactionsFor(Event event) {
    final grouped = <String, (int, bool, List<String>)>{};
    for (final reaction in event.aggregatedEvents(
      _timeline,
      RelationshipTypes.reaction,
    )) {
      if (reaction.redacted) continue;
      final relation = reaction.content['m.relates_to'];
      final key = relation is Map ? relation['key'] : null;
      if (key is! String || key.isEmpty) continue;
      final current = grouped[key] ?? (0, false, <String>[]);
      grouped[key] = (
        current.$1 + 1,
        current.$2 || reaction.senderId == _client.userID,
        current.$3..add(reaction.senderFromMemoryOrFallback.calcDisplayname()),
      );
    }
    final reactions = grouped.entries
        .map(
          (entry) => MessageReaction(
            key: entry.key,
            count: entry.value.$1,
            reactedByMe: entry.value.$2,
            senderNames: entry.value.$3,
          ),
        )
        .toList();
    reactions.sort((a, b) => a.key.compareTo(b.key));
    return reactions;
  }

  MessageDeliveryState _mapOutgoingStatus(OutgoingMessageStatus status) =>
      switch (status) {
        OutgoingMessageStatus.pending => MessageDeliveryState.pending,
        OutgoingMessageStatus.sending => MessageDeliveryState.sending,
        OutgoingMessageStatus.failed => MessageDeliveryState.failed,
      };

  void _emit() {
    if (_disposed) return;
    _updates.add(_snapshot());
    _markLatestRead();
  }

  void _markLatestRead() {
    final eventId = _timeline.events
        .where((event) => event.status == EventStatus.synced)
        .map((event) => event.eventId)
        .firstOrNull;
    if (eventId == null || eventId == _lastReadEventId) return;
    _lastReadEventId = eventId;
    unawaited(
      _timeline.setReadMarker(eventId: eventId).catchError((Object _) {}),
    );
  }

  MessageFailure _mapFailure(MatrixException error) {
    if (error.error == MatrixError.M_UNKNOWN_TOKEN) {
      return const MessageFailure(MessageFailureCode.sessionExpired);
    }
    if (error.error == MatrixError.M_FORBIDDEN) {
      return const MessageFailure(MessageFailureCode.notAllowed);
    }
    return const MessageFailure(MessageFailureCode.serverUnavailable);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _typingStopTimer?.cancel();
    if (_typingSent) unawaited(_room.setTyping(false).catchError((_) {}));
    _timeline.cancelSubscriptions();
    unawaited(_outboxSubscription?.cancel());
    unawaited(_syncSubscription?.cancel());
    unawaited(_presenceSubscription?.cancel());
    unawaited(_updates.close());
  }
}
