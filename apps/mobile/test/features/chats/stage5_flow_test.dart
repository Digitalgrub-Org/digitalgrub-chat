import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  testWidgets('replies and reacts from the long-press action sheet', (
    tester,
  ) async {
    final session = await _pumpConversation(tester);

    await tester.longPress(find.text('Can you review this?').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Replying to Bob'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Reviewing it now');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(session.sentMessages, [('Reviewing it now', r'$bob')]);

    await tester.longPress(find.text('Can you review this?').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('React'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(session.toggledReactions, [(r'$bob', '👍')]);
  });

  testWidgets('edits and deletes an owned message', (tester) async {
    final session = await _pumpConversation(tester);

    await tester.longPress(find.text('Draft response'));
    await tester.pumpAndSettle();
    // Nobody reports or blocks themselves.
    expect(find.text('Report'), findsNothing);
    expect(find.text('Block user'), findsNothing);
    await tester.ensureVisible(find.text('Edit message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit message'));
    await tester.pumpAndSettle();
    expect(find.text('Editing message'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Final response');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(session.editedMessages, [(r'$own', 'Final response')]);

    await tester.longPress(find.text('Draft response'));
    await tester.pumpAndSettle();
    // The action sheet scrolls: Forward pushed the later actions past the
    // fold on a test-sized screen.
    await tester.ensureVisible(find.text('Delete message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for everyone'));
    await tester.pumpAndSettle();
    expect(session.redactedEventIds, [r'$own']);
  });

  testWidgets('renders replies, reactions, edits, reads, and typing', (
    tester,
  ) async {
    final session = await _pumpConversation(tester);

    expect(find.text('Asha typing…'), findsOneWidget);
    expect(find.text('edited'), findsOneWidget);
    expect(find.text('👍 2'), findsOneWidget);
    expect(find.text('Draft response'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'Typing test');
    await tester.pump();
    expect(session.typingUpdates, contains(true));
  });

  testWidgets('pins a message and shows it in the bar', (tester) async {
    final session = await _pumpConversation(tester, canPin: true);

    await tester.longPress(find.text('Can you review this?').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();
    expect(session.pinChanges, [(r'$bob', true)]);

    // The bar is driven by room state, which the server echoes back.
    final before = find.text('Can you review this?').evaluate().length;
    session.emit(
      ConversationSnapshot(
        roomId: '!bob:test',
        title: 'Bob',
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: true,
        canPin: true,
        pinnedEventIds: const [r'$bob'],
        messages: session.snapshot.messages,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pinned message'), findsOneWidget);
    // One more copy of that text than before: the bar previews it. (The
    // timeline already showed it twice, once quoted in a reply.)
    expect(find.text('Can you review this?'), findsNWidgets(before + 1));
  });

  testWidgets('unpins from the bar', (tester) async {
    final session = await _pumpConversation(
      tester,
      pinnedEventIds: const [r'$bob'],
      canPin: true,
    );

    await tester.tap(find.byTooltip('Unpin'));
    await tester.pumpAndSettle();
    expect(session.pinChanges, [(r'$bob', false)]);
  });

  testWidgets('a member without power sees the pin but cannot change it', (
    tester,
  ) async {
    await _pumpConversation(tester, pinnedEventIds: const [r'$bob']);

    // Readable by everyone: the bar is how you find what was pinned.
    expect(find.text('Pinned message'), findsOneWidget);
    // Neither route to changing it is offered.
    expect(find.byTooltip('Unpin'), findsNothing);
    await tester.longPress(find.text('Draft response'));
    await tester.pumpAndSettle();
    expect(find.text('Pin'), findsNothing);
  });

  testWidgets('a call that has ended reads as a missed call', (tester) async {
    await _pumpConversation(tester, withCallEntry: true);

    // Nobody is on a call, so the entry is a record rather than an invitation.
    expect(find.text('Missed call'), findsOneWidget);
    expect(find.text('Call back'), findsOneWidget);
    expect(find.text('Join'), findsNothing);
  });

  testWidgets('a call still running is joinable from the timeline', (
    tester,
  ) async {
    await _pumpConversation(
      tester,
      withCallEntry: true,
      liveCalls: const [
        // Named apart from the chat row only so the helper's tap on "Bob"
        // stays unambiguous -- the bar renders the room name too.
        LiveCall(
          roomId: '!bob:test',
          roomName: 'Bob calling',
          participantCount: 1,
        ),
      ],
    );

    // The ring is long over; the call is not. That is the whole feature.
    expect(find.text('Bob started a call'), findsOneWidget);
    expect(find.text('Join'), findsWidgets);
    expect(find.text('Missed call'), findsNothing);
  });

  testWidgets('an earlier call does not offer to join the current one', (
    tester,
  ) async {
    // Exactly the case that showed up in testing: call once, call again, and
    // the first call was still sitting there offering to join.
    await _pumpConversation(
      tester,
      withCallEntry: true,
      withEarlierCall: true,
      liveCalls: const [
        LiveCall(
          roomId: '!bob:test',
          roomName: 'Bob calling',
          participantCount: 1,
        ),
      ],
    );

    // The newest call is live and joinable; the earlier one is history --
    // and stale history at that, so it carries no button at all.
    expect(find.text('Bob started a call'), findsOneWidget);
    expect(find.text('Call back'), findsNothing);
    expect(
      find.descendant(of: find.byType(TextButton), matching: find.text('Join')),
      findsOneWidget,
    );
  });

  testWidgets('a mouse gets reactions without long pressing', (tester) async {
    final session = await _pumpConversation(tester);

    // A mouse never long-presses, which is why reactions read as missing on
    // the web. Pointing at a message has to be enough.
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('Can you review this?').last)),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('React'), findsOneWidget);
    await tester.tap(find.byTooltip('React'));
    await tester.pumpAndSettle();

    expect(session.toggledReactions, [(r'$bob', '👍')]);
  });

  testWidgets('right click opens the same menu as a long press', (
    tester,
  ) async {
    await _pumpConversation(tester);

    final target = find.text('Can you review this?').last;
    final pointer = TestPointer(
      1,
      PointerDeviceKind.mouse,
      null,
      kSecondaryButton,
    );
    await tester.sendEventToBinding(pointer.down(tester.getCenter(target)));
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();

    // The one sheet, reached a second way -- not a second copy of it.
    expect(find.text('Reply'), findsWidgets);
    expect(find.text('Forward'), findsOneWidget);
  });

  testWidgets('ctrl+enter sends the message being typed', (tester) async {
    final session = await _pumpConversation(tester);

    await tester.enterText(find.byType(TextField), 'Shipping it now');
    await tester.pump();
    // Plain Enter is a newline in a multiline composer; the modifier is
    // what says "send" from a desk keyboard.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(session.sentTexts, ['Shipping it now']);
  });

  testWidgets('ctrl+enter with an empty composer sends nothing', (
    tester,
  ) async {
    final session = await _pumpConversation(tester);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(session.sentTexts, isEmpty);
  });

  testWidgets('a stale missed call keeps its text but loses the button', (
    tester,
  ) async {
    final session = await _pumpConversation(tester);
    session.emit(
      ConversationSnapshot(
        roomId: '!bob:test',
        title: 'Bob',
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: true,
        messages: [
          ChatMessage(
            eventId: r'$oldring',
            senderId: '@bob:test',
            senderName: 'Bob',
            body: '',
            sentAt: DateTime.now().subtract(const Duration(hours: 2)),
            isOwn: false,
            deliveryState: MessageDeliveryState.synced,
            isCallStart: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // History, not an invitation: a chat full of buttons is noise.
    expect(find.text('Missed call'), findsOneWidget);
    expect(find.text('Call back'), findsNothing);
  });
}

Future<FakeConversationSession> _pumpConversation(
  WidgetTester tester, {
  List<String> pinnedEventIds = const [],
  bool canPin = false,
  bool withCallEntry = false,
  bool withEarlierCall = false,
  List<LiveCall> liveCalls = const [],
}) async {
  final chatRepository = FakeChatRepository(
    chats: [
      ChatSummary(
        roomId: '!bob:test',
        name: 'Bob',
        lastMessage: 'Can you review this?',
        lastActivity: DateTime(2026, 8, 1, 12),
        unreadCount: 0,
        isDirect: true,
      ),
    ],
  );
  final session = FakeConversationSession(
    ConversationSnapshot(
      roomId: '!bob:test',
      title: 'Bob',
      canLoadOlder: false,
      isLoadingOlder: false,
      isDirect: true,
      typingUsers: const ['Asha'],
      pinnedEventIds: pinnedEventIds,
      canPin: canPin,
      messages: [
        if (withCallEntry)
          ChatMessage(
            eventId: r'$call',
            senderId: '@bob:test',
            senderName: 'Bob',
            body: '',
            // Recent on purpose: Call back is only offered while calling
            // back is a plausible next move.
            sentAt: DateTime.now().subtract(const Duration(minutes: 1)),
            isOwn: false,
            deliveryState: MessageDeliveryState.synced,
            isCallStart: true,
          ),
        ChatMessage(
          eventId: r'$own',
          senderId: '@current:test',
          senderName: 'You',
          body: 'Draft response',
          sentAt: DateTime(2026, 8, 1, 12, 2),
          isOwn: true,
          deliveryState: MessageDeliveryState.synced,
          isEdited: true,
          isRead: true,
          canDeleteForEveryone: true,
          replyTo: const MessageReplyPreview(
            eventId: r'$bob',
            senderName: 'Bob',
            body: 'Can you review this?',
          ),
        ),
        if (withEarlierCall)
          ChatMessage(
            eventId: r'$oldcall',
            senderId: '@current:test',
            senderName: 'You',
            body: '',
            sentAt: DateTime(2026, 8, 1, 11),
            isOwn: true,
            deliveryState: MessageDeliveryState.synced,
            isCallStart: true,
          ),
        ChatMessage(
          eventId: r'$bob',
          senderId: '@bob:test',
          senderName: 'Bob',
          body: 'Can you review this?',
          sentAt: DateTime(2026, 8, 1, 12),
          isOwn: false,
          deliveryState: MessageDeliveryState.synced,
          reactions: const [
            MessageReaction(key: '👍', count: 2, reactedByMe: true),
          ],
        ),
      ],
    ),
  );
  final messageRepository = FakeMessageRepository({'!bob:test': session});
  final authRepository = FakeAuthRepository(
    session: const AuthSession(userId: '@current:test'),
  );
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': true,
    // A returning user has already accepted the community rules; these tests
    // exercise message actions, not the guideline 1.2 gate.
    'content_agreement_version': AppPreferences.contentAgreementVersion,
  });
  final preferences = await SharedPreferences.getInstance();
  addTearDown(authRepository.dispose);
  addTearDown(chatRepository.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => authRepository),
        chatRepositoryProvider.overrideWith((ref) async => chatRepository),
        userRepositoryProvider.overrideWith(
          (ref) async => FakeUserRepository(),
        ),
        messageRepositoryProvider.overrideWith(
          (ref) async => messageRepository,
        ),
        messagingStatusProvider.overrideWith(
          (ref) => Stream.value(MessagingConnectionState.online),
        ),
        // Overridden rather than left to the real repository, which would
        // reach for a Matrix client this test has no use for.
        liveCallsProvider.overrideWith((ref) => Stream.value(liveCalls)),
      ],
      child: const DigitalgrubChatApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Bob'));
  await tester.pumpAndSettle();
  return session;
}
