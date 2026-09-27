import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/media/avatar_picker.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/groups/application/group_providers.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:dg_chat/features/moderation/application/report_providers.dart';
import 'package:dg_chat/features/moderation/domain/report_repository.dart';
import 'package:dg_chat/features/profile/application/profile_providers.dart';
import 'package:dg_chat/features/profile/domain/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_group_repository.dart';
import '../../helpers/fake_profile_repositories.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  group('own profile', () {
    testWidgets('opens from settings and shows editable fields', (
      tester,
    ) async {
      await _pumpApp(tester);
      await _openOwnProfile(tester);

      expect(find.text('My profile'), findsWidgets);
      expect(find.text('Current user'), findsWidgets);
      expect(find.text('Product and design.'), findsOneWidget);
      expect(find.text('@current:test'), findsWidgets);
      expect(find.textContaining('Not verified'), findsOneWidget);
    });

    testWidgets('saves an edited display name', (tester) async {
      final profiles = _profileRepository();
      await _pumpApp(tester, profiles: profiles);
      await _openOwnProfile(tester);

      await tester.tap(find.text('Display name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Renamed user');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(profiles.displayNames, ['Renamed user']);
    });

    testWidgets('rejects an empty display name', (tester) async {
      final profiles = _profileRepository();
      await _pumpApp(tester, profiles: profiles);
      await _openOwnProfile(tester);

      await tester.tap(find.text('Display name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a display name.'), findsOneWidget);
      expect(profiles.displayNames, isEmpty);
    });

    testWidgets('uploads a picked avatar', (tester) async {
      final profiles = _profileRepository();
      final picker = FakeAvatarPicker(result: FakeAvatarPicker.sample());
      await _pumpApp(tester, profiles: profiles, picker: picker);
      await _openOwnProfile(tester);

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();

      expect(picker.pickCount, 1);
      expect(profiles.avatars.single?.fileName, 'avatar.jpg');
      expect(find.text('Photo updated.'), findsOneWidget);
    });

    testWidgets('does not upload when picking is cancelled', (tester) async {
      final profiles = _profileRepository();
      final picker = FakeAvatarPicker();
      await _pumpApp(tester, profiles: profiles, picker: picker);
      await _openOwnProfile(tester);

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();

      expect(picker.pickCount, 1);
      expect(profiles.avatars, isEmpty);
    });

    testWidgets('reports a failed picker without uploading', (tester) async {
      final profiles = _profileRepository();
      final picker = FakeAvatarPicker(throwOnPick: true);
      await _pumpApp(tester, profiles: profiles, picker: picker);
      await _openOwnProfile(tester);

      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();

      expect(find.text('That image could not be opened.'), findsOneWidget);
      expect(profiles.avatars, isEmpty);
    });

    testWidgets('does not offer block or report on your own profile', (
      tester,
    ) async {
      await _pumpApp(tester);
      await _openOwnProfile(tester);

      expect(find.text('Block user'), findsNothing);
      expect(find.text('Report user'), findsNothing);
    });
  });

  group('other profiles', () {
    testWidgets('blocks a user after confirmation', (tester) async {
      final profiles = _profileRepository();
      await _pumpApp(tester, profiles: profiles);
      await _openOtherProfile(tester);

      await tester.tap(find.text('Block user'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Block Maya Krishnan?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Block'));
      await tester.pumpAndSettle();

      expect(profiles.blocked, ['@maya:test']);
    });

    testWidgets('keeps the user when blocking is cancelled', (tester) async {
      final profiles = _profileRepository();
      await _pumpApp(tester, profiles: profiles);
      await _openOtherProfile(tester);

      await tester.tap(find.text('Block user'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(profiles.blocked, isEmpty);
    });

    testWidgets('unblocks without a confirmation step', (tester) async {
      final profiles = _profileRepository(mayaBlocked: true);
      await _pumpApp(tester, profiles: profiles);
      await _openOtherProfile(tester);

      await tester.tap(find.widgetWithText(ListTile, 'Unblock'));
      await tester.pumpAndSettle();

      expect(profiles.unblocked, ['@maya:test']);
    });
  });

  group('reporting', () {
    testWidgets('submits a categorised report for a user', (tester) async {
      final reports = FakeReportRepository();
      await _pumpApp(tester, reports: reports);
      await _openOtherProfile(tester);

      await tester.tap(find.text('Report user'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Harassment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Repeated messages');
      await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
      await tester.pumpAndSettle();

      expect(reports.submitted, hasLength(1));
      final report = reports.submitted.single;
      expect(report.reportedUserId, '@maya:test');
      expect(report.category, ReportCategory.harassment);
      expect(report.comment, 'Repeated messages');
      expect(report.isMessageReport, isFalse);
      expect(find.text('Report submitted. Thank you.'), findsOneWidget);
    });

    testWidgets('blocks alongside the report when asked', (tester) async {
      final profiles = _profileRepository();
      final reports = FakeReportRepository();
      await _pumpApp(tester, profiles: profiles, reports: reports);
      await _openOtherProfile(tester);

      await tester.tap(find.text('Report user'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also block this user'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
      await tester.pumpAndSettle();

      expect(reports.submitted, hasLength(1));
      expect(profiles.blocked, ['@maya:test']);
    });

    testWidgets('keeps the sheet open when submission fails', (tester) async {
      final reports = FakeReportRepository()
        ..failure = const ReportFailure(ReportFailureCode.serverUnavailable);
      await _pumpApp(tester, reports: reports);
      await _openOtherProfile(tester);

      await tester.tap(find.text('Report user'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
      await tester.pumpAndSettle();

      expect(
        find.text('That report could not be submitted. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Submit report'),
        findsOneWidget,
      );
    });

    testWidgets('carries room and event for a reported message', (
      tester,
    ) async {
      final reports = FakeReportRepository();
      await _pumpApp(tester, reports: reports);

      await tester.tap(find.text('Product crew'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Hello from Maya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit report'));
      await tester.pumpAndSettle();

      final report = reports.submitted.single;
      expect(report.reportedUserId, '@maya:test');
      expect(report.roomId, '!product:test');
      expect(report.eventId, 'event-1');
      expect(report.isMessageReport, isTrue);
    });
  });

  group('blocked users', () {
    // Guideline 1.2: blocking has to be reachable from the conversation, and
    // it has to reach the developer -- the repository files that report.
    testWidgets('blocks the sender straight from their message', (
      tester,
    ) async {
      final profiles = _profileRepository();
      await _pumpApp(tester, profiles: profiles);

      await tester.tap(find.text('Product crew'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Hello from Maya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block user'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Block Maya Krishnan?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Block'));
      await tester.pumpAndSettle();

      expect(profiles.blocked, ['@maya:test']);
      expect(find.text('User blocked.'), findsOneWidget);
    });

    testWidgets('blocks no one when the confirmation is cancelled', (
      tester,
    ) async {
      final profiles = _profileRepository();
      await _pumpApp(tester, profiles: profiles);

      await tester.tap(find.text('Product crew'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Hello from Maya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block user'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(profiles.blocked, isEmpty);
    });

    testWidgets('lists blocked users and unblocks one', (tester) async {
      final profiles = _profileRepository(mayaBlocked: true);
      await _pumpApp(tester, profiles: profiles);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blocked users'));
      await tester.pumpAndSettle();

      expect(find.text('Maya Krishnan'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Unblock'));
      await tester.pumpAndSettle();

      expect(profiles.unblocked, ['@maya:test']);
    });

    testWidgets('shows an empty state when nobody is blocked', (tester) async {
      await _pumpApp(tester);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blocked users'));
      await tester.pumpAndSettle();

      expect(find.text('You have not blocked anyone.'), findsOneWidget);
    });
  });

  group('blocked message suppression', () {
    testWidgets('replaces a blocked sender message with a notice', (
      tester,
    ) async {
      await _pumpApp(tester, blockedSender: true);

      await tester.tap(find.text('Product crew'));
      await tester.pumpAndSettle();

      expect(find.text('Hello from Maya'), findsNothing);
      expect(find.text('Message from a blocked user'), findsOneWidget);
    });
  });
}

FakeProfileRepository _profileRepository({bool mayaBlocked = false}) {
  return FakeProfileRepository(
    profiles: {
      '@current:test': const UserProfile(
        userId: '@current:test',
        displayName: 'Current user',
        isSelf: true,
        about: 'Product and design.',
        mobileNumber: '+91 90000 00000',
      ),
      '@maya:test': UserProfile(
        userId: '@maya:test',
        displayName: 'Maya Krishnan',
        isSelf: false,
        isBlocked: mayaBlocked,
      ),
    },
  );
}

Future<void> _openOwnProfile(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('My profile'));
  await tester.pumpAndSettle();
}

Future<void> _openOtherProfile(WidgetTester tester) async {
  await tester.tap(find.text('Product crew'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Group details'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Maya Krishnan'));
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(
  WidgetTester tester, {
  FakeProfileRepository? profiles,
  FakeReportRepository? reports,
  FakeAvatarPicker? picker,
  bool blockedSender = false,
}) async {
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
        lastMessage: 'Hello from Maya',
        lastActivity: DateTime(2026, 8, 1, 10, 48),
        unreadCount: 0,
        isDirect: false,
      ),
    ],
  );
  final messages = FakeMessageRepository({
    '!product:test': FakeConversationSession(
      ConversationSnapshot(
        roomId: '!product:test',
        title: 'Product crew',
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: false,
        messages: [
          ChatMessage(
            eventId: 'event-1',
            senderId: '@maya:test',
            senderName: 'Maya Krishnan',
            body: 'Hello from Maya',
            sentAt: DateTime(2026, 8, 1, 10, 48),
            isOwn: false,
            deliveryState: MessageDeliveryState.synced,
            isFromBlockedUser: blockedSender,
          ),
        ],
      ),
    ),
  });
  final profileRepository = profiles ?? _profileRepository();
  // Reaching another person's profile goes through the group member list.
  final groups = FakeGroupRepository(
    group: const GroupDetails(
      roomId: '!product:test',
      name: 'Product crew',
      description: '',
      ownRole: GroupRole.member,
      permissions: GroupPermissions(),
      members: [
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
          role: GroupRole.member,
          membership: GroupMembership.joined,
          isSelf: false,
        ),
      ],
    ),
  );

  addTearDown(auth.dispose);
  addTearDown(chats.dispose);
  addTearDown(groups.dispose);
  addTearDown(profileRepository.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => auth),
        chatRepositoryProvider.overrideWith((ref) async => chats),
        userRepositoryProvider.overrideWith(
          (ref) async => FakeUserRepository(results: const []),
        ),
        messageRepositoryProvider.overrideWith((ref) async => messages),
        groupRepositoryProvider.overrideWith((ref) async => groups),
        profileRepositoryProvider.overrideWith(
          (ref) async => profileRepository,
        ),
        reportRepositoryProvider.overrideWith(
          (ref) async => reports ?? FakeReportRepository(),
        ),
        avatarPickerProvider.overrideWithValue(picker ?? FakeAvatarPicker()),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}
