import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/features/notifications/data/matrix_push_repository.dart';
import 'package:dg_chat/features/notifications/data/web_push_subscriber.dart';
import 'package:dg_chat/features/notifications/domain/push_repository.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pushRepositoryProvider = FutureProvider<PushRepository>((ref) async {
  return MatrixPushRepository(await ref.watch(matrixClientProvider.future));
});

/// Replaced with a real FCM/APNs source once credentials exist. The default
/// yields no token, which is the supported push-disabled development mode.
final pushTokenSourceProvider = Provider<PushTokenSource>(
  (ref) => const DisabledPushTokenSource(),
);

final pushRegistrationServiceProvider = Provider<PushRegistrationService>((
  ref,
) {
  final service = PushRegistrationService(
    config: ref.watch(appConfigProvider),
    tokenSource: ref.watch(pushTokenSourceProvider),
    webPush: createWebPushSubscriber(),
    loadRepository: () => ref.read(pushRepositoryProvider.future),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Keeps the homeserver's pusher list in step with this device's push token.
class PushRegistrationService {
  PushRegistrationService({
    required AppConfig config,
    required PushTokenSource tokenSource,
    required Future<PushRepository> Function() loadRepository,
    WebPushSubscriber? webPush,
    bool isWeb = kIsWeb,
    String deviceDisplayName = 'Digitalgrub Chat',
    String appDisplayName = 'Digitalgrub Chat',
    String language = 'en',
  }) : _config = config,
       _tokenSource = tokenSource,
       _webPush = webPush,
       _isWeb = isWeb,
       _loadRepository = loadRepository,
       _deviceDisplayName = deviceDisplayName,
       _appDisplayName = appDisplayName,
       _language = language;

  final AppConfig _config;
  final PushTokenSource _tokenSource;
  final WebPushSubscriber? _webPush;

  /// Injected so the web path can be exercised in tests, where kIsWeb is a
  /// compile-time false.
  final bool _isWeb;
  final Future<PushRepository> Function() _loadRepository;
  final String _deviceDisplayName;
  final String _appDisplayName;
  final String _language;

  StreamSubscription<String>? _refreshSubscription;
  String? _registeredToken;

  /// The app id the alert pusher was registered under, so sign-out removes
  /// exactly that pusher whichever platform's id it turned out to be.
  String? _registeredAppId;
  String? _registeredVoipToken;

  /// Registers the current token and follows later rotations. Returns false
  /// when push is not configured or the platform has no token, which is a
  /// normal state rather than a failure.
  ///
  /// [alertText] is the wording Apple shows on the lock screen. It is passed in
  /// rather than read here because it has to be localized, and this layer has
  /// no BuildContext.
  Future<bool> start({String? alertText}) async {
    if (!_config.isPushConfigured) return false;
    // A browser has no FCM token; it has a push subscription, and only once
    // notifications are permitted. Everything below is phone business.
    if (_isWeb) return _registerWeb();

    _refreshSubscription ??= _tokenSource.tokenRefreshes.listen((token) {
      // A rotation invalidates the old pusher; registering the new token with
      // append false replaces it rather than adding a duplicate.
      unawaited(_register(token, alertText: alertText));
    });

    // Independent of the token: the rule belongs to the account, and a device
    // that never gets a token should still leave the account able to ring.
    unawaited(_ensureCallRule());

    // iOS only: the PushKit token is the ring channel. Registered besides
    // the alert pusher, under its own app id, so the gateway can send call
    // events as VoIP pushes -- the only push Apple lets become a real
    // incoming-call screen -- and everything else as ordinary alerts.
    unawaited(refreshVoipRegistration());

    final token = await _tokenSource.currentToken();
    if (token == null || token.isEmpty) return false;
    return _register(token, alertText: alertText);
  }

  /// Re-checks the ring channel. Cheap when nothing changed, and called on
  /// every return to the foreground as well as at startup, because the one
  /// launch that races the PushKit token must not cost the account its ring
  /// channel until the next cold start.
  Future<void> refreshVoipRegistration() => _registerVoip();

  Future<void> _registerVoip() async {
    if (!_config.usesDirectApns) return;
    final gateway = _config.pushGateway;
    if (gateway == null) return;
    try {
      // PushKit hands the token over on its own schedule, usually a breath
      // after launch. Asking exactly once at startup raced it and lost --
      // an account with no ring channel at all -- so poll briefly instead.
      String? token;
      for (var attempt = 0; attempt < 15; attempt++) {
        final value = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
        if (value is String && value.isNotEmpty) {
          token = value;
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (token == null) return;
      // Defensive: the pushkey IS the routing key, and a malformed one is a
      // silent dead channel that Apple 400s on every ring.
      token = token.toLowerCase();
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) return;
      // The usual case on a resume: the same token this account already
      // registered. Re-posting it would be a round-trip per foreground for
      // no change at all. Sign-out clears this, so the next sign-in still
      // registers.
      if (token == _registeredVoipToken) return;
      final repository = await _loadRepository();
      await repository.register(
        PushRegistration(
          token: token,
          appId: '${_config.platformPushAppId}.voip',
          appDisplayName: _appDisplayName,
          deviceDisplayName: _deviceDisplayName,
          gatewayUrl: gateway,
          language: _language,
          // No payload: the gateway builds the VoIP push itself, and it
          // never renders as a notification.
          defaultPayload: null,
        ),
      );
      _registeredVoipToken = token;
    } catch (_) {
      // Ringing is an enhancement. A missing PushKit token -- simulator,
      // denied capability, plugin absent in tests -- must not block sign-in.
    }
  }

  /// Payload Apple needs to render a notification without the app's help.
  ///
  /// An `event_id_only` push carries no displayable text, so on its own it
  /// arrives as a silent notification and shows nothing. Only static wording
  /// goes in here: the message itself never travels over the push path.
  Map<String, Object?>? _applePayload(String? alertText) {
    if (!_config.usesDirectApns) return null;
    return {
      'aps': {
        'alert': {'title': _appDisplayName, 'body': alertText ?? 'New message'},
        'sound': 'default',
      },
    };
  }

  Future<void> _ensureCallRule() async {
    try {
      final repository = await _loadRepository();
      await repository.ensureCallPushRule();
    } catch (_) {
      // Best effort: a missing rule costs ringing on a locked phone, not the
      // ability to sign in.
    }
  }

  Future<bool> _register(String token, {String? alertText}) async {
    final gateway = _config.pushGateway;
    if (gateway == null) return false;
    try {
      final repository = await _loadRepository();
      await repository.register(
        PushRegistration(
          token: token,
          appId: _config.platformPushAppId,
          appDisplayName: _appDisplayName,
          deviceDisplayName: _deviceDisplayName,
          gatewayUrl: gateway,
          language: _language,
          defaultPayload: _applePayload(alertText),
        ),
      );
      _registeredToken = token;
      _registeredAppId = _config.platformPushAppId;
      return true;
    } on PushFailure {
      // Push is an enhancement; a registration failure must not block sign-in.
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _registerWeb() async {
    final gateway = _config.pushGateway;
    final webPush = _webPush;
    if (gateway == null || webPush == null || !_config.isWebPushConfigured) {
      return false;
    }
    unawaited(_ensureCallRule());
    final subscription = await webPush.subscribe(_config.webPushVapidKey);
    if (subscription == null) return false;
    if (subscription.p256dh == _registeredToken) return true;
    try {
      final repository = await _loadRepository();
      await repository.register(
        PushRegistration(
          // The gateway keys the subscription by its p256dh; endpoint and
          // auth travel alongside. events_only: a push with no event -- a
          // bare unread-count update -- is not worth waking a closed tab
          // for, and would show as a notification about nothing.
          token: subscription.p256dh,
          appId: '${_config.pushAppId}.web',
          appDisplayName: _appDisplayName,
          deviceDisplayName: _deviceDisplayName,
          gatewayUrl: gateway,
          language: _language,
          additionalData: {
            'endpoint': subscription.endpoint,
            'auth': subscription.auth,
            'events_only': true,
          },
        ),
      );
      _registeredToken = subscription.p256dh;
      _registeredAppId = '${_config.pushAppId}.web';
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes this device's pusher, so a signed-out device stops receiving
  /// notifications for the account.
  Future<void> stop() async {
    final voipToken = _registeredVoipToken;
    _registeredVoipToken = null;
    if (voipToken != null) {
      try {
        final repository = await _loadRepository();
        await repository.unregister(
          voipToken,
          appId: '${_config.platformPushAppId}.voip',
        );
      } catch (_) {
        // Same rule as below: logout must not depend on the homeserver.
      }
    }
    final token = _registeredToken;
    final appId = _registeredAppId ?? _config.platformPushAppId;
    _registeredToken = null;
    _registeredAppId = null;
    if (token == null) return;
    try {
      final repository = await _loadRepository();
      await repository.unregister(token, appId: appId);
    } catch (_) {
      // Logout must succeed even when the homeserver cannot be reached.
    }
  }

  Future<void> dispose() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
  }
}
