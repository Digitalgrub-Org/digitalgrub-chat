import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:flutter/material.dart';

/// The `@…` being typed at the cursor, if there is one.
///
/// Only the token the caret sits in counts, so an earlier mention in the same
/// message does not keep the picker open while you write the rest of it.
class MentionQuery {
  const MentionQuery({required this.start, required this.query});

  /// Index of the `@` in the text.
  final int start;

  /// What follows the `@`, which may be empty right after typing it.
  final String query;

  /// Finds the mention being typed, or null when the caret is not in one.
  static MentionQuery? of(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final caret = selection.baseOffset;
    if (caret <= 0 || caret > value.text.length) return null;

    final upToCaret = value.text.substring(0, caret);
    final at = upToCaret.lastIndexOf('@');
    if (at < 0) return null;

    // An @ mid-word is an email address or a user id, not a mention someone is
    // composing.
    if (at > 0 && !_isBoundary(upToCaret[at - 1])) return null;

    final query = upToCaret.substring(at + 1);
    // A newline ends it, and so does a bracket the picker itself inserted.
    if (query.contains('\n') || query.contains(']')) return null;
    // Two words in is past the point of usefully narrowing a name.
    if (query.split(' ').length > 2) return null;
    return MentionQuery(start: at, query: query);
  }

  static bool _isBoundary(String character) =>
      character.trim().isEmpty || character == '(' || character == '[';
}

/// Replaces the mention being typed with [candidate], leaving the caret after
/// it and a trailing space so the next word does not glue to the name.
TextEditingValue applyMention(
  TextEditingValue value,
  MentionQuery query,
  MentionCandidate candidate,
) {
  final caret = value.selection.baseOffset;
  final inserted = '${candidate.insertText} ';
  final text = value.text.replaceRange(query.start, caret, inserted);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: query.start + inserted.length),
  );
}

/// The list that sits above the composer while an @ is being typed.
class MentionSuggestions extends StatelessWidget {
  const MentionSuggestions({
    required this.candidates,
    required this.onSelected,
    super.key,
  });

  final List<MentionCandidate> candidates;
  final ValueChanged<MentionCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      child: ConstrainedBox(
        // Tall enough to show a few people, short enough that the message
        // being written stays visible above it.
        constraints: const BoxConstraints(maxHeight: 216),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: candidates.length,
          itemBuilder: (context, index) {
            final candidate = candidates[index];
            // "Everyone" is not a person: it gets an icon rather than an
            // initial, and says what it will do rather than showing a user id
            // nobody can look up.
            final isEveryone = candidate.isRoomMention;
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primaryContainer,
                foregroundImage: candidate.avatarUrl == null
                    ? null
                    : NetworkImage(
                        candidate.avatarUrl.toString(),
                        headers: candidate.avatarHeaders,
                      ),
                child: isEveryone
                    ? Icon(
                        Icons.campaign_rounded,
                        size: 18,
                        color: scheme.onPrimaryContainer,
                      )
                    : Text(
                        candidate.displayName.trim().isEmpty
                            ? '?'
                            : candidate.displayName.trim()[0].toUpperCase(),
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
              ),
              title: Text(
                candidate.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isEveryone
                    ? const TextStyle(fontWeight: FontWeight.w600)
                    : null,
              ),
              subtitle: Text(
                isEveryone
                    ? context.l10n.mentionEveryoneHint
                    : candidate.userId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => onSelected(candidate),
            );
          },
        ),
      ),
    );
  }
}
