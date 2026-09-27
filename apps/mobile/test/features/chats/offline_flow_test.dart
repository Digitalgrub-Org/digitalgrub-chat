import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  testWidgets('shows cached conversations with an offline indicator', (
    tester,
  ) async {
    final chats = FakeChatRepository(
      chats: const [
        ChatSummary(
          roomId: '!cached:test',
          name: 'Cached chat',
          lastMessage: 'Available offline',
          lastActivity: null,
          unreadCount: 0,
          isDirect: true,
          pendingCount: 1,
        ),
      ],
    );
    await _pumpApp(
      tester,
      chats: chats,
      status: MessagingConnectionState.offline,
    );

    expect(find.text('Offline — showing saved conversations'), findsOneWidget);
    expect(find.text('Cached chat'), findsOneWidget);
    expect(find.text('Available offline'), findsOneWidget);
  });

  testWidgets('offers retry for a failed queued message', (tester) async {
    final chats = FakeChatRepository(
      chats: const [
        ChatSummary(
          roomId: '!failed:test',
          name: 'Retry chat',
          lastMessage: 'Try me again',
          lastActivity: null,
          unreadCount: 0,
          isDirect: true,
          pendingCount: 1,
          hasFailedMessages: true,
        ),
      ],
    );
    final session = FakeConversationSession(
      ConversationSnapshot(
        roomId: '!failed:test',
        title: 'Retry chat',
        messages: [
          ChatMessage(
            eventId: 'txn-failed',
            transactionId: 'txn-failed',
            senderId: '@current:test',
            senderName: 'Current user',
            body: 'Try me again',
            sentAt: DateTime.utc(2026, 8, 1),
            isOwn: true,
            deliveryState: MessageDeliveryState.failed,
          ),
        ],
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: true,
      ),
    );
    await _pumpApp(
      tester,
      chats: chats,
      status: MessagingConnectionState.online,
      messageRepository: FakeMessageRepository({'!failed:test': session}),
    );

    await tester.tap(find.text('Retry chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(session.retriedTransactionIds, ['txn-failed']);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeChatRepository chats,
  required MessagingConnectionState status,
  FakeMessageRepository? messageRepository,
}) async {
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
        messagingStatusProvider.overrideWith((ref) => Stream.value(status)),
        if (messageRepository != null)
          messageRepositoryProvider.overrideWith(
            (ref) async => messageRepository,
          ),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}
