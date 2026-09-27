import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/core/storage/secure_key_value_store.dart';
import 'package:dg_chat/features/calls/data/native_incoming_call.dart';
import 'package:dg_chat/features/notifications/application/push_message_router.dart';
import 'package:dg_chat/features/notifications/application/push_providers.dart';
import 'package:dg_chat/features/notifications/data/firebase_push_token_source.dart';
import 'package:dg_chat/features/notifications/data/local_notification_presenter.dart';
import 'package:dg_chat/features/notifications/data/matrix_notification_describer.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:dg_chat/matrix/client/secure_matrix_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles pushes that arrive while the app is backgrounded or terminated.
///
/// This runs in its own isolate with no access to the running app, so it
/// builds everything it needs from scratch and cannot consult the provider
/// container — including which room is on screen. That is acceptable: if the
/// app is not in the foreground, no room is on screen.
@pragma('vm:entry-point')
Future<void> handleBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  final presenter = LocalNotificationPresenter();
  await presenter.initialize();

  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  final localizations = await AppLocalizations.delegate.load(
    AppLocalizations.delegate.isSupported(locale) ? locale : const Locale('en'),
  );

  // A call push rings like a phone, not like a message. The marker comes
  // from our Sygnal pushkin -- stock Sygnal strips the tweaks that would
  // say so -- and a phone on a build without it simply keeps the old
  // "New message" behaviour, since the marker never arrives.
  if (message.data['dg_call'] == '1') {
    final roomId = message.data['room_id'];
    if (roomId is String && roomId.isNotEmpty) {
      try {
        await showNativeIncomingCall(
          roomId: roomId,
          callerLabel: localizations.incomingCall,
        );
        return;
      } catch (_) {
        // Fall through to an ordinary notification: a ring that arrives as
        // "New message" is still better than one that arrives as nothing.
      }
    }
  }

  final describer = await _backgroundDescriber(localizations);
  try {
    await PushMessageRouter(
      presenter: presenter,
      activeRoomId: null,
      describe: describer?.call,
    ).handle(message.data, messageTitle: localizations.newMessageNotification);
  } finally {
    describer?.close();
  }
}

/// What a background push uses to say who wrote and what, or null when the
/// phone's owner has turned previews off.
///
/// Built from storage alone, because this isolate has no running app to ask:
/// the server address is compiled in, and the token is read straight from the
/// keystore the signed-in session wrote it to.
Future<MatrixNotificationDescriber?> _backgroundDescriber(
  AppLocalizations localizations,
) async {
  try {
    final preferences = await SharedPreferences.getInstance();
    // This isolate can outlive a single push, holding the preferences it read
    // when it started; the switch may have moved since.
    await preferences.reload();
    if (!AppPreferences(preferences).showsNotificationPreviews) return null;
    return MatrixNotificationDescriber(
      homeserver: AppConfig.fromBuild().homeserver,
      accessToken: () => SecureMatrixDatabase.readAccessToken(
        PlatformSecureKeyValueStore(),
        matrixClientName,
      ),
      localizations: localizations,
    );
  } catch (_) {
    // Worst case is the notification this app always showed: "New message".
    return null;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  final messagingReady = await _initializeFirebase();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        // Without Firebase the default disabled source stays in place, which
        // is the supported push-disabled mode rather than a failure.
        if (messagingReady)
          pushTokenSourceProvider.overrideWithValue(FirebasePushTokenSource()),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
}

/// Brings up Firebase if this build has the platform configuration for it.
///
/// A checkout without `google-services.json` or `GoogleService-Info.plist`
/// still runs; it simply has no push. Startup must never fail because of a
/// missing optional capability.
Future<bool> _initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    // Registered before the app starts, as the platform requires.
    FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage);
    return true;
  } catch (_) {
    return false;
  }
}
