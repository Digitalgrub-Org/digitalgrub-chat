import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/call_video_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rebuilds the grid's screen-share branch against the real widget tree.
///
/// The grid itself is private to call_screen.dart, so this drives it the way
/// the screen does -- through a CallSnapshot -- and asserts on what a person
/// would see rather than on internal state.
import 'package:dg_chat/features/calls/presentation/call_screen.dart';

CallParticipantView _person(String name, {bool screen = false}) =>
    CallParticipantView(
      id: screen ? '$name#screen0' : name,
      displayName: name,
      isLocal: false,
      hasAudio: true,
      hasVideo: !screen,
      isSpeaking: false,
      isScreenShare: screen,
    );

CallSnapshot _snapshot(List<CallParticipantView> participants) => CallSnapshot(
  roomId: '!room:test',
  state: CallConnectionState.connected,
  participants: participants,
  micEnabled: true,
  cameraEnabled: false,
  startedAt: DateTime(2026, 9, 1, 10),
);

Future<void> _pump(WidgetTester tester, CallSnapshot snapshot) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ParticipantGridForTest(call: snapshot)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('every tile offers a way to fill the view', (tester) async {
    // First asked for on a shared screen, which took two thirds with no way
    // to make it bigger; then for faces too. One control per tile.
    await _pump(
      tester,
      _snapshot([_person('Maya', screen: true), _person('Arjun')]),
    );
    expect(find.byIcon(Icons.fullscreen_rounded), findsNWidgets(2));
  });

  testWidgets('expanding hides the faces and shows the way back', (
    tester,
  ) async {
    await _pump(
      tester,
      _snapshot([_person('Maya', screen: true), _person('Arjun')]),
    );
    expect(find.byType(CallParticipantTile), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.fullscreen_rounded).first);
    await tester.pump();

    // Only the shared screen is left, and the control has flipped so the
    // person is never stuck in the expanded layout.
    expect(find.byType(CallParticipantTile), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
  });

  testWidgets('collapsing brings the faces back', (tester) async {
    await _pump(
      tester,
      _snapshot([_person('Maya', screen: true), _person('Arjun')]),
    );
    await tester.tap(find.byIcon(Icons.fullscreen_rounded).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
    await tester.pump();
    expect(find.byType(CallParticipantTile), findsNWidgets(2));
  });

  testWidgets('a double tap on the video does it too', (tester) async {
    // Reaching for a small icon is the wrong ask on a phone, and
    // double-tapping video to fill the screen is a gesture people already
    // have. Deliberately NOT tapping the button here -- that path is covered
    // above, and a test that quietly used it would prove nothing.
    await _pump(
      tester,
      _snapshot([_person('Maya', screen: true), _person('Arjun')]),
    );
    await tester.tap(find.byIcon(Icons.fullscreen_rounded).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
    await tester.pump();
    expect(find.byType(CallParticipantTile), findsNWidgets(2));

    // The detector wraps the tile rather than living inside it, so the tap
    // goes to the tile's own centre -- away from the button in the corner.
    final centre = tester.getCenter(find.byType(CallParticipantTile).first);
    await tester.tapAt(centre);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(centre);
    await tester.pump();
    expect(find.byType(CallParticipantTile), findsOneWidget);

    // The double-tap recogniser keeps a timer running after the second tap;
    // without draining it the test ends with it pending and fails on that
    // rather than on anything it set out to check.
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('a face can be pinned in a plain grid', (tester) async {
    // A grid of faces is right for a meeting and wrong for the one person
    // you are actually talking to.
    await _pump(tester, _snapshot([_person('Maya'), _person('Arjun')]));
    expect(find.byIcon(Icons.fullscreen_rounded), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.fullscreen_rounded).last);
    await tester.pump();
    expect(find.byType(CallParticipantTile), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
  });

  testWidgets('the pinned person leaving un-pins the grid', (tester) async {
    await _pump(tester, _snapshot([_person('Maya'), _person('Arjun')]));
    await tester.tap(find.byIcon(Icons.fullscreen_rounded).last);
    await tester.pump();
    expect(find.byType(CallParticipantTile), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ParticipantGridForTest(
            call: _snapshot([_person('Maya'), _person('Priya')]),
          ),
        ),
      ),
    );
    await tester.pump();
    // Arjun is gone, so nobody is pinned and both remaining faces show.
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);
    expect(find.byType(CallParticipantTile), findsNWidgets(2));
  });

  testWidgets('the share ending un-expands the grid', (tester) async {
    // Otherwise the layout stays in a shape built for something that is no
    // longer there, with one tile stretched over the whole call.
    final withShare = _snapshot([
      _person('Maya', screen: true),
      _person('Arjun'),
    ]);
    await _pump(tester, withShare);
    await tester.tap(find.byIcon(Icons.fullscreen_rounded).first);
    await tester.pump();
    expect(find.byType(CallParticipantTile), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ParticipantGridForTest(
            call: _snapshot([_person('Maya'), _person('Arjun')]),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);
    expect(find.byType(CallParticipantTile), findsNWidgets(2));
  });
}
