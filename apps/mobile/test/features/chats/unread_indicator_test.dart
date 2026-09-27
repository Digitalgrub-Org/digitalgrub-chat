import 'package:dg_chat/features/chats/domain/unread_tally.dart';
import 'package:dg_chat/features/chats/presentation/chat_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

/// Finds the plain dot: a circular Container with no text in it.
Finder _dot() => find.byWidgetPredicate((widget) {
  if (widget is! Container) return false;
  final decoration = widget.decoration;
  return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
});

void main() {
  group('the tab title', () {
    test('is the plain app name when nothing is unread', () {
      expect(
        titleForUnread('Digitalgrub Chat', UnreadTally.none),
        'Digitalgrub Chat',
      );
    });

    test('takes a dot for unread that does not mention you', () {
      // No number: the count would be noise, and a tab squeezed down to its
      // favicon cannot show one anyway.
      expect(
        titleForUnread(
          'Digitalgrub Chat',
          const UnreadTally(rooms: 4, highlights: 0),
        ),
        '• Digitalgrub Chat',
      );
    });

    test('takes a count when you were mentioned', () {
      expect(
        titleForUnread(
          'Digitalgrub Chat',
          const UnreadTally(rooms: 4, highlights: 3),
        ),
        '(3) Digitalgrub Chat',
      );
    });

    test('a mention outranks the dot', () {
      // Both are true at once in practice -- a mention is also unread. The
      // title has room for one mark, and it should be the louder one.
      final title = titleForUnread(
        'Chat',
        const UnreadTally(rooms: 9, highlights: 1),
      );
      expect(title, '(1) Chat');
      expect(title.contains('•'), isFalse);
    });

    test('caps a silly number of mentions', () {
      expect(
        titleForUnread('Chat', const UnreadTally(rooms: 2, highlights: 4000)),
        '(99+) Chat',
      );
    });
  });

  group('the chat row indicator', () {
    testWidgets('shows a dot for unread with no mention', (tester) async {
      await tester.pumpWidget(
        _host(const UnreadIndicator(unreadCount: 12, highlightCount: 0)),
      );
      expect(_dot(), findsOneWidget);
      // The point of the change: twelve routine messages must not shout the
      // way a mention does.
      expect(find.text('12'), findsNothing);
    });

    testWidgets('shows the count when you were mentioned', (tester) async {
      await tester.pumpWidget(
        _host(const UnreadIndicator(unreadCount: 12, highlightCount: 2)),
      );
      expect(find.text('2'), findsOneWidget);
      expect(_dot(), findsNothing);
    });

    testWidgets('counts mentions, not total unread', (tester) async {
      // The number answers "how many need me", not "how much arrived".
      await tester.pumpWidget(
        _host(const UnreadIndicator(unreadCount: 40, highlightCount: 1)),
      );
      expect(find.text('1'), findsOneWidget);
      expect(find.text('40'), findsNothing);
    });

    testWidgets('draws nothing when there is nothing', (tester) async {
      await tester.pumpWidget(
        _host(const UnreadIndicator(unreadCount: 0, highlightCount: 0)),
      );
      expect(_dot(), findsNothing);
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('caps a silly number of mentions', (tester) async {
      await tester.pumpWidget(
        _host(const UnreadIndicator(unreadCount: 500, highlightCount: 250)),
      );
      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('the tally', () {
    test('counts chats, not messages', () {
      // Someone pasting thirty lines into one chat is still one conversation
      // asking for attention.
      const tally = UnreadTally(rooms: 2, highlights: 0);
      expect(tally.rooms, 2);
      expect(tally.hasAnything, isTrue);
    });

    test('an empty tally is nothing at all', () {
      expect(UnreadTally.none.hasAnything, isFalse);
    });

    test('mentions alone still count as something', () {
      expect(const UnreadTally(rooms: 0, highlights: 1).hasAnything, isTrue);
    });

    test('compares by value, so a redraw can be skipped', () {
      expect(
        const UnreadTally(rooms: 1, highlights: 2),
        const UnreadTally(rooms: 1, highlights: 2),
      );
      expect(
        const UnreadTally(rooms: 1, highlights: 2),
        isNot(const UnreadTally(rooms: 1, highlights: 3)),
      );
    });
  });
}
