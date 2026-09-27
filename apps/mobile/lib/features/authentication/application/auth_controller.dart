import 'dart:async';

import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/core/storage/hidden_event_store.dart';
import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/features/authentication/data/matrix_auth_repository.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/notifications/application/push_providers.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  return MatrixAuthRepository(
    client: await ref.watch(matrixClientProvider.future),
    config: ref.watch(appConfigProvider),
    outgoingMessageStore: await ref.watch(outgoingMessageStoreProvider.future),
    hiddenEventStore: ref.watch(hiddenEventStoreProvider),
  );
});

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  StreamSubscription<AuthSession?>? _sessionSubscription;

  @override
  Future<AuthSession?> build() async {
    final repository = await ref.watch(authRepositoryProvider.future);
    _sessionSubscription = repository.sessionChanges.listen((session) {
      if (!state.isLoading) state = AsyncData(session);
    });
    ref.onDispose(() => unawaited(_sessionSubscription?.cancel()));
    return repository.restoreSession();
  }

  Future<AuthSession?> login({
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      final repository = await ref.read(authRepositoryProvider.future);
      final session = await repository.login(
        username: username,
        password: password,
      );
      state = AsyncData(session);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }

  Future<AuthSession?> register(RegistrationRequest request) async {
    state = const AsyncLoading();
    try {
      final repository = await ref.read(authRepositoryProvider.future);
      final session = await repository.register(request);
      state = AsyncData(session);
      return session;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }

  /// Deletes the account on the homeserver and clears local state. Returns
  /// null on success, or the failure to show the user.
  Future<AuthFailure?> deleteAccount(String password) async {
    // A failed deletion must leave the account signed in. Emitting a null
    // session would look like a completed sign-out and route the user away
    // from the confirmation they are still using.
    final currentSession = state.valueOrNull;
    state = const AsyncLoading();
    try {
      // Same ordering as logout: drop the pusher while the token still works.
      await ref.read(pushRegistrationServiceProvider).stop();
      final repository = await ref.read(authRepositoryProvider.future);
      await repository.deleteAccount(password: password);
      state = const AsyncData(null);
      return null;
    } on AuthFailure catch (failure) {
      state = AsyncData(currentSession);
      return failure;
    } catch (_) {
      state = AsyncData(currentSession);
      return const AuthFailure(AuthFailureCode.serverUnavailable);
    }
  }

  Future<bool> logout() async {
    state = const AsyncLoading();
    try {
      // Drop this device's pusher before the token is invalidated, otherwise
      // the account keeps a pusher that can never be removed from here.
      await ref.read(pushRegistrationServiceProvider).stop();
      final repository = await ref.read(authRepositoryProvider.future);
      await repository.logout();
      state = const AsyncData(null);
      return true;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return false;
    }
  }
}
