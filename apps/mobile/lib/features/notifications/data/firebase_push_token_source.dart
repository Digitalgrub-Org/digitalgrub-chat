import 'dart:async';

import 'package:dg_chat/features/notifications/domain/push_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Supplies the device push token: the FCM registration token on Android, and
/// the raw APNs device token on Apple platforms.
///
/// The two differ because the gateway talks to each service directly. Sending
/// an FCM token to the APNs pushkin makes Apple reject every notification as a
/// bad device token, so the platform split here has to match the gateway's app
/// configuration.
///
/// Firebase is still the source of the APNs token on iOS: the messaging plugin
/// already captures it from the system, so using it avoids hand-writing a
/// platform channel for the same value.
///
/// This is the only class in the application that touches a messaging SDK. It
/// exists so `PushRegistrationService` and everything above it stay testable
/// and free of platform plugins.
class FirebasePushTokenSource implements PushTokenSource {
  FirebasePushTokenSource({
    FirebaseMessaging? messaging,
    TargetPlatform? platform,
    this.apnsAttempts = 10,
    this.apnsRetryDelay = const Duration(milliseconds: 300),
    Future<void> Function(Duration)? delay,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _platformOverride = platform,
       _delay = delay ?? Future<void>.delayed;

  final FirebaseMessaging _messaging;
  final TargetPlatform? _platformOverride;
  final Future<void> Function(Duration) _delay;

  /// How many times to look for the APNs token before giving up.
  final int apnsAttempts;

  /// How long to wait between those attempts.
  final Duration apnsRetryDelay;

  TargetPlatform get _platform => _platformOverride ?? defaultTargetPlatform;

  bool get _isApple =>
      _platform == TargetPlatform.iOS || _platform == TargetPlatform.macOS;

  @override
  Future<String?> currentToken() async {
    try {
      // iOS will not issue a token until the user has granted permission, and
      // Android 13+ needs the runtime notification permission too. Asking here
      // keeps the prompt tied to signing in rather than to app launch.
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return null;
      }

      // Awaited, not just returned: an unawaited future completes after this
      // try has exited, so a phone with no push capability would throw past
      // the catch below instead of reporting the no-token state it means.
      if (_isApple) return await _awaitApnsToken();
      return await _messaging.getToken();
    } catch (_) {
      // A device without Play Services, or a simulator without a push
      // capability, simply has no token. That is the disabled state, not an
      // error worth surfacing to the user.
      return null;
    }
  }

  /// Polls for the APNs token, returning null if it never arrives.
  ///
  /// The handover from the system is asynchronous and routinely completes a
  /// beat after permission is granted. Reading it once and giving up means the
  /// first sign-in on a device registers no pusher at all and the account
  /// silently never receives a notification.
  Future<String?> _awaitApnsToken() async {
    for (var attempt = 0; attempt < apnsAttempts; attempt++) {
      final token = await _messaging.getAPNSToken();
      if (token != null && token.isNotEmpty) return token;
      if (attempt < apnsAttempts - 1) await _delay(apnsRetryDelay);
    }
    return null;
  }

  @override
  Stream<String> get tokenRefreshes {
    // onTokenRefresh emits FCM registration tokens. On Apple that is the wrong
    // kind of token entirely, and pushing one into the pusher would replace a
    // working APNs pushkey with a value Apple rejects. APNs tokens are stable
    // in practice, and a rotation is picked up by the read at the next launch.
    if (_isApple) return const Stream.empty();
    return _messaging.onTokenRefresh;
  }
}
