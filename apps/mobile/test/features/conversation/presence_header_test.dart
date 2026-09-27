import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/core/presence.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/conversation/presentation/conversation_screen.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool isDirect,
  UserPresence? presence,
}) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_complete': true,
    'content_agreement_version': AppPreferences.contentAgreementVersion,
  });
  final preferences = await SharedPreferences.getInstance();
  final auth = FakeAuthRepository(
    session: const AuthSession(userId: '@current:test'),
  );
  final chats = FakeChatRepository(chats: const []);
  addTearDown(auth.dispose);
  addTearDown(chats.dispose);
  final messages = FakeMessageRepository({
    '!room:test': FakeConversationSession(
      ConversationSnapshot(
        roomId: '!room:test',
        title: 'Maya',
        messages: const [],
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: isDirect,
        partnerPresence: presence,
      ),
    ),
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => auth),
        chatRepositoryProvider.overrideWith((ref) async => chats),
        messageRepositoryProvider.overrideWith((ref) async => messages),
        messagingStatusProvider.overrideWith(
          (ref) => Stream.value(MessagingConnectionState.online),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationScreen(roomId: '!room:test'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a direct chat says when the other person is online', (
    tester,
  ) async {
    await _pump(
      tester,
      isDirect: true,
      presence: const UserPresence(online: true),
    );
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('or when they were last around', (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await _pump(
      tester,
      isDirect: true,
      presence: UserPresence(online: false, lastActive: yesterday),
    );
    expect(find.textContaining('Last seen '), findsOneWidget);
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('somebody the server never saw gets no line at all', (
    tester,
  ) async {
    // More honest than "last seen never".
    await _pump(
      tester,
      isDirect: true,
      presence: const UserPresence(online: false),
    );
    expect(find.textContaining('Last seen'), findsNothing);
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('a group shows no presence', (tester) async {
    await _pump(
      tester,
      isDirect: false,
      presence: const UserPresence(online: true),
    );
    expect(find.text('Online'), findsNothing);
  });
}
