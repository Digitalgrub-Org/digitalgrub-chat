import 'package:dg_chat/features/conversation/domain/message_repository.dart';

/// Whether the Delete action belongs on [message].
///
/// Your own messages, always. Anyone else's when the room's power levels say
/// you may redact them — which is what somebody running a group needs when a
/// message has to come down, and something the message already knows through
/// [ChatMessage.canDeleteForEveryone].
///
/// A message that is already deleted offers nothing to delete.
bool canOfferDelete(ChatMessage message) =>
    !message.isDeleted && (message.isOwn || message.canDeleteForEveryone);
