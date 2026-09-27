import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/features/admin/data/http_admin_repository.dart';
import 'package:dg_chat/features/admin/domain/admin_repository.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Create-user and reset-password, through the narrow admin service.
final adminRepositoryProvider = FutureProvider<AdminRepository>((ref) async {
  final client = await ref.watch(matrixClientProvider.future);
  return HttpAdminRepository(
    accessToken: () => client.accessToken,
    config: ref.watch(appConfigProvider),
  );
});

/// Whether this account is a server admin. Gates the admin entry in Settings.
///
/// autoDispose so a re-open asks again: an account made admin a minute ago
/// should not need an app restart to see the screen.
final isAdminProvider = FutureProvider.autoDispose<bool>((ref) async {
  final admin = await ref.watch(adminRepositoryProvider.future);
  return admin.isSelfAdmin();
});

/// Every account on the homeserver, for the admin roster.
final serverUsersProvider = FutureProvider.autoDispose<List<UserSearchResult>>((
  ref,
) async {
  final repository = await ref.watch(userRepositoryProvider.future);
  return repository.listServerUsers();
});
