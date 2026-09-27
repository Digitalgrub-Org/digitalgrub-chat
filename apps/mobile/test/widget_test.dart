import 'package:dg_chat/app/app.dart';
import 'package:dg_chat/core/storage/app_preferences.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_auth_repository.dart';

void main() {
  testWidgets('completes onboarding and remembers it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final authRepository = FakeAuthRepository();
    addTearDown(authRepository.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authRepositoryProvider.overrideWith((ref) async => authRepository),
        ],
        child: const DigitalgrubChatApp(),
      ),
    );

    expect(find.text('Digitalgrub Chat'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('Fast, focused conversations'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(preferences.getBool('onboarding_complete'), isTrue);
  });
}
