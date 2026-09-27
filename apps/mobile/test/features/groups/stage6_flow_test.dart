import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/groups/application/group_providers.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_group_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  group('new group', () {
    testWidgets('creates a group from the chats create menu', (tester) async {
      final groups = FakeGroupRepository(createdRoomId: '!created:test');
      await _pumpApp(tester, groups: groups);

      await _openNewGroup(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Group name'),
        'Product crew',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (optional)'),
        'Ship the mobile app',
      );
      await _selectPerson(tester, 'Maya Krishnan');

      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Create group'),
      );
      await tester.pumpAndSettle();

      expect(groups.createRequests, hasLength(1));
      final request = groups.createRequests.single;
      expect(request.name, 'Product crew');
      expect(request.description, 'Ship the mobile app');
      expect(request.memberIds, ['@maya:digitalgrub.com']);
    });

    testWidgets('requires a group name before creating', (tester) async {
      final groups = FakeGroupRepository();
      await _pumpApp(tester, groups: groups);

      await _openNewGroup(tester);
      await _selectPerson(tester, 'Maya Krishnan');
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Create group'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter a group name.'), findsOneWidget);
      expect(groups.createRequests, isEmpty);
    });

    testWidgets('requires at least one member before creating', (tester) async {
      final groups = FakeGroupRepository();
      await _pumpApp(tester, groups: groups);

      await _openNewGroup(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Group name'),
        'Empty crew',
      );
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Create group'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select at least one person to add.'), findsOneWidget);
      expect(groups.createRequests, isEmpty);
    });

    testWidgets('reports a creation failure without leaving the form', (
      tester,
    ) async {
      final groups = FakeGroupRepository()
        ..createFailure = const GroupFailure(
          GroupFailureCode.serverUnavailable,
        );
      await _pumpApp(tester, groups: groups);

      await _openNewGroup(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Group name'),
        'Product crew',
      );
      await _selectPerson(tester, 'Maya Krishnan');
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Create group'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The group could not be created. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('New group'), findsOneWidget);
    });
  });

  group('group details', () {
    testWidgets('shows members, roles, and invited state', (tester) async {
      final groups = FakeGroupRepository(group: _adminGroup);
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      expect(find.text('Product crew'), findsWidgets);
      expect(find.text('4 members'), findsOneWidget);
      expect(find.text('Current user (You)'), findsOneWidget);
      expect(find.text('Maya Krishnan'), findsOneWidget);
      expect(find.text('Moderator'), findsOneWidget);
      expect(find.text('Invited'), findsOneWidget);
    });

    testWidgets('renames the group through the edit dialog', (tester) async {
      final groups = FakeGroupRepository(group: _adminGroup);
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      await tester.tap(find.text('Edit group name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Renamed crew');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(groups.renames, [('!product:test', 'Renamed crew')]);
    });

    testWidgets('removes a member after confirmation', (tester) async {
      final groups = FakeGroupRepository(group: _adminGroup);
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      await tester.tap(_memberMenu(tester, 'Maya Krishnan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from group').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Remove Maya Krishnan from this group?'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(groups.removedMembers, [('!product:test', '@maya:test')]);
    });

    testWidgets('keeps a member when the removal is cancelled', (tester) async {
      final groups = FakeGroupRepository(group: _adminGroup);
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      await tester.tap(_memberMenu(tester, 'Maya Krishnan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from group').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(groups.removedMembers, isEmpty);
    });

    testWidgets('promotes a member to admin', (tester) async {
      final groups = FakeGroupRepository(group: _adminGroup);
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      await tester.tap(_memberMenu(tester, 'Arjun Rao'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
      await tester.pumpAndSettle();

      expect(groups.roleChanges, [
        ('!product:test', '@arjun:test', GroupRole.admin),
      ]);
    });

    testWidgets('leaves the group after confirmation', (tester) async {
      final groups = FakeGroupRepository(group: _adminGroup);
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      await tester.tap(find.text('Leave group'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
      await tester.pumpAndSettle();

      expect(groups.leftRooms, ['!product:test']);
    });

    testWidgets('surfaces a rejected change without altering the view', (
      tester,
    ) async {
      final groups = FakeGroupRepository(group: _adminGroup)
        ..mutationFailure = const GroupFailure(GroupFailureCode.notPermitted);
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      await tester.tap(_memberMenu(tester, 'Arjun Rao'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission to do that.'),
        findsOneWidget,
      );
    });

    testWidgets('reports an unavailable group', (tester) async {
      final groups = FakeGroupRepository();
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      expect(find.text('This group is no longer available.'), findsOneWidget);
    });
  });

  group('permissions', () {
    testWidgets('hides administration controls from a plain member', (
      tester,
    ) async {
      final groups = FakeGroupRepository(group: _memberGroup);
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      expect(find.text('Edit group name'), findsNothing);
      expect(find.text('Add members'), findsNothing);
      expect(_anyPopupMenu, findsNothing);
      // Leaving is always available to a member of the group.
      expect(find.text('Leave group'), findsOneWidget);
    });

    testWidgets('offers add members only while seats remain', (tester) async {
      final groups = FakeGroupRepository(group: _fullGroup);
      await _pumpApp(tester, groups: groups);
      await _openGroupDetails(tester);

      expect(find.text('Add members'), findsNothing);
    });
  });

  group('conversation entry point', () {
    testWidgets('offers group details for a group conversation', (
      tester,
    ) async {
      await _pumpApp(tester, groups: FakeGroupRepository(group: _adminGroup));
      await tester.tap(find.text('Product crew'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Group details'), findsOneWidget);
    });

    testWidgets('hides group details for a direct conversation', (
      tester,
    ) async {
      await _pumpApp(
        tester,
        groups: FakeGroupRepository(group: _adminGroup),
        isDirect: true,
      );
      await tester.tap(find.text('Product crew'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Group details'), findsNothing);
    });
  });
}

const _people = [
  UserSearchResult(
    userId: '@maya:digitalgrub.com',
    displayName: 'Maya Krishnan',
  ),
];

final _adminGroup = GroupDetails(
  roomId: '!product:test',
  name: 'Product crew',
  description: 'Ship the mobile app',
  ownRole: GroupRole.admin,
  permissions: const GroupPermissions(
    canInvite: true,
    canRemove: true,
    canEditMetadata: true,
    canChangeRoles: true,
  ),
  members: const [
    GroupMember(
      userId: '@current:test',
      displayName: 'Current user',
      role: GroupRole.admin,
      membership: GroupMembership.joined,
      isSelf: true,
    ),
    GroupMember(
      userId: '@maya:test',
      displayName: 'Maya Krishnan',
      role: GroupRole.moderator,
      membership: GroupMembership.joined,
      isSelf: false,
    ),
    GroupMember(
      userId: '@arjun:test',
      displayName: 'Arjun Rao',
      role: GroupRole.member,
      membership: GroupMembership.joined,
      isSelf: false,
    ),
    GroupMember(
      userId: '@nisha:test',
      displayName: 'Nisha Iyer',
      role: GroupRole.member,
      membership: GroupMembership.invited,
      isSelf: false,
    ),
  ],
);

final _memberGroup = GroupDetails(
  roomId: '!product:test',
  name: 'Product crew',
  description: 'Ship the mobile app',
  ownRole: GroupRole.member,
  permissions: const GroupPermissions(),
  members: const [
    GroupMember(
      userId: '@current:test',
      displayName: 'Current user',
      role: GroupRole.member,
      membership: GroupMembership.joined,
      isSelf: true,
    ),
    GroupMember(
      userId: '@maya:test',
      displayName: 'Maya Krishnan',
      role: GroupRole.admin,
      membership: GroupMembership.joined,
      isSelf: false,
    ),
  ],
);

final _fullGroup = GroupDetails(
  roomId: '!product:test',
  name: 'Product crew',
  description: '',
  ownRole: GroupRole.admin,
  permissions: const GroupPermissions(
    canInvite: true,
    canRemove: true,
    canEditMetadata: true,
    canChangeRoles: true,
  ),
  members: [
    for (var index = 0; index < maxGroupMembers; index++)
      GroupMember(
        userId: '@member$index:test',
        displayName: 'Member $index',
        role: GroupRole.member,
        membership: GroupMembership.joined,
        isSelf: index == 0,
      ),
  ],
);

/// The member menu is typed with a private action enum, so it is matched
/// structurally rather than by an exact generic type.
final _anyPopupMenu = find.byWidgetPredicate(
  (widget) => widget is PopupMenuButton,
);

Finder _memberMenu(WidgetTester tester, String displayName) {
  return find.descendant(
    of: find.ancestor(
      of: find.text(displayName),
      matching: find.byType(ListTile),
    ),
    matching: _anyPopupMenu,
  );
}

Future<void> _openNewGroup(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create group'));
  await tester.pumpAndSettle();
}

Future<void> _openGroupDetails(WidgetTester tester) async {
  await tester.tap(find.text('Product crew'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Group details'));
  await tester.pumpAndSettle();
}

Future<void> _selectPerson(WidgetTester tester, String displayName) async {
  await tester.enterText(find.byType(SearchBar), 'maya');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  await tester.tap(find.text(displayName));
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeGroupRepository groups,
  bool isDirect = false,
}) async {
  // Tall enough that the whole member list and the leave action build without
  // scrolling; the default 800x600 surface clips them.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({'onboarding_complete': true});
  final preferences = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository(
    session: const AuthSession(userId: '@current:test'),
  );
  final chats = FakeChatRepository(
    chats: [
      ChatSummary(
        roomId: '!product:test',
        name: 'Product crew',
        lastMessage: 'Ready for QA',
        lastActivity: DateTime(2026, 8, 1, 10, 48),
        unreadCount: 0,
        isDirect: isDirect,
      ),
    ],
  );
  final messages = FakeMessageRepository({
    '!product:test': FakeConversationSession(
      ConversationSnapshot(
        roomId: '!product:test',
        title: 'Product crew',
        messages: const [],
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: isDirect,
      ),
    ),
  });

  addTearDown(auth.dispose);
  addTearDown(chats.dispose);
  addTearDown(groups.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => auth),
        chatRepositoryProvider.overrideWith((ref) async => chats),
        userRepositoryProvider.overrideWith(
          (ref) async => FakeUserRepository(results: _people),
        ),
        messageRepositoryProvider.overrideWith((ref) async => messages),
        groupRepositoryProvider.overrideWith((ref) async => groups),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}
