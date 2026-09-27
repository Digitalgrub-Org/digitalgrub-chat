import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/features/admin/application/admin_providers.dart';
import 'package:dg_chat/features/admin/domain/admin_repository.dart';
import 'package:dg_chat/features/admin/presentation/user_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:dg_chat/core/config/app_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/test_app_config.dart';

class _FakeAdmin implements AdminRepository {
  final created = <(String, String, String?)>[];
  final resets = <(String, String)>[];
  AdminFailure? failure;

  @override
  Future<String> createUser({
    required String username,
    required String password,
    String? displayName,
  }) async {
    if (failure != null) throw failure!;
    created.add((username, password, displayName));
    return '@$username:test';
  }

  @override
  Future<void> resetPassword({
    required String username,
    required String password,
  }) async {
    if (failure != null) throw failure!;
    resets.add((username, password));
  }

  @override
  Future<bool> isSelfAdmin() async => true;
}

Future<_FakeAdmin> _pump(WidgetTester tester) async {
  final admin = _FakeAdmin();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverUsersProvider.overrideWith(
          (ref) async => const [
            UserSearchResult(userId: '@sara:test', displayName: 'Sara'),
          ],
        ),
        adminRepositoryProvider.overrideWith((ref) async => admin),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UserManagementScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return admin;
}

void main() {
  testWidgets('creating a user goes through the dialog', (tester) async {
    final admin = await _pump(tester);
    await tester.tap(find.text('New user'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Priya');
    await tester.enterText(fields.at(1), 'Priya R');
    await tester.enterText(fields.at(2), 'longpass');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(admin.created, [('priya', 'longpass', 'Priya R')]);
    expect(find.text('Account created: @priya:test'), findsOneWidget);
  });

  testWidgets('a bad username never leaves the dialog', (tester) async {
    final admin = await _pump(tester);
    await tester.tap(find.text('New user'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Has Space');
    await tester.enterText(fields.at(2), 'longpass');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(admin.created, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('resetting a password from the row menu', (tester) async {
    final admin = await _pump(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset password').last);
    await tester.pumpAndSettle();

    expect(find.text('Reset password for Sara'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'newlongpass');
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pumpAndSettle();

    expect(admin.resets, [('@sara:test', 'newlongpass')]);
    expect(
      find.text('Password reset. Their sessions were signed out.'),
      findsOneWidget,
    );
  });

  testWidgets('an admin target says where to go instead', (tester) async {
    final admin = await _pump(tester);
    admin.failure = const AdminFailure(AdminFailureCode.adminAccount);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset password').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'newlongpass');
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pumpAndSettle();
    expect(
      find.text('Admin accounts are reset on the server, not from here.'),
      findsOneWidget,
    );
  });
}
