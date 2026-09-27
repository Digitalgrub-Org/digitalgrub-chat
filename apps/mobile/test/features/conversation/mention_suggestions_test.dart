import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/conversation/presentation/mention_suggestions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _at(String text, {int? caret}) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);

void main() {
  group('MentionQuery', () {
    test('finds the mention being typed at the caret', () {
      final query = MentionQuery.of(_at('hey @haf'));
      expect(query, isNotNull);
      expect(query!.query, 'haf');
      expect(query.start, 4);
    });

    test('an @ on its own opens the picker with everyone', () {
      expect(MentionQuery.of(_at('@'))?.query, '');
    });

    test('ignores an @ inside a word, which is an address not a mention', () {
      expect(MentionQuery.of(_at('mail me at sara@example.com')), isNull);
    });

    test('only the token the caret sits in counts', () {
      // Caret is at the end, well past the earlier mention: the picker must
      // not reopen for a name that was already chosen.
      expect(MentionQuery.of(_at('@Kavita thanks for that')), isNull);
    });

    test('gives up once the text is clearly no longer a name', () {
      expect(MentionQuery.of(_at('@one two three')), isNull);
    });

    test('a newline closes it', () {
      expect(MentionQuery.of(_at('@haf\nnext line')), isNull);
    });

    test('stops at a bracket the picker itself inserted', () {
      expect(MentionQuery.of(_at('@[Kavita Rajesh] ')), isNull);
    });

    test('a selection rather than a caret does not open it', () {
      expect(
        MentionQuery.of(
          const TextEditingValue(
            text: 'hey @haf',
            selection: TextSelection(baseOffset: 4, extentOffset: 8),
          ),
        ),
        isNull,
      );
    });
  });

  group('applyMention', () {
    const candidate = MentionCandidate(
      userId: '@kavita:chat.example.com',
      displayName: 'Kavita',
      insertText: '@Kavita',
    );

    test('replaces the typed token and leaves a trailing space', () {
      final result = applyMention(
        _at('hey @haf'),
        MentionQuery.of(_at('hey @haf'))!,
        candidate,
      );
      expect(result.text, 'hey @Kavita ');
      expect(result.selection.baseOffset, result.text.length);
    });

    test('keeps whatever follows the caret intact', () {
      const value = TextEditingValue(
        text: 'hey @haf can you look',
        selection: TextSelection.collapsed(offset: 8),
      );
      final result = applyMention(value, MentionQuery.of(value)!, candidate);
      expect(result.text, 'hey @Kavita  can you look');
      // Caret sits right after the inserted name, not at the end of the line.
      expect(result.selection.baseOffset, 12);
    });

    test('inserts the bracketed form for a name with a space', () {
      const twoWords = MentionCandidate(
        userId: '@kavita:chat.example.com',
        displayName: 'Kavita Rajesh',
        insertText: '@[Kavita Rajesh]',
      );
      final result = applyMention(
        _at('@haf'),
        MentionQuery.of(_at('@haf'))!,
        twoWords,
      );
      // The homeserver only resolves this exact shape back to a user id;
      // anything else pings nobody.
      expect(result.text, '@[Kavita Rajesh] ');
    });
  });
}
