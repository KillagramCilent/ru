import 'dart:convert';

import '../../data/local/local_message_store.dart';
import 'ai_provider_type.dart';
import 'ai_service.dart';
import 'semantic_search_service.dart';

class SemanticSearchServiceImpl implements SemanticSearchService {
  SemanticSearchServiceImpl(this._aiService);

  final AiService _aiService;

  @override
  Future<SemanticSearchIntent> buildIntent({
    required AiProviderType provider,
    required String apiKey,
    required String naturalLanguageQuery,
  }) async {
    final prompt = '''
Convert this natural-language chat search query into JSON with keys:
expanded_query (string), keywords (array of strings), must_include (array), exclude (array).
Only output JSON.
Query: $naturalLanguageQuery
''';
    final raw = await _aiService.rewriteMessage(
      provider: provider,
      apiKey: apiKey,
      text: prompt,
      style: 'structured_json',
    );
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      final jsonPart = (start >= 0 && end > start) ? raw.substring(start, end + 1) : raw;
      final map = jsonDecode(jsonPart) as Map<String, dynamic>;
      return SemanticSearchIntent(
        expandedQuery: map['expanded_query']?.toString() ?? naturalLanguageQuery,
        keywords: (map['keywords'] as List<dynamic>? ?? const []).map((it) => it.toString().toLowerCase()).where((it) => it.isNotEmpty).toList(),
        mustInclude: (map['must_include'] as List<dynamic>? ?? const []).map((it) => it.toString().toLowerCase()).where((it) => it.isNotEmpty).toList(),
        exclude: (map['exclude'] as List<dynamic>? ?? const []).map((it) => it.toString().toLowerCase()).where((it) => it.isNotEmpty).toList(),
      );
    } catch (_) {
      final tokens = naturalLanguageQuery
          .toLowerCase()
          .split(RegExp(r'[^\p{L}\p{N}_]+', unicode: true))
          .where((it) => it.length > 2)
          .toList();
      return SemanticSearchIntent(
        expandedQuery: naturalLanguageQuery,
        keywords: tokens,
        mustInclude: const [],
        exclude: const [],
      );
    }
  }

  @override
  Future<List<SemanticSearchResultRow>> search({
    required SemanticSearchIntent intent,
    required LocalMessageStore store,
    String? chatId,
    String? senderId,
    DateTime? from,
    DateTime? to,
    bool? hasMedia,
    bool? hasLinks,
    int limit = 30,
  }) async {
    final docs = await store.getAllSearchDocuments();
    final fromMs = from?.millisecondsSinceEpoch;
    final toMs = to?.millisecondsSinceEpoch;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final ranked = <SemanticSearchResultRow>[];
    for (final row in docs) {
      if (chatId != null && chatId.isNotEmpty && row['chat_id']?.toString() != chatId) continue;
      if (senderId != null && senderId.isNotEmpty && row['sender_id']?.toString() != senderId) continue;
      final ts = (row['timestamp'] as num?)?.toInt() ?? 0;
      if (fromMs != null && ts < fromMs) continue;
      if (toMs != null && ts > toMs) continue;
      if (hasMedia != null && (row['has_media'] as bool? ?? false) != hasMedia) continue;
      if (hasLinks != null && (row['has_links'] as bool? ?? false) != hasLinks) continue;

      final text = row['text']?.toString().toLowerCase() ?? '';
      if (text.isEmpty) continue;

      var score = 0.0;
      final tokens = (row['tokens'] as List<dynamic>? ?? const []).map((it) => it.toString().toLowerCase()).toSet();

      if (text.contains(intent.expandedQuery.toLowerCase())) {
        score += 4.5;
      }

      var matchedKeywords = 0;
      for (final keyword in intent.keywords) {
        if (keyword.isEmpty) continue;
        if (tokens.contains(keyword) || text.contains(keyword)) {
          matchedKeywords += 1;
          score += 2.0;
        }
      }

      var missingMust = false;
      for (final keyword in intent.mustInclude) {
        if (!(tokens.contains(keyword) || text.contains(keyword))) {
          missingMust = true;
          break;
        }
        score += 1.5;
      }
      if (missingMust) continue;

      var excluded = false;
      for (final keyword in intent.exclude) {
        if (tokens.contains(keyword) || text.contains(keyword)) {
          excluded = true;
          break;
        }
      }
      if (excluded) continue;

      if (matchedKeywords == 0 && !text.contains(intent.expandedQuery.toLowerCase())) {
        continue;
      }

      final ageHours = (nowMs - ts) / 3600000;
      score += (1 / (1 + ageHours / 24));

      ranked.add(SemanticSearchResultRow(row: row, score: score));
    }

    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final aTs = (a.row['timestamp'] as num?)?.toInt() ?? 0;
      final bTs = (b.row['timestamp'] as num?)?.toInt() ?? 0;
      return bTs.compareTo(aTs);
    });

    return ranked.take(limit).toList();
  }
}
