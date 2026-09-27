import 'dart:async';

import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/notifications/application/notification_providers.dart';
import 'package:dg_chat/features/notifications/application/push_message_router.dart';
import 'package:dg_chat/features/notifications/data/web_notification_presenter.dart';
import 'package:dg_chat/features/notifications/domain/push_notification.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide PushNotification;

final webNotificationPresenterProvider = Provider<WebNotificationPresenter>((
  ref,
) {
  return WebNotificationPresenter(
    onRoomSelected: (roomId) =>
        ref.read(pendingNotificationRoomProvider.notifier).state = roomId,
  );
});

/// Notifies on the web from the sync the tab is already running.
///
/// There is no push gateway in play: browsers reach the notification centre
/// through a service worker and a separate subscription, and none of that is
/// set up. What this covers instead is the case people actually hit — the app
/// open in a tab behind something else — and it costs no server work at all.
final webNotificationListenerProvider = Provider<WebNotificationListener>((
  ref,
) {
  final listener = WebNotificationListener(ref);
  ref.onDispose(listener.dispose);
  return listener;
});

class WebNotificationListener {
  WebNotificationListener(this._ref);

  final Ref _ref;
  StreamSubscription<Event>? _subscription;
  bool _started = false;

  /// Begins watching for messages worth notifying about.
  ///
  /// Returns false anywhere that is not a browser, and on a browser that has
  /// not granted permission — the caller is expected to ask for it and start
  /// again, rather than have a background service raise a prompt out of
  /// nowhere.
  Future<bool> start() async {
    if (!kIsWeb) return false;
    if (_started) return true;
    final presenter = _ref.read(webNotificationPresenterProvider);
    if (!presenter.isPermitted) return false;

    final client = await _ref.read(matrixClientProvider.future);
    _started = true;

    // The SDK has already applied the account's push rules to this stream,
    // so muted rooms, own messages and mention-only settings are respected
    // without the client second-guessing the server.
    _subscription = client.onNotification.stream.listen((event) {
      unawaited(_notify(event));
    });
    return true;
  }

  Future<void> _notify(Event event) async {
    final room = event.room;
    final body = await _preview(event);
    if (body == null) return;

    final router = PushMessageRouter(
      presenter: _ref.read(webNotificationPresenterProvider),
      activeRoomId: _ref.read(activeRoomProvider),
      ringingRoomId: _ref.read(ringingRoomProvider),
    );
    await router.deliver(
      PushNotification(
        roomId: room.id,
        eventId: event.eventId,
        unreadCount: room.notificationCount,
        body: body,
      ),
      // The room name is the title -- a notification saying only "New
      // message" would be worse than the one the browser draws for free.
      messageTitle: room.getLocalizedDisplayname(),
    );
  }

  /// The line under the title, or null for an event not worth an alert.
  Future<String?> _preview(Event event) async {
    if (event.type != EventTypes.Message) return null;
    if (event.redacted) return null;
    final text = event.plaintextBody.trim();
    if (text.isEmpty) return null;

    // In a group the room name is the title, so the sender has to be in the
    // body or there is no way to tell who spoke. A direct chat is already
    // titled with the person's name.
    if (event.room.isDirectChat) return text;
    final sender = event.senderFromMemoryOrFallback.calcDisplayname();
    return '$sender: $text';
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _started = false;
  }
}
