import 'package:dg_chat/features/calls/data/call_foreground_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('in.digitalgrub.chat/launch');
  final calls = <String>[];
  var throwOnInvoke = false;

  setUp(() {
    calls.clear();
    throwOnInvoke = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (throwOnInvoke) {
            throw PlatformException(code: 'FAILED', message: 'no service');
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('on Android', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('starting asks the platform for the service', () async {
      await const CallForegroundService().start();
      expect(calls, ['startCallService']);
    });

    test('stopping takes it down again', () async {
      await const CallForegroundService().stop();
      expect(calls, ['stopCallService']);
    });

    test('a platform failure does not break the call', () async {
      // A call that connects but cannot raise a notification is still a call.
      // Throwing here would fail the join over a status row.
      throwOnInvoke = true;
      await expectLater(const CallForegroundService().start(), completes);
      await expectLater(const CallForegroundService().stop(), completes);
    });
  });

  group('everywhere else', () {
    test('iOS does not use it', () async {
      // iOS keeps a call's audio session alive through its own background
      // mode; a second notification for the same call would be noise.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await const CallForegroundService().start();
      await const CallForegroundService().stop();
      expect(calls, isEmpty);
    });

    test('macOS does not use it', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await const CallForegroundService().start();
      expect(calls, isEmpty);
    });
  });
}
