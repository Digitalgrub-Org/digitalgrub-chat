import 'package:dg_chat/features/notifications/data/web_notifications.dart';

/// The mobile side of the conditional import. Android and iOS notify through
/// the push gateway and the system notification centre, so there is nothing
/// here to do — but the code has to compile for them.
class _UnsupportedWebNotifications implements WebNotifications {
  const _UnsupportedWebNotifications();

  @override
  WebNotificationPermission get permission =>
      WebNotificationPermission.unsupported;

  @override
  Future<WebNotificationPermission> requestPermission() async =>
      WebNotificationPermission.unsupported;

  @override
  void show({
    required String tag,
    required String title,
    String? body,
    void Function()? onClick,
  }) {}

  @override
  void close(String tag) {}
}

WebNotifications createWebNotifications() =>
    const _UnsupportedWebNotifications();
