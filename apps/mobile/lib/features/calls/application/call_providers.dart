import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/features/calls/data/livekit_call_repository.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final callRepositoryProvider = FutureProvider<CallRepository>((ref) async {
  return LiveKitCallRepository(
    await ref.watch(matrixClientProvider.future),
    ref.watch(appConfigProvider),
  );
});

/// Rings for calls started by someone else, foreground only.
final incomingRingsProvider = StreamProvider<IncomingCallRing>((ref) async* {
  final repository = await ref.watch(callRepositoryProvider.future);
  yield* repository.incomingRings;
});

/// Calls running right now in rooms this account has joined.
///
/// This is what makes a missed ring recoverable: the ring itself is gone after
/// thirty seconds, but as long as somebody is still in the call there is
/// something to join.
final liveCallsProvider = StreamProvider<List<LiveCall>>((ref) async* {
  final repository = await ref.watch(callRepositoryProvider.future);
  yield* repository.liveCalls;
});

/// The room whose call this client is currently joining, between tapping
/// answer and the media coming up. The in-app ring consults it so a call you
/// are already walking into does not ring at you again from the sync.
final joiningCallRoomProvider = StateProvider<String?>((ref) => null);

/// The one call this client is in, or null. Held globally so the incoming
/// ring banner can stay quiet during a call, and so a second join attempt has
/// something to check.
final activeCallProvider = StateProvider<CallController?>((ref) => null);

/// The room ringing right now, or null when nothing is.
///
/// A ring arrives twice over: once through the sync, which raises the call
/// UI, and once as a push, which the gateway cannot label as a call — Sygnal
/// forwards a fixed set of fields and tweaks are not among them, and the
/// event type is stripped by the `event_id_only` push format that keeps
/// message types away from Google and Apple. So the client is the only place
/// that knows the push and the ring are the same thing.
final ringingRoomProvider = StateProvider<String?>((ref) => null);
