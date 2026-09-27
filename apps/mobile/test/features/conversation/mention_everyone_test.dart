import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/conversation/presentation/mention_suggestions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _everyone = MentionCandidate(
  userId: roomMentionId,
  displayName: 'Everyone',
  insertText: roomMentionId,
);

const _person = MentionCandidate(
  userId: '@maya:test',
  displayName: 'Maya',
  insertText: '@Maya',
);

Future<void> _pump(
  WidgetTester tester,
  List<MentionCandidate> candidates, {
  ValueChanged<MentionCandidate>? onSelected,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MentionSuggestions(
        candidates: candidates,
        onSelected: onSelected ?? (_) {},
      ),
    ),
  ),
);

void main() {
  test('the room mention is recognised by its sentinel id', () {
    expect(_everyone.isRoomMention, isTrue);
    expect(_person.isRoomMention, isFalse);
  });

  test('choosing Everyone inserts the token the spec defines', () {
    // `@room` is what the SDK converts into m.mentions {room: true}. Insert
    // anything else and the message merely contains a word.
    const value = TextEditingValue(
      text: 'morning @ev',
      selection: TextSelection.collapsed(offset: 11),
    );
    final query = MentionQuery.of(value)!;
    final applied = applyMention(value, query, _everyone);
    expect(applied.text, 'morning @room ');
    expect(applied.selection.baseOffset, applied.text.length);
  });

  testWidgets('Everyone says what it does, not a user id', (tester) async {
    // "@room" in the subtitle would be a wire detail nobody can act on, and
    // it reads like an account that could be looked up. The row says what
    // pressing it will actually cause.
    await _pump(tester, const [_everyone, _person]);

    expect(find.text('Everyone'), findsOneWidget);
    expect(find.text('Notifies everyone in this group'), findsOneWidget);
    expect(find.text(roomMentionId), findsNothing);
    // A person still shows their id, which is how you tell two Mayas apart.
    expect(find.text('@maya:test'), findsOneWidget);
  });

  testWidgets('Everyone is an announcement, not an initial', (tester) async {
    await _pump(tester, const [_everyone, _person]);

    expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);
    // Maya still gets her initial; the icon belongs only to the room mention.
    expect(find.text('M'), findsOneWidget);
  });

  test('a message carries who has read it, never yourself', () {
    // The repository excludes the signed-in user, so an empty list means
    // nobody else has got here yet -- not that receipts are missing.
    final unread = ChatMessage(
      eventId: 'e1',
      senderId: '@me:test',
      senderName: 'Me',
      body: 'hello',
      sentAt: DateTime(2026, 8, 27, 10),
      isOwn: true,
      deliveryState: MessageDeliveryState.sent,
    );
    expect(unread.readBy, isEmpty);

    final read = ChatMessage(
      eventId: 'e2',
      senderId: '@me:test',
      senderName: 'Me',
      body: 'hello',
      sentAt: DateTime(2026, 8, 27, 10, 1),
      isOwn: true,
      deliveryState: MessageDeliveryState.sent,
      isRead: true,
      readBy: const ['Maya', 'Arjun Rao'],
    );
    expect(read.readBy, ['Maya', 'Arjun Rao']);
  });

  testWidgets('picking Everyone reports the room candidate', (tester) async {
    MentionCandidate? picked;
    await _pump(tester, const [
      _everyone,
      _person,
    ], onSelected: (candidate) => picked = candidate);

    await tester.tap(find.text('Everyone'));
    await tester.pump();

    expect(picked?.isRoomMention, isTrue);
    expect(picked?.insertText, roomMentionId);
  });
}
