import 'ai_provider.dart';
import 'ai_provider_type.dart';
import 'ai_service.dart';

class AiServiceImpl implements AiService {
  AiServiceImpl(this._providers);

  final Map<AiProviderType, AiProvider> _providers;

  @override
  Future<String> summarizeConversation({
    required AiProviderType provider,
    required String apiKey,
    required List<String> messages,
  }) async {
    final joined = messages.take(80).join('\n');
    return _run(
      provider: provider,
      apiKey: apiKey,
      systemPrompt: 'You summarize chats in concise bullet points.',
      userPrompt: 'Summarize this conversation:\n$joined',
    );
  }

  @override
  Future<String> generateReplySuggestion({
    required AiProviderType provider,
    required String apiKey,
    required String message,
    required List<String> context,
  }) async {
    final joined = context.take(40).join('\n');
    return _run(
      provider: provider,
      apiKey: apiKey,
      systemPrompt: 'You generate a reply suggestion for messaging. Keep it practical and human.',
      userPrompt: 'Context:\n$joined\n\nTarget message:\n$message\n\nProvide one reply suggestion.',
    );
  }

  @override
  Future<String> rewriteMessage({
    required AiProviderType provider,
    required String apiKey,
    required String text,
    required String style,
  }) {
    return _run(
      provider: provider,
      apiKey: apiKey,
      systemPrompt: 'You rewrite text preserving meaning.',
      userPrompt: 'Rewrite using "$style" style:\n$text',
    );
  }

  @override
  Future<String> extractTasks({
    required AiProviderType provider,
    required String apiKey,
    required List<String> messages,
  }) {
    final joined = messages.take(80).join('\n');
    return _run(
      provider: provider,
      apiKey: apiKey,
      systemPrompt: 'You extract actionable tasks with owners and due dates when possible.',
      userPrompt: 'Extract tasks from this conversation:\n$joined',
    );
  }

  Future<String> _run({
    required AiProviderType provider,
    required String apiKey,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('AI_API_KEY_MISSING');
    }
    final impl = _providers[provider];
    if (impl == null) {
      throw Exception('AI_PROVIDER_NOT_CONFIGURED');
    }
    final out = await impl.complete(
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
    );
    if (out.trim().isEmpty) {
      throw Exception('AI_EMPTY_RESPONSE');
    }
    return out.trim();
  }
}
