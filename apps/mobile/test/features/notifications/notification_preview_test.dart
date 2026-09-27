import 'package:dg_chat/features/notifications/domain/notification_preview.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _event(
  Map<String, Object?> content, {
  String type = 'm.room.message',
  String sender = '@asha:test',
}) => {'type': type, 'sender': sender, 'content': content};

void main() {
  group('notificationPreviewOf', () {
    test('reads a text message', () {
      final preview = notificationPreviewOf(
        _event({'msgtype': 'm.text', 'body': 'are you coming?'}),
      );

      expect(preview, isNotNull);
      expect(preview!.senderId, '@asha:test');
      expect(preview.kind, NotificationPreviewKind.text);
      expect(preview.text, 'are you coming?');
    });

    test('reads a notice, and a type it has never heard of, as text', () {
      for (final msgtype in ['m.notice', 'org.example.custom']) {
        final preview = notificationPreviewOf(
          _event({'msgtype': msgtype, 'body': 'hello'}),
        );
        expect(preview?.kind, NotificationPreviewKind.text, reason: msgtype);
        expect(preview?.text, 'hello', reason: msgtype);
      }
    });

    test('keeps an emote an emote', () {
      final preview = notificationPreviewOf(
        _event({'msgtype': 'm.emote', 'body': 'waves'}),
      );
      expect(preview?.kind, NotificationPreviewKind.emote);
      expect(preview?.text, 'waves');
    });

    test('names an attachment by its kind, never by its filename', () {
      const kinds = {
        'm.image': NotificationPreviewKind.image,
        'm.video': NotificationPreviewKind.video,
        'm.audio': NotificationPreviewKind.audio,
        'm.file': NotificationPreviewKind.file,
      };
      for (final MapEntry(key: msgtype, value: kind) in kinds.entries) {
        final preview = notificationPreviewOf(
          _event({'msgtype': msgtype, 'body': 'IMG_0421.HEIC'}),
        );
        expect(preview?.kind, kind, reason: msgtype);
        expect(preview?.text, isEmpty, reason: msgtype);
      }
    });

    test('tells a voice note from an audio file', () {
      final preview = notificationPreviewOf(
        _event({
          'msgtype': 'm.audio',
          'body': 'Voice message.m4a',
          'org.matrix.msc3245.voice': <String, Object?>{},
        }),
      );
      expect(preview?.kind, NotificationPreviewKind.voice);
    });

    test('shows the corrected text of an edit, not its fallback', () {
      final preview = notificationPreviewOf(
        _event({
          'msgtype': 'm.text',
          'body': '* see you at 6',
          'm.new_content': {'msgtype': 'm.text', 'body': 'see you at 6'},
          'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$original'},
        }),
      );
      expect(preview?.text, 'see you at 6');
    });

    test('drops the quoted original from a reply', () {
      final preview = notificationPreviewOf(
        _event({
          'msgtype': 'm.text',
          'body': '> <@bala:test> are you coming?\n> tonight\n\nyes',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': r'$question'},
          },
        }),
      );
      expect(preview?.text, 'yes');
    });

    test('leaves a quote alone in a message that is not a reply', () {
      final preview = notificationPreviewOf(
        _event({'msgtype': 'm.text', 'body': '> a line worth quoting'}),
      );
      expect(preview?.text, '> a line worth quoting');
    });

    test('gives nothing for a reply that is all quote', () {
      final preview = notificationPreviewOf(
        _event({
          'msgtype': 'm.text',
          'body': '> <@bala:test> are you coming?\n\n',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': r'$question'},
          },
        }),
      );
      expect(preview, isNull);
    });

    test('gives nothing for a deleted message', () {
      // Redaction keeps the type and empties the content.
      expect(notificationPreviewOf(_event(const {})), isNull);
    });

    test('gives nothing for events that are not messages', () {
      for (final type in [
        'm.room.member',
        'm.reaction',
        'm.room.encrypted',
        'm.call.invite',
      ]) {
        expect(
          notificationPreviewOf(
            _event({'msgtype': 'm.text', 'body': 'x'}, type: type),
          ),
          isNull,
          reason: type,
        );
      }
    });

    test('gives nothing without a sender to name', () {
      expect(
        notificationPreviewOf(
          _event({'msgtype': 'm.text', 'body': 'hi'}, sender: ''),
        ),
        isNull,
      );
    });

    test('cuts a very long message', () {
      final preview = notificationPreviewOf(
        _event({'msgtype': 'm.text', 'body': 'a' * 5000}),
      );
      expect(preview!.text.length, notificationPreviewMaxLength + 1);
      expect(preview.text, endsWith('…'));
    });

    test('never cuts a character in half', () {
      // Each of these is two UTF-16 units, so a cut by length would land
      // inside one and leave half an emoji on the screen.
      final preview = notificationPreviewOf(
        _event({'msgtype': 'm.text', 'body': '😀' * 1000}),
      );
      final runes = preview!.text.runes.toList();
      expect(runes.length, notificationPreviewMaxLength + 1);
      expect(runes.where((r) => r >= 0xD800 && r <= 0xDFFF), isEmpty);
    });
  });

  group('stripReplyFallback', () {
    test('removes the quoted lines and the blank line after them', () {
      expect(stripReplyFallback('> quoted\n> more\n\nreply'), 'reply');
    });

    test('keeps every line of a multi-line reply', () {
      expect(stripReplyFallback('> quoted\n\nfirst\nsecond'), 'first\nsecond');
    });

    test('leaves a body with no quote untouched', () {
      expect(stripReplyFallback('plain\ntext'), 'plain\ntext');
    });
  });
}
