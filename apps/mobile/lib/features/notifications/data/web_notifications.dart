import 'web_notifications_stub.dart'
    if (dart.library.js_interop) 'web_notifications_web.dart'
    as impl;

/// Where the browser stands on showing notifications for this site.
enum WebNotificationPermission {
  /// Nobody has been asked yet, so asking is worth doing.
  prompt,

  /// Notifications may be shown.
  granted,

  /// The user said no. Asking again does nothing; only the browser's own
  /// site settings can undo it.
  denied,

  /// Not a browser, or a browser without the API.
  unsupported,
}

/// The browser's Notification API, behind an interface so the presenter that
/// decides *what* to show can be tested without a browser.
abstract interface class WebNotifications {
  WebNotificationPermission get permission;

  /// Raises the browser's permission prompt. Browsers only honour this during
  /// a user gesture, so it must be called straight from a tap.
  Future<WebNotificationPermission> requestPermission();

  /// Shows a notification, replacing any earlier one with the same [tag].
  void show({
    required String tag,
    required String title,
    String? body,
    void Function()? onClick,
  });

  /// Closes the notification with [tag], if it is still on screen.
  void close(String tag);
}

/// The browser implementation on web, and one that reports [unsupported]
/// everywhere else.
WebNotifications createWebNotifications() => impl.createWebNotifications();
