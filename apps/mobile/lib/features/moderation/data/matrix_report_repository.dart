import 'package:dg_chat/features/moderation/domain/report_repository.dart';
import 'package:matrix/matrix.dart';

/// Submits reports through the homeserver's own report endpoints. The report
/// body is a single reason string, so the structured fields are serialized
/// into it; a dedicated moderation service can replace this class without any
/// change above the domain contract.
class MatrixReportRepository implements ReportRepository {
  MatrixReportRepository(this._client);

  final Client _client;

  @override
  Future<void> submit(ContentReport report) async {
    final comment = report.comment?.trim() ?? '';
    if (comment.length > maxReportCommentLength) {
      throw const ReportFailure(ReportFailureCode.invalidComment);
    }
    if (!report.reportedUserId.trim().isValidMatrixIdStrict()) {
      throw const ReportFailure(ReportFailureCode.invalidTarget);
    }

    final reason = _reason(report, comment);
    try {
      if (report.isMessageReport) {
        await _client.reportEvent(
          report.roomId!,
          report.eventId!,
          reason: reason,
        );
      } else {
        await _client.reportUser(report.reportedUserId, reason);
      }
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } catch (_) {
      throw const ReportFailure(ReportFailureCode.serverUnavailable);
    }
  }

  String _reason(ContentReport report, String comment) {
    final lines = <String>[
      'category: ${report.category.name}',
      'reported_user: ${report.reportedUserId}',
      if (report.roomId != null) 'room: ${report.roomId}',
      if (report.eventId != null) 'event: ${report.eventId}',
      'reported_at: ${report.createdAt.toUtc().toIso8601String()}',
      if (comment.isNotEmpty) 'comment: $comment',
    ];
    return lines.join('\n');
  }

  ReportFailure _mapFailure(MatrixException error) {
    return switch (error.error) {
      MatrixError.M_LIMIT_EXCEEDED => const ReportFailure(
        ReportFailureCode.rateLimited,
      ),
      MatrixError.M_UNKNOWN_TOKEN => const ReportFailure(
        ReportFailureCode.sessionExpired,
      ),
      MatrixError.M_NOT_FOUND => const ReportFailure(
        ReportFailureCode.invalidTarget,
      ),
      _ => const ReportFailure(ReportFailureCode.serverUnavailable),
    };
  }
}
