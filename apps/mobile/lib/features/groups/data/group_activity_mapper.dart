import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:matrix/matrix.dart';

/// The state changes that read as activity, minus the call notification.
///
/// Calls are activity in the group's log but not in its timeline, where they
/// already have a row of their own with a Join button on it.
const timelineActivityEventTypes = {
  'm.room.create',
  'm.room.member',
  'm.room.name',
  'm.room.avatar',
  'm.room.pinned_events',
  'm.room.power_levels',
};

/// The activity line for [event], or null when the event is not activity.
///
/// Resolves the Matrix-flavoured parts — who sent it, who it was about — and
/// hands the rest to [activityEntryFrom], which is where the decisions live.
GroupActivityEntry? activityEntryOf(Event event, Room room) {
  final stateKey = event.stateKey;
  // Only a member event's state key names a person; a room-name event's is
  // the empty string.
  final targetId = stateKey != null && stateKey.startsWith('@')
      ? stateKey
      : null;
  return activityEntryFrom(
    type: event.type,
    content: event.content,
    previousContent: event.prevContent,
    actorId: event.senderId,
    targetId: targetId,
    actorName: event.senderFromMemoryOrFallback.calcDisplayname(),
    targetName: targetId == null
        ? null
        : room.unsafeGetUserFromMemoryOrFallback(targetId).calcDisplayname(),
    at: event.originServerTs,
  );
}

/// Maps one room event to an activity line, or null for the many event types
/// that are not activity.
///
/// Pure on purpose: everything Matrix-flavoured is passed in as plain values,
/// so the mapping — which is where the correctness lives — is testable
/// without a client.
GroupActivityEntry? activityEntryFrom({
  required String type,
  required Map<String, Object?> content,
  required Map<String, Object?>? previousContent,
  required String actorId,
  required String? targetId,
  required String actorName,
  required String? targetName,
  required DateTime at,
}) {
  switch (type) {
    case 'm.room.create':
      return GroupActivityEntry(
        kind: GroupActivityKind.created,
        actorName: actorName,
        at: at,
      );
    case 'm.room.member':
      final membership = content['membership'];
      final previous = previousContent?['membership'];
      if (membership == previous) return null; // profile change, not activity
      switch (membership) {
        case 'join':
          return GroupActivityEntry(
            kind: GroupActivityKind.joined,
            actorName: targetName ?? actorName,
            at: at,
          );
        case 'invite':
          return GroupActivityEntry(
            kind: GroupActivityKind.invited,
            actorName: actorName,
            targetName: targetName,
            at: at,
          );
        case 'leave':
          // Leaving yourself and being removed share a membership value; the
          // difference is whose hand was on the door. That is a question about
          // user ids -- display names are neither unique nor stable, and two
          // people called "Kumar" would otherwise turn a removal into a
          // voluntary exit credited to the wrong person.
          final byThemselves = targetId == null || targetId == actorId;
          if (byThemselves && previous == 'invite') {
            // A declined invite is not worth a line in the group's log. An
            // invite somebody else revoked is: that is a removal, and this
            // screen exists to answer who removed whom.
            return null;
          }
          return GroupActivityEntry(
            kind: byThemselves
                ? GroupActivityKind.left
                : GroupActivityKind.removed,
            actorName: actorName,
            targetName: byThemselves ? null : targetName,
            at: at,
          );
        default:
          return null;
      }
    case 'm.room.name':
      final name = content['name'];
      return GroupActivityEntry(
        kind: GroupActivityKind.renamed,
        actorName: actorName,
        detail: name is String ? name : null,
        at: at,
      );
    case 'm.room.avatar':
      return GroupActivityEntry(
        kind: GroupActivityKind.photoChanged,
        actorName: actorName,
        at: at,
      );
    case 'm.room.pinned_events':
      return GroupActivityEntry(
        kind: GroupActivityKind.pinsChanged,
        actorName: actorName,
        at: at,
      );
    case 'm.room.power_levels':
      if (previousContent == null) return null; // initial state, not a change
      return GroupActivityEntry(
        kind: GroupActivityKind.rolesChanged,
        actorName: actorName,
        at: at,
      );
    case 'org.matrix.msc4075.rtc.notification':
      return GroupActivityEntry(
        kind: GroupActivityKind.callStarted,
        actorName: actorName,
        at: at,
      );
    default:
      return null;
  }
}
