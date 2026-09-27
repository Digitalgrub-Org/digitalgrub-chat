import 'package:dg_chat/app/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('initialLocationForUri', () {
    test('a meeting link boots into the meeting, not the splash', () {
      // The bug this guards: the meeting code travels in the path, routing
      // lives in the fragment, and booting through splash threw the address
      // away — every invitee landed in the chat list instead of the call.
      expect(
        initialLocationForUri(
          Uri.parse('https://chat.example.com/meet/abc-defg-hij'),
        ),
        '/meet/abc-defg-hij',
      );
    });

    test('a room-id meeting link still resolves', () {
      expect(
        initialLocationForUri(
          Uri.parse('https://chat.example.com/meet/%21abc%3Achat.example.com'),
        ),
        '/meet/${Uri.encodeComponent('!abc:chat.example.com')}',
      );
    });

    test('everything else boots through splash as before', () {
      for (final url in [
        'https://chat.example.com/',
        'https://chat.example.com/index.html',
        'https://chat.example.com/#/chats',
        'https://chat.example.com/meet',
        'https://chat.example.com/meet/a/b',
        'https://chat.example.com/dl/x/app.apk',
      ]) {
        expect(initialLocationForUri(Uri.parse(url)), '/splash', reason: url);
      }
    });
  });
}
