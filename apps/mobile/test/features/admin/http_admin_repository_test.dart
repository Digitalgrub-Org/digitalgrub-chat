import 'dart:convert';

import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/features/admin/data/http_admin_repository.dart';
import 'package:dg_chat/features/admin/domain/admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AppConfig _config({bool withAdmin = true}) => AppConfig(
  homeserver: Uri.parse('https://dgchat.test'),
  adminUrl: withAdmin ? Uri.parse('https://dgchat.test/dg/admin/') : null,
);

HttpAdminRepository _repo(
  int status,
  Object body, {
  void Function(http.Request)? onRequest,
  bool withAdmin = true,
}) => HttpAdminRepository(
  accessToken: () => 'tok-admin',
  config: _config(withAdmin: withAdmin),
  httpClient: MockClient((request) async {
    onRequest?.call(request);
    return http.Response(jsonEncode(body), status);
  }),
);

void main() {
  test('creates a user with the caller\'s own token', () async {
    http.Request? seen;
    final repo = _repo(201, {
      'user_id': '@priya:dgchat.test',
    }, onRequest: (r) => seen = r);
    final id = await repo.createUser(
      username: ' Priya ',
      password: 'longpass',
      displayName: 'Priya R',
    );
    expect(id, '@priya:dgchat.test');
    expect(seen!.url.toString(), 'https://dgchat.test/dg/admin/users');
    expect(seen!.headers['Authorization'], 'Bearer tok-admin');
    final sent = jsonDecode(seen!.body) as Map;
    expect(
      sent['username'],
      'priya',
      reason: 'normalised like the sign-up form',
    );
    expect(sent['password'], 'longpass');
    expect(sent['display_name'], 'Priya R');
  });

  test(
    'resets a password by localpart, whatever form the id came in',
    () async {
      http.Request? seen;
      final repo = _repo(200, {
        'user_id': '@sara:dgchat.test',
        'sessions_signed_out': true,
      }, onRequest: (r) => seen = r);
      await repo.resetPassword(
        username: '@sara:dgchat.test',
        password: 'newlongpass',
      );
      expect(seen!.url.path, '/dg/admin/users/sara/password');
      expect(jsonDecode(seen!.body), {'password': 'newlongpass'});
    },
  );

  group('refusals map to something the screen can say', () {
    Future<AdminFailureCode> codeFor(
      int status, [
      Object body = const {},
    ]) async {
      try {
        await _repo(
          status,
          body,
        ).resetPassword(username: 'sara', password: 'newlongpass');
      } on AdminFailure catch (f) {
        return f.code;
      }
      fail('expected a refusal for $status');
    }

    test('401 and 403 are not-an-admin', () async {
      expect(await codeFor(401), AdminFailureCode.notAdmin);
      expect(
        await codeFor(403, {'error': 'admin only'}),
        AdminFailureCode.notAdmin,
      );
    });

    test('an admin target is its own message', () async {
      // Reset on the server, never from here -- and the screen must say so,
      // not shrug.
      expect(
        await codeFor(403, {'error': 'IN.DIGITALGRUB.ADMIN_ACCOUNT'}),
        AdminFailureCode.adminAccount,
      );
    });

    test('404 is nobody, 409 is somebody', () async {
      expect(await codeFor(404), AdminFailureCode.notFound);
      expect(await codeFor(409), AdminFailureCode.usernameTaken);
    });

    test('a dead service is unavailable, not unknown', () async {
      expect(await codeFor(502), AdminFailureCode.serverUnavailable);
    });
  });

  group('isSelfAdmin', () {
    test('asks the service with the caller\'s own token', () async {
      http.Request? seen;
      final repo = _repo(200, {
        'user_id': '@admin:dgchat.test',
        'admin': true,
      }, onRequest: (r) => seen = r);

      expect(await repo.isSelfAdmin(), isTrue);
      expect(seen!.method, 'GET');
      expect(seen!.url.toString(), 'https://dgchat.test/dg/admin/me');
      expect(seen!.headers['Authorization'], 'Bearer tok-admin');
    });

    test('an ordinary account is not one', () async {
      final repo = _repo(200, {'user_id': '@sara:dgchat.test', 'admin': false});
      expect(await repo.isSelfAdmin(), isFalse);
    });

    test('every failure means no, never an error', () async {
      for (final status in [401, 404, 502]) {
        expect(await _repo(status, {'error': 'x'}).isSelfAdmin(), isFalse);
      }
      expect(await _repo(200, 'not an object').isSelfAdmin(), isFalse);
      expect(await _repo(200, {}, withAdmin: false).isSelfAdmin(), isFalse);
    });
  });

  test('a build without the service refuses before any request', () async {
    var requests = 0;
    final repo = _repo(200, {}, withAdmin: false, onRequest: (_) => requests++);
    await expectLater(
      repo.createUser(username: 'x', password: 'longpass'),
      throwsA(
        isA<AdminFailure>().having(
          (f) => f.code,
          'code',
          AdminFailureCode.unavailable,
        ),
      ),
    );
    expect(requests, 0);
  });
}
