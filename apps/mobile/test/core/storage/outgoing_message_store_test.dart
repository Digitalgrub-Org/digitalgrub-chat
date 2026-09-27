import 'dart:io';

import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('outbox survives a database close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('dg-chat-outbox-');
    addTearDown(() => directory.delete(recursive: true));
    final databasePath = path.join(directory.path, 'outbox.db');
    final createdAt = DateTime.utc(2026, 8, 1, 10);

    var store = await SqfliteOutgoingMessageStore.open(
      databasePath,
      factory: databaseFactoryFfi,
    );
    await store.put(
      OutgoingMessage(
        transactionId: 'persisted-txn',
        ownerUserId: '@alice:test',
        roomId: '!room:test',
        body: 'Survive restart',
        createdAt: createdAt,
        status: OutgoingMessageStatus.sending,
        attemptCount: 2,
        nextAttemptAt: createdAt,
        replyToEventId: r'$reply',
        editEventId: r'$edit',
      ),
    );
    await store.close();

    store = await SqfliteOutgoingMessageStore.open(
      databasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(store.close);
    await store.resetSending('@alice:test', createdAt);
    final restored = (await store.readForRoom(
      '@alice:test',
      '!room:test',
    )).single;

    expect(restored.transactionId, 'persisted-txn');
    expect(restored.body, 'Survive restart');
    expect(restored.status, OutgoingMessageStatus.pending);
    expect(restored.attemptCount, 2);
    expect(restored.replyToEventId, r'$reply');
    expect(restored.editEventId, r'$edit');
  });

  test('outbox data is isolated and removable by account', () async {
    final store = MemoryOutgoingMessageStore();
    addTearDown(store.close);
    final now = DateTime.utc(2026, 8, 1);
    for (final userId in ['@alice:test', '@bob:test']) {
      await store.put(
        OutgoingMessage(
          transactionId: 'txn-$userId',
          ownerUserId: userId,
          roomId: '!room:test',
          body: userId,
          createdAt: now,
          status: OutgoingMessageStatus.pending,
          attemptCount: 0,
          nextAttemptAt: now,
        ),
      );
    }

    await store.deleteForUser('@alice:test');

    expect(await store.readForUser('@alice:test'), isEmpty);
    expect(await store.readForUser('@bob:test'), hasLength(1));
  });
}
