import 'dart:convert';
import 'dart:io';

import '../ai_provider.dart';

class GeminiProvider implements AiProvider {
  @override
  Future<String> complete({
    required String apiKey,
    required String systemPrompt,
    required String userPrompt,
    String? model,
  }) async {
    final resolvedModel = model ?? 'gemini-1.5-flash';
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$resolvedModel:generateContent?key=$apiKey'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': '$systemPrompt\n\n$userPrompt'}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.3,
      },
    }));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    client.close(force: true);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw Exception('AI_REQUEST_FAILED:$body');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>? ?? const [];
    final first = candidates.isEmpty ? null : candidates.first as Map<String, dynamic>;
    final content = first?['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>? ?? const [];
    final part = parts.isEmpty ? null : parts.first as Map<String, dynamic>;
    return part?['text']?.toString().trim() ?? '';
  }
}
