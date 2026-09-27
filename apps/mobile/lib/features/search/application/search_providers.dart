import 'package:dg_chat/features/search/data/matrix_search_repository.dart';
import 'package:dg_chat/features/search/domain/search_repository.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchRepositoryProvider = FutureProvider<SearchRepository>((ref) async {
  return MatrixSearchRepository(await ref.watch(matrixClientProvider.future));
});

/// Results for one settled query. Family-keyed by the query string, so the
/// caller decides when a keystroke becomes a search — debouncing lives in the
/// widget, caching lives here.
final messageSearchProvider = FutureProvider.autoDispose
    .family<List<MessageSearchResult>, String>((ref, query) async {
      final repository = await ref.watch(searchRepositoryProvider.future);
      return repository.searchMessages(query);
    });
