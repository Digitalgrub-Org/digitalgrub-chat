import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/authentication/presentation/password_reset_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';

import '../../helpers/fake_auth_repository.dart';

Future<void> _pump(WidgetTester tester, FakeAuthRepository auth) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWith((ref) async => auth)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PasswordResetScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the email step', () {
    testWidgets('refuses an address that is not one', (tester) async {
      final auth = FakeAuthRepository();
      await _pump(tester, auth);
      await tester.enterText(find.byType(TextFormField), 'not-an-address');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      // Nothing was asked of the server, so nobody was told whether that
      // string is registered.
      expect(auth.lastResetEmail, isNull);
    });

    testWidgets('sends for a real-looking address', (tester) async {
      final auth = FakeAuthRepository();
      await _pump(tester, auth);
      await tester.enterText(find.byType(TextFormField), 'maya@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(auth.lastResetEmail, 'maya@example.com');
      expect(find.text('Check your email'), findsOneWidget);
    });
  });

  group('an address nobody has registered', () {
    testWidgets('looks exactly like one that is', (tester) async {
      // The whole point. If an unknown address said so, this form would be a
      // way of asking the server who is registered on it -- a directory
      // nobody agreed to publish, readable by anyone with the sign-in page.
      final auth = FakeAuthRepository()
        ..resetRequestFailure = const AuthFailure(AuthFailureCode.emailUnknown);
      await _pump(tester, auth);
      await tester.enterText(find.byType(TextFormField), 'nobody@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(find.text('Check your email'), findsOneWidget);
    });

    testWidgets('cannot then be used to set a password', (tester) async {
      final auth = FakeAuthRepository()
        ..resetRequestFailure = const AuthFailure(AuthFailureCode.emailUnknown);
      await _pump(tester, auth);
      await tester.enterText(find.byType(TextFormField), 'nobody@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'longenoughpassword');
      await tester.enterText(fields.at(1), 'longenoughpassword');
      await tester.tap(find.text('Set new password'));
      await tester.pumpAndSettle();
      // No session was ever minted, so there is nothing to change -- and the
      // refusal reads the same as an unopened link.
      expect(auth.lastNewPassword, isNull);
    });
  });

  group('the password step', () {
    Future<void> reachIt(WidgetTester tester, FakeAuthRepository auth) async {
      await _pump(tester, auth);
      await tester.enterText(find.byType(TextFormField), 'maya@example.com');
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
    }

    testWidgets('refuses two passwords that differ', (tester) async {
      final auth = FakeAuthRepository();
      await reachIt(tester, auth);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'longenoughpassword');
      await tester.enterText(fields.at(1), 'somethingelse1234');
      await tester.tap(find.text('Set new password'));
      await tester.pumpAndSettle();
      expect(auth.lastNewPassword, isNull);
      expect(find.text('Those two passwords are different'), findsOneWidget);
    });

    testWidgets('refuses one that is too short', (tester) async {
      final auth = FakeAuthRepository();
      await reachIt(tester, auth);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'abc');
      await tester.enterText(fields.at(1), 'abc');
      await tester.tap(find.text('Set new password'));
      await tester.pumpAndSettle();
      expect(auth.lastNewPassword, isNull);
    });

    testWidgets('sets a good one', (tester) async {
      final auth = FakeAuthRepository();
      await reachIt(tester, auth);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'longenoughpassword');
      await tester.enterText(fields.at(1), 'longenoughpassword');
      await tester.tap(find.text('Set new password'));
      await tester.pumpAndSettle();
      expect(auth.lastNewPassword, 'longenoughpassword');
    });

    testWidgets('says to open the link when it has not been', (tester) async {
      // The ordinary case for somebody who pressed the button too early, so
      // it must say what to do rather than "something went wrong".
      final auth = FakeAuthRepository()
        ..resetCompleteFailure = const AuthFailure(
          AuthFailureCode.emailNotVerified,
        );
      await reachIt(tester, auth);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'longenoughpassword');
      await tester.enterText(fields.at(1), 'longenoughpassword');
      await tester.tap(find.text('Set new password'));
      await tester.pumpAndSettle();
      expect(
        find.text('Open the link in the email first, then try again.'),
        findsOneWidget,
      );
    });

    testWidgets('can send the mail again', (tester) async {
      final auth = FakeAuthRepository();
      await reachIt(tester, auth);
      await tester.tap(find.text('Send it again'));
      await tester.pumpAndSettle();
      expect(auth.resendCount, 1);
    });
  });
}
