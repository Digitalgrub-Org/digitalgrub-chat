import 'dart:async';
import 'dart:convert';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/notifications/domain/notification_preview.dart';
import 'package:dg_chat/features/notifications/domain/push_notification.dart';
import 'package:http/http.dart' as http;

/// Finds out what a push is about by asking the homeserver directly.
///
/// A push arrives as an event id and nothing more, deliberately: message text
/// never passes through Google or Apple. So to say more than "New message",
/// the phone fetches the event itself, over its own connection and with its
/// own token -- the message travels from our server to the phone and nowhere
/// else, exactly as it does when the chat is opened.
///
/// At most three requests: the event, then the sender's name and the room's
/// name side by side. Any failure -- no token, a 404, a slow network, a kind
/// of event this does not know -- comes back as null, and the caller shows
/// the generic notification. A missing preview is a small loss and a missing
/// notification is not, so nothing here is allowed to throw.
class MatrixNotificationDescriber {
  MatrixNotificationDescriber({
    required this.homeserver,
    required this.accessToken,
    required this.localizations,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 5),
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null;

  final Uri homeserver;

  /// Read at the moment of use, not captured: a token that changed since
  /// this was built must not be the one sent.
  final Future<String?> Function() accessToken;

  final AppLocalizations localizations;

  /// The whole lookup's budget. A backgrounded app is given seconds, not
  /// minutes, and the notification has to be drawn inside them.
  final Duration timeout;

  final http.Client _http;
  final bool _ownsHttp;

  Future<NotificationText?> call(PushNotification notification) async {
    final eventId = notification.eventId;
    if (eventId == null) return null;
    try {
      return await _describe(notification.roomId, eventId).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// Releases the connection pool, if this describer made its own.
  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<NotificationText?> _describe(String roomId, String eventId) async {
    final token = await accessToken();
    if (token == null || token.isEmpty) return null;
    final headers = {'Authorization': 'Bearer $token'};

    final event = await _getJson(['rooms', roomId, 'event', eventId], headers);
    if (event == null) return null;
    final preview = notificationPreviewOf(event);
    if (preview == null) return null;

    final (member, name) = await (
      _getJson([
        'rooms',
        roomId,
        'state',
        'm.room.member',
        preview.senderId,
      ], headers),
      _getJson(['rooms', roomId, 'state', 'm.room.name'], headers),
    ).wait;

    final sender =
        _nonEmpty(member?['displayname']) ?? _localpart(preview.senderId);
    final line = _line(preview, sender);

    // A room with a name of its own is a group or a meeting, and the name is
    // the title, so the line has to say who spoke. A direct chat has none,
    // and the person is the title. An emote already starts with the name.
    final roomName = _nonEmpty(name?['name']);
    if (roomName == null) return NotificationText(title: sender, body: line);
    return NotificationText(
      title: roomName,
      body: preview.kind == NotificationPreviewKind.emote
          ? line
          : '$sender: $line',
    );
  }

  String _line(NotificationPreview preview, String sender) =>
      switch (preview.kind) {
        NotificationPreviewKind.text => preview.text,
        NotificationPreviewKind.emote => '$sender ${preview.text}',
        NotificationPreviewKind.image => localizations.attachmentPhoto,
        NotificationPreviewKind.video => localizations.attachmentVideo,
        NotificationPreviewKind.audio => localizations.attachmentAudio,
        NotificationPreviewKind.voice => localizations.attachmentVoice,
        NotificationPreviewKind.file => localizations.attachmentFile,
      };

  /// A client-server GET, or null for anything but a JSON object with a 200.
  ///
  /// Built from path segments so every id is escaped as a segment of its
  /// own: room ids carry `!` and `:`, older event ids carry `/` and `+`.
  Future<Map<String, Object?>?> _getJson(
    List<String> path,
    Map<String, String> headers,
  ) async {
    try {
      final uri = homeserver.replace(
        pathSegments: [
          ...homeserver.pathSegments.where((segment) => segment.isNotEmpty),
          '_matrix',
          'client',
          'v3',
          ...path,
        ],
      );
      final response = await _http.get(uri, headers: headers);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

String? _nonEmpty(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// `asha` from `@asha:example.org`: better than an id, for someone whose
/// display name did not load.
String _localpart(String userId) {
  final start = userId.startsWith('@') ? 1 : 0;
  final colon = userId.indexOf(':');
  return colon > start ? userId.substring(start, colon) : userId;
}
