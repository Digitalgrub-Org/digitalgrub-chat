import 'dart:async';

import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/features/groups/data/matrix_group_repository.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final groupRepositoryProvider = FutureProvider<GroupRepository>((ref) async {
  return MatrixGroupRepository(await ref.watch(matrixClientProvider.future));
});

final groupDetailsProvider = StreamProvider.autoDispose
    .family<GroupDetails, String>((ref, roomId) async* {
      final repository = await ref.watch(groupRepositoryProvider.future);
      yield* repository.watchGroup(roomId);
    });

final newGroupControllerProvider =
    StateNotifierProvider.autoDispose<NewGroupController, NewGroupState>((ref) {
      return NewGroupController(
        () => ref.read(groupRepositoryProvider.future),
        () => ref.read(userRepositoryProvider.future),
      );
    });

class NewGroupState {
  const NewGroupState({
    this.query = '',
    this.results = const [],
    this.selected = const [],
    this.isSearching = false,
    this.isCreating = false,
    this.failure,
  });

  final String query;
  final List<UserSearchResult> results;
  final List<UserSearchResult> selected;
  final bool isSearching;
  final bool isCreating;
  final GroupFailure? failure;

  /// The creator always occupies one seat.
  int get remainingSeats => maxGroupMembers - 1 - selected.length;

  bool get isFull => remainingSeats <= 0;

  NewGroupState copyWith({
    String? query,
    List<UserSearchResult>? results,
    List<UserSearchResult>? selected,
    bool? isSearching,
    bool? isCreating,
    GroupFailure? failure,
    bool clearFailure = false,
  }) {
    return NewGroupState(
      query: query ?? this.query,
      results: results ?? this.results,
      selected: selected ?? this.selected,
      isSearching: isSearching ?? this.isSearching,
      isCreating: isCreating ?? this.isCreating,
      failure: clearFailure ? null : failure ?? this.failure,
    );
  }
}

class NewGroupController extends StateNotifier<NewGroupState> {
  NewGroupController(this._loadGroupRepository, this._loadUserRepository)
    : super(const NewGroupState());

  static const debounceDuration = Duration(milliseconds: 350);

  final Future<GroupRepository> Function() _loadGroupRepository;
  final Future<UserRepository> Function() _loadUserRepository;
  Timer? _debounce;
  int _requestGeneration = 0;

  void setQuery(String value) {
    final query = value.trim();
    _debounce?.cancel();
    final generation = ++_requestGeneration;
    if (query.length < 2) {
      state = state.copyWith(
        query: query,
        results: const [],
        isSearching: false,
        clearFailure: true,
      );
      return;
    }
    state = state.copyWith(query: query, isSearching: true, clearFailure: true);
    _debounce = Timer(debounceDuration, () => _search(query, generation));
  }

  Future<void> _search(String query, int generation) async {
    try {
      final repository = await _loadUserRepository();
      final results = await repository.search(query);
      if (!mounted || generation != _requestGeneration) return;
      state = state.copyWith(results: results, isSearching: false);
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      state = state.copyWith(
        results: const [],
        isSearching: false,
        failure: const GroupFailure(GroupFailureCode.serverUnavailable),
      );
    }
  }

  void toggleMember(UserSearchResult person) {
    final selected = [...state.selected];
    final index = selected.indexWhere(
      (candidate) => candidate.userId == person.userId,
    );
    if (index >= 0) {
      selected.removeAt(index);
    } else {
      if (state.isFull) {
        state = state.copyWith(
          failure: const GroupFailure(GroupFailureCode.memberLimitExceeded),
        );
        return;
      }
      selected.add(person);
    }
    state = state.copyWith(selected: selected, clearFailure: true);
  }

  bool isSelected(String userId) =>
      state.selected.any((person) => person.userId == userId);

  /// Returns the new room id, or null when creation failed. Concurrent calls
  /// are ignored so a double tap cannot create two groups.
  Future<String?> create({required String name, String? description}) async {
    if (state.isCreating) return null;
    if (state.selected.isEmpty) {
      state = state.copyWith(
        failure: const GroupFailure(GroupFailureCode.noMembersSelected),
      );
      return null;
    }

    state = state.copyWith(isCreating: true, clearFailure: true);
    try {
      final repository = await _loadGroupRepository();
      return await repository.createGroup(
        name: name,
        description: description,
        memberIds: state.selected
            .map((person) => person.userId)
            .toList(growable: false),
      );
    } on GroupFailure catch (failure) {
      if (mounted) state = state.copyWith(failure: failure);
      return null;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          failure: const GroupFailure(GroupFailureCode.unknown),
        );
      }
      return null;
    } finally {
      if (mounted) state = state.copyWith(isCreating: false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// The group's recent activity, loaded once per visit to the screen.
final groupActivityProvider = FutureProvider.autoDispose
    .family<List<GroupActivityEntry>, String>((ref, roomId) async {
      final repository = await ref.watch(groupRepositoryProvider.future);
      return repository.activity(roomId);
    });
