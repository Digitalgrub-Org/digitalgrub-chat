import 'package:dg_chat/features/meetings/data/matrix_meeting_repository.dart';
import 'package:dg_chat/features/meetings/domain/meeting_repository.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final meetingRepositoryProvider = FutureProvider<MeetingRepository>((
  ref,
) async {
  return MatrixMeetingRepository(await ref.watch(matrixClientProvider.future));
});

/// The address a meeting is shared as. One place, because the link IS the
/// product surface of a meeting and it must never drift between the copy
/// button, the email body and the router. New meetings share their short
/// code; the room-id form remains only so links minted before codes existed
/// keep working.
String meetingLink(Meeting meeting) => meeting.code != null
    ? 'https://chat.example.com/meet/${meeting.code}'
    : 'https://chat.example.com/meet/${Uri.encodeComponent(meeting.roomId)}';
