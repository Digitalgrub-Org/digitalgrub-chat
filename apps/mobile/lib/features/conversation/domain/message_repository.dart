import 'package:dg_chat/core/presence.dart';
import 'dart:typed_data';

import 'package:dg_chat/features/groups/domain/group_repository.dart';

enum MessageDeliveryState { pending, sending, sent, synced, failed }

class MessageReplyPreview {
  const MessageReplyPreview({
    required this.eventId,
    required this.senderName,
    required this.body,
  });

  final String eventId;
  final String senderName;
  final String body;
}

class MessageReaction {
  const MessageReaction({
    required this.key,
    required this.count,
    required this.reactedByMe,
    this.senderNames = const [],
  });

  final String key;
  final int count;
  final bool reactedByMe;

  /// Who reacted, as display names, in the order the reactions arrived.
  ///
  /// A count alone answers "how many"; in a working group the question is
  /// always "who". Shown on hover where there is a pointer, on long-press
  /// where there is not.
  final List<String> senderNames;
}

enum AttachmentKind { image, video, audio, file }

/// A file shared in a conversation.
///
/// The bytes are never held here. [url] and [thumbnailUrl] point at the
/// homeserver's media repository, and [headers] carries the credentials it
/// now requires: authenticated media means an image widget cannot simply be
/// handed the URL.
class MessageAttachment {
  const MessageAttachment({
    required this.kind,
    required this.fileName,
    this.mimeType,
    this.sizeBytes,
    this.url,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.headers = const {},
    this.durationMs,
    this.isVoice = false,
  });

  final AttachmentKind kind;
  final String fileName;
  final String? mimeType;
  final int? sizeBytes;

  /// Null when the sender's homeserver gave no usable content URI, which is
  /// what a redacted or malformed event looks like.
  final Uri? url;
  final Uri? thumbnailUrl;

  /// Pixel dimensions, when the sender reported them. Used to reserve the
  /// right space before the image loads so the timeline does not jump.
  final double? width;
  final double? height;

  final Map<String, String> headers;

  /// Milliseconds of audio, for voice messages.
  final int? durationMs;

  /// A spoken message rather than an attached audio file: rendered as a
  /// player, not a filename.
  final bool isVoice;

  bool get isImage => kind == AttachmentKind.image;
}

class ChatMessage {
  const ChatMessage({
    required this.eventId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.sentAt,
    required this.isOwn,
    required this.deliveryState,
    this.transactionId,
    this.replyTo,
    this.reactions = const [],
    this.isEdited = false,
    this.isDeleted = false,
    this.isRead = false,
    this.canDeleteForEveryone = false,
    this.isFromBlockedUser = false,
    this.formattedBody,
    this.attachment,
    this.mentionsMe = false,
    this.isForwarded = false,
    this.isCallStart = false,
    this.activity,
    this.readBy = const [],
  });

  /// Who has read this message, as display names, excluding yourself.
  ///
  /// Matrix records a read marker as a pointer to one event, so a person
  /// appears against the last message they read rather than against every
  /// message behind it. That makes this "whose reading stopped here", which
  /// is the useful reading of it in a group: the newest of your messages
  /// carrying names is the one everyone has got to.
  final List<String> readBy;

  /// Set when this entry is something that happened to the group rather than
  /// something somebody said — a join, a removal, a new name.
  ///
  /// It reads as a line in the middle of the timeline, not a bubble, which is
  /// where people coming from WhatsApp expect to find it. Direct chats never
  /// carry these: "you joined" between two people is noise.
  final GroupActivityEntry? activity;

  /// True when this entry is activity rather than a message.
  bool get isActivity => activity != null;

  /// The file this message carries, or null for a plain text message.
  ///
  /// [body] still holds the filename, which is what the Matrix fallback puts
  /// there and what a client without attachment support would show.
  final MessageAttachment? attachment;

  /// True when this message arrived here by being forwarded from elsewhere.
  final bool isForwarded;

  /// True when this entry is somebody starting a call rather than a message.
  ///
  /// It stays in the timeline after the ring stops, which is what turns a
  /// missed call into something you can still see and act on. Whether it is
  /// still joinable is not a property of the event — the call outlives it, or
  /// ended before you looked — so the UI asks who is on a call now.
  final bool isCallStart;

  /// True when this message names the signed-in user, or the whole room.
  ///
  /// Read from the event's intentional mentions rather than by searching the
  /// text, so someone merely saying your name in passing does not light up
  /// as a ping.
  final bool mentionsMe;

  final String eventId;
  final String senderId;
  final String senderName;
  final String body;

  /// The sender's `org.matrix.custom.html` body, or null for a plain message.
  ///
  /// [body] stays the source of truth for anything that is not rendered type:
  /// search, the copy action, notification text and the chat list preview. A
  /// client that cannot render the markup still shows something sensible,
  /// which is exactly what the plaintext fallback is for.
  final String? formattedBody;
  final DateTime sentAt;
  final bool isOwn;
  final MessageDeliveryState deliveryState;
  final String? transactionId;
  final MessageReplyPreview? replyTo;
  final List<MessageReaction> reactions;
  final bool isEdited;
  final bool isDeleted;
  final bool isRead;
  final bool canDeleteForEveryone;

  /// The sender is on the account's ignore list. The homeserver stops sending
  /// their new events, but anything already cached still has to be suppressed
  /// locally.
  final bool isFromBlockedUser;
}

class ConversationSnapshot {
  const ConversationSnapshot({
    required this.roomId,
    required this.title,
    required this.messages,
    required this.canLoadOlder,
    required this.isLoadingOlder,
    required this.isDirect,
    this.typingUsers = const [],
    this.avatarUrl,
    this.avatarHeaders = const {},
    this.pinnedEventIds = const [],
    this.canPin = false,
    this.partnerPresence,
  });

  final String roomId;
  final String title;
  final List<ChatMessage> messages;
  final bool canLoadOlder;
  final bool isLoadingOlder;
  final bool isDirect;
  final List<String> typingUsers;
  final Uri? avatarUrl;
  final Map<String, String> avatarHeaders;

  /// Messages pinned in this room, oldest first.
  final List<String> pinnedEventIds;

  /// Whether this account may pin and unpin here.
  final bool canPin;

  /// The other person's presence in a direct chat; null for a group.
  final UserPresence? partnerPresence;
}

enum MessageFailureCode {
  roomNotFound,

  /// The room's power levels refuse this change. Retrying cannot help.
  notAllowed,

  emptyMessage,
  serverUnavailable,
  sessionExpired,

  /// The file exceeds what the homeserver accepts. Carried as its own code
  /// because the fix is the user's — pick a smaller file — not a retry.
  attachmentTooLarge,
  unknown,
}

class MessageFailure implements Exception {
  const MessageFailure(this.code);

  final MessageFailureCode code;
}

/// A file the user picked, ready to send.
///
/// Bytes live in memory for the duration of the send only. Files do not ride
/// the offline outbox the way text does: persisting arbitrary bytes to disk
/// and managing their lifetime is real machinery, and the trade accepted here
/// is that sending a file with no connection fails loudly instead of queueing.
/// Someone the composer can insert a mention for.
class MentionCandidate {
  const MentionCandidate({
    required this.userId,
    required this.displayName,
    required this.insertText,
    this.avatarUrl,
    this.avatarHeaders = const {},
  });

  final String userId;
  final String displayName;

  /// Exactly what goes into the message so the homeserver resolves it back to
  /// [userId] — `@Name` for a single word, `@[Two Words]` otherwise. Typing
  /// the name by hand works too, but only if it is spelled this precisely,
  /// which is the whole reason the picker exists.
  final String insertText;

  final Uri? avatarUrl;
  final Map<String, String> avatarHeaders;

  /// True for the one candidate that notifies the whole room rather than a
  /// person. It has no avatar and no real user id, so the picker draws it
  /// differently and the composer treats it the same as any other insert.
  bool get isRoomMention => userId == roomMentionId;
}

/// Sentinel user id for the "Everyone" candidate.
///
/// `@room` is what the Matrix spec reserves for a room-wide mention, and the
/// SDK turns exactly that token in a message body into `m.mentions: {room:
/// true}` — so inserting this text is all it takes to ping the room.
const roomMentionId = '@room';

class AttachmentDraft {
  const AttachmentDraft({
    required this.bytes,
    required this.fileName,
    this.mimeType,
    this.width,
    this.height,
    this.voiceDurationMs,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;

  /// Pixel dimensions when the pick was an image, so receivers can reserve
  /// the right space before the bytes arrive.
  final double? width;
  final double? height;

  /// Set for a recorded voice message; carried in the event so other clients
  /// show a proper duration before playback starts.
  final int? voiceDurationMs;

  int get sizeBytes => bytes.length;
}

abstract interface class ConversationSession {
  Stream<ConversationSnapshot> get changes;

  Future<void> loadOlder();

  Future<void> sendText(String text, {String? replyToEventId});

  /// Uploads [draft] and sends it as a file message.
  ///
  /// Throws [MessageFailure] with [MessageFailureCode.attachmentTooLarge]
  /// when the homeserver's advertised upload limit says it cannot succeed.
  Future<void> sendAttachment(AttachmentDraft draft);

  Future<void> editMessage(String eventId, String text);

  Future<void> toggleReaction(String eventId, String key);

  Future<void> deleteForMe(String eventId);

  Future<void> deleteForEveryone(String eventId);

  Future<void> updateTyping(bool isTyping);

  Future<void> retryMessage(String transactionId);

  /// People in this room whose name starts with [query], for the composer's
  /// @ autocomplete. [query] excludes the leading @.
  Future<List<MentionCandidate>> mentionCandidates(String query);

  /// Sends [message] on to another room, attachments included.
  Future<void> forwardTo(String roomId, ChatMessage message);

  /// Pins or unpins [eventId] for everyone in the room.
  Future<void> setPinned(String eventId, {required bool pinned});

  void dispose();
}

abstract interface class MessageRepository {
  Future<ConversationSession> openConversation(String roomId);
}
