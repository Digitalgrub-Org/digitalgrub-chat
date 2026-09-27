import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/media/avatar_picker.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/groups/application/group_providers.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _MemberAction { remove, makeAdmin, makeModerator, makeMember }

class GroupDetailsScreen extends ConsumerWidget {
  const GroupDetailsScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupDetailsProvider(roomId));

    return group.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(context.l10n.groupDetails)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.groupDetails)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 44),
                const SizedBox(height: AppSpacing.md),
                Text(
                  error is GroupFailure &&
                          error.code == GroupFailureCode.roomNotFound
                      ? context.l10n.groupNotFound
                      : context.l10n.groupDetailsFailed,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: () => ref.invalidate(groupDetailsProvider(roomId)),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (details) => _GroupDetailsView(details: details),
    );
  }
}

class _GroupDetailsView extends ConsumerStatefulWidget {
  const _GroupDetailsView({required this.details});

  final GroupDetails details;

  @override
  ConsumerState<_GroupDetailsView> createState() => _GroupDetailsViewState();
}

class _GroupDetailsViewState extends ConsumerState<_GroupDetailsView> {
  bool _busy = false;

  GroupDetails get _details => widget.details;

  Future<void> _run(
    Future<void> Function(GroupRepository repository) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repository = await ref.read(groupRepositoryProvider.future);
      await action(repository);
    } on GroupFailure catch (failure) {
      if (mounted) _showMessage(_failureMessage(context, failure));
    } catch (_) {
      if (mounted) _showMessage(context.l10n.groupUpdateFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editName() async {
    final value = await _promptText(
      title: context.l10n.editGroupName,
      initialValue: _details.name,
      maxLength: maxGroupNameLength,
      isRequired: true,
    );
    if (value == null) return;
    await _run((repository) => repository.updateName(_details.roomId, value));
  }

  Future<void> _editDescription() async {
    final value = await _promptText(
      title: context.l10n.editGroupDescription,
      initialValue: _details.description,
      maxLength: maxGroupDescriptionLength,
      isRequired: false,
    );
    if (value == null) return;
    await _run(
      (repository) => repository.updateDescription(_details.roomId, value),
    );
  }

  Future<String?> _promptText({
    required String title,
    required String initialValue,
    required int maxLength,
    required bool isRequired,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _TextPromptDialog(
        title: title,
        initialValue: initialValue,
        maxLength: maxLength,
        isRequired: isRequired,
      ),
    );
  }

  Future<void> _changeAvatar() async {
    AvatarUpload? picked;
    try {
      picked = await ref.read(avatarPickerProvider).pick();
    } catch (_) {
      if (mounted) _showMessage(context.l10n.photoPickFailed);
      return;
    }
    if (picked == null) return;
    await _run(
      (repository) => repository.updateAvatar(_details.roomId, picked),
    );
  }

  Future<void> _removeAvatar() async {
    await _run((repository) => repository.updateAvatar(_details.roomId, null));
  }

  Future<void> _addMembers() async {
    final selected = await context.push<List<String>>(
      AppRoutes.groupAddMembersPath(_details.roomId),
    );
    if (selected == null || selected.isEmpty) return;
    await _run((repository) async {
      await repository.addMembers(_details.roomId, selected);
      if (mounted) _showMessage(context.l10n.invitationsSent);
    });
  }

  Future<void> _removeMember(GroupMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          context.l10n.removeMemberConfirmation(member.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      (repository) => repository.removeMember(_details.roomId, member.userId),
    );
  }

  Future<void> _setRole(GroupMember member, GroupRole role) async {
    await _run(
      (repository) =>
          repository.setMemberRole(_details.roomId, member.userId, role),
    );
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.l10n.leaveGroupConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.leave),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run((repository) async {
      await repository.leaveGroup(_details.roomId);
      if (mounted) context.go(AppRoutes.chats);
    });
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final permissions = details.permissions;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.groupDetails),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                ProfileAvatar(
                  label: details.name,
                  imageUrl: details.avatarUrl,
                  httpHeaders: details.avatarHeaders,
                  radius: 44,
                ),
                if (permissions.canEditMetadata) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _changeAvatar,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(context.l10n.changePhoto),
                      ),
                      if (details.avatarUrl != null)
                        TextButton(
                          onPressed: _busy ? null : _removeAvatar,
                          child: Text(context.l10n.removePhoto),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(
                  details.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.memberCount(details.memberCount),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notes_rounded),
            title: Text(
              details.description.isEmpty
                  ? context.l10n.noGroupDescription
                  : details.description,
            ),
            trailing: permissions.canEditMetadata
                ? const Icon(Icons.edit_outlined)
                : null,
            onTap: permissions.canEditMetadata && !_busy
                ? _editDescription
                : null,
          ),
          if (permissions.canEditMetadata)
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: Text(context.l10n.editGroupName),
              onTap: _busy ? null : _editName,
            ),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(context.l10n.groupActivity),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(
              AppRoutes.groupActivityPath(widget.details.roomId),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.members,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (permissions.canInvite && !details.isFull)
                  TextButton.icon(
                    onPressed: _busy ? null : _addMembers,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(context.l10n.addMembers),
                  ),
              ],
            ),
          ),
          for (final member in details.members)
            _MemberTile(
              member: member,
              permissions: permissions,
              enabled: !_busy,
              onRemove: () => _removeMember(member),
              onRoleSelected: (role) => _setRole(member, role),
            ),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.logout_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              context.l10n.leaveGroup,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: _busy ? null : _leaveGroup,
          ),
        ],
      ),
    );
  }
}

/// Owns its editing controller so the field is torn down with the dialog
/// route rather than while it still holds focus.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initialValue,
    required this.maxLength,
    required this.isRequired,
  });

  final String title;
  final String initialValue;
  final int maxLength;
  final bool isRequired;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          textCapitalization: TextCapitalization.sentences,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (widget.isRequired && text.isEmpty) {
              return context.l10n.groupNameRequired;
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(context, _controller.text.trim());
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.permissions,
    required this.enabled,
    required this.onRemove,
    required this.onRoleSelected,
  });

  final GroupMember member;
  final GroupPermissions permissions;
  final bool enabled;
  final VoidCallback onRemove;
  final void Function(GroupRole role) onRoleSelected;

  @override
  Widget build(BuildContext context) {
    // Own membership is managed through Leave, never through Remove.
    final canRemove = permissions.canRemove && !member.isSelf;
    final canChangeRole = permissions.canChangeRoles && !member.isSelf;
    final actions = <_MemberAction>[
      if (canChangeRole && member.role != GroupRole.admin)
        _MemberAction.makeAdmin,
      if (canChangeRole && member.role != GroupRole.moderator)
        _MemberAction.makeModerator,
      if (canChangeRole && member.role != GroupRole.member)
        _MemberAction.makeMember,
      if (canRemove) _MemberAction.remove,
    ];

    return ListTile(
      minTileHeight: 68,
      leading: ProfileAvatar(
        label: member.displayName,
        imageUrl: member.avatarUrl,
        httpHeaders: member.avatarHeaders,
      ),
      title: Text(
        member.isSelf
            ? '${member.displayName} (${context.l10n.you})'
            : member.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        member.userId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.push(AppRoutes.userProfilePath(member.userId)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (member.membership == GroupMembership.invited)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Chip(
                label: Text(context.l10n.invited),
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (member.role != GroupRole.member)
            Text(
              _roleLabel(context, member.role),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          if (actions.isNotEmpty)
            PopupMenuButton<_MemberAction>(
              enabled: enabled,
              tooltip: context.l10n.changeRole,
              onSelected: (action) => switch (action) {
                _MemberAction.remove => onRemove(),
                _MemberAction.makeAdmin => onRoleSelected(GroupRole.admin),
                _MemberAction.makeModerator => onRoleSelected(
                  GroupRole.moderator,
                ),
                _MemberAction.makeMember => onRoleSelected(GroupRole.member),
              },
              itemBuilder: (context) => [
                for (final action in actions)
                  PopupMenuItem(
                    value: action,
                    child: Text(switch (action) {
                      _MemberAction.remove => context.l10n.removeFromGroup,
                      _MemberAction.makeAdmin => context.l10n.roleAdmin,
                      _MemberAction.makeModerator => context.l10n.roleModerator,
                      _MemberAction.makeMember => context.l10n.roleMember,
                    }),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

String _roleLabel(BuildContext context, GroupRole role) => switch (role) {
  GroupRole.admin => context.l10n.roleAdmin,
  GroupRole.moderator => context.l10n.roleModerator,
  GroupRole.member => context.l10n.roleMember,
};

String _failureMessage(BuildContext context, GroupFailure failure) {
  return switch (failure.code) {
    GroupFailureCode.notPermitted => context.l10n.groupNotPermitted,
    GroupFailureCode.roomNotFound => context.l10n.groupNotFound,
    GroupFailureCode.memberLimitExceeded =>
      context.l10n.groupMemberLimitReached(maxGroupMembers),
    GroupFailureCode.noMembersSelected => context.l10n.selectAtLeastOneMember,
    GroupFailureCode.invalidName => context.l10n.groupNameRequired,
    GroupFailureCode.invalidDescription => context.l10n.groupDescriptionTooLong(
      maxGroupDescriptionLength,
    ),
    GroupFailureCode.rateLimited => context.l10n.rateLimited,
    GroupFailureCode.sessionExpired => context.l10n.sessionExpired,
    _ => context.l10n.groupUpdateFailed,
  };
}
