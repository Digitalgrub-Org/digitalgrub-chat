import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/moderation/application/report_providers.dart';
import 'package:dg_chat/features/moderation/domain/report_repository.dart';
import 'package:dg_chat/features/profile/application/profile_providers.dart';
import 'package:dg_chat/features/profile/domain/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Collects a category and optional comment, then submits. Returns true when a
/// report was accepted so the caller can confirm to the user.
Future<bool> showReportSheet(
  BuildContext context, {
  required String reportedUserId,
  String? roomId,
  String? eventId,
  bool offerBlock = true,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _ReportSheet(
        reportedUserId: reportedUserId,
        roomId: roomId,
        eventId: eventId,
        offerBlock: offerBlock,
      ),
    ),
  );
  return submitted ?? false;
}

class _ReportSheet extends ConsumerStatefulWidget {
  const _ReportSheet({
    required this.reportedUserId,
    required this.roomId,
    required this.eventId,
    required this.offerBlock,
  });

  final String reportedUserId;
  final String? roomId;
  final String? eventId;
  final bool offerBlock;

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _commentController = TextEditingController();
  ReportCategory _category = ReportCategory.spam;
  bool _alsoBlock = false;
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final comment = _commentController.text.trim();
    if (comment.length > maxReportCommentLength) {
      _showMessage(context.l10n.reportCommentTooLong(maxReportCommentLength));
      return;
    }

    setState(() => _submitting = true);
    try {
      final repository = await ref.read(reportRepositoryProvider.future);
      await repository.submit(
        ContentReport(
          reportedUserId: widget.reportedUserId,
          category: _category,
          createdAt: DateTime.now(),
          roomId: widget.roomId,
          eventId: widget.eventId,
          comment: comment.isEmpty ? null : comment,
        ),
      );
      // Blocking is a separate action; a failure here must not read as a
      // failed report.
      if (_alsoBlock) {
        try {
          final profiles = await ref.read(profileRepositoryProvider.future);
          await profiles.blockUser(widget.reportedUserId);
        } on ProfileFailure {
          if (mounted) _showMessage(context.l10n.blockFailed);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } on ReportFailure catch (failure) {
      if (mounted) _showMessage(_failureMessage(context, failure));
    } catch (_) {
      if (mounted) _showMessage(context.l10n.reportFailed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.reportCategory,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final category in ReportCategory.values)
                  ChoiceChip(
                    label: Text(reportCategoryLabel(context, category)),
                    selected: _category == category,
                    onSelected: _submitting
                        ? null
                        : (_) => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _commentController,
              enabled: !_submitting,
              maxLength: maxReportCommentLength,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.reportComment,
              ),
            ),
            if (widget.offerBlock)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _alsoBlock,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _alsoBlock = value ?? false),
                title: Text(context.l10n.alsoBlockUser),
              ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flag_outlined),
                label: Text(context.l10n.submitReport),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String reportCategoryLabel(BuildContext context, ReportCategory category) =>
    switch (category) {
      ReportCategory.spam => context.l10n.reportSpam,
      ReportCategory.harassment => context.l10n.reportHarassment,
      ReportCategory.abuse => context.l10n.reportAbuse,
      ReportCategory.fraud => context.l10n.reportFraud,
      ReportCategory.inappropriateContent => context.l10n.reportInappropriate,
      ReportCategory.other => context.l10n.reportOther,
    };

String _failureMessage(BuildContext context, ReportFailure failure) {
  return switch (failure.code) {
    ReportFailureCode.invalidComment => context.l10n.reportCommentTooLong(
      maxReportCommentLength,
    ),
    ReportFailureCode.rateLimited => context.l10n.rateLimited,
    ReportFailureCode.sessionExpired => context.l10n.sessionExpired,
    _ => context.l10n.reportFailed,
  };
}
