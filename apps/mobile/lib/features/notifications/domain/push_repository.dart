/// A device push token obtained from FCM or APNs, together with everything the
/// homeserver needs to route notifications through the push gateway.
class PushRegistration {
  const PushRegistration({
    required this.token,
    required this.appId,
    required this.appDisplayName,
    required this.deviceDisplayName,
    required this.gatewayUrl,
    required this.language,
    this.defaultPayload,
    this.additionalData = const {},
  });

  final String token;

  /// Anything else the gateway reads off the pusher. Web Push puts the
  /// subscription's endpoint and auth secret here, since the pushkey slot
  /// only holds one string and the gateway wants three.
  final Map<String, Object?> additionalData;

  /// Extra payload the gateway merges into every notification it sends for
  /// this device, or null to send the gateway's own minimal payload.
  ///
  /// Needed where the platform renders the notification itself rather than
  /// handing it to the app: an `event_id_only` push carries no displayable
  /// text, so without this the device receives it and shows nothing.
  final Map<String, Object?>? defaultPayload;

  /// Reverse-DNS identifier agreed with the push gateway configuration.
  final String appId;
  final String appDisplayName;
  final String deviceDisplayName;

  /// The gateway's notify endpoint, for example
  /// `https://push.example.com/_matrix/push/v1/notify`.
  final Uri gatewayUrl;
  final String language;
}

/// The event type a call ring arrives as (MSC4075).
///
/// Synapse's built-in call rule only matches the old `m.call.invite`, so
/// without a rule for this type a ring produces no push at all and a locked
/// phone stays silent.
const rtcNotificationEventType = 'org.matrix.msc4075.rtc.notification';

/// Push-rule tweak that marks a notification as an incoming call.
///
/// The gateway keys off this rather than the event type, because a privacy
/// preserving `event_id_only` push carries no type at all.
const callTweak = 'dg_call';

enum PushFailureCode {
  /// Push is switched off for this build, or no gateway is configured.
  notConfigured,
  invalidToken,
  rateLimited,
  sessionExpired,
  serverUnavailable,
  unknown,
}

class PushFailure implements Exception {
  const PushFailure(this.code);

  final PushFailureCode code;
}

abstract interface class PushRepository {
  /// Registers or refreshes the pusher for [registration].
  Future<void> register(PushRegistration registration);

  /// Removes the pusher for [token]. Safe to call when none exists.
  Future<void> unregister(String token, {required String appId});

  /// Makes sure this account has a push rule for incoming calls.
  ///
  /// Idempotent: writing it again simply overwrites the same rule.
  Future<void> ensureCallPushRule();
}

/// Supplies the device push token. The default implementation returns null so
/// the application builds and runs without FCM or APNs credentials; wiring a
/// real messaging plugin means replacing this one class.
abstract interface class PushTokenSource {
  /// Returns the current token, or null when push is unavailable or disabled.
  Future<String?> currentToken();

  /// Emits a new token whenever the platform rotates it.
  Stream<String> get tokenRefreshes;
}

class DisabledPushTokenSource implements PushTokenSource {
  const DisabledPushTokenSource();

  @override
  Future<String?> currentToken() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
}

/// A browser's push subscription: where to send, and the keys that encrypt.
class WebPushSubscription {
  const WebPushSubscription({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;

  /// Base64url. The gateway uses it as the pushkey.
  final String p256dh;

  /// Base64url auth secret.
  final String auth;
}

/// Subscribes the browser to Web Push. Null everywhere that is not a browser
/// with notification permission already granted.
abstract interface class WebPushSubscriber {
  Future<WebPushSubscription?> subscribe(String vapidPublicKey);
}
