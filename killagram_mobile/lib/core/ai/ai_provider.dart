abstract class AiProvider {
  Future<String> complete({
    required String apiKey,
    required String systemPrompt,
    required String userPrompt,
    String? model,
  });
}
