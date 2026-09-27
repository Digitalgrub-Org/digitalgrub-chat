// An invited room cannot be opened: Matrix serves no timeline until the
// account joins. Every existing test used fakes that only ever modelled joined
// rooms, which is how a recipient being unable to read their messages went
// unnoticed until the stack was exercised end to end.
import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  testWidgets('an invite offers a decision instead of opening', (tester) async {
    final chats = _chats();
    await _pumpApp(tester, chats: chats);

    expect(find.text('dgtest1'), findsOneWidget);
    expect(find.text('dgtest1 invited you to chat'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Decline'), findsOneWidget);
  });

  testWidgets('accepting joins the room', (tester) async {
    final chats = _chats();
    await _pumpApp(tester, chats: chats);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.pumpAndSettle();

    expect(chats.acceptedInvites, ['!invited:test']);
    expect(chats.declinedInvites, isEmpty);
  });

  testWidgets('declining asks first, then leaves', (tester) async {
    final chats = _chats();
    await _pumpApp(tester, chats: chats);

    await tester.tap(find.widgetWithText(TextButton, 'Decline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Decline this invitation?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(chats.declinedInvites, ['!invited:test']);
    expect(chats.acceptedInvites, isEmpty);
  });

  testWidgets('a cancelled decline leaves the invite alone', (tester) async {
    final chats = _chats();
    await _pumpApp(tester, chats: chats);

    await tester.tap(find.widgetWithText(TextButton, 'Decline'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(chats.declinedInvites, isEmpty);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
  });

  testWidgets('a failure is reported and the invite stays', (tester) async {
    final chats = _chats()
      ..inviteFailure = const ChatFailure(ChatFailureCode.serverUnavailable);
    await _pumpApp(tester, chats: chats);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('invitation could not be updated'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
  });

  testWidgets('a joined room still opens normally', (tester) async {
    final chats = FakeChatRepository(
      chats: [
        ChatSummary(
          roomId: '!joined:test',
          name: 'Joined room',
          lastMessage: 'Already a member',
          lastActivity: DateTime(2026, 8, 4, 10),
          unreadCount: 0,
          isDirect: true,
        ),
      ],
    );
    await _pumpApp(tester, chats: chats);

    // No invite affordances on a room the account has already joined.
    expect(find.widgetWithText(FilledButton, 'Accept'), findsNothing);
    expect(find.text('Already a member'), findsOneWidget);
  });

  testWidgets('an invite without a resolvable inviter still works', (
    tester,
  ) async {
    final chats = FakeChatRepository(
      chats: [
        ChatSummary(
          roomId: '!invited:test',
          name: 'Someone',
          lastMessage: '',
          lastActivity: null,
          unreadCount: 0,
          isDirect: true,
          isInvite: true,
        ),
      ],
    );
    await _pumpApp(tester, chats: chats);

    expect(find.text('You have been invited to chat'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
  });
}

FakeChatRepository _chats() => FakeChatRepository(
  chats: [
    ChatSummary(
      roomId: '!invited:test',
      name: 'dgtest1',
      lastMessage: '',
      lastActivity: null,
      unreadCount: 0,
      isDirect: true,
      isInvite: true,
      invitedBy: 'dgtest1',
    ),
  ],
);

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeChatRepository chats,
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
  addTearDown(auth.dispose);
  addTearDown(chats.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => auth),
        chatRepositoryProvider.overrideWith((ref) async => chats),
        // Accepting opens the conversation, so the room has to be openable.
        messageRepositoryProvider.overrideWith(
          (ref) async => FakeMessageRepository({
            '!invited:test': FakeConversationSession(
              ConversationSnapshot(
                roomId: '!invited:test',
                title: 'dgtest1',
                messages: const [],
                canLoadOlder: false,
                isLoadingOlder: false,
                isDirect: true,
              ),
            ),
          }),
        ),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}
