import 'dart:async';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeController implements CallController {
  _FakeController(this.roomId);

  final String roomId;
  int hangUpCount = 0;

  CallSnapshot get _snapshot => CallSnapshot(
    roomId: roomId,
    state: CallConnectionState.connected,
    participants: const [],
    micEnabled: true,
    cameraEnabled: false,
    startedAt: DateTime(2026, 8, 20, 10),
  );

  @override
  Stream<CallSnapshot> get changes async* {
    yield _snapshot;
  }

  @override
  CallSnapshot get current => _snapshot;

  @override
  Future<void> hangUp() async => hangUpCount++;

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

class _FakeRepository implements CallRepository {
  _FakeRepository({this.pending});

  /// When set, joins block on this instead of returning at once, so a test
  /// can act while the screen is still connecting.
  final Completer<CallController>? pending;

  final joined = <String>[];

  Future<CallController> _join(String target) {
    joined.add(target);
    return pending?.future ?? Future.value(_FakeController(target));
  }

  @override
  Future<CallController> startOrJoin(
    String roomId, {
    required bool withVideo,
    required bool ring,
  }) => _join(roomId);

  @override
  Future<CallController> joinMeetingAsGuest(
    String target, {
    required String displayName,
    required bool withVideo,
  }) => _join(target);

  @override
  Stream<IncomingCallRing> get incomingRings => const Stream.empty();

  @override
  Stream<List<LiveCall>> get liveCalls => const Stream.empty();
}

/// Mounts an app the call screen can be pushed onto.
///
/// The screen is pushed rather than handed straight to [WidgetTester.pumpWidget]
/// so that its initState runs outside the provider scope's own build, the way
/// it does in the app — and so that leaving it is a real pop.
Future<GlobalKey<NavigatorState>> _pumpApp(
  WidgetTester tester,
  ProviderContainer container,
) async {
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
  return navigator;
}

Future<void> _push(
  WidgetTester tester,
  GlobalKey<NavigatorState> navigator,
  Widget screen,
) async {
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => screen),
    ),
  );
  await _settle(tester);
}

/// Runs a route transition out, frame by frame.
///
/// Not [WidgetTester.pumpAndSettle]: the call screen redraws its duration
/// readout once a second forever, so the tree never goes quiet. One long jump
/// is not enough either — a popped route needs several frames before it
/// leaves the tree.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('joining a second call ends the one it replaces', (tester) async {
    // The guest case, where this went wrong: their route carries the meeting
    // code while the running controller carries the room id the code resolved
    // to, so the "already in this call" check at the top of _join can never
    // match and the old call would be left connected with a live microphone
    // and nothing on screen to end it.
    final abandoned = _FakeController('!resolved:test');
    final repository = _FakeRepository();
    final container = ProviderContainer(
      overrides: [
        callRepositoryProvider.overrideWith((ref) async => repository),
      ],
    );
    addTearDown(container.dispose);
    container.read(activeCallProvider.notifier).state = abandoned;

    final navigator = await _pumpApp(tester, container);
    await _push(
      tester,
      navigator,
      const CallScreen(
        roomId: 'abc-defg-hij',
        withVideo: false,
        ring: false,
        guestName: 'Asha',
      ),
    );

    expect(abandoned.hangUpCount, 1);
    expect(container.read(activeCallProvider), isNot(abandoned));
    expect(repository.joined, ['abc-defg-hij']);

    // Dispose the screen so its duration timer does not outlive the test.
    navigator.currentState!.pop();
    await _settle(tester);
  });

  testWidgets('backing out mid-join does not mute later rings', (tester) async {
    // The joining marker suppresses a ring for the call you are already
    // joining. Left behind, it suppresses every later ring for that room --
    // so it has to be cleared even when the screen is gone by the time the
    // join finishes.
    final pending = Completer<CallController>();
    final repository = _FakeRepository(pending: pending);
    final container = ProviderContainer(
      overrides: [
        callRepositoryProvider.overrideWith((ref) async => repository),
      ],
    );
    addTearDown(container.dispose);

    final navigator = await _pumpApp(tester, container);
    await _push(
      tester,
      navigator,
      const CallScreen(roomId: '!room:test', withVideo: false, ring: false),
    );
    expect(container.read(joiningCallRoomProvider), '!room:test');

    // Gone before the join lands.
    navigator.currentState!.pop();
    await _settle(tester);
    await tester.pump();
    expect(find.byType(CallScreen), findsNothing);
    final arrived = _FakeController('!room:test');
    pending.complete(arrived);
    await _settle(tester);

    expect(container.read(joiningCallRoomProvider), isNull);
    // The call that arrived with nobody to show it is ended, not orphaned.
    expect(arrived.hangUpCount, 1);
  });
}
