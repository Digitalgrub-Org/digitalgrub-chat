import 'package:dg_chat/features/meetings/domain/meeting_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a bare code', () {
    expect(parseMeetingCode('abc-defg-hij'), 'abc-defg-hij');
    expect(parseMeetingCode('  ABC-DEFG-HIJ  '), 'abc-defg-hij');
  });

  test('the full link, however it was pasted', () {
    for (final link in [
      'https://chat.example.com/meet/abc-defg-hij',
      'https://chat.example.com/meet/abc-defg-hij/',
      'https://chat.example.com/meet/abc-defg-hij?from=mail',
      'chat.example.com/meet/abc-defg-hij',
    ]) {
      expect(parseMeetingCode(link), 'abc-defg-hij', reason: link);
    }
  });

  test('the whole invitation email, link somewhere inside', () {
    expect(
      parseMeetingCode(
        'Join my meeting on Digitalgrub Chat:\n\n'
        'https://chat.example.com/meet/abc-defg-hij\n\n'
        'Open the link and sign in.',
      ),
      'abc-defg-hij',
    );
  });

  test('not a code', () {
    for (final junk in [
      '',
      'hello',
      'abc-defg',
      '123-4567-890',
      'https://example.com/x',
    ]) {
      expect(parseMeetingCode(junk), isNull, reason: junk);
    }
  });
}
