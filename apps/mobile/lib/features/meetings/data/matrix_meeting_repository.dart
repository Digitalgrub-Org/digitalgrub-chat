import 'dart:math';

import 'package:dg_chat/features/meetings/domain/meeting_repository.dart';
import 'package:matrix/matrix.dart';

class MatrixMeetingRepository implements MeetingRepository {
  MatrixMeetingRepository(this._client, {Random? random})
    : _random = random ?? Random.secure();

  /// Marks a room as having been created as a meeting, so clients can treat
  /// it differently from an ordinary group where that ever matters.
  static const meetingMarkerType = 'in.digitalgrub.meeting';

  /// Lowercase letters minus the lookalikes, because these codes get read
  /// aloud and typed from a phone screen.
  static const _codeAlphabet = 'abcdefghjkmnpqrstuvwxyz';

  final Client _client;
  final Random _random;

  String get _serverName {
    final userId = _client.userID ?? '';
    final colon = userId.indexOf(':');
    return colon == -1 ? userId : userId.substring(colon + 1);
  }

  /// Meet-shaped: `abc-defg-hij`. The alphabet is 23 letters, so ten of them
  /// give ~4×10¹³ combinations — collisions are lottery events, but the
  /// create path still retries a fresh code if the alias is somehow taken.
  String _newCode() {
    String run(int length) => String.fromCharCodes(
      List.generate(
        length,
        (_) => _codeAlphabet.codeUnitAt(_random.nextInt(_codeAlphabet.length)),
      ),
    );
    return '${run(3)}-${run(4)}-${run(3)}';
  }

  @override
  Future<Meeting> createMeeting(String title) async {
    final name = title.trim();
    MatrixException? lastAliasError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final code = _newCode();
      try {
        final roomId = await _client.createRoom(
          name: name,
          // publicChat is what makes the link the invitation: join rules end
          // up public, so any account on this homeserver can enter by opening
          // it. Visibility stays private — joinable by code is not the same
          // as advertised in a directory.
          preset: CreateRoomPreset.publicChat,
          visibility: Visibility.private,
          // The short code is a room alias, so the server itself is the code
          // directory and resolving one is a standard lookup.
          roomAliasName: code,
          initialState: [
            StateEvent(type: meetingMarkerType, content: const {}),
          ],
        );
        return Meeting(roomId: roomId, title: name, code: code);
      } on MatrixException catch (error) {
        if (error.error == MatrixError.M_ROOM_IN_USE) {
          lastAliasError = error;
          continue;
        }
        throw _mapFailure(error);
      } catch (_) {
        throw const MeetingFailure(MeetingFailureCode.serverUnavailable);
      }
    }
    throw lastAliasError == null
        ? const MeetingFailure(MeetingFailureCode.serverUnavailable)
        : _mapFailure(lastAliasError);
  }

  @override
  Future<String> ensureJoined(String target) async {
    // Older links carry the raw room id; new ones carry the short code,
    // which lives server-side as the alias #<code>:<server>.
    final String roomId;
    if (target.startsWith('!')) {
      roomId = target;
    } else {
      try {
        final alias = '#$target:$_serverName';
        roomId =
            (await _client.getRoomIdByAlias(alias)).roomId ??
            (throw const MeetingFailure(MeetingFailureCode.notJoinable));
      } on MeetingFailure {
        rethrow;
      } on MatrixException catch (error) {
        throw switch (error.error) {
          MatrixError.M_UNKNOWN_TOKEN => const MeetingFailure(
            MeetingFailureCode.sessionExpired,
          ),
          _ => const MeetingFailure(MeetingFailureCode.notJoinable),
        };
      } catch (_) {
        throw const MeetingFailure(MeetingFailureCode.serverUnavailable);
      }
    }

    await _client.roomsLoading;
    final room = _client.getRoomById(roomId);
    if (room != null && room.membership == Membership.join) return roomId;
    try {
      await _client.joinRoom(roomId);
      // The joined room has to land in local state before a call screen can
      // open a timeline or membership on it.
      await _client.waitForRoomInSync(roomId, join: true);
      return roomId;
    } on MatrixException catch (error) {
      throw switch (error.error) {
        MatrixError.M_UNKNOWN_TOKEN => const MeetingFailure(
          MeetingFailureCode.sessionExpired,
        ),
        MatrixError.M_FORBIDDEN || MatrixError.M_NOT_FOUND =>
          const MeetingFailure(MeetingFailureCode.notJoinable),
        _ => const MeetingFailure(MeetingFailureCode.serverUnavailable),
      };
    } catch (_) {
      throw const MeetingFailure(MeetingFailureCode.serverUnavailable);
    }
  }

  MeetingFailure _mapFailure(MatrixException error) {
    return switch (error.error) {
      MatrixError.M_UNKNOWN_TOKEN => const MeetingFailure(
        MeetingFailureCode.sessionExpired,
      ),
      _ => const MeetingFailure(MeetingFailureCode.serverUnavailable),
    };
  }
}
