import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/meetings/domain/meeting_repository.dart';
import 'package:dg_chat/features/meetings/presentation/join_meeting_dialog.dart';
import 'package:dg_chat/features/meetings/presentation/meeting_invite_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String?> _openJoin(WidgetTester tester) async {
  String? result;
  var opened = false;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                opened = true;
                result = await showJoinMeetingDialog(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(opened, isTrue);
  return Future.value(result);
}

void main() {
  group('join with a code', () {
    testWidgets('a pasted link resolves to its code', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showJoinMeetingDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://chat.example.com/meet/abc-defg-hij?from=mail',
      );
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(result, 'abc-defg-hij');
    });

    testWidgets('junk is refused in place, not swallowed', (tester) async {
      await _openJoin(tester);
      await tester.enterText(find.byType(TextField), 'hello there');
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.text('That is not a meeting link or code.'), findsOneWidget);
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'still open to fix it',
      );
    });
  });

  testWidgets('the invitation offers share, copy, email and join', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMeetingInviteDialog(
                context,
                const Meeting(
                  roomId: '!m:test',
                  title: 'Standup',
                  code: 'abc-defg-hij',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.text('https://chat.example.com/meet/abc-defg-hij'),
      findsOneWidget,
    );
    for (final label in ['Share', 'Copy link', 'Email invite', 'Join now']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}
