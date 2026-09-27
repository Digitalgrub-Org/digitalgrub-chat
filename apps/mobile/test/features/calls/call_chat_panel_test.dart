import 'dart:async';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/call_screen.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
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

const _room = '!team:test';

class _FakeController implements CallController {
  @override
  Stream<CallSnapshot> get changes async* {
    yield current;
  }

  @override
  CallSnapshot get current => CallSnapshot(
    roomId: _room,
    state: CallConnectionState.connected,
    participants: const [],
    micEnabled: true,
    cameraEnabled: false,
    startedAt: DateTime(2026, 9, 7, 10),
  );

  @override
  Future<void> hangUp() async {}
  @override
  Future<void> setCameraEnabled(bool enabled) async {}
  @override
  Future<void> setMicEnabled(bool enabled) async {}
  @override
  Future<void> setSpeakerphone(bool enabled) async {}
  @override
  Future<void> setScreenShareEnabled(bool enabled) async {}
  @override
  Stream<CallReaction> get reactions => const Stream.empty();
  @override
  Future<void> sendReaction(String emoji) async {}
  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> setHandRaised(bool raised) async {}

  @override
  Future<void> requestMute({String? participantId}) async {}
}

class _FakeCallRepository implements CallRepository {
  @override
  Future<CallController> startOrJoin(
    String roomId, {
    required bool withVideo,
    required bool ring,
  }) async => _FakeController();

  @override
  Future<CallController> joinMeetingAsGuest(
    String target, {
    required String displayName,
    required bool withVideo,
  }) async => _FakeController();

  @override
  Stream<IncomingCallRing> get incomingRings => const Stream.empty();
  @override
  Stream<List<LiveCall>> get liveCalls => const Stream.empty();
}

/// Pumps the call screen with enough of the app underneath it for the chat
/// panel -- which is the real conversation screen -- to come up.
Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  int unread = 0,
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': true,
    'content_agreement_version': AppPreferences.contentAgreementVersion,
  });
  final preferences = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository(
    session: const AuthSession(userId: '@current:test'),
  );
  final chats = FakeChatRepository(
    chats: [
      ChatSummary(
        roomId: _room,
        name: 'Team',
        lastMessage: 'Can you hear me?',
        lastActivity: DateTime(2026, 9, 7, 10),
        unreadCount: unread,
        isDirect: false,
      ),
    ],
  );
  final messages = FakeMessageRepository({
    _room: FakeConversationSession(
      ConversationSnapshot(
        roomId: _room,
        title: 'Team',
        messages: [
          ChatMessage(
            eventId: r'$hear',
            senderId: '@maya:test',
            senderName: 'Maya',
            body: 'Can you hear me?',
            sentAt: DateTime(2026, 9, 7, 10),
            isOwn: false,
            deliveryState: MessageDeliveryState.synced,
          ),
        ],
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: false,
      ),
    ),
  });
  addTearDown(auth.dispose);
  addTearDown(chats.dispose);

  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => auth),
        chatRepositoryProvider.overrideWith((ref) async => chats),
        messageRepositoryProvider.overrideWith((ref) async => messages),
        callRepositoryProvider.overrideWith(
          (ref) async => _FakeCallRepository(),
        ),
        messagingStatusProvider.overrideWith(
          (ref) => Stream.value(MessagingConnectionState.online),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox(),
      ),
    ),
  );
  unawaited(
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => screen),
    ),
  );
  await _settle(tester);
}

/// The call screen redraws its clock every second, so the tree never goes
/// quiet enough for pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _member = CallScreen(roomId: _room, withVideo: false, ring: false);

void main() {
  testWidgets('a member gets a chat button', (tester) async {
    await _pump(tester, screen: _member);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
  });

  testWidgets('a guest does not', (tester) async {
    // No account, so no room to read. Absent rather than disabled: a button
    // that can only ever say no is noise.
    await _pump(
      tester,
      screen: const CallScreen(
        roomId: 'abc-defg-hij',
        withVideo: false,
        ring: false,
        guestName: 'Asha',
      ),
    );
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
  });

  testWidgets('opening the panel shows the room, in the call', (tester) async {
    // The thing that was missing. The message is readable, and the call's own
    // controls are still there underneath -- you can mute while reading.
    await _pump(tester, screen: _member);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await _settle(tester);

    expect(find.text('Can you hear me?'), findsOneWidget);
    expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
    // By tooltip, not icon: the panel's composer carries a microphone of its
    // own for voice messages, and that one is not the mute control.
    expect(find.byTooltip('Mute'), findsOneWidget);
  });

  testWidgets('the panel has no call buttons of its own', (tester) async {
    // You are already in the call. A "start call" button inside it would
    // ring the same room from inside the ring.
    await _pump(tester, screen: _member);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await _settle(tester);
    expect(find.byIcon(Icons.call_rounded), findsNothing);
  });

  testWidgets('the panel closes from its own corner', (tester) async {
    await _pump(tester, screen: _member);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await _settle(tester);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await _settle(tester);
    expect(find.text('Can you hear me?'), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
  });

  testWidgets('unread messages put a dot on the button', (tester) async {
    await _pump(tester, screen: _member, unread: 3);
    expect(find.byKey(const ValueKey('call-control-badge')), findsOneWidget);
  });

  testWidgets('no unread, no dot', (tester) async {
    await _pump(tester, screen: _member);
    expect(find.byKey(const ValueKey('call-control-badge')), findsNothing);
  });

  testWidgets('a wide window keeps the video beside the chat', (tester) async {
    // Meet's layout: a shared screen and the chat about it both in view.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(tester, screen: _member);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await _settle(tester);

    expect(find.text('Can you hear me?'), findsOneWidget);
    // The grid's empty-state text is the video area; still on screen.
    expect(find.text('Waiting for others to join…'), findsOneWidget);
  });

  testWidgets('a phone gives the chat the video area', (tester) async {
    // Default test surface is phone-sized. The controls stay; the grid goes.
    await _pump(tester, screen: _member);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await _settle(tester);

    expect(find.text('Can you hear me?'), findsOneWidget);
    expect(find.text('Waiting for others to join…'), findsNothing);
    expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
  });
}
