import 'dart:async';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CallParticipantView _person(
  String id,
  String name, {
  bool isLocal = false,
  bool hasAudio = true,
  bool handRaised = false,
}) => CallParticipantView(
  id: id,
  displayName: name,
  isLocal: isLocal,
  hasAudio: hasAudio,
  hasVideo: false,
  isSpeaking: false,
  handRaised: handRaised,
);

CallSnapshot _snapshot({
  required List<CallParticipantView> people,
  bool canModerate = false,
}) => CallSnapshot(
  roomId: '!team:test',
  state: CallConnectionState.connected,
  participants: people,
  micEnabled: true,
  cameraEnabled: false,
  startedAt: DateTime(2026, 9, 8, 10),
  canModerate: canModerate,
);

class _FakeController implements CallController {
  _FakeController(this._current);

  CallSnapshot _current;
  final _updates = StreamController<CallSnapshot>.broadcast();
  final handCalls = <bool>[];
  final muteRequests = <String?>[];

  @override
  Stream<CallSnapshot> get changes => _updates.stream;
  @override
  CallSnapshot get current => _current;
  @override
  Future<void> setHandRaised(bool raised) async => handCalls.add(raised);
  @override
  Future<void> requestMute({String? participantId}) async =>
      muteRequests.add(participantId);
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

Future<_FakeController> _pumpCall(
  WidgetTester tester,
  CallSnapshot snapshot,
) async {
  final controller = _FakeController(snapshot);
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
        builder: (_) => const CallScreen(
          roomId: '!team:test',
          withVideo: false,
          ring: false,
        ),
      ),
    ),
  );
  await _settle(tester);
  return controller;
}

/// The call screen ticks its clock every second, so pumpAndSettle never
/// returns; step frames by hand instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final _me = _person('@me:test/A', 'Me', isLocal: true);
final _maya = _person('@maya:test/B', 'Maya');
final _arjun = _person('@arjun:test/C', 'Arjun', handRaised: true);

void main() {
  testWidgets('raising a hand tells the call', (tester) async {
    final controller = await _pumpCall(tester, _snapshot(people: [_me, _maya]));
    await tester.tap(find.byIcon(Icons.pan_tool_outlined));
    await _settle(tester);
    expect(controller.handCalls, [true]);
  });

  testWidgets('a raised hand shows on the tile', (tester) async {
    await _pumpCall(tester, _snapshot(people: [_me, _arjun]));
    expect(find.byKey(const ValueKey('hand-chip')), findsOneWidget);
  });

  testWidgets('hands up put a dot on the people button', (tester) async {
    // Somebody asking for a turn is the one thing worth interrupting for;
    // mere presence is not.
    await _pumpCall(tester, _snapshot(people: [_me, _arjun]));
    expect(find.byKey(const ValueKey('call-control-badge')), findsOneWidget);
  });

  testWidgets('no hands, no dot', (tester) async {
    await _pumpCall(tester, _snapshot(people: [_me, _maya]));
    expect(find.byKey(const ValueKey('call-control-badge')), findsNothing);
  });

  testWidgets('the people button opens the list', (tester) async {
    await _pumpCall(tester, _snapshot(people: [_me, _maya, _arjun]));
    await tester.tap(find.byIcon(Icons.people_alt_rounded));
    await _settle(tester);
    // Scoped to the sheet: the video tile behind it carries the same name.
    final sheet = find.byType(CallPeopleSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Maya')),
      findsOneWidget,
    );
    expect(find.text('Me (you)'), findsOneWidget);
  });

  group('the people sheet', () {
    Future<(List<String?>, int)> pumpSheet(
      WidgetTester tester, {
      required bool canModerate,
    }) async {
      final requests = <String?>[];
      var muteAll = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CallPeopleSheet(
              call: _snapshot(
                people: [_me, _maya, _arjun],
                canModerate: canModerate,
              ),
              onMute: (id) async => requests.add(id),
              onMuteAll: () async => muteAll++,
            ),
          ),
        ),
      );
      await tester.pump();
      return (requests, muteAll);
    }

    testWidgets('a moderator can mute one person or everyone', (tester) async {
      final (requests, _) = await pumpSheet(tester, canModerate: true);
      // One Mute: Maya. Arjun has a hand up and gets the hand instead --
      // silencing somebody who just asked to speak is not a control anyone
      // wants one tap from. Me is me.
      expect(find.text('Mute'), findsOneWidget);
      await tester.tap(find.text('Mute'));
      await tester.pump();
      expect(requests, ['@maya:test/B']);
      expect(find.text('Mute all'), findsOneWidget);
    });

    testWidgets('mute all asks for everyone', (tester) async {
      var muteAll = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CallPeopleSheet(
              call: _snapshot(people: [_me, _maya], canModerate: true),
              onMute: (_) async {},
              onMuteAll: () async => muteAll++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Mute all'));
      await tester.pump();
      expect(muteAll, 1);
    });

    testWidgets('an ordinary member gets no mute controls', (tester) async {
      await pumpSheet(tester, canModerate: false);
      expect(find.text('Mute'), findsNothing);
      expect(find.text('Mute all'), findsNothing);
      // But still sees who is here and who has a hand up.
      expect(find.text('Arjun'), findsOneWidget);
      expect(find.text('Hand raised'), findsOneWidget);
    });

    testWidgets('hands come first', (tester) async {
      await pumpSheet(tester, canModerate: false);
      final arjun = tester.getTopLeft(find.text('Arjun'));
      final maya = tester.getTopLeft(find.text('Maya'));
      expect(arjun.dy, lessThan(maya.dy));
    });
  });
}
