import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('online draws the dot', (tester) async {
    await tester.pumpWidget(
      _host(const ProfileAvatar(label: 'Maya', online: true)),
    );
    expect(find.byKey(const ValueKey('presence-dot')), findsOneWidget);
  });

  testWidgets('offline draws nothing, not a grey dot', (tester) async {
    // Offline is most people most of the time; a grey dot on every row is a
    // page of noise saying nothing.
    await tester.pumpWidget(
      _host(const ProfileAvatar(label: 'Maya', online: false)),
    );
    expect(find.byKey(const ValueKey('presence-dot')), findsNothing);
  });

  testWidgets('a group has no presence at all', (tester) async {
    await tester.pumpWidget(_host(const ProfileAvatar(label: 'Team')));
    expect(find.byKey(const ValueKey('presence-dot')), findsNothing);
  });
}
