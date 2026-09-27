import 'dart:async';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/notifications/application/push_message_router.dart';
import 'package:dg_chat/features/notifications/data/apple_notification_taps.dart';
import 'package:dg_chat/features/notifications/data/local_notification_presenter.dart';
import 'package:dg_chat/features/notifications/data/matrix_notification_describer.dart';
import 'package:dg_chat/features/notifications/domain/push_notification.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// A room the user asked to open by tapping a notification, consumed by the
/// app shell once a navigator exists. Kept as state because a tap can arrive
/// before the widget tree is ready, from a cold start.
final pendingNotificationRoomProvider = StateProvider<String?>((ref) => null);

final notificationPresenterProvider = Provider<NotificationPresenter>((ref) {
  final presenter = LocalNotificationPresenter(
    onRoomSelected: (roomId) =>
        ref.read(pendingNotificationRoomProvider.notifier).state = roomId,
  );
  return presenter;
});

/// Subscribes to messaging events and turns them into notifications.
///
/// Foreground messages only: a terminated or backgrounded app is handled by
/// the top-level background handler, which runs in its own isolate and cannot
/// reach this provider container.
final pushMessageListenerProvider = Provider<PushMessageListener>((ref) {
  final listener = PushMessageListener(ref);
  ref.onDispose(listener.dispose);
  return listener;
});

class PushMessageListener {
  PushMessageListener(this._ref, {AppleNotificationTaps? appleTaps})
    : _appleTaps = appleTaps ?? AppleNotificationTaps();

  final Ref _ref;
  final AppleNotificationTaps _appleTaps;
  final List<StreamSubscription<RemoteMessage>> _subscriptions = [];

  /// Shared by every foreground preview lookup, and closed with the listener.
  final http.Client _http = http.Client();
  bool _started = false;

  /// Records the room a tapped notification points at, for the app shell to
  /// consume once a navigator exists.
  bool _selectRoom(String roomId) {
    if (roomId.isEmpty) return false;
    _ref.read(pendingNotificationRoomProvider.notifier).state = roomId;
    return true;
  }

  /// Returns true once messaging events are being observed.
  ///
  /// Notifications are an enhancement, so anywhere the platform cannot provide
  /// them — an unsupported target, or a test environment with no plugins —
  /// this gives up quietly rather than taking the app down with it.
  Future<bool> start() async {
    if (_started) return true;
    _started = true;
    try {
      await _subscribe();
      return true;
    } catch (_) {
      _started = false;
      return false;
    }
  }

  Future<void> _subscribe() async {
    final presenter = _ref.read(notificationPresenterProvider);
    await presenter.initialize();

    // Taps on a notification the system drew itself, which is every
    // notification on iOS now that push goes straight to APNs. No-op
    // elsewhere, where the messaging plugin reports the tap instead.
    _appleTaps.listen(_selectRoom);
    final pending = await _appleTaps.takePending();
    if (pending != null) _selectRoom(pending);

    _subscriptions.add(
      FirebaseMessaging.onMessage.listen((message) {
        unawaited(_show(message));
      }),
    );

    // Tapped while the app was backgrounded but alive.
    _subscriptions.add(
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final roomId = message.data['room_id'];
        if (roomId is String) _selectRoom(roomId);
      }),
    );

    // Tapped while the app was terminated, which is what launched it.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    final roomId = initial?.data['room_id'];
    if (roomId is String) _selectRoom(roomId);
  }

  Future<void> _show(RemoteMessage message) async {
    final localizations = await _localizations();
    final router = PushMessageRouter(
      presenter: _ref.read(notificationPresenterProvider),
      activeRoomId: _ref.read(activeRoomProvider),
      ringingRoomId: _ref.read(ringingRoomProvider),
      describe: _ref.read(appPreferencesProvider).showsNotificationPreviews
          ? MatrixNotificationDescriber(
              homeserver: _ref.read(appConfigProvider).homeserver,
              // The running client's token rather than the keystore's copy:
              // it is the one the app is using this minute.
              accessToken: () async =>
                  (await _ref.read(matrixClientProvider.future)).accessToken,
              localizations: localizations,
              httpClient: _http,
            ).call
          : null,
    );
    await router.handle(
      message.data,
      messageTitle: localizations.newMessageNotification,
    );
  }

  Future<AppLocalizations> _localizations() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    return AppLocalizations.delegate.load(
      AppLocalizations.delegate.isSupported(locale)
          ? locale
          : const Locale('en'),
    );
  }

  void dispose() {
    _appleTaps.dispose();
    _http.close();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}
