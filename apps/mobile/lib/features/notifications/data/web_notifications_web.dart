import 'dart:js_interop';
// `has`, for feature-detecting the API before touching it.
import 'dart:js_interop_unsafe';

import 'package:dg_chat/features/notifications/data/web_notifications.dart';
import 'package:web/web.dart' as web;

/// The browser's Notification API.
///
/// Everything here is guarded: an unsupported browser, a blocked API behind a
/// permissions policy, or a notification the browser simply refuses to draw
/// must all leave messaging working. A missed notification is a nuisance; a
/// thrown exception in the sync loop is a broken app.
class _BrowserNotifications implements WebNotifications {
  /// Live notifications by tag, so a room's alert can be taken down when the
  /// user opens that room. The browser gives no way to enumerate them.
  final Map<String, web.Notification> _open = {};

  static const _icon = 'icons/Icon-192.png';

  bool get _supported => globalContext.has('Notification');

  @override
  WebNotificationPermission get permission {
    if (!_supported) return WebNotificationPermission.unsupported;
    return switch (web.Notification.permission) {
      'granted' => WebNotificationPermission.granted,
      'denied' => WebNotificationPermission.denied,
      _ => WebNotificationPermission.prompt,
    };
  }

  @override
  Future<WebNotificationPermission> requestPermission() async {
    if (!_supported) return WebNotificationPermission.unsupported;
    try {
      await web.Notification.requestPermission().toDart;
    } catch (_) {
      // Safari once implemented this callback-only, and a browser is free to
      // reject the call outright. Fall through and read the state back.
    }
    return permission;
  }

  @override
  void show({
    required String tag,
    required String title,
    String? body,
    void Function()? onClick,
  }) {
    if (permission != WebNotificationPermission.granted) return;
    try {
      final notification = web.Notification(
        title,
        web.NotificationOptions(
          body: body ?? '',
          // One notification per room: a second message replaces the first
          // rather than stacking a fresh alert for the same conversation.
          tag: tag,
          icon: _icon,
        ),
      );
      notification.onclick = (web.Event _) {
        // The tab is usually behind something else, which is the whole
        // point of having been notified.
        web.window.focus();
        notification.close();
        _open.remove(tag);
        onClick?.call();
      }.toJS;
      _open[tag]?.close();
      _open[tag] = notification;
    } catch (_) {
      // Nothing to recover: the message is already in the timeline.
    }
  }

  @override
  void close(String tag) {
    final notification = _open.remove(tag);
    if (notification == null) return;
    try {
      notification.close();
    } catch (_) {
      // Already gone.
    }
  }
}

WebNotifications createWebNotifications() => _BrowserNotifications();
