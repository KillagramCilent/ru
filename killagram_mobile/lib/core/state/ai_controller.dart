import 'package:flutter/foundation.dart';

import '../../data/local/local_message_store.dart';
import '../ai/ai_provider_type.dart';
import '../ai/ai_service.dart';

class AiController {
  AiController(this._store, this._service);

  final LocalMessageStore _store;
  final AiService _service;

  final ValueNotifier<AiProviderType> provider = ValueNotifier<AiProviderType>(AiProviderType.openai);
  final ValueNotifier<bool> panelExpanded = ValueNotifier<bool>(false);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);
  final ValueNotifier<String?> output = ValueNotifier<String?>(null);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  Future<void> init() async {
    final raw = await _store.getUiSetting('ai_provider');
    provider.value = AiProviderTypeX.fromId(raw ?? 'openai');
  }

  Future<void> setProvider(AiProviderType next) async {
    provider.value = next;
    await _store.setUiSetting('ai_provider', next.id);
  }

  Future<String> getApiKey(AiProviderType type) async {
    return (await _store.getUiSetting('ai_key_${type.id}') ?? '').trim();
  }

  Future<void> setApiKey(AiProviderType type, String value) async {
    await _store.setUiSetting('ai_key_${type.id}', value.trim());
  }

  void togglePanel() {
    panelExpanded.value = !panelExpanded.value;
  }

  void clear() {
    output.value = null;
    error.value = null;
  }

  Future<void> summarizeConversation(List<String> messages) async {
    await _run((key) => _service.summarizeConversation(provider: provider.value, apiKey: key, messages: messages));
  }

  Future<void> generateReplySuggestion({required String message, required List<String> context}) async {
    await _run((key) => _service.generateReplySuggestion(provider: provider.value, apiKey: key, message: message, context: context));
  }

  Future<void> rewriteMessage({required String text, required String style}) async {
    await _run((key) => _service.rewriteMessage(provider: provider.value, apiKey: key, text: text, style: style));
  }

  Future<void> extractTasks(List<String> messages) async {
    await _run((key) => _service.extractTasks(provider: provider.value, apiKey: key, messages: messages));
  }

  Future<void> _run(Future<String> Function(String apiKey) invoke) async {
    loading.value = true;
    error.value = null;
    try {
      final key = await getApiKey(provider.value);
      final res = await invoke(key);
      output.value = res;
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
    }
  }
}
