import 'dart:async';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CallSnapshot _snapshot({required bool isGroup}) => CallSnapshot(
  roomId: '!room:test',
  state: CallConnectionState.connected,
  participants: const [],
  micEnabled: true,
  cameraEnabled: false,
  startedAt: DateTime(2026, 9, 9, 10),
  isGroup: isGroup,
);

class _FakeController implements CallController {
  _FakeController(this._current);
  final CallSnapshot _current;
  final speaker = <bool>[];
  @override
  Stream<CallSnapshot> get changes => const Stream.empty();
  @override
  CallSnapshot get current => _current;
  @override
  Future<void> setSpeakerphone(bool enabled) async => speaker.add(enabled);
  @override
  Future<void> setHandRaised(bool raised) async {}
  @override
  Future<void> requestMute({String? participantId}) async {}
  @override
  Future<void> hangUp() async {}
  @override
  Future<void> setCameraEnabled(bool enabled) async {}
  @override
  Future<void> setMicEnabled(bool enabled) async {}
  @override
  Future<void> setScreenShareEnabled(bool enabled) async {}
  @override
  Stream<CallReaction> get reactions => const Stream.empty();
  @override
  Future<void> sendReaction(String emoji) async {}
  @override
  Future<void> switchCamera() async {}
}

class _FakeRepository implements CallRepository {
  _FakeRepository(this.controller);
  final _FakeController controller;
  @override
  Future<CallController> startOrJoin(
    String roomId, {
    required bool withVideo,
    required bool ring,
  }) async => controller;
  @override
  Future<CallController> joinMeetingAsGuest(
    String target, {
    required String displayName,
    required bool withVideo,
  }) async => controller;
  @override
  Stream<IncomingCallRing> get incomingRings => const Stream.empty();
  @override
  Stream<List<LiveCall>> get liveCalls => const Stream.empty();
}

Future<_FakeController> _pump(
  WidgetTester tester, {
  required bool isGroup,
  bool withVideo = false,
}) async {
  final controller = _FakeController(_snapshot(isGroup: isGroup));
  final container = ProviderContainer(
    overrides: [
      callRepositoryProvider.overrideWith(
        (ref) async => _FakeRepository(controller),
      ),
    ],
  );
  addTearDown(container.dispose);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox(),
      ),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CallScreen(roomId: '!room:test', withVideo: withVideo, ring: false),
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return controller;
}

void main() {
  group('the default audio route', () {
    testWidgets('a one-to-one voice call goes to the earpiece', (tester) async {
      final controller = await _pump(tester, isGroup: false);
      expect(controller.speaker, [false]);
    });

    testWidgets('a group voice call goes to the speaker', (tester) async {
      // The "volume is not enough" report: a group call through the earpiece
      // is a phone held to one ear that the rest of the room strains to hear.
      final controller = await _pump(tester, isGroup: true);
      expect(controller.speaker, [true]);
    });

    testWidgets('video always goes to the speaker', (tester) async {
      final controller = await _pump(tester, isGroup: false, withVideo: true);
      expect(controller.speaker, [true]);
    });
  });

  group('picture-in-picture', () {
    Future<void> pip(bool inPip) async {
      const codec = StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'in.digitalgrub.chat/launch',
            codec.encodeMethodCall(MethodCall('pipChanged', inPip)),
            (_) {},
          );
    }

    testWidgets('the floating window shows only the video', (tester) async {
      await _pump(tester, isGroup: true);
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);

      await pip(true);
      await tester.pump();
      // No controls, no header: a 9:16 window has room for the call and
      // nothing else, and tapping it brings the full screen back anyway.
      expect(find.byIcon(Icons.call_end_rounded), findsNothing);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.text('Waiting for others to join…'), findsOneWidget);

      await pip(false);
      await tester.pump();
      expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
    });
  });
}
