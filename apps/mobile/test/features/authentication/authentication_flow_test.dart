import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/app/theme/theme_controller.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  testWidgets('restores an authenticated session into the chat shell', (
    tester,
  ) async {
    final repository = FakeAuthRepository(
      session: const AuthSession(userId: '@alice:test'),
    );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('submits username and password then opens chats', (tester) async {
    final repository = FakeAuthRepository();
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'alice');
    await tester.enterText(fields.at(1), 'ValidPassword1');
    await _agreeToRules(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(repository.lastUsername, 'alice');
    expect(repository.lastPassword, 'ValidPassword1');
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('maps registration fields to the repository request', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Create account'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Alice Example');
    await tester.enterText(fields.at(1), 'alice');
    await tester.enterText(fields.at(2), 'ValidPassword1');
    await tester.enterText(fields.at(3), '+919876543210');
    await tester.enterText(fields.at(4), 'TEAM-2026');
    await _agreeToRules(tester);
    final submit = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(repository.lastRegistration?.displayName, 'Alice Example');
    expect(repository.lastRegistration?.username, 'alice');
    expect(repository.lastRegistration?.password, 'ValidPassword1');
    expect(repository.lastRegistration?.mobileNumber, '+919876543210');
    // The server is invite-only; a sign-up that dropped the code on the way
    // to the repository would fail at the homeserver, not here.
    expect(repository.lastRegistration?.inviteCode, 'TEAM-2026');
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  group('the community rules, before signing in', () {
    testWidgets('will not sign in until they are agreed to', (tester) async {
      final repository = FakeAuthRepository();
      addTearDown(repository.dispose);
      await _pumpApp(tester, repository);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'alice');
      await tester.enterText(fields.at(1), 'ValidPassword1');
      await tester.pump();

      final button = find.widgetWithText(FilledButton, 'Sign in');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(button);
      await tester.pumpAndSettle();

      // Nothing was sent, and the sign-in screen is still the one on show.
      expect(repository.lastUsername, isNull);
      expect(find.text('I agree to the community rules'), findsOneWidget);
    });

    testWidgets('are readable from the sign-in screen, and agreeing there '
        'ticks the box', (tester) async {
      final repository = FakeAuthRepository();
      addTearDown(repository.dispose);
      await _pumpApp(tester, repository);

      await tester.tap(find.text('Read the community rules'));
      await tester.pumpAndSettle();

      // The rules themselves, including the line App Review asks for.
      expect(find.text('Our community rules'), findsOneWidget);
      expect(find.textContaining('no tolerance for abusive'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'I agree'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('are not asked for again once someone is signed in', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'onboarding_complete': true});
      final preferences = await SharedPreferences.getInstance();
      final repository = FakeAuthRepository();
      addTearDown(repository.dispose);
      await _pumpApp(tester, repository, preferences: preferences);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'alice');
      await tester.enterText(fields.at(1), 'ValidPassword1');
      await _agreeToRules(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      // What the composer checks before a first message.
      expect(AppPreferences(preferences).hasAcceptedContentAgreement, isTrue);
    });
  });

  testWidgets('routes an expired authenticated session back to login', (
    tester,
  ) async {
    final repository = FakeAuthRepository(
      session: const AuthSession(userId: '@alice:test'),
    );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    repository.emitSession(null);
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('confirms logout and clears the current session', (tester) async {
    final repository = FakeAuthRepository(
      session: const AuthSession(userId: '@alice:test'),
    );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(repository.logoutCount, 1);
    expect(repository.session, isNull);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('switches and persists the selected appearance', (tester) async {
    final repository = FakeAuthRepository(
      session: const AuthSession(userId: '@alice:test'),
    );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      ).read(appThemeSettingProvider),
      AppThemeSetting.dark,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('theme_mode'), 'dark');
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  FakeAuthRepository repository, {

  /// Passed in by a test that reads it back afterwards.
  SharedPreferences? preferences,
}) async {
  if (preferences == null) {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
  }
  preferences ??= await SharedPreferences.getInstance();
  final chatRepository = FakeChatRepository();
  addTearDown(chatRepository.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        authRepositoryProvider.overrideWith((ref) async => repository),
        chatRepositoryProvider.overrideWith((ref) async => chatRepository),
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

/// Ticks the rules box that gates signing in and registering.
Future<void> _agreeToRules(WidgetTester tester) async {
  final consent = find.byType(CheckboxListTile);
  await tester.ensureVisible(consent);
  await tester.tap(consent);
  await tester.pump();
}
