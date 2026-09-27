import 'dart:convert';

import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/features/admin/domain/admin_repository.dart';
import 'package:http/http.dart' as http;

/// Talks to the dg-admin service with the signed-in account's own token.
///
/// No credential of its own: the service asks Synapse who the token belongs
/// to and whether that account is a server admin, so an ordinary session
/// gets a 403 from the homeserver itself.
class HttpAdminRepository implements AdminRepository {
  HttpAdminRepository({
    required String? Function() accessToken,
    required AppConfig config,
    http.Client? httpClient,
  }) : _accessToken = accessToken,
       _config = config,
       _http = httpClient ?? http.Client();

  /// Read at call time, not construction: a token is replaced on refresh and
  /// on re-login, and a repository built once must follow it.
  final String? Function() _accessToken;
  final AppConfig _config;
  final http.Client _http;

  Uri _endpoint(String path) {
    final base = _config.adminUrl;
    if (base == null) throw const AdminFailure(AdminFailureCode.unavailable);
    return Uri.parse('${base.toString().replaceAll(RegExp(r'/+$'), '')}$path');
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final token = _accessToken();
    if (token == null) throw const AdminFailure(AdminFailureCode.notAdmin);
    final http.Response response;
    try {
      response = await _http
          .post(
            _endpoint(path),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on AdminFailure {
      rethrow;
    } catch (_) {
      throw const AdminFailure(AdminFailureCode.serverUnavailable);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    final error = decoded is Map ? decoded['error'] : null;
    switch (response.statusCode) {
      case 200:
      case 201:
        return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
      case 401:
      case 403:
        throw AdminFailure(
          error == 'IN.DIGITALGRUB.ADMIN_ACCOUNT'
              ? AdminFailureCode.adminAccount
              : AdminFailureCode.notAdmin,
        );
      case 404:
        throw const AdminFailure(AdminFailureCode.notFound);
      case 409:
        throw const AdminFailure(AdminFailureCode.usernameTaken);
      case 502:
      case 503:
      case 504:
        throw const AdminFailure(AdminFailureCode.serverUnavailable);
      default:
        throw const AdminFailure(AdminFailureCode.unknown);
    }
  }

  @override
  Future<String> createUser({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final result = await _post('/users', {
      'username': username.trim().toLowerCase(),
      'password': password,
      if (displayName != null && displayName.trim().isNotEmpty)
        'display_name': displayName.trim(),
    });
    final userId = result['user_id'];
    if (userId is! String) throw const AdminFailure(AdminFailureCode.unknown);
    return userId;
  }

  @override
  Future<bool> isSelfAdmin() async {
    final token = _accessToken();
    if (token == null || token.isEmpty) return false;
    try {
      final response = await _http
          .get(_endpoint('/me'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> resetPassword({
    required String username,
    required String password,
  }) async {
    final localpart = username
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^@'), '')
        .split(':')
        .first;
    await _post('/users/${Uri.encodeComponent(localpart)}/password', {
      'password': password,
    });
  }
}
