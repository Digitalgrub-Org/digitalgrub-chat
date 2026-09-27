/// State of the one call this client can be in at a time.
enum CallConnectionState { connecting, connected, reconnecting, ended }

enum CallFailureCode {
  notConfigured,
  permissionDenied,

  roomNotFound,
  serverUnavailable,
  unknown,
}

class CallFailure implements Exception {
  const CallFailure(this.code);

  final CallFailureCode code;
}

/// A person in the call.
///
/// [videoTrack] is deliberately opaque at this layer: rendering a live video
/// stream is inherently engine-specific, so the domain carries the handle and
/// only the presentation adapter knows what is inside it. Everything the UI
/// decides layout by — who, muted, speaking — is typed.
class CallParticipantView {
  const CallParticipantView({
    required this.id,
    required this.displayName,
    required this.isLocal,
    required this.hasAudio,
    required this.hasVideo,
    required this.isSpeaking,
    this.videoTrack,
    this.isScreenShare = false,
    this.handRaised = false,
  });

  final String id;
  final String displayName;
  final bool isLocal;
  final bool hasAudio;
  final bool hasVideo;
  final bool isSpeaking;
  final Object? videoTrack;

  /// This person has asked to speak. A signal on the call's data channel,
  /// not a media state, so it survives muting and is cleared when they leave.
  final bool handRaised;

  /// True when [videoTrack] is a shared screen rather than a camera. A
  /// shared screen is shown large and never mirrored, and it is a tile of its
  /// own even when the same person also has their camera on.
  final bool isScreenShare;
}

/// Snapshot of the active call, emitted on every change.
class CallSnapshot {
  const CallSnapshot({
    required this.roomId,
    required this.state,
    required this.participants,
    required this.micEnabled,
    required this.cameraEnabled,
    this.isScreenSharing = false,
    this.startedAt,
    this.canModerate = false,
    this.isGroup = false,
  });

  final String roomId;
  final CallConnectionState state;
  final List<CallParticipantView> participants;
  final bool micEnabled;
  final bool cameraEnabled;

  /// Whether this device is sharing its screen right now.
  final bool isScreenSharing;

  /// When the call reached [CallConnectionState.connected], for the duration
  /// readout. Null while still connecting.
  final DateTime? startedAt;

  /// Whether this account may ask others to mute. Follows the room's own
  /// idea of who moderates -- the same power that removes a member -- so a
  /// call has no host list of its own to fall out of step with the group.
  /// Always false for a guest, who has no room.
  final bool canModerate;

  /// More than one other person could be here: a group room or a meeting,
  /// as opposed to a direct chat. Decides the default audio route -- a group
  /// voice call through the earpiece is a phone held to one ear that
  /// everyone else in the room strains to hear.
  final bool isGroup;
}

/// The reactions a call offers, and the only ones it will render.
///
/// A fixed set rather than free text, deliberately: what arrives over the
/// call's data channel is written by other participants -- guests included --
/// and an allowlist is what keeps that channel from becoming a way to put
/// arbitrary content on everyone's screen.
const allowedCallReactions = ['👋', '👍', '👏', '❤️', '😂', '🎉'];

/// A greeting or emoji somebody raised mid-call.
class CallReaction {
  const CallReaction({
    required this.emoji,
    required this.senderName,
    required this.isLocal,
  });

  final String emoji;
  final String senderName;
  final bool isLocal;
}

/// A live call this client is part of.
abstract interface class CallController {
  Stream<CallSnapshot> get changes;

  CallSnapshot get current;

  Future<void> setMicEnabled(bool enabled);

  Future<void> setCameraEnabled(bool enabled);

  Future<void> switchCamera();

  Future<void> setSpeakerphone(bool enabled);

  /// Reactions raised by anyone in the call, this device's own included.
  Stream<CallReaction> get reactions;

  /// Raises [emoji] for everyone in the call. Anything outside
  /// [allowedCallReactions] is ignored.
  Future<void> sendReaction(String emoji);

  /// Raises or lowers this participant's hand for everyone in the call.
  Future<void> setHandRaised(bool raised);

  /// Asks [participantId] to mute, or everyone when null.
  ///
  /// A request, not an order: a client cannot silence another's microphone,
  /// so the other side's app does it on receipt -- and only after checking
  /// that the asker really does moderate the room. Does nothing unless
  /// [CallSnapshot.canModerate].
  Future<void> requestMute({String? participantId});

  /// Starts or stops sharing this device's screen. On iOS the system asks the
  /// user to confirm before the broadcast begins, so the change may land a
  /// moment after this returns; on Android it raises the projection-consent
  /// dialog. Not offered on mobile web, where the platform has no equivalent.
  Future<void> setScreenShareEnabled(bool enabled);

  /// Leaves the call and releases every device. Safe to call twice.
  Future<void> hangUp();
}

/// Someone started a call in a room this account is in.
class IncomingCallRing {
  const IncomingCallRing({
    required this.roomId,
    required this.roomName,
    required this.senderName,
    required this.receivedAt,
  });

  final String roomId;
  final String roomName;
  final String senderName;
  final DateTime receivedAt;
}

/// A call running in a room right now, whether or not it is still ringing.
///
/// A ring lasts thirty seconds; a call lasts as long as somebody is in it. This
/// is what lets a missed ring stay joinable instead of vanishing.
class LiveCall {
  const LiveCall({
    required this.roomId,
    required this.roomName,
    required this.participantCount,
  });

  final String roomId;
  final String roomName;

  /// How many people are in it, counted from unexpired memberships.
  final int participantCount;
}

abstract interface class CallRepository {
  /// Starts a call in [roomId], or joins the one already running there.
  ///
  /// [withVideo] controls whether the camera starts on; the microphone always
  /// does, because joining a call muted-and-invisible is an ambush, not a
  /// call. [ring] sounds the other side's devices and is set by the caller,
  /// not by someone joining an existing call.
  Future<CallController> startOrJoin(
    String roomId, {
    required bool withVideo,
    required bool ring,
  });

  /// Rings for calls started by others, while the app is in the foreground.
  Stream<IncomingCallRing> get incomingRings;

  /// Joins a meeting's call with a name instead of an account.
  ///
  /// [target] is what the link carried — a meeting code or a room id. The
  /// server decides whether it names a meeting at all; a guest never touches
  /// Matrix, only the call media, so there is no room, no history, and no
  /// membership left behind when they hang up.
  Future<CallController> joinMeetingAsGuest(
    String target, {
    required String displayName,
    required bool withVideo,
  });

  /// Calls running right now in rooms this account has joined.
  ///
  /// Separate from [incomingRings] on purpose: a ring is a moment, and this is
  /// a state. Someone who missed the ring — phone in a pocket, app closed —
  /// can still see the call is up and join it.
  Stream<List<LiveCall>> get liveCalls;
}
