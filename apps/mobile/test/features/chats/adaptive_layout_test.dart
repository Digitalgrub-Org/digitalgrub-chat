import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/layout/breakpoints.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/chats/presentation/app_shell.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppBreakpoints', () {
    test('classifies window widths', () {
      expect(AppBreakpoints.of(390), AppWindowSize.compact);
      expect(AppBreakpoints.of(899), AppWindowSize.compact);
      expect(AppBreakpoints.of(900), AppWindowSize.medium);
      expect(AppBreakpoints.of(1399), AppWindowSize.medium);
      expect(AppBreakpoints.of(1400), AppWindowSize.expanded);
    });

    test('only the wider classes carry a second pane', () {
      expect(AppWindowSize.compact.hasSidePanes, isFalse);
      expect(AppWindowSize.medium.hasSidePanes, isTrue);
      expect(AppWindowSize.expanded.hasSidePanes, isTrue);
    });
  });

  testWidgets('a wide window opens a conversation beside the list', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1440, 900));
    await _pumpSeededApp(tester);

    // Nothing is selected yet, so the detail pane invites a choice rather than
    // sitting empty.
    expect(find.text('Pick up a conversation'), findsOneWidget);
    // Top-level navigation is a rail, not the phone's bottom bar.
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.text('Asha Menon'));
    await tester.pumpAndSettle();

    // This is the point of the layout: the conversation is open *and* the rest
    // of the list is still there to switch between.
    expect(find.text('The revised brief is uploading now.'), findsWidgets);
    expect(find.text('Product crew'), findsOneWidget);
  });

  testWidgets('the sidebar still works after a conversation is open', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1440, 900));
    await _pumpSeededApp(tester);

    await tester.tap(find.text('Asha Menon'));
    await tester.pumpAndSettle();
    expect(find.text('The revised brief is uploading now.'), findsWidgets);

    // The bug this guards: opening a chat used to push a transparent page
    // over the sidebar, and its ModalBarrier swallowed every later tap. The
    // list stayed perfectly visible and completely dead -- one chat in, and
    // you could not switch to another without reloading.
    await tester.tap(find.text('Product crew'));
    await tester.pumpAndSettle();
    // Its message shows nowhere else, so seeing it proves the second room
    // actually opened rather than the first one lingering.
    expect(find.text('Shipping the QA build tonight.'), findsWidgets);
  });

  testWidgets('a phone window still covers the list with the conversation', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpSeededApp(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Pick up a conversation'), findsNothing);

    await tester.tap(find.text('Asha Menon'));
    await tester.pumpAndSettle();

    // The conversation was pushed over the list, so no other chat is on screen.
    expect(find.text('The revised brief is uploading now.'), findsWidgets);
    expect(find.text('Product crew'), findsNothing);
  });

  testWidgets('a real connection problem is still reported', (tester) async {
    await _setViewport(tester, const Size(1440, 900));
    await _pumpSeededApp(
      tester,
      connectionState: MessagingConnectionState.serverUnavailable,
    );

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('syncing is not reported at all', (tester) async {
    await _setViewport(tester, const Size(1440, 900));
    await _pumpSeededApp(
      tester,
      connectionState: MessagingConnectionState.synchronizing,
    );

    // None of the banner's icons are on screen, so nothing was inserted above
    // the shell and nothing shifted.
    expect(find.byIcon(Icons.sync_rounded), findsNothing);
    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    expect(find.byIcon(Icons.cloud_sync_outlined), findsNothing);
  });

  testWidgets('a conversation address restores the room on a wide window', (
    tester,
  ) async {
    // What a browser refresh is: nothing but the location, and the UI has to
    // come back from it.
    await _setViewport(tester, const Size(1440, 900));
    await _pumpSeededApp(tester);

    _router(
      tester,
    ).go('/chats/room/${Uri.encodeComponent('!asha:digitalgrub.com')}');
    await tester.pumpAndSettle();

    expect(find.text('The revised brief is uploading now.'), findsWidgets);
    // The list stays beside it, still interactive.
    expect(find.text('Product crew'), findsOneWidget);
  });

  testWidgets('a conversation address restores the room on a phone', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    await _pumpSeededApp(tester);

    _router(
      tester,
    ).go('/chats/room/${Uri.encodeComponent('!asha:digitalgrub.com')}');
    await tester.pumpAndSettle();

    expect(find.text('The revised brief is uploading now.'), findsWidgets);
    // Full screen: the tab bar and compose FAB belong to the list, and the
    // FAB would sit exactly on the send button.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    // Back returns to the list, chrome restored.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('the old conversation address still resolves', (tester) async {
    // Web tabs and bookmarks from builds that used /conversation/:id.
    await _setViewport(tester, const Size(390, 844));
    await _pumpSeededApp(tester);

    _router(
      tester,
    ).go('/conversation/${Uri.encodeComponent('!asha:digitalgrub.com')}');
    await tester.pumpAndSettle();

    expect(find.text('The revised brief is uploading now.'), findsWidgets);
  });

  testWidgets('selecting a conversation writes it into the location', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1440, 900));
    await _pumpSeededApp(tester);

    await tester.tap(find.text('Asha Menon'));
    await tester.pumpAndSettle();

    final uri = _router(
      tester,
    ).routerDelegate.currentConfiguration.uri.toString();
    expect(uri, '/chats/room/${Uri.encodeComponent('!asha:digitalgrub.com')}');
  });

  testWidgets('the rail switches branches without closing the conversation', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1440, 900));
    await _pumpSeededApp(tester);

    await tester.tap(find.text('Asha Menon'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Contacts'));
    await tester.pumpAndSettle();

    // The sidebar changed but the open conversation stayed put, the way a
    // desktop client keeps the channel you were reading.
    expect(find.text('The revised brief is uploading now.'), findsWidgets);
  });
}

GoRouter _router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(AppShell)));

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
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
    results: const [],
    roomIds: const {},
  );
  final messageRepository = FakeMessageRepository({
    '!asha:digitalgrub.com': FakeConversationSession(_ashaConversation),
    '!product:digitalgrub.com': FakeConversationSession(_productConversation),
  });

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
  ),
  ChatSummary(
    roomId: '!product:digitalgrub.com',
    name: 'Product crew',
    lastMessage: 'Maya: The mobile flow is ready for QA',
    lastActivity: DateTime(2026, 8, 1, 10, 48),
    unreadCount: 4,
    isDirect: false,
  ),
];

final _ashaConversation = ConversationSnapshot(
  roomId: '!asha:digitalgrub.com',
  title: 'Asha Menon',
  isDirect: true,
  canLoadOlder: false,
  isLoadingOlder: false,
  typingUsers: const [],
  messages: [
    ChatMessage(
      eventId: 'event-1',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'The revised brief is uploading now.',
      sentAt: DateTime(2026, 8, 1, 11, 22),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
    ),
  ],
);

/// A second room, so switching between conversations is observable rather
/// than inferred: its message appears nowhere else, including the sidebar
/// previews.
final _productConversation = ConversationSnapshot(
  roomId: '!product:digitalgrub.com',
  title: 'Product crew',
  isDirect: false,
  canLoadOlder: false,
  isLoadingOlder: false,
  typingUsers: const [],
  messages: [
    ChatMessage(
      eventId: 'event-2',
      senderId: '@maya:digitalgrub.com',
      senderName: 'Maya',
      body: 'Shipping the QA build tonight.',
      sentAt: DateTime(2026, 8, 1, 10, 48),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
  ],
);
