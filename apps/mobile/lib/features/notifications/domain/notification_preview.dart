/// What one Matrix message says, cut down to what a notification can carry.
///
/// Reads the raw event JSON rather than the SDK's `Event`, because the place
/// this runs most -- a push waking an app that was killed -- has no Matrix
/// client to build one from. It has whatever the homeserver sent back for a
/// single event id, and nothing else.
library;

enum NotificationPreviewKind { text, emote, image, video, audio, voice, file }

class NotificationPreview {
  const NotificationPreview({
    required this.senderId,
    required this.kind,
    this.text = '',
  });

  final String senderId;
  final NotificationPreviewKind kind;

  /// The words, for text and emotes. Empty for an attachment, whose body is
  /// only ever a filename: "IMG_0421.HEIC" tells nobody a photo arrived.
  final String text;
}

/// The most a notification carries, in characters. The shade shows a few
/// lines at best; anything past this is somebody's pasted log.
const notificationPreviewMaxLength = 400;

/// The preview for [event], or null when it is not a message worth one: a
/// state change, a redaction's empty shell, a reply that is all quote.
NotificationPreview? notificationPreviewOf(Map<String, Object?> event) {
  if (event['type'] != 'm.room.message') return null;
  final sender = event['sender'];
  if (sender is! String || sender.isEmpty) return null;

  var content = event['content'];
  if (content is! Map) return null;
  final relatesTo = content['m.relates_to'];
  // An edit carries its new text in m.new_content. Its own body is a
  // "* corrected text" fallback for clients that do not understand edits.
  final replacement = content['m.new_content'];
  if (relatesTo is Map &&
      relatesTo['rel_type'] == 'm.replace' &&
      replacement is Map) {
    content = replacement;
  }

  final msgtype = content['msgtype'];
  final body = content['body'];
  // Redaction keeps an event's type and strips its content, so this is
  // also where a deleted message stops.
  if (msgtype is! String || body is! String) return null;

  final kind = switch (msgtype) {
    'm.image' => NotificationPreviewKind.image,
    'm.video' => NotificationPreviewKind.video,
    // MSC3245: the marker that makes an audio file a voice message, the
    // same one this app puts on the voice notes it sends.
    'm.audio' when content.containsKey('org.matrix.msc3245.voice') =>
      NotificationPreviewKind.voice,
    'm.audio' => NotificationPreviewKind.audio,
    'm.file' => NotificationPreviewKind.file,
    'm.emote' => NotificationPreviewKind.emote,
    // m.text, m.notice, and anything newer: every message type has a
    // plain-text body, and saying it beats saying nothing.
    _ => NotificationPreviewKind.text,
  };
  if (kind != NotificationPreviewKind.text &&
      kind != NotificationPreviewKind.emote) {
    return NotificationPreview(senderId: sender, kind: kind);
  }

  final isReply = relatesTo is Map && relatesTo['m.in_reply_to'] is Map;
  var text = (isReply ? stripReplyFallback(body) : body).trim();
  if (text.isEmpty) return null;
  // By code point, so the cut never lands inside a surrogate pair.
  final runes = text.runes;
  if (runes.length > notificationPreviewMaxLength) {
    text =
        '${String.fromCharCodes(runes.take(notificationPreviewMaxLength)).trimRight()}…';
  }
  return NotificationPreview(senderId: sender, kind: kind, text: text);
}

/// A reply's body with the quoted original taken off the front.
///
/// Replies carry what they answer as leading `> ` lines and a blank line --
/// a fallback for clients that cannot draw a quote. Left in, a notification
/// for "yes" reads "> <@asha:…> are you coming?" and never gets to the yes.
String stripReplyFallback(String body) {
  final lines = body.split('\n');
  var start = 0;
  while (start < lines.length && lines[start].startsWith('>')) {
    start++;
  }
  if (start == 0) return body;
  while (start < lines.length && lines[start].trim().isEmpty) {
    start++;
  }
  return lines.skip(start).join('\n');
}
