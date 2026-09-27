import 'package:dg_chat/features/profile/data/matrix_profile_repository.dart';
import 'package:dg_chat/features/profile/domain/profile_repository.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profileRepositoryProvider = FutureProvider<ProfileRepository>((
  ref,
) async {
  return MatrixProfileRepository(await ref.watch(matrixClientProvider.future));
});

final userProfileProvider = StreamProvider.autoDispose
    .family<UserProfile, String>((ref, userId) async* {
      final repository = await ref.watch(profileRepositoryProvider.future);
      yield* repository.watchProfile(userId);
    });

final blockedUsersProvider = StreamProvider.autoDispose<List<UserProfile>>((
  ref,
) async* {
  final repository = await ref.watch(profileRepositoryProvider.future);
  yield* repository.watchBlockedUsers();
});
