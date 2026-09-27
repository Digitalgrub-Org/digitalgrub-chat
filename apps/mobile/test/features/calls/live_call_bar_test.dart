import 'dart:async';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/live_call_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeController implements CallController {
  @override
  Stream<CallSnapshot> get changes => const Stream.empty();

  @override
  CallSnapshot get current => const CallSnapshot(
    roomId: '!mine:test',
    state: CallConnectionState.connected,
    participants: [],
    micEnabled: true,
    cameraEnabled: false,
  );

  @override
  Future<void> hangUp() async {}
  @override
  Future<void> setCameraEnabled(bool enabled) async {}
  @override
  Future<void> setMicEnabled(bool enabled) async {}
  @override
  Future<void> setSpeakerphone(bool enabled) async {}

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {}

  @override
  Stream<CallReaction> get reactions => const Stream.empty();

  @override
  Future<void> sendReaction(String emoji) async {}
  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> setHandRaised(bool raised) async {}

  @override
  Future<void> requestMute({String? participantId}) async {}
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required List<LiveCall> calls,
  CallController? ownCall,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        liveCallsProvider.overrideWith((ref) => Stream.value(calls)),
        if (ownCall != null) activeCallProvider.overrideWith((ref) => ownCall),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: LiveCallBar()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows nothing when no call is running', (tester) async {
    await _pumpBar(tester, calls: const []);

    expect(find.text('Join'), findsNothing);
  });

  testWidgets('offers to join a call somebody else is on', (tester) async {
    await _pumpBar(
      tester,
      calls: const [
        LiveCall(
          roomId: '!asha:test',
          roomName: 'Asha Menon',
          participantCount: 1,
        ),
      ],
    );

    // The whole point: the ring is long gone, and the call is still joinable.
    expect(find.text('Asha Menon'), findsOneWidget);
    expect(find.text('On a call now'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
  });

  testWidgets('counts the people already in a group call', (tester) async {
    await _pumpBar(
      tester,
      calls: const [
        LiveCall(
          roomId: '!crew:test',
          roomName: 'Product crew',
          participantCount: 3,
        ),
      ],
    );

    expect(find.text('3 on the call'), findsOneWidget);
  });

  testWidgets('stays out of the way during your own call', (tester) async {
    await _pumpBar(
      tester,
      calls: const [
        LiveCall(
          roomId: '!asha:test',
          roomName: 'Asha Menon',
          participantCount: 1,
        ),
      ],
      ownCall: _FakeController(),
    );

    // The ongoing-call bar already owns this row; two call bars is noise.
    expect(find.text('Join'), findsNothing);
  });

  testWidgets('shows the newest when two calls are running', (tester) async {
    await _pumpBar(
      tester,
      calls: const [
        LiveCall(roomId: '!old:test', roomName: 'Older', participantCount: 1),
        LiveCall(roomId: '!new:test', roomName: 'Newer', participantCount: 2),
      ],
    );

    expect(find.text('Newer'), findsOneWidget);
    expect(find.text('Older'), findsNothing);
  });
}
