import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/conversation/presentation/system_timeline_entry.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, GroupActivityEntry entry) =>
    tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SystemTimelineEntry(entry: entry)),
      ),
    );

void main() {
  testWidgets('a removal names both people', (tester) async {
    await _pump(
      tester,
      GroupActivityEntry(
        kind: GroupActivityKind.removed,
        actorName: 'Sara',
        targetName: 'Dev',
        at: DateTime(2026, 8, 20, 10),
      ),
    );

    expect(find.text('Sara removed Dev'), findsOneWidget);
  });

  testWidgets('a rename carries the new name', (tester) async {
    await _pump(
      tester,
      GroupActivityEntry(
        kind: GroupActivityKind.renamed,
        actorName: 'Sara',
        detail: 'Launch crew',
        at: DateTime(2026, 8, 20, 10),
      ),
    );

    expect(find.textContaining('Launch crew'), findsOneWidget);
  });

  testWidgets('it is a line, not a bubble anyone can act on', (tester) async {
    // The distinction that matters: nobody said this, so there is nothing to
    // reply to, react to or delete. It must not arrive with a gesture
    // attached.
    await _pump(
      tester,
      GroupActivityEntry(
        kind: GroupActivityKind.joined,
        actorName: 'Dev',
        at: DateTime(2026, 8, 20, 10),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    expect(
      tester.widget<Text>(find.text('Dev joined')).textAlign,
      TextAlign.center,
    );
  });
}
