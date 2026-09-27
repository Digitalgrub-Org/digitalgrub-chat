import 'dart:async';
import 'dart:math';

import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/matrix/synchronization/outgoing_message_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryOutgoingMessageStore store;
  late DateTime now;

  setUp(() {
    store = MemoryOutgoingMessageStore();
    now = DateTime.utc(2026, 8, 1, 12);
  });

  tearDown(() => store.close());

  test('persists before send and reuses the transaction ID on retry', () async {
    final attemptedTransactionIds = <String>[];
    var shouldSucceed = false;
    final queue = OutgoingMessageQueue(
      store: store,
      ownerUserId: '@alice:test',
      sender: (message) async {
        attemptedTransactionIds.add(message.transactionId);
        return shouldSucceed;
      },
      generateTransactionId: () => 'txn-1',
      now: () => now,
      random: Random(1),
    );
    addTearDown(queue.dispose);

    final transactionId = await queue.enqueue('!room:test', 'Hello offline');
    expect(transactionId, 'txn-1');
    expect(attemptedTransactionIds, isEmpty);
    expect(
      (await store.readForUser('@alice:test')).single.body,
      'Hello offline',
    );

    await queue.flush();
    final failed = (await store.readForUser('@alice:test')).single;
    expect(failed.status, OutgoingMessageStatus.failed);
    expect(failed.attemptCount, 1);

    shouldSucceed = true;
    await queue.retry(transactionId);
    await queue.flush(force: true);

    expect(attemptedTransactionIds, ['txn-1', 'txn-1']);
    expect(await store.readForUser('@alice:test'), isEmpty);
  });

  test('coalesces concurrent flush requests into one network send', () async {
    final sendResult = Completer<bool>();
    var sendCount = 0;
    final queue = OutgoingMessageQueue(
      store: store,
      ownerUserId: '@alice:test',
      sender: (_) {
        sendCount++;
        return sendResult.future;
      },
      generateTransactionId: () => 'txn-2',
      now: () => now,
      random: Random(2),
    );
    addTearDown(queue.dispose);

    await queue.enqueue('!room:test', 'Only once');
    final firstFlush = queue.flush();
    final secondFlush = queue.flush();
    await Future<void>.delayed(Duration.zero);
    expect(sendCount, 1);

    sendResult.complete(true);
    await Future.wait([firstFlush, secondFlush]);

    expect(sendCount, 1);
    expect(await store.readForUser('@alice:test'), isEmpty);
  });

  test('persists reply and edit relationships through retries', () async {
    OutgoingMessage? attempted;
    final queue = OutgoingMessageQueue(
      store: store,
      ownerUserId: '@alice:test',
      sender: (message) async {
        attempted = message;
        return false;
      },
      generateTransactionId: () => 'txn-relations',
      now: () => now,
      random: Random(4),
    );
    addTearDown(queue.dispose);

    await queue.enqueue(
      '!room:test',
      'Related message',
      replyToEventId: r'$reply',
      editEventId: r'$edit',
    );
    await queue.flush();

    expect(attempted?.replyToEventId, r'$reply');
    expect(attempted?.editEventId, r'$edit');
    final failed = (await store.readForUser('@alice:test')).single;
    expect(failed.replyToEventId, r'$reply');
    expect(failed.editEventId, r'$edit');
  });

  test('restores an interrupted send to pending after restart', () async {
    await store.put(
      OutgoingMessage(
        transactionId: 'txn-3',
        ownerUserId: '@alice:test',
        roomId: '!room:test',
        body: 'Interrupted',
        createdAt: now,
        status: OutgoingMessageStatus.sending,
        attemptCount: 0,
        nextAttemptAt: now,
      ),
    );
    final queue = OutgoingMessageQueue(
      store: store,
      ownerUserId: '@alice:test',
      sender: (_) async => true,
      generateTransactionId: () => 'unused',
      now: () => now,
      random: Random(3),
    );
    addTearDown(queue.dispose);

    await queue.restore();

    expect(
      (await store.readForUser('@alice:test')).single.status,
      OutgoingMessageStatus.pending,
    );
  });
}
