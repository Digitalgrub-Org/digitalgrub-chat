import 'package:dg_chat/features/notifications/domain/push_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The conversation currently on screen, or null when none is.
///
/// The product requirement is not to notify for the room the user is already
/// looking at, and the homeserver cannot know that, so the client decides.
final activeRoomProvider = StateProvider<String?>((ref) => null);

/// Decides what a push should do. Kept free of plugins and of Riverpod's
/// widget layer so the rules are testable on their own.
class PushMessageRouter {
  const PushMessageRouter({
    required this.presenter,
    required this.activeRoomId,
    this.ringingRoomId,
    this.describe,
  });

  final NotificationPresenter presenter;

  /// The room on screen right now, if the app is in the foreground.
  final String? activeRoomId;

  /// The room whose call is ringing right now, if any.
  final String? ringingRoomId;

  /// Finds out who wrote and what they said, where the app may show it.
  ///
  /// Null means the generic wording: the web passes its text in already,
  /// and on a phone whose owner turned previews off there is nothing to find.
  final NotificationDescriber? describe;

  /// Returns true when a notification was shown.
  Future<bool> handle(
    Map<String, dynamic> payload, {
    required String messageTitle,
  }) async {
    final notification = PushNotification.fromPayload(payload);
    if (notification == null) return false;
    return deliver(notification, messageTitle: messageTitle);
  }

  /// The rules themselves, for callers that already hold a notification —
  /// the web client builds one from its own sync instead of a gateway push.
  Future<bool> deliver(
    PushNotification notification, {
    required String messageTitle,
  }) async {
    // A counts-only push updates the badge; it is not a new message.
    if (!notification.isMessage) return false;

    // A ringing call raises its own surface -- a full-screen incoming call on
    // a phone, a banner on the web -- and the push for that same ring would
    // sit underneath it saying "New message". The gateway cannot tell the two
    // apart, so the client does.
    if (ringingRoomId != null && notification.roomId == ringingRoomId) {
      return false;
    }

    // Already reading this room, so an alert would be noise. Clear anything
    // stale for it instead.
    if (notification.roomId == activeRoomId) {
      await presenter.dismissForRoom(notification.roomId);
      return false;
    }

    final text = await _describe(notification);
    if (text == null) {
      await presenter.show(notification, title: messageTitle);
    } else {
      await presenter.show(notification.withBody(text.body), title: text.title);
    }
    return true;
  }

  /// Asked only once the rules above have settled on showing something, so a
  /// push for the room already on screen costs no requests at all.
  Future<NotificationText?> _describe(PushNotification notification) async {
    final describe = this.describe;
    if (describe == null) return null;
    try {
      return await describe(notification);
    } catch (_) {
      // Describers are written not to throw. One that does anyway costs the
      // preview, never the notification.
      return null;
    }
  }
}
