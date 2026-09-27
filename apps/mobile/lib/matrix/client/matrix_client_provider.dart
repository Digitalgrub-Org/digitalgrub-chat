import 'dart:async';
import 'dart:io';

import 'package:dg_chat/core/storage/secure_key_value_store.dart';
import 'package:dg_chat/matrix/client/secure_matrix_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqflite.dart';

const matrixClientName = 'digitalgrub-chat';

final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>(
  (ref) => PlatformSecureKeyValueStore(),
);

final matrixClientProvider = FutureProvider<Client>((ref) async {
  Database? sqliteDatabase;
  Uri? fileStorageLocation;

  if (!kIsWeb) {
    final supportDirectory = await getApplicationSupportDirectory();
    sqliteDatabase = await sqflite.openDatabase(
      path.join(supportDirectory.path, 'matrix_store.db'),
    );
    // The SDK writes attachment bytes straight into this directory with
    // File.writeAsBytes, which does not create parents. Without this line
    // every photo and file send died on a PathNotFoundException before a
    // single byte reached the server, surfacing as "Could not send that
    // file" with nothing in the logs to say why.
    final fileStorage = Directory(
      path.join(supportDirectory.path, 'matrix_files'),
    );
    await fileStorage.create(recursive: true);
    fileStorageLocation = fileStorage.uri;
  }

  final database = await SecureMatrixDatabase.init(
    matrixClientName,
    secureStore: ref.watch(secureKeyValueStoreProvider),
    database: sqliteDatabase,
    fileStorageLocation: fileStorageLocation,
  );
  final client = Client(
    matrixClientName,
    database: database,
    supportedLoginTypes: {AuthenticationTypes.password},
    sendTimelineEventTimeout: const Duration(seconds: 20),
    onSoftLogout: (client) => client.refreshAccessToken(),
  );

  ref.onDispose(() => unawaited(client.dispose()));

  try {
    await client.init(waitForFirstSync: false);
    return client;
  } catch (_) {
    await client.dispose();
    rethrow;
  }
});
