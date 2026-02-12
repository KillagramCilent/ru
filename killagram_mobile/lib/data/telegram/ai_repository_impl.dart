import '../../domain/repositories/ai_repository.dart';
import 'telegram_gateway.dart';

class AiRepositoryImpl implements AiRepository {
  AiRepositoryImpl(this._gateway);

  final TelegramGateway _gateway;

  @override
  Future<String> summarizeChat(String chatId) {
    return _gateway.requestAiSummary(chatId);
  }

  @override
  Future<List<String>> smartReplies(String chatId) {
    return _gateway.requestSmartReplies(chatId);
  }
}
