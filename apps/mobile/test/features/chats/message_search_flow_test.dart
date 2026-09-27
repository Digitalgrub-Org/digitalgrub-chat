import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/search/application/search_providers.dart';
import 'package:dg_chat/features/search/domain/search_repository.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

class _FakeSearchRepository implements SearchRepository {
  final List<String> queries = [];
  List<MessageSearchResult> results = const [];
  SearchFailure? failure;

  @override
  Future<List<MessageSearchResult>> searchMessages(String term) async {
    queries.add(term);
    final error = failure;
    if (error != null) throw error;
    return results;
  }
}

Future<_FakeSearchRepository> _pumpChatList(WidgetTester tester) async {
  final search = _FakeSearchRepository()
    ..results = [
      MessageSearchResult(
        roomId: '!team:test',
        roomName: 'Team room',
        eventId: r'$hit',
        senderName: 'Maya',
        body: 'the budget spreadsheet is ready',
        sentAt: DateTime(2026, 8, 10, 9, 30),
      ),
    ];
  final chatRepository = FakeChatRepository(
    chats: [
      ChatSummary(
        roomId: '!team:test',
        name: 'Team room',
        lastMessage: 'budget talks tomorrow',
        lastActivity: DateTime(2026, 8, 10, 9),
        unreadCount: 0,
        isDirect: false,
        isInvite: false,
      ),
    ],
  );
  final session = FakeConversationSession(
    ConversationSnapshot(
      roomId: '!team:test',
      title: 'Team room',
      messages: const [],
      canLoadOlder: false,
      isLoadingOlder: false,
      isDirect: false,
    ),
  );
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': true,
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
        messageRepositoryProvider.overrideWith(
          (ref) async => FakeMessageRepository({'!team:test': session}),
        ),
        searchRepositoryProvider.overrideWith((ref) async => search),
        messagingStatusProvider.overrideWith(
          (ref) => Stream.value(MessagingConnectionState.online),
        ),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
  return search;
}

void main() {
  testWidgets('finds messages and opens the conversation they live in', (
    tester,
  ) async {
    final search = await _pumpChatList(tester);

    await tester.tap(find.byTooltip('Search conversations'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'budget');
    // The debounce has to settle before anything reaches the repository.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(search.queries, ['budget']);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.textContaining('budget spreadsheet'), findsOneWidget);

    await tester.tap(find.textContaining('budget spreadsheet'));
    await tester.pumpAndSettle();

    // The conversation opened: its app bar carries the room title.
    expect(find.widgetWithText(AppBar, 'Team room'), findsOneWidget);
  });

  testWidgets('waits for three characters before searching', (tester) async {
    final search = await _pumpChatList(tester);

    await tester.tap(find.byTooltip('Search conversations'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bu');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Two characters would match half the room — noise served as results.
    expect(search.queries, isEmpty);
    expect(find.text('Messages'), findsNothing);
  });

  testWidgets('a failed search leaves the conversation list working', (
    tester,
  ) async {
    final search = await _pumpChatList(tester);
    search.failure = const SearchFailure(SearchFailureCode.serverUnavailable);

    await tester.tap(find.byTooltip('Search conversations'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'budget');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      find.text('Message search is unavailable right now.'),
      findsOneWidget,
    );
    // The local preview match above the section is unaffected.
    expect(find.text('Team room'), findsWidgets);
  });
}
