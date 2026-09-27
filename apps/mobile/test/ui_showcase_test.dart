import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
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

import 'helpers/fake_auth_repository.dart';
import 'helpers/fake_stage3_repositories.dart';
import 'helpers/test_app_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the populated offline chat list', (tester) async {
    await _setPhoneViewport(tester);
    await _pumpSeededApp(
      tester,
      connectionState: MessagingConnectionState.offline,
    );

    expect(find.text('Digitalgrub Chat'), findsOneWidget);
    expect(find.text('Asha Menon'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chat-list.png'),
    );
  });

  testWidgets('renders message delivery and retry states', (tester) async {
    await _setPhoneViewport(tester);
    await _pumpSeededApp(tester);

    await tester.tap(find.text('Asha Menon'));
    await tester.pumpAndSettle();

    expect(find.text('The revised brief is uploading now.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/conversation.png'),
    );
  });

  testWidgets('renders people search results', (tester) async {
    await _setPhoneViewport(tester);
    await _pumpSeededApp(tester);

    await tester.tap(find.byTooltip('Search people'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'maya');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('Maya Krishnan'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/people-search.png'),
    );
  });
}

Future<void> _setPhoneViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpSeededApp(
  WidgetTester tester, {
  MessagingConnectionState connectionState = MessagingConnectionState.online,
}) async {
  SharedPreferences.setMockInitialValues({'onboarding_complete': true});
  final preferences = await SharedPreferences.getInstance();
  final authRepository = FakeAuthRepository(
    session: const AuthSession(userId: '@preview:digitalgrub.com'),
  );
  final chatRepository = FakeChatRepository(chats: _chats);
  final userRepository = FakeUserRepository(
    results: _people,
    roomIds: const {'@maya:digitalgrub.com': '!maya:digitalgrub.com'},
  );
  final messageRepository = FakeMessageRepository({
    '!asha:digitalgrub.com': FakeConversationSession(_ashaConversation),
  });

  addTearDown(authRepository.dispose);
  addTearDown(chatRepository.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => authRepository),
        chatRepositoryProvider.overrideWith((ref) async => chatRepository),
        userRepositoryProvider.overrideWith((ref) async => userRepository),
        messageRepositoryProvider.overrideWith(
          (ref) async => messageRepository,
        ),
        messagingStatusProvider.overrideWith(
          (ref) => Stream.value(connectionState),
        ),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

final _chats = [
  ChatSummary(
    roomId: '!asha:digitalgrub.com',
    name: 'Asha Menon',
    lastMessage: 'The revised brief is uploading now.',
    lastActivity: DateTime(2026, 8, 1, 11, 22),
    unreadCount: 0,
    isDirect: true,
    pendingCount: 1,
    hasFailedMessages: true,
  ),
  ChatSummary(
    roomId: '!product:digitalgrub.com',
    name: 'Product crew',
    lastMessage: 'Maya: The mobile flow is ready for QA',
    lastActivity: DateTime(2026, 8, 1, 10, 48),
    unreadCount: 4,
    // Named in one of the four, so this row carries a count while the merely
    // unread one below it carries a dot. The golden is worth little if it
    // only ever shows one of the two states.
    highlightCount: 1,
    isDirect: false,
  ),
  ChatSummary(
    roomId: '!arjun:digitalgrub.com',
    name: 'Arjun Rao',
    lastMessage: 'Let us ship the smaller scope first.',
    lastActivity: DateTime(2026, 8, 1, 9, 15),
    unreadCount: 1,
    isDirect: true,
  ),
  ChatSummary(
    roomId: '!ops:digitalgrub.com',
    name: 'Operations',
    lastMessage: 'Sync is healthy across both homeservers.',
    lastActivity: DateTime(2026, 7, 31, 18, 40),
    unreadCount: 0,
    isDirect: false,
  ),
  ChatSummary(
    roomId: '!nisha:digitalgrub.com',
    name: 'Nisha Iyer',
    lastMessage: 'Thanks, talk tomorrow!',
    lastActivity: DateTime(2026, 7, 30, 20, 4),
    unreadCount: 0,
    isDirect: true,
  ),
];

const _people = [
  UserSearchResult(
    userId: '@maya:digitalgrub.com',
    displayName: 'Maya Krishnan',
  ),
  UserSearchResult(
    userId: '@mayank:digitalgrub.com',
    displayName: 'Mayank Shah',
  ),
  UserSearchResult(
    userId: '@maya.design:digitalgrub.com',
    displayName: 'Maya · Design',
  ),
];

final _ashaConversation = ConversationSnapshot(
  roomId: '!asha:digitalgrub.com',
  title: 'Asha Menon',
  isDirect: true,
  canLoadOlder: true,
  isLoadingOlder: false,
  typingUsers: const ['Asha Menon'],
  messages: [
    ChatMessage(
      eventId: 'local-failed',
      transactionId: 'dg-42',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'The revised brief is uploading now.',
      sentAt: DateTime(2026, 8, 1, 11, 22),
      isOwn: true,
      deliveryState: MessageDeliveryState.failed,
      canDeleteForEveryone: true,
    ),
    ChatMessage(
      eventId: 'event-4',
      senderId: '@asha:digitalgrub.com',
      senderName: 'Asha Menon',
      body: 'Perfect — I will review it before lunch.',
      sentAt: DateTime(2026, 8, 1, 11, 20),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
      replyTo: const MessageReplyPreview(
        eventId: 'event-3',
        senderName: 'You',
        body: 'The onboarding flow is ready for QA.',
      ),
      reactions: const [
        MessageReaction(key: '👍', count: 2, reactedByMe: false),
        MessageReaction(key: '🎉', count: 1, reactedByMe: true),
      ],
    ),
    ChatMessage(
      eventId: 'event-3',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'The onboarding flow is ready for QA.',
      sentAt: DateTime(2026, 8, 1, 11, 18),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      isEdited: true,
      isRead: true,
      canDeleteForEveryone: true,
    ),
    ChatMessage(
      eventId: 'event-2',
      senderId: '@asha:digitalgrub.com',
      senderName: 'Asha Menon',
      body: 'Looks clean. Can we keep the gold accent?',
      sentAt: DateTime(2026, 8, 1, 11, 17),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
    ChatMessage(
      eventId: 'event-1',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'Yes — deep teal for structure, gold for emphasis.',
      sentAt: DateTime(2026, 8, 1, 11, 15),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
    ),
  ],
);
