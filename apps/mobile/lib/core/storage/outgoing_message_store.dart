import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqflite.dart';

enum OutgoingMessageStatus { pending, sending, failed }

class OutgoingMessage {
  const OutgoingMessage({
    required this.transactionId,
    required this.ownerUserId,
    required this.roomId,
    required this.body,
    required this.createdAt,
    required this.status,
    required this.attemptCount,
    required this.nextAttemptAt,
    this.replyToEventId,
    this.editEventId,
  });

  final String transactionId;
  final String ownerUserId;
  final String roomId;
  final String body;
  final DateTime createdAt;
  final OutgoingMessageStatus status;
  final int attemptCount;
  final DateTime nextAttemptAt;
  final String? replyToEventId;
  final String? editEventId;

  OutgoingMessage copyWith({
    OutgoingMessageStatus? status,
    int? attemptCount,
    DateTime? nextAttemptAt,
  }) {
    return OutgoingMessage(
      transactionId: transactionId,
      ownerUserId: ownerUserId,
      roomId: roomId,
      body: body,
      createdAt: createdAt,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      replyToEventId: replyToEventId,
      editEventId: editEventId,
    );
  }
}

abstract interface class OutgoingMessageStore {
  Stream<void> get changes;

  Future<void> put(OutgoingMessage message);

  Future<List<OutgoingMessage>> readForUser(String userId);

  Future<List<OutgoingMessage>> readForRoom(String userId, String roomId);

  Future<List<OutgoingMessage>> readReady(String userId, DateTime now);

  Future<void> remove(String transactionId);

  Future<void> resetSending(String userId, DateTime now);

  Future<void> deleteForUser(String userId);

  Future<void> close();
}

final outgoingMessageStoreProvider = FutureProvider<OutgoingMessageStore>((
  ref,
) async {
  final OutgoingMessageStore store;
  if (kIsWeb) {
    store = MemoryOutgoingMessageStore();
  } else {
    final supportDirectory = await getApplicationSupportDirectory();
    store = await SqfliteOutgoingMessageStore.open(
      path.join(supportDirectory.path, 'outgoing_messages.db'),
    );
  }
  ref.onDispose(() => unawaited(store.close()));
  return store;
});

class SqfliteOutgoingMessageStore implements OutgoingMessageStore {
  SqfliteOutgoingMessageStore._(this._database);

  static const _table = 'outgoing_messages';

  final Database _database;
  final _changes = StreamController<void>.broadcast();

  static Future<SqfliteOutgoingMessageStore> open(
    String databasePath, {
    DatabaseFactory? factory,
  }) async {
    final database = await (factory ?? sqflite.databaseFactory).openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, _) async {
          await database.execute('''
CREATE TABLE $_table (
  transaction_id TEXT PRIMARY KEY,
  owner_user_id TEXT NOT NULL,
  room_id TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  status TEXT NOT NULL,
  attempt_count INTEGER NOT NULL,
  next_attempt_at_ms INTEGER NOT NULL,
  reply_to_event_id TEXT,
  edit_event_id TEXT
)
''');
          await database.execute(
            'CREATE INDEX outgoing_messages_owner_room '
            'ON $_table(owner_user_id, room_id, created_at_ms)',
          );
          await database.execute(
            'CREATE INDEX outgoing_messages_retry '
            'ON $_table(owner_user_id, status, next_attempt_at_ms)',
          );
        },
        onUpgrade: (database, oldVersion, _) async {
          if (oldVersion < 2) {
            await database.execute(
              'ALTER TABLE $_table ADD COLUMN reply_to_event_id TEXT',
            );
            await database.execute(
              'ALTER TABLE $_table ADD COLUMN edit_event_id TEXT',
            );
          }
        },
      ),
    );
    return SqfliteOutgoingMessageStore._(database);
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> put(OutgoingMessage message) async {
    await _database.insert(
      _table,
      _toRow(message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  @override
  Future<List<OutgoingMessage>> readForUser(String userId) async {
    final rows = await _database.query(
      _table,
      where: 'owner_user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at_ms DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<OutgoingMessage>> readForRoom(
    String userId,
    String roomId,
  ) async {
    final rows = await _database.query(
      _table,
      where: 'owner_user_id = ? AND room_id = ?',
      whereArgs: [userId, roomId],
      orderBy: 'created_at_ms DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<OutgoingMessage>> readReady(String userId, DateTime now) async {
    final rows = await _database.query(
      _table,
      where: 'owner_user_id = ? AND status != ? AND next_attempt_at_ms <= ?',
      whereArgs: [
        userId,
        OutgoingMessageStatus.sending.name,
        now.millisecondsSinceEpoch,
      ],
      orderBy: 'created_at_ms ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> remove(String transactionId) async {
    await _database.delete(
      _table,
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
    _notify();
  }

  @override
  Future<void> resetSending(String userId, DateTime now) async {
    await _database.update(
      _table,
      {
        'status': OutgoingMessageStatus.pending.name,
        'next_attempt_at_ms': now.millisecondsSinceEpoch,
      },
      where: 'owner_user_id = ? AND status = ?',
      whereArgs: [userId, OutgoingMessageStatus.sending.name],
    );
    _notify();
  }

  @override
  Future<void> deleteForUser(String userId) async {
    await _database.delete(
      _table,
      where: 'owner_user_id = ?',
      whereArgs: [userId],
    );
    _notify();
  }

  Map<String, Object?> _toRow(OutgoingMessage message) => {
    'transaction_id': message.transactionId,
    'owner_user_id': message.ownerUserId,
    'room_id': message.roomId,
    'body': message.body,
    'created_at_ms': message.createdAt.millisecondsSinceEpoch,
    'status': message.status.name,
    'attempt_count': message.attemptCount,
    'next_attempt_at_ms': message.nextAttemptAt.millisecondsSinceEpoch,
    'reply_to_event_id': message.replyToEventId,
    'edit_event_id': message.editEventId,
  };

  OutgoingMessage _fromRow(Map<String, Object?> row) {
    final statusName = row['status'] as String;
    final status = OutgoingMessageStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => OutgoingMessageStatus.failed,
    );
    return OutgoingMessage(
      transactionId: row['transaction_id'] as String,
      ownerUserId: row['owner_user_id'] as String,
      roomId: row['room_id'] as String,
      body: row['body'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at_ms'] as int,
      ),
      status: status,
      attemptCount: row['attempt_count'] as int,
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
        row['next_attempt_at_ms'] as int,
      ),
      replyToEventId: row['reply_to_event_id'] as String?,
      editEventId: row['edit_event_id'] as String?,
    );
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> close() async {
    await _changes.close();
    await _database.close();
  }
}

class MemoryOutgoingMessageStore implements OutgoingMessageStore {
  final Map<String, OutgoingMessage> _messages = {};
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> put(OutgoingMessage message) async {
    _messages[message.transactionId] = message;
    _notify();
  }

  @override
  Future<List<OutgoingMessage>> readForUser(String userId) async {
    final messages =
        _messages.values
            .where((message) => message.ownerUserId == userId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return messages;
  }

  @override
  Future<List<OutgoingMessage>> readForRoom(
    String userId,
    String roomId,
  ) async {
    final messages =
        _messages.values
            .where(
              (message) =>
                  message.ownerUserId == userId && message.roomId == roomId,
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return messages;
  }

  @override
  Future<List<OutgoingMessage>> readReady(String userId, DateTime now) async {
    final messages =
        _messages.values
            .where(
              (message) =>
                  message.ownerUserId == userId &&
                  message.status != OutgoingMessageStatus.sending &&
                  !message.nextAttemptAt.isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  @override
  Future<void> remove(String transactionId) async {
    _messages.remove(transactionId);
    _notify();
  }

  @override
  Future<void> resetSending(String userId, DateTime now) async {
    for (final entry in _messages.entries.toList()) {
      final message = entry.value;
      if (message.ownerUserId == userId &&
          message.status == OutgoingMessageStatus.sending) {
        _messages[entry.key] = message.copyWith(
          status: OutgoingMessageStatus.pending,
          nextAttemptAt: now,
        );
      }
    }
    _notify();
  }

  @override
  Future<void> deleteForUser(String userId) async {
    _messages.removeWhere((_, message) => message.ownerUserId == userId);
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> close() => _changes.close();
}
