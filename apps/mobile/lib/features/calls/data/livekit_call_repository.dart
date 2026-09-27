import 'dart:async';
import 'dart:convert';

import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/features/calls/data/call_foreground_service.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';
import 'package:webrtc_interface/webrtc_interface.dart' as rtc;

/// Calls through our own LiveKit SFU, with Matrix as the control plane.
///
/// The Matrix side (via the SDK's call module) carries who-is-in-the-call
/// state and the ring; media never touches Matrix. Every call is an SFU call,
/// 1:1 included — one media path for every size of conversation, which is the
/// same trade Element X makes.
class LiveKitCallRepository implements CallRepository {
  LiveKitCallRepository(this._client, this._config, {http.Client? httpClient})
    : _http = httpClient ?? http.Client() {
    _rings = _watchRings();
    _live = _watchLiveCalls();
  }

  final Client _client;
  final AppConfig _config;
  final http.Client _http;

  VoIP? _voip;
  late final Stream<IncomingCallRing> _rings;
  late final Stream<List<LiveCall>> _live;

  /// The SDK's call module, created on first use. Its constructor scans rooms
  /// and subscribes to sync, which there is no reason to pay for at startup
  /// on an account that never calls anyone.
  VoIP get _voipModule => _voip ??= VoIP(_client, _CallWebRTCDelegate());

  @override
  Stream<IncomingCallRing> get incomingRings => _rings;

  @override
  Stream<List<LiveCall>> get liveCalls => _live;

  /// Reads call membership straight from room state rather than through the
  /// SDK's call module.
  ///
  /// The module's constructor scans every room and subscribes to sync, and
  /// this runs for every account on every sync — including the many that never
  /// place a call — so paying that at startup to answer "is anyone calling"
  /// would undo the laziness above. The state event is public and its shape is
  /// stable; reading it directly costs nothing.
  Stream<List<LiveCall>> _watchLiveCalls() async* {
    var previous = '';
    yield _currentLiveCalls();
    await for (final _ in _client.onSync.stream) {
      final calls = _currentLiveCalls();
      // Sync fires continuously. Only a change in who is on a call is worth
      // rebuilding the UI for.
      final signature = calls
          .map((call) => '${call.roomId}:${call.participantCount}')
          .join(',');
      if (signature == previous) continue;
      previous = signature;
      yield calls;
    }
  }

  List<LiveCall> _currentLiveCalls() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final calls = <LiveCall>[];
    for (final room in _client.rooms) {
      if (room.membership != Membership.join) continue;
      final memberStates = room.states.tryGetMap<String, Event>(
        EventTypes.GroupCallMember,
      );
      if (memberStates == null) continue;

      var participants = 0;
      for (final event in memberStates.values) {
        final memberships = event.content['memberships'];
        if (memberships is! List) continue;
        // One state event per member, each listing that member's memberships.
        // A membership past its expiry is somebody whose client died without
        // tidying up, not somebody in the call.
        final present = memberships.any((membership) {
          if (membership is! Map) return false;
          final expires = membership['expires_ts'];
          return expires is num && expires > now;
        });
        if (present) participants++;
      }
      if (participants == 0) continue;
      calls.add(
        LiveCall(
          roomId: room.id,
          roomName: room.getLocalizedDisplayname(),
          participantCount: participants,
        ),
      );
    }
    return calls;
  }

  Stream<IncomingCallRing> _watchRings() async* {
    await for (final sync in _client.onSync.stream) {
      final joins = sync.rooms?.join;
      if (joins == null) continue;
      for (final entry in joins.entries) {
        for (final event in entry.value.timeline?.events ?? const []) {
          if (event.type != 'org.matrix.msc4075.rtc.notification') continue;
          if (event.senderId == _client.userID) continue;
          // A stale ring replayed from history must not sound: the event is
          // only honoured within its declared lifetime.
          final age = DateTime.now().difference(event.originServerTs).abs();
          final lifetime = event.content['lifetime'];
          final maxAge = Duration(
            milliseconds: lifetime is int ? lifetime : 30000,
          );
          if (age > maxAge) continue;

          final room = _client.getRoomById(entry.key);
          if (room == null || room.membership != Membership.join) continue;
          yield IncomingCallRing(
            roomId: entry.key,
            roomName: room.getLocalizedDisplayname(),
            senderName: room
                .unsafeGetUserFromMemoryOrFallback(event.senderId)
                .calcDisplayname(),
            receivedAt: DateTime.now(),
          );
        }
      }
    }
  }

  @override
  Future<CallController> startOrJoin(
    String roomId, {
    required bool withVideo,
    required bool ring,
  }) async {
    final jwtBase = _config.livekitJwtUrl;
    if (jwtBase == null) throw const CallFailure(CallFailureCode.notConfigured);
    final room = _client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      throw const CallFailure(CallFailureCode.roomNotFound);
    }

    // Membership first: the state event is what tells everyone else — and
    // future Element-family clients — that a call is running here.
    final groupCall = await _voipModule.fetchOrCreateGroupCall(
      'dgchat',
      room,
      LiveKitBackend(
        livekitServiceUrl: jwtBase.toString(),
        livekitAlias: roomId,
        // Media is TLS to our own SFU; rooms themselves are not end-to-end
        // encrypted in MVP 1, and pretending the calls are would be theatre.
        e2eeEnabled: false,
      ),
      'm.call',
      'm.room',
      preShareKey: false,
    );
    await groupCall.enter();

    if (ring) {
      // Fire-and-forget: the call must not fail because a notification did.
      unawaited(
        room
            .sendRtcNotification(
              type: RtcNotificationType.ring,
              mentionRoom: true,
            )
            .catchError((_) => null),
      );
    }

    lk.Room? lkRoom;
    try {
      final grant = await _fetchSfuGrant(jwtBase, roomId);
      lkRoom = lk.Room(
        // Both stay off deliberately. adaptiveStream pauses remote video by
        // the rendered element's reported size, and Flutter web's platform
        // views can report zero — which showed up as the phone's camera
        // reaching the SFU but never appearing in the browser. The bandwidth
        // these save matters at conference scale, not for this team.
        roomOptions: lk.RoomOptions(
          adaptiveStream: false,
          dynacast: false,
          // LiveKit's AudioManager owns the audio route on mobile and
          // PREFERS THE LOUDSPEAKER by default. Declaring the route here
          // makes it hold ours instead, so every time it re-applies the
          // session -- CallKit activating audio on answer, tracks starting --
          // it re-asserts earpiece-for-voice rather than dragging the call
          // back onto the speaker.
          defaultAudioOutputOptions: lk.AudioOutputOptions(
            // Earpiece for a one-to-one voice call, the way a phone call
            // sounds. A group -- or any video -- goes to the speaker: a
            // group call held to one ear is a call the room cannot hear.
            speakerOn: withVideo || room?.isDirectChat != true,
          ),
        ),
      );
      await lkRoom.connect(grant.url, grant.jwt);
      // Device failures past this point are survivable: joining muted with a
      // banner beats refusing the call. Only the connection itself is fatal.
      try {
        await lkRoom.localParticipant?.setMicrophoneEnabled(true);
      } catch (_) {}
      if (withVideo) {
        try {
          await lkRoom.localParticipant?.setCameraEnabled(true);
        } catch (_) {}
      }
    } catch (error) {
      // The connection can already be up when a later step fails — a denied
      // microphone after a successful connect left a silent zombie
      // participant in the room until the tab closed. Everything acquired is
      // released, in reverse.
      if (lkRoom != null) {
        try {
          await lkRoom.disconnect();
          await lkRoom.dispose();
        } catch (_) {
          // Releasing a broken connection must not mask the original error.
        }
      }
      await groupCall.leave().catchError((_) {});
      if (error is CallFailure) rethrow;
      // getUserMedia failures surface as platform exceptions; a denied
      // permission is the one the user can actually fix.
      final text = error.toString().toLowerCase();
      throw CallFailure(
        text.contains('permission') || text.contains('notallowed')
            ? CallFailureCode.permissionDenied
            : CallFailureCode.serverUnavailable,
      );
    }

    return _LiveKitCallController(
      roomId: roomId,
      matrixRoom: room,
      groupCall: groupCall,
      lkRoom: lkRoom,
      client: _client,
    );
  }

  @override
  Future<CallController> joinMeetingAsGuest(
    String target, {
    required String displayName,
    required bool withVideo,
  }) async {
    final grant = await fetchGuestGrant(
      _config.meetGuestUrl,
      _http,
      target,
      displayName: displayName,
    );

    lk.Room? lkRoom;
    try {
      lkRoom = lk.Room(
        // Same reasoning as the signed-in path: adaptiveStream judges by
        // rendered element size, which Flutter web can report as zero.
        roomOptions: lk.RoomOptions(
          adaptiveStream: false,
          dynacast: false,
          defaultAudioOutputOptions: lk.AudioOutputOptions(
            // A meeting is a room of people; the speaker is the only route
            // that makes sense for a guest.
            speakerOn: true,
          ),
        ),
      );
      await lkRoom.connect(grant.url, grant.jwt);
      try {
        await lkRoom.localParticipant?.setMicrophoneEnabled(true);
      } catch (_) {}
      if (withVideo) {
        try {
          await lkRoom.localParticipant?.setCameraEnabled(true);
        } catch (_) {}
      }
    } catch (error) {
      if (lkRoom != null) {
        try {
          await lkRoom.disconnect();
          await lkRoom.dispose();
        } catch (_) {}
      }
      if (error is CallFailure) rethrow;
      final text = error.toString().toLowerCase();
      throw CallFailure(
        text.contains('permission') || text.contains('notallowed')
            ? CallFailureCode.permissionDenied
            : CallFailureCode.serverUnavailable,
      );
    }

    return _LiveKitCallController(roomId: grant.roomId, lkRoom: lkRoom);
  }

  /// Exchanges a Matrix OpenID token for a LiveKit JWT at the token service.
  Future<({String url, String jwt})> _fetchSfuGrant(
    Uri base,
    String roomId,
  ) async {
    final OpenIdCredentials openId;
    try {
      openId = await _client.requestOpenIdToken(_client.userID!, {});
    } catch (_) {
      throw const CallFailure(CallFailureCode.serverUnavailable);
    }

    final endpoint = Uri.parse(
      '${base.toString().replaceAll(RegExp(r'/+$'), '')}/sfu/get',
    );
    final response = await _http.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'room': roomId,
        'openid_token': {
          'access_token': openId.accessToken,
          'expires_in': openId.expiresIn,
          'matrix_server_name': openId.matrixServerName,
          'token_type': openId.tokenType,
        },
        'device_id': _client.deviceID,
      }),
    );
    if (response.statusCode != 200) {
      throw const CallFailure(CallFailureCode.serverUnavailable);
    }
    final body = jsonDecode(response.body);
    final jwt = body is Map ? body['jwt'] : null;
    final url = body is Map ? body['url'] : null;
    if (jwt is! String || url is! String) {
      throw const CallFailure(CallFailureCode.serverUnavailable);
    }
    return (url: url, jwt: jwt);
  }
}

/// How long the app must have been away before coming back counts as an
/// interruption worth recovering from.
///
/// A cellular call, the thing this exists for, always takes longer than this.
/// A glance at another app usually does not, and recovery costs a beat of
/// silence, so it is not done for every return.
const audioRecoveryThreshold = Duration(seconds: 3);

/// Whether a return to the foreground after [pausedFor] should restart the
/// microphone. Null means the app never left.
bool needsAudioRecovery(Duration? pausedFor) =>
    pausedFor != null && pausedFor >= audioRecoveryThreshold;

class _LiveKitCallController
    with WidgetsBindingObserver
    implements CallController {
  _LiveKitCallController({
    required this.roomId,
    required lk.Room lkRoom,
    // Null for a guest: no Matrix account, so no membership to keep and no
    // room to resolve names from. Everything Matrix-flavoured in here has to
    // survive their absence.
    Room? matrixRoom,
    GroupCallSession? groupCall,
    Client? client,
  }) : _matrixRoom = matrixRoom,
       _groupCall = groupCall,
       _lkRoom = lkRoom,
       _client = client {
    _listener = _lkRoom.createListener();
    _listener.listen((event) {
      // Reactions ride the data channel and change nothing about the
      // snapshot, so they take their own path instead of a full re-emit.
      if (event is lk.DataReceivedEvent) {
        _handleData(event);
        return;
      }
      // Somebody new cannot have seen a hand that went up before they
      // arrived: the channel carries moments, not state. Say it again.
      if (event is lk.ParticipantConnectedEvent && _ownHandRaised) {
        unawaited(_publishSignal({'t': 'hand', 'up': true}));
      }
      _emit();
    });
    _startedAt = DateTime.now();
    // The connection is up by the time this controller exists, so this is the
    // first moment the microphone matters and the last one before the person
    // can switch away from the app.
    unawaited(_foregroundService.start());
    // For the phone call that takes the microphone away mid-call; see
    // didChangeAppLifecycleState.
    WidgetsBinding.instance.addObserver(this);
    _emit();
  }

  /// When the app last left the foreground during this call.
  DateTime? _pausedAt;

  /// The route the person asked for, re-asserted after an interruption.
  bool _speakerPreferred = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ended) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pausedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final pausedFor = _pausedAt == null
            ? null
            : DateTime.now().difference(_pausedAt!);
        _pausedAt = null;
        if (needsAudioRecovery(pausedFor)) unawaited(_recoverAudio());
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Brings the audio back after something else had it.
  ///
  /// A cellular call takes the microphone and the audio session. When it
  /// ends, the OS hands them back, but the capture that was running before
  /// does not restart on its own: the person is heard by nobody until they
  /// mute and unmute, which is exactly the toggle that restarts it. So that
  /// toggle is done here, on their behalf, and the speaker route they had
  /// chosen is asserted again for the same reason.
  Future<void> _recoverAudio() async {
    final local = _lkRoom.localParticipant;
    if (local == null ||
        _lkRoom.connectionState != lk.ConnectionState.connected) {
      return;
    }
    if (local.isMicrophoneEnabled()) {
      try {
        await local.setMicrophoneEnabled(false);
        await local.setMicrophoneEnabled(true);
      } catch (_) {
        // The old behaviour, then: the person toggles it by hand.
      }
    }
    if (!kIsWeb) {
      try {
        await lk.AudioManager.instance.setSpeakerOutputPreferred(
          _speakerPreferred,
        );
      } catch (_) {}
    }
    _emit();
  }

  final String roomId;
  final Room? _matrixRoom;
  final GroupCallSession? _groupCall;
  final lk.Room _lkRoom;
  final Client? _client;
  late final lk.EventsListener<lk.RoomEvent> _listener;
  final _updates = StreamController<CallSnapshot>.broadcast();
  final _reactions = StreamController<CallReaction>.broadcast();
  final _foregroundService = const CallForegroundService();

  /// The data-channel topic reactions travel on, namespaced so any future
  /// payload kind cannot be mistaken for one.
  static const _reactionTopic = 'in.digitalgrub.reaction';

  /// Hands and mute requests. Separate from reactions on purpose: a reaction
  /// is fire-and-forget decoration, and these change what the grid shows or
  /// what a microphone does.
  static const _signalTopic = 'in.digitalgrub.call';

  /// Identities with a hand up, pruned to the people still in the call.
  final _raisedHands = <String>{};
  bool _ownHandRaised = false;

  DateTime? _startedAt;
  bool _ended = false;
  CallSnapshot _current = const CallSnapshot(
    roomId: '',
    state: CallConnectionState.connecting,
    participants: [],
    micEnabled: true,
    cameraEnabled: false,
  );

  @override
  Stream<CallSnapshot> get changes async* {
    yield _current;
    yield* _updates.stream;
  }

  @override
  CallSnapshot get current => _current;

  void _emit() {
    if (_ended) return;
    final state = switch (_lkRoom.connectionState) {
      lk.ConnectionState.connected => CallConnectionState.connected,
      lk.ConnectionState.reconnecting => CallConnectionState.reconnecting,
      lk.ConnectionState.disconnected => CallConnectionState.ended,
      _ => CallConnectionState.connecting,
    };
    // Belt and braces with hangUp. A call the other side dropped while this
    // phone was in another app would otherwise keep an "in a call"
    // notification standing until the person came back to notice it.
    if (state == CallConnectionState.ended) {
      unawaited(_foregroundService.stop());
    }

    // A hand belongs to a person in the call. Somebody who leaves takes
    // theirs with them, or the list would keep asking for a turn on behalf
    // of somebody long gone.
    _raisedHands.retainAll(
      _lkRoom.remoteParticipants.values.map((p) => p.identity).toSet(),
    );
    final participants = <CallParticipantView>[
      if (_lkRoom.localParticipant != null)
        ..._mapParticipant(_lkRoom.localParticipant!, isLocal: true),
      for (final participant in _lkRoom.remoteParticipants.values)
        ..._mapParticipant(participant, isLocal: false),
    ];

    _current = CallSnapshot(
      roomId: roomId,
      state: state,
      participants: participants,
      micEnabled: _lkRoom.localParticipant?.isMicrophoneEnabled() ?? false,
      canModerate: _matrixRoom?.canKick ?? false,
      // No Matrix room means a meeting guest, and a meeting is a group.
      isGroup: _matrixRoom == null || !_matrixRoom!.isDirectChat,
      cameraEnabled: _lkRoom.localParticipant?.isCameraEnabled() ?? false,
      isScreenSharing:
          _lkRoom.localParticipant?.isScreenShareEnabled() ?? false,
      startedAt: _startedAt,
    );
    _updates.add(_current);
  }

  /// One tile for the person, plus one for each screen they are sharing.
  ///
  /// A camera and a shared screen are two separate video publications on the
  /// same participant, so they cannot share a tile: the old code stopped at
  /// the first non-muted video and would have shown a shared screen where the
  /// face belonged, or hidden the screen behind the camera.
  List<CallParticipantView> _mapParticipant(
    lk.Participant participant, {
    required bool isLocal,
  }) {
    lk.VideoTrack? camera;
    final screens = <lk.VideoTrack>[];
    for (final publication in participant.videoTrackPublications) {
      final track = publication.track;
      if (track is! lk.VideoTrack || publication.muted) continue;
      if (publication.isScreenShare) {
        screens.add(track);
      } else {
        camera ??= track;
      }
    }
    final name = _displayNameFor(participant, isLocal: isLocal);
    final hasAudio = participant.audioTrackPublications.any((p) => !p.muted);
    return [
      CallParticipantView(
        id: participant.identity,
        displayName: name,
        isLocal: isLocal,
        hasAudio: hasAudio,
        hasVideo: camera != null,
        isSpeaking: participant.isSpeaking,
        videoTrack: camera,
        handRaised: isLocal
            ? _ownHandRaised
            : _raisedHands.contains(participant.identity),
      ),
      for (var i = 0; i < screens.length; i++)
        CallParticipantView(
          // A distinct id so the grid keys the screen tile apart from the
          // face tile of the same participant.
          id: '${participant.identity}#screen$i',
          displayName: name,
          isLocal: isLocal,
          hasAudio: false,
          hasVideo: true,
          isSpeaking: false,
          videoTrack: screens[i],
          isScreenShare: true,
        ),
    ];
  }

  /// The SFU identity is the Matrix user id, suffixed by the token service
  /// with the device. Mapping it back through the room membership gives the
  /// same display name the rest of the app shows.
  String _displayNameFor(lk.Participant participant, {required bool isLocal}) {
    final matrixRoom = _matrixRoom;
    final userId = _client?.userID;
    if (isLocal && matrixRoom != null && userId != null) {
      return matrixRoom
          .unsafeGetUserFromMemoryOrFallback(userId)
          .calcDisplayname();
    }
    var identity = participant.identity;
    final slash = identity.indexOf('/');
    if (slash > 0) identity = identity.substring(0, slash);
    if (identity.startsWith('@')) {
      if (matrixRoom != null) {
        return matrixRoom
            .unsafeGetUserFromMemoryOrFallback(identity)
            .calcDisplayname();
      }
      // A guest has no room to resolve names from; the localpart reads
      // better than a full Matrix id in a call grid.
      final bare = identity.substring(1);
      final colon = bare.indexOf(':');
      return participant.name.isNotEmpty
          ? participant.name
          : (colon > 0 ? bare.substring(0, colon) : bare);
    }
    return participant.name.isNotEmpty ? participant.name : identity;
  }

  @override
  Future<void> setMicEnabled(bool enabled) async {
    await _lkRoom.localParticipant?.setMicrophoneEnabled(enabled);
    _emit();
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    await _lkRoom.localParticipant?.setCameraEnabled(enabled);
    _emit();
  }

  @override
  Future<void> switchCamera() async {
    final local = _lkRoom.localParticipant;
    if (local == null) return;
    for (final publication in local.videoTrackPublications) {
      final track = publication.track;
      if (track is lk.LocalVideoTrack) {
        // flutter_webrtc's helper flips between front and back without
        // renegotiating the track.
        await webrtc.Helper.switchCamera(track.mediaStreamTrack);
        break;
      }
    }
  }

  @override
  Future<void> setSpeakerphone(bool enabled) async {
    if (kIsWeb) return;
    _speakerPreferred = enabled;
    // Through LiveKit's AudioManager, never around it. The manager re-applies
    // its own preference whenever the session is reconfigured, so a route set
    // behind its back (the old webrtc.Helper call) survived only until the
    // next re-apply -- which on iOS is CallKit activating audio on answer,
    // i.e. the first seconds of every answered call.
    await lk.AudioManager.instance.setSpeakerOutputPreferred(enabled);
  }

  @override
  Stream<CallReaction> get reactions => _reactions.stream;

  @override
  Future<void> sendReaction(String emoji) async {
    // The allowlist is enforced on BOTH ends: here so this client cannot be
    // coaxed into sending arbitrary content, and on receive so nobody
    // else's client can put it on our screen.
    if (!allowedCallReactions.contains(emoji)) return;
    final local = _lkRoom.localParticipant;
    if (local == null) return;
    await local.publishData(
      utf8.encode(jsonEncode({'e': emoji})),
      reliable: true,
      topic: _reactionTopic,
    );
    // The SFU does not echo data back to its sender, so the sender's own
    // reaction is raised locally.
    if (!_reactions.isClosed) {
      _reactions.add(
        CallReaction(
          emoji: emoji,
          senderName: _displayNameFor(local, isLocal: true),
          isLocal: true,
        ),
      );
    }
  }

  Future<void> _publishSignal(Map<String, Object?> message) async {
    final local = _lkRoom.localParticipant;
    if (local == null) return;
    try {
      await local.publishData(
        utf8.encode(jsonEncode(message)),
        reliable: true,
        topic: _signalTopic,
      );
    } catch (_) {
      // A signal that did not go out is a hand nobody saw; the call itself
      // is unaffected and must stay that way.
    }
  }

  @override
  Future<void> setHandRaised(bool raised) async {
    if (_ownHandRaised == raised) return;
    _ownHandRaised = raised;
    _emit();
    await _publishSignal({'t': 'hand', 'up': raised});
  }

  @override
  Future<void> requestMute({String? participantId}) async {
    // Checked here as well as on receipt. Here so this client cannot be
    // coaxed into asking; there so nobody else's client can be.
    if (!(_matrixRoom?.canKick ?? false)) return;
    await _publishSignal({'t': 'mute', 'to': participantId ?? '*'});
  }

  /// Whether [sender] moderates the Matrix room behind this call.
  ///
  /// The SFU identity is the Matrix id plus a device suffix; the room's own
  /// power levels decide the rest. A guest call has no room, so nobody
  /// moderates it and no request is honoured -- a meeting link must not be a
  /// way to mute strangers.
  bool _senderCanModerate(lk.Participant sender) {
    final room = _matrixRoom;
    if (room == null) return false;
    var identity = sender.identity;
    final slash = identity.indexOf('/');
    if (slash > 0) identity = identity.substring(0, slash);
    if (!identity.startsWith('@')) return false;
    final levels = room.getState(EventTypes.RoomPowerLevels)?.content;
    final kick = levels?['kick'];
    final required = kick is int ? kick : 50;
    return room.getPowerLevelByUserId(identity) >= PowerLevel(required);
  }

  void _handleSignal(lk.DataReceivedEvent event) {
    // Written by another participant's client: data, not instructions.
    final sender = event.participant;
    if (sender == null) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(event.data));
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    switch (decoded['t']) {
      case 'hand':
        if (decoded['up'] == true) {
          _raisedHands.add(sender.identity);
        } else {
          _raisedHands.remove(sender.identity);
        }
        _emit();
      case 'mute':
        final to = decoded['to'];
        final mine = _lkRoom.localParticipant?.identity;
        if (to != '*' && to != mine) return;
        if (!_senderCanModerate(sender)) return;
        // Muting is the whole of what a moderator can do to you here: no
        // camera, no kick, no unmute. The microphone stays yours to turn
        // back on.
        unawaited(setMicEnabled(false));
    }
  }

  void _handleData(lk.DataReceivedEvent event) {
    if (event.topic == _signalTopic) {
      _handleSignal(event);
      return;
    }
    if (event.topic != _reactionTopic) return;
    // Sent by another participant's client: data, not instructions. Anything
    // malformed or outside the fixed set is dropped without comment.
    final sender = event.participant;
    if (sender == null) return;
    try {
      final decoded = jsonDecode(utf8.decode(event.data));
      final emoji = decoded is Map ? decoded['e'] : null;
      if (emoji is! String || !allowedCallReactions.contains(emoji)) return;
      if (_reactions.isClosed) return;
      _reactions.add(
        CallReaction(
          emoji: emoji,
          senderName: _displayNameFor(sender, isLocal: false),
          isLocal: false,
        ),
      );
    } catch (_) {
      // Not a reaction; nothing to do.
    }
  }

  @override
  Future<void> setScreenShareEnabled(bool enabled) async {
    final local = _lkRoom.localParticipant;
    if (local == null) return;
    // Web only for now. A phone capturing its whole screen needs a foreground
    // service on Android and a ReplayKit broadcast extension on iOS, each with
    // its own native plumbing and its own store-review surface; those ship as
    // their own releases. The control is hidden off-web, so this guard is the
    // backstop rather than the gate.
    if (!kIsWeb) {
      debugPrint('dg-call: screen share is web-only in this build');
      return;
    }
    await local.setScreenShareEnabled(enabled);
    _emit();
  }

  /// Clears our call membership, retrying once.
  ///
  /// Errors were swallowed here, which is the wrong trade: a silent failure
  /// is not a smaller problem than a loud one, it is the same problem with
  /// the evidence removed, and it leaves a phantom call on everyone's
  /// screen. One retry covers the ordinary case -- a request lost on a
  /// network that is already dropping -- and anything worse is logged.
  Future<void> _leaveGroupCall() async {
    final call = _groupCall;
    if (call == null) return;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await call.leave();
        return;
      } catch (error) {
        if (attempt == 1) {
          debugPrint(
            'dg-call: could not clear call membership, the room will show a '
            'phantom call until it expires: $error',
          );
        }
      }
    }
  }

  @override
  Future<void> hangUp() async {
    if (_ended) return;
    _ended = true;
    WidgetsBinding.instance.removeObserver(this);
    // First, not last: a notification that outlives its call can only be
    // cleared by force-stopping the app, so it goes before anything that
    // might throw on the way out.
    await _foregroundService.stop();
    // Stop any screen share so the browser drops its "sharing your screen"
    // banner when the call ends.
    if (kIsWeb && (_lkRoom.localParticipant?.isScreenShareEnabled() ?? false)) {
      await setScreenShareEnabled(false).catchError((_) {});
    }
    await _listener.dispose();
    // Leave Matrix FIRST, while the client is still healthy. The membership
    // event disappearing is the only thing that tells everyone else this
    // participant is gone -- media dropping is invisible to them. Doing it
    // after tearing LiveKit down meant a failure here left the membership
    // standing, and the room kept offering "Join" to a call nobody was in
    // until the membership expired six minutes later.
    await _leaveGroupCall();
    await _lkRoom.disconnect();
    await _lkRoom.dispose();
    _updates.add(
      CallSnapshot(
        roomId: roomId,
        state: CallConnectionState.ended,
        participants: const [],
        micEnabled: false,
        cameraEnabled: false,
        startedAt: _startedAt,
      ),
    );
    await _updates.close();
    await _reactions.close();
  }
}

/// WebRTC primitives for the SDK's call module.
///
/// The livekit backend never opens peer connections itself — media is the
/// livekit client's job — but the module's contract wants the primitives, and
/// flutter_webrtc is already here as livekit's own engine.
class _CallWebRTCDelegate implements WebRTCDelegate {
  @override
  rtc.MediaDevices get mediaDevices => webrtc.navigator.mediaDevices;

  @override
  Future<rtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration, [
    Map<String, dynamic> constraints = const {},
  ]) => webrtc.createPeerConnection(configuration, constraints);

  @override
  bool get isWeb => kIsWeb;

  @override
  bool get canHandleNewCall => true;

  @override
  EncryptionKeyProvider? get keyProvider => null;

  @override
  Future<void> playRingtone() async {}

  @override
  Future<void> stopRingtone() async {}

  @override
  Future<void> registerListeners(CallSession session) async {}

  @override
  Future<void> handleNewCall(CallSession session) async {}

  @override
  Future<void> handleCallEnded(CallSession session) async {}

  @override
  Future<void> handleMissedCall(CallSession session) async {}

  @override
  Future<void> handleNewGroupCall(GroupCallSession groupCall) async {}

  @override
  Future<void> handleGroupCallEnded(GroupCallSession groupCall) async {}
}

/// Trades a meeting code and a display name for call access.
///
/// No Matrix credentials go over this call — a guest has none, which is also
/// why this is a plain function: it must work before any client exists. The
/// server decides whether the code names a meeting; a team room or a dead
/// code comes back 404 and surfaces as "room not found".
@visibleForTesting
Future<({String url, String jwt, String roomId})> fetchGuestGrant(
  Uri? base,
  http.Client httpClient,
  String target, {
  required String displayName,
}) async {
  if (base == null) throw const CallFailure(CallFailureCode.notConfigured);
  final endpoint = Uri.parse(
    '${base.toString().replaceAll(RegExp(r'/+$'), '')}/token',
  );
  final http.Response response;
  try {
    response = await httpClient.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': target, 'name': displayName}),
    );
  } catch (_) {
    throw const CallFailure(CallFailureCode.serverUnavailable);
  }
  if (response.statusCode == 404) {
    throw const CallFailure(CallFailureCode.roomNotFound);
  }
  if (response.statusCode != 200) {
    throw const CallFailure(CallFailureCode.serverUnavailable);
  }
  final body = jsonDecode(response.body);
  final jwt = body is Map ? body['jwt'] : null;
  final url = body is Map ? body['url'] : null;
  final roomId = body is Map ? body['room_id'] : null;
  if (jwt is! String || url is! String || roomId is! String) {
    throw const CallFailure(CallFailureCode.serverUnavailable);
  }
  return (url: url, jwt: jwt, roomId: roomId);
}
