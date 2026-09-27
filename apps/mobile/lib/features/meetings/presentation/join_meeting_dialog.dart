import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/meetings/domain/meeting_code.dart';
import 'package:flutter/material.dart';

/// Asks for a meeting code or link and hands back the code, or null.
///
/// Whatever was pasted is accepted -- the code, the link, the whole
/// invitation -- because that is what people have in their clipboard. The
/// caller navigates; this only resolves what was typed.
Future<String?> showJoinMeetingDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _JoinMeetingDialog(),
  );
}

class _JoinMeetingDialog extends StatefulWidget {
  const _JoinMeetingDialog();

  @override
  State<_JoinMeetingDialog> createState() => _JoinMeetingDialogState();
}

class _JoinMeetingDialogState extends State<_JoinMeetingDialog> {
  final _controller = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = parseMeetingCode(_controller.text);
    if (code == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.keyboard_rounded),
      title: Text(context.l10n.joinWithCode),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_invalid) setState(() => _invalid = false);
        },
        decoration: InputDecoration(
          hintText: context.l10n.meetingCodeHint,
          errorText: _invalid ? context.l10n.meetingCodeInvalid : null,
          prefixIcon: const Icon(Icons.link_rounded),
          contentPadding: const EdgeInsets.all(AppSpacing.sm),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.joinMeeting)),
      ],
    );
  }
}
