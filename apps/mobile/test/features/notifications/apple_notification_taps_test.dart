import 'package:dg_chat/features/notifications/data/apple_notification_taps.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(AppleNotificationTaps.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Invokes a call from the native side, the way the app delegate does.
  Future<Object?> sendFromNative(String method, Object? arguments) async {
    final data = await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, arguments)),
      null,
    );
    return data == null ? null : channel.codec.decodeEnvelope(data);
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('taps while running', () {
    test('reports the tapped room and confirms it was handled', () async {
      final taps = AppleNotificationTaps();
      addTearDown(taps.dispose);
      final opened = <String>[];
      taps.listen((roomId) {
        opened.add(roomId);
        return true;
      });

      // True is what tells the native side to stop holding the tap.
      expect(await sendFromNative('openRoom', '!room:test'), isTrue);
      expect(opened, ['!room:test']);
    });

    test(
      'leaves an unusable payload pending rather than dropping it',
      () async {
        final taps = AppleNotificationTaps();
        addTearDown(taps.dispose);
        var called = false;
        taps.listen((_) {
          called = true;
          return true;
        });

        expect(await sendFromNative('openRoom', ''), isFalse);
        expect(await sendFromNative('openRoom', 42), isFalse);
        expect(called, isFalse);
      },
    );

    test('ignores a method it does not implement', () async {
      final taps = AppleNotificationTaps();
      addTearDown(taps.dispose);
      taps.listen((_) => true);

      expect(await sendFromNative('somethingElse', '!room:test'), isNull);
    });
  });

  group('a tap that launched the app', () {
    test('claims the room held natively', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'takePendingRoom' ? '!room:test' : null,
      );

      expect(await AppleNotificationTaps().takePending(), '!room:test');
    });

    test('reports nothing when the app was opened some other way', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);

      expect(await AppleNotificationTaps().takePending(), isNull);
    });

    test('treats an empty room as nothing', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => '');

      expect(await AppleNotificationTaps().takePending(), isNull);
    });

    test('stays quiet where the channel does not exist', () async {
      // Android and the test environment have no such channel, and asking for
      // a tap there must not take startup down.
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );

      expect(await AppleNotificationTaps().takePending(), isNull);
    });

    test('survives a platform error', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'error'),
      );

      expect(await AppleNotificationTaps().takePending(), isNull);
    });
  });
}
