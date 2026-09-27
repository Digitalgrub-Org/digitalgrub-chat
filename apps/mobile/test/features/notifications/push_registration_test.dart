import 'dart:async';

import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/features/notifications/application/push_providers.dart';
import 'package:dg_chat/features/notifications/data/matrix_push_repository.dart';
import 'package:dg_chat/features/notifications/domain/push_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements Client {}

class _FakePusher extends Fake implements Pusher {}

class _FakePusherId extends Fake implements PusherId {}

class _FakeTokenSource implements PushTokenSource {
  _FakeTokenSource({this.token});

  String? token;
  final _refreshes = StreamController<String>.broadcast();

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<String> get tokenRefreshes => _refreshes.stream;

  void rotate(String value) => _refreshes.add(value);

  Future<void> dispose() => _refreshes.close();
}

class _FakeWebPush implements WebPushSubscriber {
  _FakeWebPush({this.subscription});

  WebPushSubscription? subscription;
  final keysSeen = <String>[];

  @override
  Future<WebPushSubscription?> subscribe(String vapidPublicKey) async {
    keysSeen.add(vapidPublicKey);
    return subscription;
  }
}

class _RecordingPushRepository implements PushRepository {
  int callRuleWrites = 0;

  @override
  Future<void> ensureCallPushRule() async => callRuleWrites++;

  final List<PushRegistration> registrations = [];
  final List<(String, String)> removals = [];
  PushFailure? failure;

  @override
  Future<void> register(PushRegistration registration) async {
    registrations.add(registration);
    final value = failure;
    if (value != null) throw value;
  }

  @override
  Future<void> unregister(String token, {required String appId}) async {
    removals.add((token, appId));
  }
}

void main() {
  final gateway = Uri.parse('https://push.example.com/_matrix/push/v1/notify');

  group('MatrixPushRepository', () {
    late _MockClient client;
    late MatrixPushRepository repository;

    setUpAll(() {
      registerFallbackValue(_FakePusher());
      registerFallbackValue(_FakePusherId());
    });

    setUp(() {
      client = _MockClient();
      repository = MatrixPushRepository(client);
    });

    test('registers an http pusher that replaces any previous one', () async {
      when(
        () => client.postPusher(any(), append: any(named: 'append')),
      ).thenAnswer((_) async {});

      await repository.register(
        PushRegistration(
          token: 'device-token',
          appId: 'com.digitalgrub.chat',
          appDisplayName: 'Digitalgrub Chat',
          deviceDisplayName: 'Pixel 8',
          gatewayUrl: gateway,
          language: 'en',
        ),
      );

      final invocation = verify(
        () => client.postPusher(
          captureAny(),
          append: captureAny(named: 'append'),
        ),
      ).captured;
      final pusher = invocation[0] as Pusher;
      expect(pusher.pushkey, 'device-token');
      expect(pusher.appId, 'com.digitalgrub.chat');
      expect(pusher.kind, 'http');
      expect(pusher.data.url, gateway);
      // Message content stays off the push path.
      expect(pusher.data.format, 'event_id_only');
      // Replacing rather than appending is what prevents duplicate alerts.
      expect(invocation[1], isFalse);
    });

    test('passes the default payload through to the pusher', () async {
      // The gateway reads default_payload off the pusher itself, so it has to
      // survive serialization as an additional property.
      when(
        () => client.postPusher(any(), append: any(named: 'append')),
      ).thenAnswer((_) async {});

      await repository.register(
        PushRegistration(
          token: 'apns-token',
          appId: 'com.digitalgrub.chat.ios',
          appDisplayName: 'Digitalgrub Chat',
          deviceDisplayName: 'iPhone',
          gatewayUrl: gateway,
          language: 'en',
          defaultPayload: const {
            'aps': {
              'alert': {'title': 'Digitalgrub Chat', 'body': 'New message'},
            },
          },
        ),
      );

      final pusher =
          verify(
                () => client.postPusher(
                  captureAny(),
                  append: any(named: 'append'),
                ),
              ).captured.single
              as Pusher;
      final json = pusher.data.toJson();
      expect(json['format'], 'event_id_only');
      expect(json['default_payload'], isA<Map<String, Object?>>());
      expect(
        (json['default_payload']! as Map<String, Object?>)['aps'],
        isNotNull,
      );
    });

    test('omits default_payload when none is supplied', () async {
      when(
        () => client.postPusher(any(), append: any(named: 'append')),
      ).thenAnswer((_) async {});

      await repository.register(
        PushRegistration(
          token: 'device-token',
          appId: 'com.digitalgrub.chat.android',
          appDisplayName: 'Digitalgrub Chat',
          deviceDisplayName: 'Pixel 8',
          gatewayUrl: gateway,
          language: 'en',
        ),
      );

      final pusher =
          verify(
                () => client.postPusher(
                  captureAny(),
                  append: any(named: 'append'),
                ),
              ).captured.single
              as Pusher;
      expect(pusher.data.toJson().containsKey('default_payload'), isFalse);
    });

    test('rejects an empty token without calling the server', () async {
      await expectLater(
        repository.register(
          PushRegistration(
            token: '   ',
            appId: 'com.digitalgrub.chat',
            appDisplayName: 'Digitalgrub Chat',
            deviceDisplayName: 'Pixel 8',
            gatewayUrl: gateway,
            language: 'en',
          ),
        ),
        throwsA(_hasPushCode(PushFailureCode.invalidToken)),
      );
      verifyNever(() => client.postPusher(any(), append: any(named: 'append')));
    });

    test('maps an expired session', () async {
      when(
        () => client.postPusher(any(), append: any(named: 'append')),
      ).thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_UNKNOWN_TOKEN',
          'error': 'Invalid token',
        }),
      );

      await expectLater(
        repository.register(
          PushRegistration(
            token: 'device-token',
            appId: 'com.digitalgrub.chat',
            appDisplayName: 'Digitalgrub Chat',
            deviceDisplayName: 'Pixel 8',
            gatewayUrl: gateway,
            language: 'en',
          ),
        ),
        throwsA(_hasPushCode(PushFailureCode.sessionExpired)),
      );
    });

    test('deletes the pusher on unregister', () async {
      when(() => client.deletePusher(any())).thenAnswer((_) async {});

      await repository.unregister(
        'device-token',
        appId: 'com.digitalgrub.chat',
      );

      final pusher =
          verify(() => client.deletePusher(captureAny())).captured.single
              as PusherId;
      expect(pusher.pushkey, 'device-token');
      expect(pusher.appId, 'com.digitalgrub.chat');
    });

    test('ignores an empty token on unregister', () async {
      await repository.unregister('', appId: 'com.digitalgrub.chat');
      verifyNever(() => client.deletePusher(any()));
    });
  });

  group('PushRegistrationService', () {
    test('does nothing when no gateway is configured', () async {
      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource(token: 'device-token');
      addTearDown(tokens.dispose);
      final service = PushRegistrationService(
        config: AppConfig(homeserver: Uri.parse('https://chat.example.com')),
        tokenSource: tokens,
        loadRepository: () async => repository,
      );
      addTearDown(service.dispose);

      expect(await service.start(), isFalse);
      expect(repository.registrations, isEmpty);
    });

    test(
      'writes the call push rule so a ring can wake a locked phone',
      () async {
        final repository = _RecordingPushRepository();
        final tokens = _FakeTokenSource(token: 'device-token');
        addTearDown(tokens.dispose);
        final service = PushRegistrationService(
          config: AppConfig(
            homeserver: Uri.parse('https://chat.example.com'),
            pushGateway: Uri.parse(
              'https://push.example.com/_matrix/push/v1/notify',
            ),
          ),
          tokenSource: tokens,
          loadRepository: () async => repository,
        );
        addTearDown(service.dispose);

        await service.start();
        // Without this rule Synapse never pushes the ring event at all: its
        // built-in call rule only matches the long-superseded m.call.invite.
        await Future<void>.delayed(Duration.zero);
        expect(repository.callRuleWrites, greaterThan(0));
      },
    );

    test('does nothing when the platform has no token', () async {
      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource();
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      expect(await service.start(), isFalse);
      expect(repository.registrations, isEmpty);
    });

    test('registers the current token', () async {
      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource(token: 'device-token');
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      expect(await service.start(), isTrue);
      expect(repository.registrations.single.token, 'device-token');
      expect(repository.registrations.single.gatewayUrl, gateway);
    });

    test('re-registers when the platform rotates the token', () async {
      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource(token: 'first-token');
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      await service.start();
      tokens.rotate('second-token');
      await Future<void>.delayed(Duration.zero);

      expect(repository.registrations.map((entry) => entry.token), [
        'first-token',
        'second-token',
      ]);
    });

    test('reports failure without throwing so sign-in is unaffected', () async {
      final repository = _RecordingPushRepository()
        ..failure = const PushFailure(PushFailureCode.serverUnavailable);
      final tokens = _FakeTokenSource(token: 'device-token');
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      expect(await service.start(), isFalse);
    });

    test('removes the pusher on stop and only once', () async {
      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource(token: 'device-token');
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      await service.start();
      await service.stop();
      await service.stop();

      // Suffixed because the gateway keeps a separate entry per platform.
      expect(repository.removals, [
        ('device-token', 'com.digitalgrub.chat.android'),
      ]);
    });

    test('stop is a no-op when nothing was registered', () async {
      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource();
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      await service.stop();

      expect(repository.removals, isEmpty);
    });
  });

  group('AppConfig', () {
    test('treats a missing gateway as push disabled', () {
      final config = AppConfig(
        homeserver: Uri.parse('https://chat.example.com'),
      );
      expect(config.isPushConfigured, isFalse);
      expect(config.pushGateway, isNull);
    });

    test('treats a supplied gateway as push enabled', () {
      final config = AppConfig(
        homeserver: Uri.parse('https://chat.example.com'),
        pushGateway: gateway,
      );
      expect(config.isPushConfigured, isTrue);
    });

    test('a build with no defines knows no server but a placeholder', () {
      // Nothing in this code knows your server. Push, calls, guest links
      // and the admin screen stay off until a build is told where they are.
      final config = AppConfig.fromBuild();

      expect(config.homeserver.host, 'chat.example.com');
      expect(config.isPushConfigured, isFalse);
      expect(config.isCallsConfigured, isFalse);
      expect(config.meetGuestUrl, isNull);
      expect(config.adminUrl, isNull);
      expect(config.webPushVapidKey, isEmpty);
    });

    test('suffixes the app id for the running platform', () {
      final config = AppConfig(
        homeserver: Uri.parse('https://chat.example.com'),
        pushGateway: gateway,
      );

      // A push gateway keeps one entry per platform because FCM and APNs need
      // different credentials. Registering the unsuffixed id makes the gateway
      // reject every notification while registration still looks successful,
      // so this must never silently regress.
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(config.platformPushAppId, 'com.digitalgrub.chat.android');

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(config.platformPushAppId, 'com.digitalgrub.chat.ios');
    });

    test('carries a renderable payload for Apple', () async {
      // An event_id_only push has no displayable text of its own, so without
      // this Apple delivers a silent notification and the device shows
      // nothing at all.
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource(token: 'apns-token');
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      await service.start(alertText: 'புதிய செய்தி');

      final payload =
          repository.registrations.single.defaultPayload!['aps']
              as Map<String, Object?>;
      final alert = payload['alert']! as Map<String, Object?>;
      // Localized, because the platform draws this without asking the app.
      expect(alert['body'], 'புதிய செய்தி');
      expect(alert['title'], 'Digitalgrub Chat');
      // The message itself must never travel over the push path.
      expect(payload.toString(), isNot(contains('event')));
    });

    test('sends no payload on Android, which renders in Dart', () async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource(token: 'device-token');
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      await service.start(alertText: 'New message');

      // A payload here would draw a second notification alongside the one the
      // app already builds from the FCM background handler.
      expect(repository.registrations.single.defaultPayload, isNull);
    });

    test('falls back to English when no wording is supplied', () async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource(token: 'apns-token');
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      await service.start();

      final aps =
          repository.registrations.single.defaultPayload!['aps']
              as Map<String, Object?>;
      expect((aps['alert']! as Map<String, Object?>)['body'], 'New message');
    });

    test('registers with the platform-suffixed app id', () async {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final repository = _RecordingPushRepository();
      final tokens = _FakeTokenSource(token: 'device-token');
      addTearDown(tokens.dispose);
      final service = _service(repository, tokens, gateway);
      addTearDown(service.dispose);

      await service.start();
      await service.stop();

      expect(
        repository.registrations.single.appId,
        'com.digitalgrub.chat.android',
      );
      expect(repository.removals.single.$2, 'com.digitalgrub.chat.android');
    });
  });
}

PushRegistrationService _service(
  PushRepository repository,
  PushTokenSource tokens,
  Uri gateway,
) {
  return PushRegistrationService(
    config: AppConfig(
      homeserver: Uri.parse('https://chat.example.com'),
      pushGateway: gateway,
    ),
    tokenSource: tokens,
    loadRepository: () async => repository,
  );

  group('web push', () {
    const key = 'BGd_test_public_key';
    AppConfig config({bool withKey = true}) => AppConfig(
      homeserver: Uri.parse('https://dgchat.test'),
      pushGateway: gateway,
      webPushVapidKey: withKey ? key : '',
    );
    const subscription = WebPushSubscription(
      endpoint: 'https://fcm.googleapis.com/fcm/send/abc',
      p256dh: 'p256dh-key',
      auth: 'auth-secret',
    );

    test('registers the subscription the way the gateway reads it', () async {
      final repository = _RecordingPushRepository();
      final webPush = _FakeWebPush(subscription: subscription);
      final service = PushRegistrationService(
        config: config(),
        tokenSource: _FakeTokenSource(token: 'never-used-on-web'),
        webPush: webPush,
        isWeb: true,
        loadRepository: () async => repository,
      );
      expect(await service.start(), isTrue);
      expect(webPush.keysSeen, [key]);
      final registration = repository.registrations.single;
      // The gateway keys the subscription by p256dh; the rest rides along.
      expect(registration.token, 'p256dh-key');
      expect(registration.appId, 'com.digitalgrub.chat.web');
      expect(registration.additionalData['endpoint'], subscription.endpoint);
      expect(registration.additionalData['auth'], 'auth-secret');
      expect(registration.additionalData['events_only'], isTrue);
      expect(registration.defaultPayload, isNull);
    });

    test('a browser that will not subscribe is not a failure', () async {
      final repository = _RecordingPushRepository();
      final service = PushRegistrationService(
        config: config(),
        tokenSource: _FakeTokenSource(),
        webPush: _FakeWebPush(subscription: null),
        isWeb: true,
        loadRepository: () async => repository,
      );
      expect(await service.start(), isFalse);
      expect(repository.registrations, isEmpty);
    });

    test('no VAPID key means web push is simply off', () async {
      final repository = _RecordingPushRepository();
      final webPush = _FakeWebPush(subscription: subscription);
      final service = PushRegistrationService(
        config: config(withKey: false),
        tokenSource: _FakeTokenSource(),
        webPush: webPush,
        isWeb: true,
        loadRepository: () async => repository,
      );
      expect(await service.start(), isFalse);
      expect(webPush.keysSeen, isEmpty, reason: 'must not even ask');
    });

    test('signing out removes the web pusher under the id it used', () async {
      final repository = _RecordingPushRepository();
      final service = PushRegistrationService(
        config: config(),
        tokenSource: _FakeTokenSource(),
        webPush: _FakeWebPush(subscription: subscription),
        isWeb: true,
        loadRepository: () async => repository,
      );
      await service.start();
      await service.stop();
      expect(repository.removals, [('p256dh-key', 'com.digitalgrub.chat.web')]);
    });

    test('the repository carries the extra data onto the pusher', () async {
      final client = _MockClient();
      when(
        () => client.postPusher(any(), append: any(named: 'append')),
      ).thenAnswer((_) async {});
      await MatrixPushRepository(client).register(
        PushRegistration(
          token: 'p256dh-key',
          appId: 'com.digitalgrub.chat.web',
          appDisplayName: 'Digitalgrub Chat',
          deviceDisplayName: 'Chrome',
          gatewayUrl: gateway,
          language: 'en',
          additionalData: const {
            'endpoint': 'https://push.test/x',
            'auth': 'a',
          },
        ),
      );
      final pusher =
          verify(
                () => client.postPusher(
                  captureAny(),
                  append: any(named: 'append'),
                ),
              ).captured.single
              as Pusher;
      expect(pusher.pushkey, 'p256dh-key');
      expect(
        pusher.data.additionalProperties['endpoint'],
        'https://push.test/x',
      );
      expect(
        pusher.data.format,
        'event_id_only',
        reason: 'no text on the push path, on any platform',
      );
    });
  });
}

Matcher _hasPushCode(PushFailureCode code) =>
    isA<PushFailure>().having((failure) => failure.code, 'code', code);
