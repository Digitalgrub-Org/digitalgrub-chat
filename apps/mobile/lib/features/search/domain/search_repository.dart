/// A message that matched a search, with enough context to show a result row
/// and open the conversation it lives in.
class MessageSearchResult {
  const MessageSearchResult({
    required this.roomId,
    required this.roomName,
    required this.eventId,
    required this.senderName,
    required this.body,
    required this.sentAt,
  });

  final String roomId;
  final String roomName;
  final String eventId;
  final String senderName;
  final String body;
  final DateTime sentAt;
}

enum SearchFailureCode { sessionExpired, serverUnavailable, unknown }

class SearchFailure implements Exception {
  const SearchFailure(this.code);

  final SearchFailureCode code;
}

abstract interface class SearchRepository {
  /// Finds messages containing [term] across every joined room, newest first.
  ///
  /// The homeserver does the searching: nothing here downloads history, so
  /// results cover the whole account rather than what this device has cached.
  Future<List<MessageSearchResult>> searchMessages(String term);
}
