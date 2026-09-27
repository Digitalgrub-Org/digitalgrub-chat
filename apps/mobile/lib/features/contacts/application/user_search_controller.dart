import 'dart:async';

import 'package:dg_chat/features/contacts/data/matrix_user_repository.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final userRepositoryProvider = FutureProvider<UserRepository>((ref) async {
  return MatrixUserRepository(await ref.watch(matrixClientProvider.future));
});

final userSearchControllerProvider =
    StateNotifierProvider.autoDispose<UserSearchController, UserSearchState>((
      ref,
    ) {
      return UserSearchController(
        () => ref.read(userRepositoryProvider.future),
      );
    });

class UserSearchState {
  const UserSearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
    this.startingUserId,
    this.failure,
  });

  final String query;
  final List<UserSearchResult> results;
  final bool isSearching;
  final String? startingUserId;
  final UserFailure? failure;

  UserSearchState copyWith({
    String? query,
    List<UserSearchResult>? results,
    bool? isSearching,
    String? startingUserId,
    bool clearStartingUserId = false,
    UserFailure? failure,
    bool clearFailure = false,
  }) {
    return UserSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      startingUserId: clearStartingUserId
          ? null
          : startingUserId ?? this.startingUserId,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }
}

class UserSearchController extends StateNotifier<UserSearchState> {
  UserSearchController(this._loadRepository) : super(const UserSearchState());

  static const debounceDuration = Duration(milliseconds: 350);

  final Future<UserRepository> Function() _loadRepository;
  Timer? _debounce;
  int _requestGeneration = 0;

  void setQuery(String value) {
    final query = value.trim();
    _debounce?.cancel();
    final generation = ++_requestGeneration;
    if (query.length < 2) {
      state = UserSearchState(query: query);
      return;
    }
    state = state.copyWith(query: query, isSearching: true, clearFailure: true);
    _debounce = Timer(debounceDuration, () => _search(query, generation));
  }

  Future<void> _search(String query, int generation) async {
    try {
      final repository = await _loadRepository();
      final results = await repository.search(query);
      if (!mounted || generation != _requestGeneration) return;
      state = state.copyWith(results: results, isSearching: false);
    } on UserFailure catch (failure) {
      if (!mounted || generation != _requestGeneration) return;
      state = state.copyWith(
        results: const [],
        isSearching: false,
        failure: failure,
      );
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      state = state.copyWith(
        results: const [],
        isSearching: false,
        failure: const UserFailure(UserFailureCode.unknown),
      );
    }
  }

  Future<String?> startConversation(String userId) async {
    if (state.startingUserId != null) return null;
    state = state.copyWith(startingUserId: userId, clearFailure: true);
    try {
      final repository = await _loadRepository();
      return await repository.startDirectConversation(userId);
    } on UserFailure catch (failure) {
      if (mounted) state = state.copyWith(failure: failure);
      return null;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          failure: const UserFailure(UserFailureCode.unknown),
        );
      }
      return null;
    } finally {
      if (mounted) state = state.copyWith(clearStartingUserId: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
