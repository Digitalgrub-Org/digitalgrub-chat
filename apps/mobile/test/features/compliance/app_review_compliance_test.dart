// Covers the two App Review requirements that apply to this app's shape:
// guideline 5.1.1(v) in-app account deletion, and guideline 1.2 agreement to
// the community rules before contributing user-generated content.
import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/moderation/presentation/content_agreement_sheet.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  group('account deletion', () {
    testWidgets('deletes the account after password confirmation', (
      tester,
    ) async {
      final auth = _auth();
      await _pumpApp(tester, auth: auth);
      await _openSettings(tester);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.textContaining('permanently deletes'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'CorrectPassword1');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(auth.deleteCount, 1);
      expect(auth.lastDeletePassword, 'CorrectPassword1');
      // Deleting the account must not merely sign out and stay put.
      expect(find.text('Your account has been deleted.'), findsOneWidget);
    });

    testWidgets('requires a password before deleting', (tester) async {
      final auth = _auth();
      await _pumpApp(tester, auth: auth);
      await _openSettings(tester);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('This field is required.'), findsOneWidget);
      expect(auth.deleteCount, 0);
    });

    testWidgets('keeps the account when cancelled', (tester) async {
      final auth = _auth();
      await _pumpApp(tester, auth: auth);
      await _openSettings(tester);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(auth.deleteCount, 0);
    });

    testWidgets('surfaces a wrong password without deleting', (tester) async {
      final auth = _auth()
        ..deleteFailure = const AuthFailure(AuthFailureCode.invalidCredentials);
      await _pumpApp(tester, auth: auth);
      await _openSettings(tester);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'WrongPassword1');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text('The username or password is incorrect.'),
        findsOneWidget,
      );
      expect(auth.deleteCount, 0);
      // The dialog stays open so the user can retry.
      expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
    });
  });

  group('content agreement', () {
    testWidgets('is required before a first message can be sent', (
      tester,
    ) async {
      final session = _session();
      await _pumpApp(tester, session: session, agreementAccepted: false);
      await _openConversation(tester);

      await tester.enterText(find.byType(TextField), 'Hello');
      // The composer enables its send button on the frame after the text
      // changes, so the tap needs that frame to have been rendered.
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();

      expect(find.text('Our community rules'), findsOneWidget);
      expect(session.sentTexts, isEmpty);
    });

    testWidgets('sends once the rules are accepted', (tester) async {
      final session = _session();
      await _pumpApp(tester, session: session, agreementAccepted: false);
      await _openConversation(tester);

      await tester.enterText(find.byType(TextField), 'Hello');
      // The composer enables its send button on the frame after the text
      // changes, so the tap needs that frame to have been rendered.
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'I agree'));
      await tester.pumpAndSettle();

      expect(session.sentTexts, ['Hello']);
    });

    testWidgets('blocks sending when the rules are declined', (tester) async {
      final session = _session();
      await _pumpApp(tester, session: session, agreementAccepted: false);
      await _openConversation(tester);

      await tester.enterText(find.byType(TextField), 'Hello');
      // The composer enables its send button on the frame after the text
      // changes, so the tap needs that frame to have been rendered.
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Not now'));
      await tester.pumpAndSettle();

      expect(session.sentTexts, isEmpty);
      expect(find.textContaining('accept the community rules'), findsOneWidget);
    });

    testWidgets('shows the published moderation contact', (tester) async {
      await _pumpApp(tester, agreementAccepted: false);
      await _openConversation(tester);

      await tester.enterText(find.byType(TextField), 'Hello');
      // The composer enables its send button on the frame after the text
      // changes, so the tap needs that frame to have been rendered.
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();

      expect(find.textContaining(moderationContactEmail), findsOneWidget);
    });

    testWidgets('is not shown again to a user who accepted', (tester) async {
      final session = _session();
      await _pumpApp(tester, session: session, agreementAccepted: true);
      await _openConversation(tester);

      await tester.enterText(find.byType(TextField), 'Hello');
      // The composer enables its send button on the frame after the text
      // changes, so the tap needs that frame to have been rendered.
      await tester.pump();
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();

      expect(find.text('Our community rules'), findsNothing);
      expect(session.sentTexts, ['Hello']);
    });
  });
}

FakeAuthRepository _auth() =>
    FakeAuthRepository(session: const AuthSession(userId: '@current:test'));

FakeConversationSession _session() => FakeConversationSession(
  ConversationSnapshot(
    roomId: '!room:test',
    title: 'Asha Menon',
    messages: const [],
    canLoadOlder: false,
    isLoadingOlder: false,
    isDirect: true,
  ),
);

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

Future<void> _openConversation(WidgetTester tester) async {
  await tester.tap(find.text('Asha Menon'));
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(
  WidgetTester tester, {
  FakeAuthRepository? auth,
  FakeConversationSession? session,
  bool agreementAccepted = true,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({
    'onboarding_complete': true,
    if (agreementAccepted)
      'content_agreement_version': AppPreferences.contentAgreementVersion,
  });
  final preferences = await SharedPreferences.getInstance();
  final authRepository = auth ?? _auth();
  final chats = FakeChatRepository(
    chats: [
      ChatSummary(
        roomId: '!room:test',
        name: 'Asha Menon',
        lastMessage: 'Hi',
        lastActivity: DateTime(2026, 8, 1, 11, 22),
        unreadCount: 0,
        isDirect: true,
      ),
    ],
  );
  final messages = FakeMessageRepository({'!room:test': session ?? _session()});

  addTearDown(authRepository.dispose);
  addTearDown(chats.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => authRepository),
        chatRepositoryProvider.overrideWith((ref) async => chats),
        messageRepositoryProvider.overrideWith((ref) async => messages),
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
