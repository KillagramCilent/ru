import 'dart:convert';
import 'dart:io';

import '../ai_provider.dart';

class GrokProvider implements AiProvider {
  @override
  Future<String> complete({
    required String apiKey,
    required String systemPrompt,
    required String userPrompt,
    String? model,
  }) async {
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('https://api.x.ai/v1/chat/completions'));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    request.write(jsonEncode({
      'model': model ?? 'grok-2-latest',
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': 0.3,
    }));
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    client.close(force: true);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw Exception('AI_REQUEST_FAILED:$body');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>? ?? const [];
    final first = choices.isEmpty ? null : choices.first as Map<String, dynamic>;
    final message = first?['message'] as Map<String, dynamic>?;
    return message?['content']?.toString().trim() ?? '';
  }
}
