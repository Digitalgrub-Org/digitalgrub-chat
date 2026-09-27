import 'dart:convert';

import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/features/calls/data/livekit_call_repository.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AppConfig _config({bool guests = true}) => AppConfig(
  homeserver: Uri.parse('https://chat.example.com'),
  meetGuestUrl: guests
      ? Uri.parse('https://chat.example.com/livekit/guest')
      : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trades a code and a name for a grant', () async {
    late Uri posted;
    late Map<String, Object?> body;
    final mock = MockClient((request) async {
      posted = request.url;
      body = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode({
          'url': 'wss://chat.example.com/livekit/sfu',
          'jwt': 'signed.jwt.here',
          'room_id': '!meeting:chat.example.com',
        }),
        200,
      );
    });

    final grant = await fetchGuestGrant(
      _config().meetGuestUrl,
      mock,
      'brj-hqmr-cph',
      displayName: 'Asha',
    );

    expect(posted.toString(), 'https://chat.example.com/livekit/guest/token');
    // No Matrix credentials on the wire: a guest has none to send.
    expect(body, {'code': 'brj-hqmr-cph', 'name': 'Asha'});
    expect(grant.jwt, 'signed.jwt.here');
    expect(grant.roomId, '!meeting:chat.example.com');
  });

  test('a code that is not a meeting reads as room not found', () async {
    await expectLater(
      fetchGuestGrant(
        _config().meetGuestUrl,
        MockClient((_) async => http.Response('{"error":"no"}', 404)),
        '!team:chat.example.com',
        displayName: 'X',
      ),
      throwsA(
        isA<CallFailure>().having(
          (f) => f.code,
          'code',
          CallFailureCode.roomNotFound,
        ),
      ),
    );
  });

  test('a broken service reads as server unavailable', () async {
    await expectLater(
      fetchGuestGrant(
        _config().meetGuestUrl,
        MockClient((_) async => http.Response('nope', 500)),
        'abc-defg-hij',
        displayName: 'X',
      ),
      throwsA(
        isA<CallFailure>().having(
          (f) => f.code,
          'code',
          CallFailureCode.serverUnavailable,
        ),
      ),
    );
  });

  test('guests switched off reads as not configured', () async {
    await expectLater(
      fetchGuestGrant(
        _config(guests: false).meetGuestUrl,
        MockClient((_) async => http.Response('', 200)),
        'abc-defg-hij',
        displayName: 'X',
      ),
      throwsA(
        isA<CallFailure>().having(
          (f) => f.code,
          'code',
          CallFailureCode.notConfigured,
        ),
      ),
    );
  });
}
