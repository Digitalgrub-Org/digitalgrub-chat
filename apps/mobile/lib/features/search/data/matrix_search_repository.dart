import 'package:dg_chat/features/search/domain/search_repository.dart';
import 'package:matrix/matrix.dart';

/// Searches through the homeserver's `/search` endpoint.
class MatrixSearchRepository implements SearchRepository {
  MatrixSearchRepository(this._client);

  final Client _client;

  /// Enough to fill a phone screen several times over; anyone digging deeper
  /// than this has a query worth refining instead.
  static const _maxResults = 40;

  @override
  Future<List<MessageSearchResult>> searchMessages(String term) async {
    final normalized = term.trim();
    if (normalized.isEmpty) return const [];

    final SearchResults response;
    try {
      response = await _client.search(
        Categories(
          roomEvents: RoomEventsCriteria(
            searchTerm: normalized,
            orderBy: SearchOrder.recent,
          ),
        ),
      );
    } on MatrixException catch (error) {
      throw switch (error.error) {
        MatrixError.M_UNKNOWN_TOKEN => const SearchFailure(
          SearchFailureCode.sessionExpired,
        ),
        _ => const SearchFailure(SearchFailureCode.serverUnavailable),
      };
    } catch (_) {
      throw const SearchFailure(SearchFailureCode.serverUnavailable);
    }

    final results = response.searchCategories.roomEvents?.results;
    if (results == null || results.isEmpty) return const [];

    final mapped = <MessageSearchResult>[];
    for (final result in results) {
      final event = result.result;
      if (event == null) continue;
      // The server matches on content this client may not render — an edit
      // fallback, a file caption. Only plain messages with visible text make
      // useful result rows.
      if (event.type != EventTypes.Message) continue;
      final body = event.content['body'];
      if (body is! String || body.trim().isEmpty) continue;
      final roomId = event.roomId;
      if (roomId == null) continue;

      final room = _client.getRoomById(roomId);
      // A hit in a room the account has since left cannot be opened, so a row
      // for it would be a dead tap.
      if (room == null || room.membership != Membership.join) continue;

      mapped.add(
        MessageSearchResult(
          roomId: roomId,
          roomName: room.getLocalizedDisplayname(),
          eventId: event.eventId,
          senderName: room
              .unsafeGetUserFromMemoryOrFallback(event.senderId)
              .calcDisplayname(),
          body: body,
          sentAt: event.originServerTs,
        ),
      );
      if (mapped.length >= _maxResults) break;
    }
    return mapped;
  }
}
