import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/conversation/presentation/message_actions.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage _message({
  bool isOwn = false,
  bool canDeleteForEveryone = false,
  bool isDeleted = false,
}) => ChatMessage(
  eventId: r'$1:test',
  senderId: isOwn ? '@me:test' : '@dev:test',
  senderName: isOwn ? 'Sara' : 'Dev',
  body: 'hello',
  sentAt: DateTime(2026, 8, 20, 10),
  isOwn: isOwn,
  deliveryState: MessageDeliveryState.synced,
  canDeleteForEveryone: canDeleteForEveryone,
  isDeleted: isDeleted,
);

void main() {
  group('canOfferDelete', () {
    test('your own message can always be deleted', () {
      expect(canOfferDelete(_message(isOwn: true)), isTrue);
    });

    test('someone else\'s can be, when the room says you may redact it', () {
      // What a group's admin needs: the power level allows the redaction, so
      // the option has to be reachable. Gating this on "is it mine" left a
      // moderator with no way to take anything down.
      expect(canOfferDelete(_message(canDeleteForEveryone: true)), isTrue);
    });

    test('someone else\'s cannot be, without that power', () {
      expect(canOfferDelete(_message()), isFalse);
    });

    test('an already deleted message offers nothing to delete', () {
      expect(
        canOfferDelete(
          _message(isOwn: true, canDeleteForEveryone: true, isDeleted: true),
        ),
        isFalse,
      );
    });
  });
}
