abstract class AiRepository {
  Future<String> summarizeChat(String chatId);
  Future<List<String>> smartReplies(String chatId);
}
