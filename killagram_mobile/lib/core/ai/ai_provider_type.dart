enum AiProviderType {
  openai,
  grok,
  gemini,
  deepseek,
}

extension AiProviderTypeX on AiProviderType {
  String get id => switch (this) {
        AiProviderType.openai => 'openai',
        AiProviderType.grok => 'grok',
        AiProviderType.gemini => 'gemini',
        AiProviderType.deepseek => 'deepseek',
      };

  String get label => switch (this) {
        AiProviderType.openai => 'OpenAI',
        AiProviderType.grok => 'Grok',
        AiProviderType.gemini => 'Gemini',
        AiProviderType.deepseek => 'DeepSeek',
      };

  static AiProviderType fromId(String raw) {
    return AiProviderType.values.firstWhere(
      (it) => it.id == raw,
      orElse: () => AiProviderType.openai,
    );
  }
}
