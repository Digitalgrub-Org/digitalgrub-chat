import 'package:dg_chat/features/notifications/data/firebase_push_token_source.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockMessaging extends Mock implements FirebaseMessaging {}

void main() {
  late _MockMessaging messaging;
  late List<Duration> waits;

  setUp(() {
    messaging = _MockMessaging();
    waits = [];
    when(
      () => messaging.requestPermission(),
    ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
    when(() => messaging.getToken()).thenAnswer((_) async => 'fcm-token');
  });

  FirebasePushTokenSource source(TargetPlatform platform) {
    return FirebasePushTokenSource(
      messaging: messaging,
      platform: platform,
      apnsAttempts: 4,
      delay: (duration) async => waits.add(duration),
    );
  }

  group('on iOS', () {
    test('registers the APNs token, never the FCM one', () async {
      // The gateway pushes to Apple directly, so the pushkey has to be the
      // APNs device token. An FCM token here is rejected by Apple as a bad
      // device token while registration still looks like it succeeded.
      when(
        () => messaging.getAPNSToken(),
      ).thenAnswer((_) async => 'apns-token');

      expect(await source(TargetPlatform.iOS).currentToken(), 'apns-token');
      verifyNever(() => messaging.getToken());
    });

    test('waits for the APNs token to arrive', () async {
      // APNs hands its token over a beat after permission is granted. Reading
      // it once and giving up is what left the first TestFlight build with no
      // pusher registered at all.
      var reads = 0;
      when(
        () => messaging.getAPNSToken(),
      ).thenAnswer((_) async => ++reads < 3 ? null : 'apns-token');

      expect(await source(TargetPlatform.iOS).currentToken(), 'apns-token');
      expect(reads, 3);
      expect(waits, hasLength(2));
    });

    test('takes the token on the first read without waiting', () async {
      when(
        () => messaging.getAPNSToken(),
      ).thenAnswer((_) async => 'apns-token');

      expect(await source(TargetPlatform.iOS).currentToken(), 'apns-token');
      expect(waits, isEmpty);
    });

    test('ignores FCM token rotations', () async {
      // onTokenRefresh emits FCM tokens. Letting one through would overwrite a
      // working APNs pushkey with a value Apple cannot deliver to.
      expect(await source(TargetPlatform.iOS).tokenRefreshes.isEmpty, isTrue);
      verifyNever(() => messaging.onTokenRefresh);
    });

    test('gives up rather than retrying forever', () async {
      when(() => messaging.getAPNSToken()).thenAnswer((_) async => null);

      expect(await source(TargetPlatform.iOS).currentToken(), isNull);
      verify(() => messaging.getAPNSToken()).called(4);
      // No trailing sleep after the final attempt.
      expect(waits, hasLength(3));
      verifyNever(() => messaging.getToken());
    });

    test('treats an empty APNs token as absent', () async {
      when(() => messaging.getAPNSToken()).thenAnswer((_) async => '');

      expect(await source(TargetPlatform.iOS).currentToken(), isNull);
    });
  });

  group('on Android', () {
    test('registers the FCM token and never consults APNs', () async {
      expect(await source(TargetPlatform.android).currentToken(), 'fcm-token');
      verifyNever(() => messaging.getAPNSToken());
      expect(waits, isEmpty);
    });

    test('follows FCM token rotations', () async {
      when(
        () => messaging.onTokenRefresh,
      ).thenAnswer((_) => Stream.value('rotated'));

      expect(
        await source(TargetPlatform.android).tokenRefreshes.first,
        'rotated',
      );
    });
  });

  test('returns nothing when the user declines notifications', () async {
    when(
      () => messaging.requestPermission(),
    ).thenAnswer((_) async => _settings(AuthorizationStatus.denied));

    expect(await source(TargetPlatform.android).currentToken(), isNull);
    verifyNever(() => messaging.getToken());
  });

  test('reports no token when the platform throws', () async {
    // A simulator without a push capability throws rather than returning null,
    // and that must not break sign-in.
    when(() => messaging.requestPermission()).thenThrow(Exception('no push'));

    expect(await source(TargetPlatform.iOS).currentToken(), isNull);
  });
}

NotificationSettings _settings(AuthorizationStatus status) =>
    NotificationSettings(
      alert: AppleNotificationSetting.enabled,
      announcement: AppleNotificationSetting.disabled,
      authorizationStatus: status,
      badge: AppleNotificationSetting.enabled,
      carPlay: AppleNotificationSetting.disabled,
      lockScreen: AppleNotificationSetting.enabled,
      notificationCenter: AppleNotificationSetting.enabled,
      showPreviews: AppleShowPreviewSetting.always,
      timeSensitive: AppleNotificationSetting.disabled,
      criticalAlert: AppleNotificationSetting.disabled,
      sound: AppleNotificationSetting.enabled,
      providesAppNotificationSettings: AppleNotificationSetting.disabled,
    );
