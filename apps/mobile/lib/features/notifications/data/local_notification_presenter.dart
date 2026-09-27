import 'package:dg_chat/features/notifications/domain/push_notification.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Renders notifications with the platform notification centre.
///
/// The gateway sends data-only pushes, so nothing is displayed unless the app
/// draws it. This is the only class that touches the plugin.
class LocalNotificationPresenter implements NotificationPresenter {
  LocalNotificationPresenter({
    FlutterLocalNotificationsPlugin? plugin,
    this.onRoomSelected,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'dg_chat_messages';
  static const _channelName = 'Messages';
  static const _channelDescription = 'New messages in your conversations';

  final FlutterLocalNotificationsPlugin _plugin;

  /// Invoked with a room id when the user taps a notification.
  final void Function(String roomId)? onRoomSelected;

  @override
  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is requested by the messaging layer at sign-in, so the
        // prompt is not raised twice.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final roomId = response.payload;
        if (roomId != null && roomId.isNotEmpty) onRoomSelected?.call(roomId);
      },
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
  }

  @override
  Future<void> show(
    PushNotification notification, {
    required String title,
  }) async {
    final body = notification.body;
    await _plugin.show(
      // One notification per room, so a second message replaces the first
      // rather than stacking a separate alert for the same conversation.
      id: notification.roomId.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          // Private: on a lock screen set to hide sensitive content, Android
          // says a message came and keeps who and what off the glass. The
          // phone's own privacy setting wins over ours.
          visibility: NotificationVisibility.private,
          // A long message opens up when pulled down, instead of stopping at
          // one line. Plain text, never HTML: this is somebody's message.
          styleInformation: body == null ? null : BigTextStyleInformation(body),
          number: notification.unreadCount > 0
              ? notification.unreadCount
              : null,
        ),
        iOS: DarwinNotificationDetails(
          badgeNumber: notification.unreadCount > 0
              ? notification.unreadCount
              : null,
        ),
      ),
      payload: notification.roomId,
    );
  }

  @override
  Future<void> dismissForRoom(String roomId) =>
      _plugin.cancel(id: roomId.hashCode);
}
