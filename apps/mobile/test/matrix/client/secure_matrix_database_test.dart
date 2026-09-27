import 'dart:io';

import 'package:dg_chat/core/storage/secure_key_value_store.dart';
import 'package:dg_chat/matrix/client/secure_matrix_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('keeps Matrix credentials out of the SQLite client record', () async {
    final sqlite = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final secureStore = _MemorySecureStore();
    final database = await SecureMatrixDatabase.init(
      'test-client',
      secureStore: secureStore,
      database: sqlite,
      sqfliteFactory: databaseFactoryFfi,
    );
    addTearDown(database.close);

    final expiresAt = DateTime.utc(2026, 8, 1);
    await database.insertClient(
      'test-client',
      'https://chat.example.com',
      'secret-access-token',
      expiresAt,
      'secret-refresh-token',
      '@alice:chat.example.com',
      'DEVICE',
      'Test device',
      'sync-position',
      null,
      null,
    );

    final restored = await database.getClient('test-client');
    expect(restored?['token'], 'secret-access-token');
    expect(restored?['refresh_token'], 'secret-refresh-token');
    expect(
      restored?['token_expires_at'],
      expiresAt.millisecondsSinceEpoch.toString(),
    );

    final unprotected = await database.readUnprotectedClientForTesting();
    expect(unprotected?['token'], isNot('secret-access-token'));
    expect(unprotected, isNot(contains('refresh_token')));
    expect(unprotected, isNot(contains('token_expires_at')));
    expect(secureStore.values.values.single, contains('secret-access-token'));
  });

  test('clears secure credentials with the Matrix cache', () async {
    final sqlite = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final secureStore = _MemorySecureStore();
    final database = await SecureMatrixDatabase.init(
      'test-client',
      secureStore: secureStore,
      database: sqlite,
      sqfliteFactory: databaseFactoryFfi,
    );
    addTearDown(database.close);

    await database.insertClient(
      'test-client',
      'https://chat.example.com',
      'secret-access-token',
      null,
      null,
      '@alice:chat.example.com',
      'DEVICE',
      'Test device',
      null,
      null,
      null,
    );

    await database.clear();

    expect(secureStore.values, isEmpty);
    expect(await database.getClient('test-client'), isNull);
  });

  test(
    'restores secure credentials after reopening the SQLite cache',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'dg-chat-matrix-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final databasePath =
          '${directory.path}${Platform.pathSeparator}matrix_store.db';
      final secureStore = _MemorySecureStore();

      final firstSqlite = await databaseFactoryFfi.openDatabase(databasePath);
      final firstDatabase = await SecureMatrixDatabase.init(
        'test-client',
        secureStore: secureStore,
        database: firstSqlite,
        sqfliteFactory: databaseFactoryFfi,
      );
      await firstDatabase.insertClient(
        'test-client',
        'https://chat.example.com',
        'persistent-access-token',
        null,
        'persistent-refresh-token',
        '@alice:chat.example.com',
        'DEVICE',
        'Test device',
        'sync-position',
        null,
        null,
      );
      await firstDatabase.close();

      final secondSqlite = await databaseFactoryFfi.openDatabase(databasePath);
      final secondDatabase = await SecureMatrixDatabase.init(
        'test-client',
        secureStore: secureStore,
        database: secondSqlite,
        sqfliteFactory: databaseFactoryFfi,
      );
      addTearDown(secondDatabase.close);

      final restored = await secondDatabase.getClient('test-client');
      expect(restored?['token'], 'persistent-access-token');
      expect(restored?['refresh_token'], 'persistent-refresh-token');
      expect(restored?['prev_batch'], 'sync-position');
    },
  );

  test('migrates legacy plaintext credentials into secure storage', () async {
    final directory = await Directory.systemTemp.createTemp('dg-chat-matrix-');
    addTearDown(() => directory.delete(recursive: true));
    final databasePath =
        '${directory.path}${Platform.pathSeparator}matrix_store.db';

    final legacySqlite = await databaseFactoryFfi.openDatabase(databasePath);
    final legacyDatabase = await MatrixSdkDatabase.init(
      'test-client',
      database: legacySqlite,
      sqfliteFactory: databaseFactoryFfi,
    );
    await legacyDatabase.insertClient(
      'test-client',
      'https://chat.example.com',
      'legacy-access-token',
      null,
      'legacy-refresh-token',
      '@alice:chat.example.com',
      'DEVICE',
      'Test device',
      'legacy-sync-position',
      null,
      null,
    );
    await legacyDatabase.close();

    final secureStore = _MemorySecureStore();
    final migratedSqlite = await databaseFactoryFfi.openDatabase(databasePath);
    final migratedDatabase = await SecureMatrixDatabase.init(
      'test-client',
      secureStore: secureStore,
      database: migratedSqlite,
      sqfliteFactory: databaseFactoryFfi,
    );
    addTearDown(migratedDatabase.close);

    final restored = await migratedDatabase.getClient('test-client');
    expect(restored?['token'], 'legacy-access-token');
    expect(restored?['refresh_token'], 'legacy-refresh-token');
    expect(restored?['prev_batch'], 'legacy-sync-position');
    final unprotected = await migratedDatabase
        .readUnprotectedClientForTesting();
    expect(unprotected?['token'], isNot('legacy-access-token'));
    expect(unprotected, isNot(contains('refresh_token')));
  });

  test(
    'restores previous secure credentials when cache update fails',
    () async {
      final sqlite = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      final secureStore = _MemorySecureStore();
      final database = await SecureMatrixDatabase.init(
        'test-client',
        secureStore: secureStore,
        database: sqlite,
        sqfliteFactory: databaseFactoryFfi,
      );
      await database.insertClient(
        'test-client',
        'https://chat.example.com',
        'original-access-token',
        null,
        'original-refresh-token',
        '@alice:chat.example.com',
        'DEVICE',
        'Test device',
        null,
        null,
        null,
      );
      await database.close();

      await expectLater(
        database.updateClient(
          'https://chat.example.com',
          'replacement-access-token',
          null,
          'replacement-refresh-token',
          '@alice:chat.example.com',
          'DEVICE',
          'Test device',
          null,
          null,
          null,
        ),
        throwsA(anything),
      );

      expect(
        secureStore.values.values.single,
        contains('original-access-token'),
      );
      expect(
        secureStore.values.values.single,
        isNot(contains('replacement-access-token')),
      );
    },
  );

  group('readAccessToken', () {
    // The key every signed-in phone already has its token under. Changing it
    // would sign everyone out at the next update, so it is pinned here.
    const storedKey = 'digitalgrub_chat.matrix_session.v1.test-client';

    test('reads the token a session stored, without the database', () async {
      final sqlite = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      final secureStore = _MemorySecureStore();
      final database = await SecureMatrixDatabase.init(
        'test-client',
        secureStore: secureStore,
        database: sqlite,
        sqfliteFactory: databaseFactoryFfi,
      );
      addTearDown(database.close);
      await database.insertClient(
        'test-client',
        'https://chat.example.com',
        'secret-access-token',
        null,
        null,
        '@alice:chat.example.com',
        'DEVICE',
        'Test device',
        null,
        null,
        null,
      );

      expect(secureStore.values.keys, [storedKey]);
      expect(
        await SecureMatrixDatabase.readAccessToken(secureStore, 'test-client'),
        'secret-access-token',
      );
    });

    test('reads nothing for a phone that never signed in', () async {
      expect(
        await SecureMatrixDatabase.readAccessToken(
          _MemorySecureStore(),
          'test-client',
        ),
        isNull,
      );
    });

    test('leaves a record it cannot read exactly where it was', () async {
      // A background wake-up must never be what deletes a session.
      final secureStore = _MemorySecureStore()..values[storedKey] = 'not json';

      expect(
        await SecureMatrixDatabase.readAccessToken(secureStore, 'test-client'),
        isNull,
      );
      expect(secureStore.values[storedKey], 'not json');
    });
  });
}

class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
