import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:flutter/material.dart';

/// One activity entry, in words.
///
/// Shared rather than private to the activity screen: the same lines appear
/// inline in the conversation, and two copies of this would drift.
String groupActivityLine(BuildContext context, GroupActivityEntry entry) {
  final l10n = context.l10n;
  final name = entry.actorName;
  return switch (entry.kind) {
    GroupActivityKind.created => l10n.activityCreated(name),
    GroupActivityKind.joined => l10n.activityJoined(name),
    GroupActivityKind.left => l10n.activityLeft(name),
    GroupActivityKind.invited => l10n.activityInvited(
      name,
      entry.targetName ?? '',
    ),
    GroupActivityKind.removed => l10n.activityRemoved(
      name,
      entry.targetName ?? '',
    ),
    GroupActivityKind.renamed => l10n.activityRenamed(name, entry.detail ?? ''),
    GroupActivityKind.photoChanged => l10n.activityPhotoChanged(name),
    GroupActivityKind.callStarted => l10n.activityCallStarted(name),
    GroupActivityKind.pinsChanged => l10n.activityPinsChanged(name),
    GroupActivityKind.rolesChanged => l10n.activityRolesChanged(name),
  };
}

IconData groupActivityIcon(GroupActivityKind kind) => switch (kind) {
  GroupActivityKind.created => Icons.flag_outlined,
  GroupActivityKind.joined => Icons.person_add_alt_outlined,
  GroupActivityKind.left => Icons.logout_rounded,
  GroupActivityKind.invited => Icons.mail_outline_rounded,
  GroupActivityKind.removed => Icons.person_remove_outlined,
  GroupActivityKind.renamed => Icons.edit_outlined,
  GroupActivityKind.photoChanged => Icons.image_outlined,
  GroupActivityKind.callStarted => Icons.call_rounded,
  GroupActivityKind.pinsChanged => Icons.push_pin_outlined,
  GroupActivityKind.rolesChanged => Icons.admin_panel_settings_outlined,
};
