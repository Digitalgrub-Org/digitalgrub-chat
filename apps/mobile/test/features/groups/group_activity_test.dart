import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/groups/application/group_providers.dart';
import 'package:dg_chat/features/groups/data/group_activity_mapper.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:dg_chat/features/groups/presentation/group_activity_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

GroupActivityEntry? _map({
  required String type,
  Map<String, Object?> content = const {},
  Map<String, Object?>? previous,
  String actorId = '@sara:test',
  String? targetId,
  String actor = 'Sara',
  String? target,
}) => activityEntryFrom(
  type: type,
  content: content,
  previousContent: previous,
  actorId: actorId,
  targetId: targetId,
  actorName: actor,
  targetName: target,
  at: DateTime(2026, 8, 19, 10),
);

void main() {
  group('activityEntryFrom', () {
    test('walking out and being removed read differently', () {
      // The membership value is "leave" either way; whose hand was on the
      // door is the entire difference.
      final walked = _map(
        type: 'm.room.member',
        actorId: '@dev:test',
        targetId: '@dev:test',
        content: {'membership': 'leave'},
        previous: {'membership': 'join'},
        actor: 'Dev',
        target: 'Dev',
      );
      expect(walked!.kind, GroupActivityKind.left);
      expect(walked.targetName, isNull);

      final removed = _map(
        type: 'm.room.member',
        targetId: '@dev:test',
        content: {'membership': 'leave'},
        previous: {'membership': 'join'},
        actor: 'Sara',
        target: 'Dev',
      );
      expect(removed!.kind, GroupActivityKind.removed);
      expect(removed.targetName, 'Dev');
    });

    test('two people with one name still read correctly', () {
      // Display names are not unique. Deciding this by name meant an admin
      // removing their namesake was logged as that person walking out.
      final removed = _map(
        type: 'm.room.member',
        actorId: '@kumar.admin:test',
        targetId: '@kumar.dev:test',
        content: {'membership': 'leave'},
        previous: {'membership': 'join'},
        actor: 'Kumar',
        target: 'Kumar',
      );
      expect(removed!.kind, GroupActivityKind.removed);
      expect(removed.targetName, 'Kumar');
    });

    test('a revoked invite is logged, a declined one is not', () {
      // Both are invite -> leave. Only one of them is somebody else's doing,
      // and that one is exactly what this screen exists to record.
      expect(
        _map(
          type: 'm.room.member',
          actorId: '@dev:test',
          targetId: '@dev:test',
          content: {'membership': 'leave'},
          previous: {'membership': 'invite'},
          actor: 'Dev',
          target: 'Dev',
        ),
        isNull,
      );
      final revoked = _map(
        type: 'm.room.member',
        targetId: '@dev:test',
        content: {'membership': 'leave'},
        previous: {'membership': 'invite'},
        actor: 'Sara',
        target: 'Dev',
      );
      expect(revoked!.kind, GroupActivityKind.removed);
      expect(revoked.targetName, 'Dev');
    });

    test('a profile change is not activity', () {
      // Same membership before and after: just a new display name or photo.
      expect(
        _map(
          type: 'm.room.member',
          targetId: '@dev:test',
          content: {'membership': 'join', 'displayname': 'New Name'},
          previous: {'membership': 'join', 'displayname': 'Old'},
          target: 'Dev',
        ),
        isNull,
      );
    });

    test('joins, invites, renames and calls map to their lines', () {
      expect(
        _map(
          type: 'm.room.member',
          targetId: '@dev:test',
          content: {'membership': 'join'},
          previous: {'membership': 'invite'},
          target: 'Dev',
        )!.kind,
        GroupActivityKind.joined,
      );
      expect(
        _map(
          type: 'm.room.member',
          targetId: '@dev:test',
          content: {'membership': 'invite'},
          target: 'Dev',
        )!.kind,
        GroupActivityKind.invited,
      );
      final renamed = _map(
        type: 'm.room.name',
        content: {'name': 'Launch crew'},
      );
      expect(renamed!.kind, GroupActivityKind.renamed);
      expect(renamed.detail, 'Launch crew');
      expect(
        _map(type: 'org.matrix.msc4075.rtc.notification')!.kind,
        GroupActivityKind.callStarted,
      );
    });

    test('messages and the initial power levels are not activity', () {
      expect(_map(type: 'm.room.message'), isNull);
      // previousContent null means room creation boilerplate, not a change.
      expect(_map(type: 'm.room.power_levels'), isNull);
    });
  });

  testWidgets('the screen tells the story newest first', (tester) async {
    // Newest first, the order the repository documents and returns. Feeding
    // this oldest-first is what hid a reversal in the screen: both the
    // fixture and the screen were backwards, so the test passed and the
    // real log opened on "group created".
    final entries = [
      GroupActivityEntry(
        kind: GroupActivityKind.left,
        actorName: 'Dev',
        at: DateTime(2026, 8, 19, 9),
      ),
      GroupActivityEntry(
        kind: GroupActivityKind.joined,
        actorName: 'Dev',
        at: DateTime(2026, 8, 2, 9),
      ),
      GroupActivityEntry(
        kind: GroupActivityKind.created,
        actorName: 'Sara',
        at: DateTime(2026, 8, 1, 9),
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupActivityProvider('!g:test').overrideWith((ref) async => entries),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupActivityScreen(roomId: '!g:test'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dev left'), findsOneWidget);
    expect(find.text('Dev joined'), findsOneWidget);
    expect(find.text('Sara created the group'), findsOneWidget);
    // Newest first: the leave sits above the join.
    final leftY = tester.getTopLeft(find.text('Dev left')).dy;
    final joinedY = tester.getTopLeft(find.text('Dev joined')).dy;
    expect(leftY, lessThan(joinedY));
  });
}
