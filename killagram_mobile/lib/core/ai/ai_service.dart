import 'ai_provider_type.dart';

abstract class AiService {
  Future<String> summarizeConversation({
    required AiProviderType provider,
    required String apiKey,
    required List<String> messages,
  });

  Future<String> generateReplySuggestion({
    required AiProviderType provider,
    required String apiKey,
    required String message,
    required List<String> context,
  });

  Future<String> rewriteMessage({
    required AiProviderType provider,
    required String apiKey,
    required String text,
    required String style,
  });

  Future<String> extractTasks({
    required AiProviderType provider,
    required String apiKey,
    required List<String> messages,
  });
}
