const int maxReportCommentLength = 500;

enum ReportCategory {
  spam,
  harassment,
  abuse,
  fraud,
  inappropriateContent,
  other,
}

/// A report of a user or of one of their messages. [roomId] and [eventId] are
/// set together when a specific message is reported and are both absent when
/// the whole account is reported.
class ContentReport {
  const ContentReport({
    required this.reportedUserId,
    required this.category,
    required this.createdAt,
    this.roomId,
    this.eventId,
    this.comment,
  });

  final String reportedUserId;
  final ReportCategory category;
  final DateTime createdAt;
  final String? roomId;
  final String? eventId;
  final String? comment;

  bool get isMessageReport => roomId != null && eventId != null;
}

enum ReportFailureCode {
  invalidComment,
  invalidTarget,
  rateLimited,
  serverUnavailable,
  sessionExpired,
  unknown,
}

class ReportFailure implements Exception {
  const ReportFailure(this.code);

  final ReportFailureCode code;
}

/// Submission is abstracted so reports can move from the homeserver's report
/// endpoints to a dedicated moderation service without touching the UI.
abstract interface class ReportRepository {
  Future<void> submit(ContentReport report);
}
