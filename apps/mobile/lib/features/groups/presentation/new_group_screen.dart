import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/features/groups/application/group_providers.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final controller = ref.read(newGroupControllerProvider.notifier);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (ref.read(newGroupControllerProvider).selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.selectAtLeastOneMember)),
      );
      return;
    }

    final description = _descriptionController.text.trim();
    final roomId = await controller.create(
      name: _nameController.text,
      description: description.isEmpty ? null : description,
    );

    if (!mounted) return;
    if (roomId == null) {
      final failure = ref.read(newGroupControllerProvider).failure;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_failureMessage(context, failure))),
      );
      return;
    }
    openConversation(context, roomId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newGroupControllerProvider);
    final controller = ref.read(newGroupControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.newGroup),
        bottom: state.isCreating
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Form(
              key: _formKey,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      enabled: !state.isCreating,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      maxLength: maxGroupNameLength,
                      decoration: InputDecoration(
                        labelText: context.l10n.groupNameLabel,
                        hintText: context.l10n.groupNameHint,
                        prefixIcon: const Icon(Icons.groups_rounded),
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';
                        if (name.isEmpty) return context.l10n.groupNameRequired;
                        if (name.length > maxGroupNameLength) {
                          return context.l10n.groupNameTooLong(
                            maxGroupNameLength,
                          );
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: _descriptionController,
                      enabled: !state.isCreating,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: maxGroupDescriptionLength,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: context.l10n.groupDescriptionLabel,
                        hintText: context.l10n.groupDescriptionHint,
                      ),
                      validator: (value) {
                        final description = value?.trim() ?? '';
                        if (description.length > maxGroupDescriptionLength) {
                          return context.l10n.groupDescriptionTooLong(
                            maxGroupDescriptionLength,
                          );
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            _SelectedMembers(
              selected: state.selected,
              onRemove: state.isCreating ? null : controller.toggleMember,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: SearchBar(
                hintText: context.l10n.peopleSearchHint,
                leading: const Icon(Icons.search_rounded),
                enabled: !state.isCreating,
                onChanged: controller.setQuery,
              ),
            ),
            if (state.isSearching) const LinearProgressIndicator(),
            Expanded(
              child: _MemberPicker(
                state: state,
                onToggle: state.isCreating ? null : controller.toggleMember,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.isCreating ? null : _create,
        icon: state.isCreating
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_rounded),
        label: Text(
          state.isCreating
              ? context.l10n.creatingGroup
              : context.l10n.createGroup,
        ),
      ),
    );
  }
}

class _SelectedMembers extends StatelessWidget {
  const _SelectedMembers({required this.selected, required this.onRemove});

  final List<UserSearchResult> selected;
  final void Function(UserSearchResult person)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (selected.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.selectedCount(selected.length),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final person in selected)
                InputChip(
                  avatar: ProfileAvatar(
                    label: person.displayName,
                    imageUrl: person.avatarUrl,
                    httpHeaders: person.avatarHeaders,
                    radius: 12,
                  ),
                  label: Text(person.displayName),
                  onDeleted: onRemove == null ? null : () => onRemove!(person),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberPicker extends StatelessWidget {
  const _MemberPicker({required this.state, required this.onToggle});

  final NewGroupState state;
  final void Function(UserSearchResult person)? onToggle;

  @override
  Widget build(BuildContext context) {
    if (state.failure?.code == GroupFailureCode.memberLimitExceeded) {
      return _PickerMessage(
        icon: Icons.groups_rounded,
        message: context.l10n.groupMemberLimitReached(maxGroupMembers),
      );
    }
    if (state.query.length < 2) {
      return _PickerMessage(
        icon: Icons.person_search_rounded,
        message: context.l10n.peopleSearchInstructions,
      );
    }
    if (!state.isSearching && state.results.isEmpty) {
      return _PickerMessage(
        icon: Icons.search_off_rounded,
        message: context.l10n.noPeopleFound,
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: state.results.length,
      separatorBuilder: (_, _) => const Divider(indent: 72),
      itemBuilder: (context, index) {
        final person = state.results[index];
        final selected = state.selected.any(
          (candidate) => candidate.userId == person.userId,
        );
        return CheckboxListTile(
          value: selected,
          onChanged: onToggle == null ? null : (_) => onToggle!(person),
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

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({required this.icon, required this.message});

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

String _failureMessage(BuildContext context, GroupFailure? failure) {
  return switch (failure?.code) {
    GroupFailureCode.invalidName => context.l10n.groupNameRequired,
    GroupFailureCode.invalidDescription => context.l10n.groupDescriptionTooLong(
      maxGroupDescriptionLength,
    ),
    GroupFailureCode.noMembersSelected => context.l10n.selectAtLeastOneMember,
    GroupFailureCode.memberLimitExceeded =>
      context.l10n.groupMemberLimitReached(maxGroupMembers),
    GroupFailureCode.notPermitted => context.l10n.groupNotPermitted,
    GroupFailureCode.rateLimited => context.l10n.rateLimited,
    GroupFailureCode.sessionExpired => context.l10n.sessionExpired,
    _ => context.l10n.groupCreationFailed,
  };
}
