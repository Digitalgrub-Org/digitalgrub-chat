/// A meeting is a room whose door is a link.
///
/// Structurally it is an ordinary group with a public join rule, so any
/// signed-in account on this homeserver can enter by opening the link —
/// which is the whole Meet-style gesture: no per-person invites, the URL is
/// the invitation.
class Meeting {
  const Meeting({required this.roomId, required this.title, this.code});

  final String roomId;
  final String title;

  /// The short joining code — the `abc-defg-hij` in the link. Held as a room
  /// alias on the server, so resolving it needs no directory of our own.
  final String? code;
}

enum MeetingFailureCode {
  /// The link points at a room that no longer exists or cannot be joined.
  notJoinable,
  sessionExpired,
  serverUnavailable,
  unknown,
}

class MeetingFailure implements Exception {
  const MeetingFailure(this.code);

  final MeetingFailureCode code;
}

abstract interface class MeetingRepository {
  /// Creates a meeting room and returns it. The caller is already joined.
  Future<Meeting> createMeeting(String title);

  /// Makes sure this account is in the meeting behind [target] — a short
  /// joining code, or a raw room id from an older link — joining on first
  /// contact. Returns the canonical room id. Idempotent.
  Future<String> ensureJoined(String target);
}
