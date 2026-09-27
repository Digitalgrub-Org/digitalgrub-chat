import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromBuild());

class AppConfig {
  const AppConfig({
    required this.homeserver,
    this.pushGateway,
    this.pushAppId = 'com.digitalgrub.chat',
    this.livekitJwtUrl,
    this.meetGuestUrl,
    this.adminUrl,
    this.webPushVapidKey = '',
  });

  factory AppConfig.fromBuild() {
    const rawHomeserver = String.fromEnvironment(
      'APP_HOMESERVER_URL',
      defaultValue: 'https://chat.example.com',
    );
    final homeserver = Uri.tryParse(rawHomeserver);
    if (homeserver == null ||
        !homeserver.hasScheme ||
        homeserver.host.isEmpty ||
        !{'http', 'https'}.contains(homeserver.scheme)) {
      throw const FormatException('APP_HOMESERVER_URL must be an HTTP(S) URL.');
    }
    if (kReleaseMode && homeserver.scheme != 'https') {
      throw const FormatException(
        'APP_HOMESERVER_URL must use HTTPS in release builds.',
      );
    }

    // Defaults to the live gateway for the same reason the homeserver does:
    // a build that forgets the define is not obviously broken, it just never
    // registers a pusher and silently has no notifications. Pass an empty
    // value to switch push off, which is the local-development mode.
    const rawGateway = String.fromEnvironment(
      'APP_PUSH_GATEWAY_URL',
      defaultValue: '',
    );
    Uri? pushGateway;
    if (rawGateway.isNotEmpty) {
      final parsed = Uri.tryParse(rawGateway);
      if (parsed == null ||
          !parsed.hasScheme ||
          parsed.host.isEmpty ||
          !{'http', 'https'}.contains(parsed.scheme)) {
        throw const FormatException(
          'APP_PUSH_GATEWAY_URL must be an HTTP(S) URL.',
        );
      }
      if (kReleaseMode && parsed.scheme != 'https') {
        throw const FormatException(
          'APP_PUSH_GATEWAY_URL must use HTTPS in release builds.',
        );
      }
      pushGateway = parsed;
    }

    const appId = String.fromEnvironment(
      'APP_PUSH_APP_ID',
      defaultValue: 'com.digitalgrub.chat',
    );

    // Defaults on for the same reason the push gateway does: a build that
    // forgets the define should not silently ship without calls. Empty value
    // switches calls off, which is the local-development mode.
    const rawMeetGuest = String.fromEnvironment(
      'APP_MEET_GUEST_URL',
      defaultValue: '',
    );
    Uri? meetGuestUrl;
    if (rawMeetGuest.isNotEmpty) {
      final parsed = Uri.tryParse(rawMeetGuest);
      if (parsed == null ||
          !parsed.hasScheme ||
          parsed.host.isEmpty ||
          !{'http', 'https'}.contains(parsed.scheme)) {
        throw const FormatException(
          'APP_MEET_GUEST_URL must be an HTTP(S) URL.',
        );
      }
      if (kReleaseMode && parsed.scheme != 'https') {
        throw const FormatException(
          'APP_MEET_GUEST_URL must use HTTPS in release builds.',
        );
      }
      meetGuestUrl = parsed;
    }

    const rawLivekitJwt = String.fromEnvironment(
      'APP_LIVEKIT_JWT_URL',
      defaultValue: '',
    );
    Uri? livekitJwtUrl;
    if (rawLivekitJwt.isNotEmpty) {
      final parsed = Uri.tryParse(rawLivekitJwt);
      if (parsed == null ||
          !parsed.hasScheme ||
          parsed.host.isEmpty ||
          !{'http', 'https'}.contains(parsed.scheme)) {
        throw const FormatException(
          'APP_LIVEKIT_JWT_URL must be an HTTP(S) URL.',
        );
      }
      if (kReleaseMode && parsed.scheme != 'https') {
        throw const FormatException(
          'APP_LIVEKIT_JWT_URL must use HTTPS in release builds.',
        );
      }
      livekitJwtUrl = parsed;
    }

    // The narrow admin service: two operations from Synapse's admin API,
    // which itself stays unrouted. Empty switches the in-app admin actions
    // off, which is the local-development mode.
    const rawAdmin = String.fromEnvironment('APP_ADMIN_URL', defaultValue: '');
    Uri? adminUrl;
    if (rawAdmin.isNotEmpty) {
      final parsed = Uri.tryParse(rawAdmin);
      if (parsed == null ||
          !parsed.hasScheme ||
          parsed.host.isEmpty ||
          !{'http', 'https'}.contains(parsed.scheme)) {
        throw const FormatException('APP_ADMIN_URL must be an HTTP(S) URL.');
      }
      if (kReleaseMode && parsed.scheme != 'https') {
        throw const FormatException(
          'APP_ADMIN_URL must use HTTPS in release builds.',
        );
      }
      adminUrl = parsed;
    }

    // The VAPID public key the browser subscribes with, from your push
    // gateway's key pair; the private half stays with the gateway. Empty,
    // the default, switches web push off.
    const vapidKey = String.fromEnvironment('APP_WEB_PUSH_VAPID_KEY');

    return AppConfig(
      homeserver: homeserver,
      pushGateway: pushGateway,
      pushAppId: appId,
      livekitJwtUrl: livekitJwtUrl,
      meetGuestUrl: meetGuestUrl,
      adminUrl: adminUrl,
      webPushVapidKey: vapidKey,
    );
  }

  final Uri homeserver;

  /// Where a meeting guest trades a code and a name for call access, or null
  /// when guests are switched off.
  final Uri? meetGuestUrl;

  /// The admin service that creates users and resets passwords, or null when
  /// those actions are not offered in the app.
  final Uri? adminUrl;

  /// The Matrix push gateway notify endpoint, or null when push is disabled.
  final Uri? pushGateway;

  /// Reverse-DNS identifier that must match the push gateway's app entry.
  ///
  /// A Matrix push gateway keeps one entry per platform, because FCM and APNs
  /// need different credentials and cannot share an id. [platformPushAppId]
  /// derives the per-platform value the gateway actually expects; this is the
  /// base it is built from.
  final String pushAppId;

  bool get isPushConfigured => pushGateway != null;

  /// The LiveKit token service, or null when calls are disabled.
  final Uri? livekitJwtUrl;

  bool get isCallsConfigured => livekitJwtUrl != null;

  /// The app id to register with, suffixed for the running platform so it
  /// matches the gateway's `com.digitalgrub.chat.android` / `.ios` entries.
  /// Sending the unsuffixed id makes the gateway reject every notification
  /// with an unknown-app-id error, while pusher registration still appears to
  /// succeed.
  String get platformPushAppId => kIsWeb
      ? '$pushAppId.web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.iOS || TargetPlatform.macOS => '$pushAppId.ios',
          _ => '$pushAppId.android',
        };

  /// Base64url VAPID public key for Web Push, or empty when it is off.
  final String webPushVapidKey;

  bool get isWebPushConfigured => webPushVapidKey.isNotEmpty;

  /// Whether the gateway pushes to this platform through APNs directly rather
  /// than through FCM.
  ///
  /// It changes what the client must supply: APNs renders the notification
  /// itself from a payload the pusher carries, whereas an FCM message is
  /// handed to the app and drawn in Dart.
  bool get usesDirectApns => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };
}
