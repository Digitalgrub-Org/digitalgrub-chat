import 'package:dg_chat/core/presence.dart';
export 'package:dg_chat/core/presence.dart';

/// What the newest message in a room is, when it is not plain text. Carried
/// as a kind rather than a phrase because wording is localized and belongs to
/// the presentation layer.
enum ChatPreviewKind { text, image, video, audio, file }

class ChatSummary {
  const ChatSummary({
    required this.roomId,
    required this.name,
    required this.lastMessage,
    required this.lastActivity,
    required this.unreadCount,
    this.highlightCount = 0,
    this.previewKind = ChatPreviewKind.text,
    required this.isDirect,
    this.pendingCount = 0,
    this.hasFailedMessages = false,
    this.isInvite = false,
    this.invitedBy,
    this.avatarUrl,
    this.avatarHeaders = const {},
    this.presence,
  });

  /// The other person's presence, for a direct chat. Null for a group, where
  /// one dot could not say anything true about several people.
  final UserPresence? presence;

  final String roomId;
  final String name;
  final String lastMessage;
  final DateTime? lastActivity;
  final int unreadCount;

  /// How many of the unread messages actually mention this account.
  ///
  /// Separate from [unreadCount] because the two deserve different volume:
  /// a mention is someone waiting on you, ordinary unread is not. Kept
  /// optional so the demo and test summaries that predate it still build.
  final int highlightCount;

  /// Lets the list say "Photo" instead of showing a raw filename, which is all
  /// the plaintext fallback of a file event contains.
  final ChatPreviewKind previewKind;
  final bool isDirect;
  final int pendingCount;
  final bool hasFailedMessages;

  /// The account has been invited but has not joined. Matrix will not serve
  /// the timeline until it does, so an invited room cannot simply be opened.
  final bool isInvite;

  /// Display name of whoever sent the invite, when it can be resolved.
  final String? invitedBy;
  final Uri? avatarUrl;
  final Map<String, String> avatarHeaders;
}

enum ChatFailureCode { serverUnavailable, sessionExpired, unknown }

class ChatFailure implements Exception {
  const ChatFailure(this.code);

  final ChatFailureCode code;
}

abstract interface class ChatRepository {
  Stream<List<ChatSummary>> watchChats();

  Future<void> refresh();

  /// Joins an invited room. Until this happens the account cannot read the
  /// timeline, so every invite needs an explicit decision.
  Future<void> acceptInvite(String roomId);

  /// Rejects an invited room by leaving it.
  Future<void> declineInvite(String roomId);
}
