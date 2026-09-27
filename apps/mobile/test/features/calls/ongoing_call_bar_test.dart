import 'dart:async';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/ongoing_call_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCallController implements CallController {
  _FakeCallController({
    CallConnectionState state = CallConnectionState.connected,
  }) : _state = state;

  final String roomId = '!call:test';
  CallConnectionState _state;
  final _updates = StreamController<CallSnapshot>.broadcast();
  int hangUpCount = 0;

  CallSnapshot get _snapshot => CallSnapshot(
    roomId: roomId,
    state: _state,
    participants: const [],
    micEnabled: true,
    cameraEnabled: false,
    startedAt: _state == CallConnectionState.connected
        ? DateTime(2026, 8, 18, 10)
        : null,
  );

  /// The other side hanging up, which nothing else in the tree is watching
  /// for once the call screen is gone.
  void endRemotely() {
    _state = CallConnectionState.ended;
    _updates.add(_snapshot);
  }

  @override
  Stream<CallSnapshot> get changes async* {
    yield _snapshot;
    yield* _updates.stream;
  }

  @override
  CallSnapshot get current => _snapshot;

  @override
  Future<void> hangUp() async {
    hangUpCount++;
    _state = CallConnectionState.ended;
  }

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

Future<ProviderContainer> _pumpBar(
  WidgetTester tester,
  CallController? controller,
) async {
  final container = ProviderContainer(
    overrides: [
      if (controller != null)
        activeCallProvider.overrideWith((ref) => controller),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: OngoingCallBar()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('shows nothing when no call is running', (tester) async {
    await _pumpBar(tester, null);

    expect(find.byIcon(Icons.call_end_rounded), findsNothing);
  });

  testWidgets('offers a way back into a live call', (tester) async {
    await _pumpBar(tester, _FakeCallController());

    // Without this the call is an open microphone with nothing on screen to
    // say so, which is why leaving the call screen used to hang up.
    expect(find.text('Tap to return to your call'), findsOneWidget);
  });

  testWidgets('hangs up from the bar and clears the call', (tester) async {
    final controller = _FakeCallController();
    final container = await _pumpBar(tester, controller);

    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump();

    expect(controller.hangUpCount, 1);
    expect(container.read(activeCallProvider), isNull);
  });

  testWidgets('disappears when the other side hangs up', (tester) async {
    final controller = _FakeCallController();
    final container = await _pumpBar(tester, controller);
    expect(find.text('Tap to return to your call'), findsOneWidget);

    controller.endRemotely();
    await tester.pump();
    await tester.pump();

    // A bar advertising a call that ended minutes ago is worse than no bar.
    expect(container.read(activeCallProvider), isNull);
  });

  testWidgets('says connecting before the call is up', (tester) async {
    await _pumpBar(
      tester,
      _FakeCallController(state: CallConnectionState.connecting),
    );

    expect(find.text('Connecting…'), findsOneWidget);
  });
}
