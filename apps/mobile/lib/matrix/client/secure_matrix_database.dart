import 'dart:convert';

import 'package:dg_chat/core/storage/secure_key_value_store.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:matrix/matrix.dart';
import 'package:sqflite_common/sqflite.dart';

class SecureMatrixDatabase extends MatrixSdkDatabase {
  SecureMatrixDatabase._(
    this.clientName,
    this._secureStore, {
    super.database,
    super.sqfliteFactory,
    super.maxFileSize,
    super.fileStorageLocation,
    super.deleteFilesAfterDuration,
  }) : super.buildWithoutOpen(clientName);

  static const _cacheMarker = 'stored-in-platform-secure-storage';
  static const _secureKeyPrefix = 'digitalgrub_chat.matrix_session.v1';

  final String clientName;
  final SecureKeyValueStore _secureStore;

  String get _secureKey => _secureKeyFor(clientName);

  static String _secureKeyFor(String clientName) =>
      '$_secureKeyPrefix.$clientName';

  /// The access token stored for [clientName], read without opening the
  /// database or starting the SDK.
  ///
  /// For a push waking the app in a background isolate, which needs the
  /// token for one request and nothing else. Read-only on purpose: the
  /// instance's own reader discards a malformed record, and a background
  /// wake-up has no business deleting somebody's session.
  static Future<String?> readAccessToken(
    SecureKeyValueStore store,
    String clientName,
  ) async {
    try {
      final encoded = await store.read(_secureKeyFor(clientName));
      if (encoded == null) return null;
      final json = jsonDecode(encoded);
      final token = json is Map ? json['access_token'] : null;
      return token is String && token.isNotEmpty ? token : null;
    } catch (_) {
      return null;
    }
  }

  static Future<SecureMatrixDatabase> init(
    String clientName, {
    required SecureKeyValueStore secureStore,
    Database? database,
    DatabaseFactory? sqfliteFactory,
    int maxFileSize = 0,
    Uri? fileStorageLocation,
    Duration? deleteFilesAfterDuration,
  }) async {
    final matrixDatabase = SecureMatrixDatabase._(
      clientName,
      secureStore,
      database: database,
      sqfliteFactory: sqfliteFactory,
      maxFileSize: maxFileSize,
      fileStorageLocation: fileStorageLocation,
      deleteFilesAfterDuration: deleteFilesAfterDuration,
    );
    await matrixDatabase.open();
    await matrixDatabase._migratePlaintextCredentials();
    return matrixDatabase;
  }

  @override
  Future<Map<String, dynamic>?> getClient(String name) async {
    final cachedClient = await super.getClient(name);
    if (cachedClient == null) return null;

    cachedClient.remove('token');
    cachedClient.remove('token_expires_at');
    cachedClient.remove('refresh_token');

    final credentials = await _readCredentials();
    if (credentials == null) return cachedClient;

    cachedClient['token'] = credentials.accessToken;
    if (credentials.tokenExpiresAt != null) {
      cachedClient['token_expires_at'] = credentials.tokenExpiresAt;
    }
    if (credentials.refreshToken != null) {
      cachedClient['refresh_token'] = credentials.refreshToken;
    }
    return cachedClient;
  }

  @override
  Future<int> insertClient(
    String name,
    String homeserverUrl,
    String token,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    String userId,
    String? deviceId,
    String? deviceName,
    String? prevBatch,
    String? olmAccount,
    String? oidcClientId,
  ) async {
    return _replaceCredentials(
      token,
      tokenExpiresAt,
      refreshToken,
      () => super.insertClient(
        name,
        homeserverUrl,
        _cacheMarker,
        null,
        null,
        userId,
        deviceId,
        deviceName,
        prevBatch,
        olmAccount,
        oidcClientId,
      ),
    );
  }

  @override
  Future<void> updateClient(
    String homeserverUrl,
    String token,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    String userId,
    String? deviceId,
    String? deviceName,
    String? prevBatch,
    String? olmAccount,
    String? oidcClientId,
  ) async {
    await _replaceCredentials(
      token,
      tokenExpiresAt,
      refreshToken,
      () => super.updateClient(
        homeserverUrl,
        _cacheMarker,
        null,
        null,
        userId,
        deviceId,
        deviceName,
        prevBatch,
        olmAccount,
        oidcClientId,
      ),
    );
  }

  @override
  Future<void> clear() async {
    try {
      await _secureStore.delete(_secureKey);
    } finally {
      await super.clear();
    }
  }

  Future<void> _writeCredentials(
    String accessToken,
    DateTime? tokenExpiresAt,
    String? refreshToken,
  ) {
    final credentials = <String, String>{'access_token': accessToken};
    if (tokenExpiresAt != null) {
      credentials['token_expires_at'] = tokenExpiresAt.millisecondsSinceEpoch
          .toString();
    }
    if (refreshToken != null) {
      credentials['refresh_token'] = refreshToken;
    }
    final encoded = jsonEncode(credentials);
    return _secureStore.write(_secureKey, encoded);
  }

  Future<T> _replaceCredentials<T>(
    String accessToken,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    Future<T> Function() updateCache,
  ) async {
    final previousCredentials = await _secureStore.read(_secureKey);
    await _writeCredentials(accessToken, tokenExpiresAt, refreshToken);
    try {
      return await updateCache();
    } catch (_) {
      if (previousCredentials == null) {
        await _secureStore.delete(_secureKey);
      } else {
        await _secureStore.write(_secureKey, previousCredentials);
      }
      rethrow;
    }
  }

  Future<_MatrixCredentials?> _readCredentials() async {
    final encoded = await _secureStore.read(_secureKey);
    if (encoded == null) return null;

    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final accessToken = json['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) return null;
      return _MatrixCredentials(
        accessToken: accessToken,
        tokenExpiresAt: json['token_expires_at'] as String?,
        refreshToken: json['refresh_token'] as String?,
      );
    } on FormatException {
      // The exception is deliberately not interpolated: a JSON FormatException
      // carries the offending source, which here is the credentials blob.
      await _discardCredentials('malformed JSON');
      return null;
    } on TypeError {
      await _discardCredentials('unexpected field types');
      return null;
    }
  }

  Future<void> _discardCredentials(String reason) async {
    debugPrint('Discarding stored Matrix credentials: $reason');
    await _secureStore.delete(_secureKey);
  }

  Future<void> _migratePlaintextCredentials() async {
    final cachedClient = await super.getClient(clientName);
    if (cachedClient == null) return;

    final cachedToken = cachedClient['token'] as String?;
    if (cachedToken == null || cachedToken == _cacheMarker) return;

    if (await _readCredentials() == null) {
      final expiresAtMilliseconds = int.tryParse(
        cachedClient['token_expires_at'] as String? ?? '',
      );
      await _writeCredentials(
        cachedToken,
        expiresAtMilliseconds == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiresAtMilliseconds),
        cachedClient['refresh_token'] as String?,
      );
    }

    await super.updateClient(
      cachedClient['homeserver_url'] as String,
      _cacheMarker,
      null,
      null,
      cachedClient['user_id'] as String,
      cachedClient['device_id'] as String?,
      cachedClient['device_name'] as String?,
      cachedClient['prev_batch'] as String?,
      cachedClient['olm_account'] as String?,
      cachedClient['oidc_client_id'] as String?,
    );
  }

  @visibleForTesting
  Future<Map<String, dynamic>?> readUnprotectedClientForTesting() =>
      super.getClient(clientName);
}

class _MatrixCredentials {
  const _MatrixCredentials({
    required this.accessToken,
    this.tokenExpiresAt,
    this.refreshToken,
  });

  final String accessToken;
  final String? tokenExpiresAt;
  final String? refreshToken;
}
