import 'dart:convert';

import 'package:dg_chat/app/localization/generated/app_localizations.dart';
import 'package:dg_chat/features/notifications/data/matrix_notification_describer.dart';
import 'package:dg_chat/features/notifications/domain/push_notification.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _roomId = '!room:test';
const _eventId = r'$event';

/// A homeserver that knows one event, one member and maybe a room name.
class _Homeserver {
  _Homeserver({
    this.event = const {
      'type': 'm.room.message',
      'sender': '@asha:test',
      'content': {'msgtype': 'm.text', 'body': 'are you coming?'},
    },
    this.displayName = 'Asha Menon',
    this.roomName,
    this.delay,
  });

  Map<String, Object?>? event;
  String? displayName;
  String? roomName;
  Duration? delay;
  final requests = <http.BaseRequest>[];

  late final client = MockClient((request) async {
    requests.add(request);
    if (delay != null) await Future<void>.delayed(delay!);
    final path = request.url.pathSegments;
    final at = path.indexOf('rooms');
    if (at < 0 || path.length <= at + 1 || path[at + 1] != _roomId) {
      return http.Response('', 404);
    }
    final rest = path.sublist(at + 2);
    final Object? body = switch (rest) {
      ['event', _eventId] => event,
      ['state', 'm.room.member', '@asha:test'] =>
        displayName == null ? null : {'displayname': displayName},
      ['state', 'm.room.name'] => roomName == null ? null : {'name': roomName},
      _ => null,
    };
    return body == null
        ? http.Response('{"errcode":"M_NOT_FOUND"}', 404)
        : http.Response(jsonEncode(body), 200);
  });
}

MatrixNotificationDescriber _describer(
  _Homeserver server, {
  String homeserver = 'https://chat.example.com',
  Future<String?> Function()? token,
  Locale locale = const Locale('en'),
  Duration timeout = const Duration(seconds: 5),
}) => MatrixNotificationDescriber(
  homeserver: Uri.parse(homeserver),
  accessToken: token ?? () async => 'token-1',
  localizations: lookupAppLocalizations(locale),
  httpClient: server.client,
  timeout: timeout,
);

const _push = PushNotification(roomId: _roomId, eventId: _eventId);

void main() {
  test('titles a direct chat with the person, and shows the message', () async {
    final text = await _describer(_Homeserver())(_push);

    expect(text?.title, 'Asha Menon');
    expect(text?.body, 'are you coming?');
  });

  test('titles a group with its name, and says who spoke', () async {
    final text = await _describer(_Homeserver(roomName: 'Sales team'))(_push);

    expect(text?.title, 'Sales team');
    expect(text?.body, 'Asha Menon: are you coming?');
  });

  test('lets an emote lead with the name instead of doubling it', () async {
    final server = _Homeserver(roomName: 'Sales team')
      ..event = const {
        'type': 'm.room.message',
        'sender': '@asha:test',
        'content': {'msgtype': 'm.emote', 'body': 'waves'},
      };

    final text = await _describer(server)(_push);
    expect(text?.body, 'Asha Menon waves');
  });

  test('says Photo for a photo, not its filename', () async {
    final server = _Homeserver()
      ..event = const {
        'type': 'm.room.message',
        'sender': '@asha:test',
        'content': {'msgtype': 'm.image', 'body': 'IMG_0421.HEIC'},
      };

    expect((await _describer(server)(_push))?.body, 'Photo');
  });

  test('says Voice message for a voice note', () async {
    final server = _Homeserver()
      ..event = const {
        'type': 'm.room.message',
        'sender': '@asha:test',
        'content': {
          'msgtype': 'm.audio',
          'body': 'Voice message.m4a',
          'org.matrix.msc3245.voice': <String, Object?>{},
        },
      };

    expect((await _describer(server)(_push))?.body, 'Voice message');
  });

  test("speaks the phone's language", () async {
    final server = _Homeserver()
      ..event = const {
        'type': 'm.room.message',
        'sender': '@asha:test',
        'content': {'msgtype': 'm.image', 'body': 'IMG_0421.HEIC'},
      };

    final text = await _describer(server, locale: const Locale('ta'))(_push);
    expect(text?.body, 'படம்');
  });

  test('falls back to the name in the user id', () async {
    final text = await _describer(_Homeserver(displayName: null))(_push);
    expect(text?.title, 'asha');
  });

  test('sends the token to the homeserver and nowhere else', () async {
    final server = _Homeserver(roomName: 'Sales team');
    await _describer(server)(_push);

    expect(server.requests, hasLength(3));
    for (final request in server.requests) {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'chat.example.com');
      expect(request.headers['Authorization'], 'Bearer token-1');
    }
  });

  test('keeps an id with a slash in it as one path segment', () async {
    // Older room versions minted event ids from base64 with / and +.
    const oddEventId = r'$abc/def+ghi';
    final server = _Homeserver();
    await _describer(server)(
      const PushNotification(roomId: _roomId, eventId: oddEventId),
    );

    final segments = server.requests.first.url.pathSegments;
    expect(segments.sublist(segments.length - 2), ['event', oddEventId]);
  });

  test('keeps a homeserver that lives under a path', () async {
    final server = _Homeserver();
    await _describer(server, homeserver: 'https://example.com/matrix/')(_push);

    expect(server.requests.first.url.path, startsWith('/matrix/_matrix/'));
  });

  test('asks nothing when there is no token', () async {
    final server = _Homeserver();
    final text = await _describer(server, token: () async => null)(_push);

    expect(text, isNull);
    expect(server.requests, isEmpty);
  });

  test('gives up when the event cannot be fetched', () async {
    final text = await _describer(_Homeserver(event: null))(_push);
    expect(text, isNull);
  });

  test('stops at the event when it is not a message', () async {
    final server = _Homeserver()
      ..event = const {
        'type': 'm.room.member',
        'sender': '@asha:test',
        'content': {'membership': 'join'},
      };

    expect(await _describer(server)(_push), isNull);
    expect(server.requests, hasLength(1));
  });

  test('gives up rather than hold the notification back', () async {
    final server = _Homeserver(delay: const Duration(milliseconds: 300));
    final text = await _describer(
      server,
      timeout: const Duration(milliseconds: 50),
    )(_push);

    expect(text, isNull);
  });

  test('gives up on an answer that is not JSON', () async {
    final server = _Homeserver();
    final describer = MatrixNotificationDescriber(
      homeserver: Uri.parse('https://chat.example.com'),
      accessToken: () async => 'token-1',
      localizations: lookupAppLocalizations(const Locale('en')),
      httpClient: MockClient((_) async => http.Response('<html>', 200)),
    );

    expect(await describer(_push), isNull);
    expect(server.requests, isEmpty);
  });

  test('says nothing for a push that names no event', () async {
    final server = _Homeserver();
    final text = await _describer(server)(
      const PushNotification(roomId: _roomId),
    );

    expect(text, isNull);
    expect(server.requests, isEmpty);
  });
}
