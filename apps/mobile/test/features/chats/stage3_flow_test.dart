import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/chats/presentation/chat_list_screen.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  testWidgets('opens a cached conversation and sends plain text', (
    tester,
  ) async {
    final chatRepository = FakeChatRepository(
      chats: [
        ChatSummary(
          roomId: '!bob:test',
          name: 'Bob',
          lastMessage: 'See you soon',
          lastActivity: DateTime(2026, 8, 1, 9, 30),
          unreadCount: 2,
          isDirect: true,
        ),
      ],
    );
    final session = FakeConversationSession(
      ConversationSnapshot(
        roomId: '!bob:test',
        title: 'Bob',
        messages: [
          ChatMessage(
            eventId: r'$event',
            senderId: '@bob:test',
            senderName: 'Bob',
            body: 'See you soon',
            sentAt: DateTime(2026, 8, 1, 9, 30),
            isOwn: false,
            deliveryState: MessageDeliveryState.synced,
          ),
        ],
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: true,
      ),
    );
    final messageRepository = FakeMessageRepository({'!bob:test': session});

    await _pumpApp(
      tester,
      chatRepository: chatRepository,
      userRepository: FakeUserRepository(),
      messageRepository: messageRepository,
    );

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('See you soon'), findsOneWidget);
    // Unread, but nothing that mentions this account -- so the row marks
    // itself with a dot rather than a count.
    expect(find.byType(UnreadIndicator), findsOneWidget);
    expect(find.text('2'), findsNothing);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.text('See you soon'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Hello Bob');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(session.sentTexts, ['Hello Bob']);
  });

  testWidgets('debounces people search and opens the reused direct room', (
    tester,
  ) async {
    final chatRepository = FakeChatRepository();
    final userRepository = FakeUserRepository(
      results: const [
        UserSearchResult(userId: '@alice:test', displayName: 'Alice'),
      ],
      roomIds: {'@alice:test': '!alice:test'},
    );
    final session = FakeConversationSession(
      const ConversationSnapshot(
        roomId: '!alice:test',
        title: 'Alice',
        messages: [],
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: true,
      ),
    );
    final messageRepository = FakeMessageRepository({'!alice:test': session});

    await _pumpApp(
      tester,
      chatRepository: chatRepository,
      userRepository: userRepository,
      messageRepository: messageRepository,
    );

    await tester.tap(find.text('Find people'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'ali');
    await tester.pump(const Duration(milliseconds: 349));
    expect(userRepository.queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(userRepository.queries, ['ali']);
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(userRepository.startedUsers, ['@alice:test']);
    expect(messageRepository.openedRooms, ['!alice:test']);
    expect(find.text('No messages yet'), findsOneWidget);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeChatRepository chatRepository,
  required FakeUserRepository userRepository,
  required FakeMessageRepository messageRepository,
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': true,
    // A returning user has already accepted the community rules; these tests
    // exercise sending, not the guideline 1.2 gate.
    'content_agreement_version': AppPreferences.contentAgreementVersion,
  });
  final preferences = await SharedPreferences.getInstance();
  final authRepository = FakeAuthRepository(
    session: const AuthSession(userId: '@current:test'),
  );
  addTearDown(authRepository.dispose);
  addTearDown(chatRepository.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => authRepository),
        chatRepositoryProvider.overrideWith((ref) async => chatRepository),
        userRepositoryProvider.overrideWith((ref) async => userRepository),
        messageRepositoryProvider.overrideWith(
          (ref) async => messageRepository,
        ),
        messagingStatusProvider.overrideWith(
          (ref) => Stream.value(MessagingConnectionState.online),
        ),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}
