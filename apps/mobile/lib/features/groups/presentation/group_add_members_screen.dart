import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/contacts/application/user_search_controller.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/features/groups/application/group_providers.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Picks additional members for an existing group and pops the chosen Matrix
/// user ids. People already joined or invited are filtered out so the caller
/// never sends a redundant invite.
class GroupAddMembersScreen extends ConsumerStatefulWidget {
  const GroupAddMembersScreen({required this.roomId, super.key});

  final String roomId;

  @override
  ConsumerState<GroupAddMembersScreen> createState() =>
      _GroupAddMembersScreenState();
}

class _GroupAddMembersScreenState extends ConsumerState<GroupAddMembersScreen> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(userSearchControllerProvider);
    final controller = ref.read(userSearchControllerProvider.notifier);
    final group = ref.watch(groupDetailsProvider(widget.roomId)).valueOrNull;
    final existing =
        group?.members.map((member) => member.userId).toSet() ??
        const <String>{};
    final remainingSeats = group == null
        ? maxGroupMembers
        : group.remainingSeats - _selected.length;
    final results = search.results
        .where((person) => !existing.contains(person.userId))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.addMembers),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.pop(context, _selected.toList()),
            child: Text(context.l10n.addPeople),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: SearchBar(
              autoFocus: true,
              hintText: context.l10n.peopleSearchHint,
              leading: const Icon(Icons.search_rounded),
              onChanged: controller.setQuery,
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.l10n.selectedCount(_selected.length),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          if (search.isSearching) const LinearProgressIndicator(),
          Expanded(
            child: _AddMemberResults(
              query: search.query,
              isSearching: search.isSearching,
              results: results,
              selected: _selected,
              hasSeats: remainingSeats > 0,
              onToggle: (userId) {
                setState(() {
                  if (!_selected.remove(userId)) {
                    if (remainingSeats <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.l10n.groupMemberLimitReached(
                              maxGroupMembers,
                            ),
                          ),
                        ),
                      );
                      return;
                    }
                    _selected.add(userId);
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMemberResults extends StatelessWidget {
  const _AddMemberResults({
    required this.query,
    required this.isSearching,
    required this.results,
    required this.selected,
    required this.hasSeats,
    required this.onToggle,
  });

  final String query;
  final bool isSearching;
  final List<UserSearchResult> results;
  final Set<String> selected;
  final bool hasSeats;
  final void Function(String userId) onToggle;

  @override
  Widget build(BuildContext context) {
    if (query.length < 2) {
      return _Message(
        icon: Icons.person_search_rounded,
        message: context.l10n.peopleSearchInstructions,
      );
    }
    if (!isSearching && results.isEmpty) {
      return _Message(
        icon: Icons.search_off_rounded,
        message: context.l10n.noPeopleFound,
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(indent: 72),
      itemBuilder: (context, index) {
        final person = results[index];
        final isSelected = selected.contains(person.userId);
        return CheckboxListTile(
          value: isSelected,
          onChanged: !isSelected && !hasSeats
              ? null
              : (_) => onToggle(person.userId),
          controlAffinity: ListTileControlAffinity.trailing,
          secondary: ProfileAvatar(
            label: person.displayName,
            imageUrl: person.avatarUrl,
            httpHeaders: person.avatarHeaders,
          ),
          title: Text(person.displayName),
          subtitle: Text(person.userId),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
