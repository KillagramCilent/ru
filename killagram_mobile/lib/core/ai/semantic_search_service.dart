import '../../data/local/local_message_store.dart';
import 'ai_provider_type.dart';

class SemanticSearchIntent {
  const SemanticSearchIntent({
    required this.expandedQuery,
    required this.keywords,
    required this.mustInclude,
    required this.exclude,
  });

  final String expandedQuery;
  final List<String> keywords;
  final List<String> mustInclude;
  final List<String> exclude;
}

class SemanticSearchResultRow {
  const SemanticSearchResultRow({
    required this.row,
    required this.score,
  });

  final Map<String, dynamic> row;
  final double score;
}

abstract class SemanticSearchService {
  Future<SemanticSearchIntent> buildIntent({
    required AiProviderType provider,
    required String apiKey,
    required String naturalLanguageQuery,
  });

  Future<List<SemanticSearchResultRow>> search({
    required SemanticSearchIntent intent,
    required LocalMessageStore store,
    String? chatId,
    String? senderId,
    DateTime? from,
    DateTime? to,
    bool? hasMedia,
    bool? hasLinks,
    int limit,
  });
}
