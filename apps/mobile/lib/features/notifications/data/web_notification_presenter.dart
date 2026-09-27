import 'package:dg_chat/features/notifications/data/web_notifications.dart';
import 'package:dg_chat/features/notifications/domain/push_notification.dart';

/// Draws notifications with the browser rather than a platform plugin.
///
/// Unlike the mobile path, nothing here passes through a push gateway: the
/// text comes straight from the sync the tab is already running, so the
/// notification can carry the message itself without it ever reaching Google
/// or Apple.
class WebNotificationPresenter implements NotificationPresenter {
  WebNotificationPresenter({
    WebNotifications? notifications,
    this.onRoomSelected,
  }) : _notifications = notifications ?? createWebNotifications();

  final WebNotifications _notifications;

  /// Invoked with a room id when the user clicks a notification.
  final void Function(String roomId)? onRoomSelected;

  /// Whether the browser will draw notifications right now.
  bool get isPermitted =>
      _notifications.permission == WebNotificationPermission.granted;

  /// Whether asking for permission is worth doing: a browser that has already
  /// been answered, either way, must not be asked again.
  bool get canRequestPermission =>
      _notifications.permission == WebNotificationPermission.prompt;

  Future<bool> requestPermission() async {
    final result = await _notifications.requestPermission();
    return result == WebNotificationPermission.granted;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show(
    PushNotification notification, {
    required String title,
  }) async {
    _notifications.show(
      tag: notification.roomId,
      title: title,
      body: notification.body,
      onClick: () => onRoomSelected?.call(notification.roomId),
    );
  }

  @override
  Future<void> dismissForRoom(String roomId) async =>
      _notifications.close(roomId);
}
