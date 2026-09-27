/// A push delivered by the gateway.
///
/// Pushes use the `event_id_only` format, so the payload carries identifiers
/// and counts but no message text — deliberately, so content never passes
/// through Google or Apple. Anything richer has to be read from the
/// homeserver once the app is awake.
class PushNotification {
  const PushNotification({
    required this.roomId,
    this.eventId,
    this.unreadCount = 0,
    this.body,
  });

  /// Builds a notification from a gateway payload, or returns null when the
  /// payload is not one: gateways also send counts-only pushes to clear
  /// badges, and those must not raise an alert.
  static PushNotification? fromPayload(Map<String, dynamic> payload) {
    final roomId = payload['room_id'];
    if (roomId is! String || roomId.isEmpty) return null;
    final eventId = payload['event_id'];
    return PushNotification(
      roomId: roomId,
      eventId: eventId is String && eventId.isNotEmpty ? eventId : null,
      unreadCount: _readCount(payload['unread']),
    );
  }

  static int _readCount(Object? value) => switch (value) {
    int() => value,
    String() => int.tryParse(value) ?? 0,
    _ => 0,
  };

  final String roomId;
  final String? eventId;
  final int unreadCount;

  /// The message itself, when the app knows it. A gateway push never carries
  /// it -- by design, so content stays off Google's and Apple's servers -- so
  /// on a phone it is filled in afterwards, by the app asking the homeserver
  /// directly (see [NotificationDescriber]).
  final String? body;

  /// A push with no event is a badge update rather than a new message.
  bool get isMessage => eventId != null;

  /// The same push with the line under the title filled in.
  PushNotification withBody(String body) => PushNotification(
    roomId: roomId,
    eventId: eventId,
    unreadCount: unreadCount,
    body: body,
  );
}

/// What a notification says, once the app has found out.
class NotificationText {
  const NotificationText({required this.title, required this.body});

  /// The person in a direct chat; the group's name in a group.
  final String title;

  /// The message itself, led by who sent it whenever the title is a group.
  final String body;
}

/// Finds out what a push is about. Returns null whenever it cannot say, and
/// the caller falls back to the generic wording.
typedef NotificationDescriber =
    Future<NotificationText?> Function(PushNotification notification);

/// Shows notifications to the user. Abstracted so the decision logic can be
/// tested without the platform plugin.
abstract interface class NotificationPresenter {
  Future<void> initialize();

  Future<void> show(PushNotification notification, {required String title});

  /// Clears any notifications for a room, used when the user opens it.
  Future<void> dismissForRoom(String roomId);
}
