import '../../domain/entities/chat.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/account_state.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';

abstract class TelegramGateway {
  Future<void> requestCode(String phone);
  Future<String> confirmCode({
    required String phone,
    required String code,
    String? password,
  });
  Future<List<Chat>> fetchChats({required int limit});
  Future<List<Folder>> fetchFolders();
  Future<List<Chat>> fetchFolderChats(String folderId);
  Future<AccountState> fetchMe();
  Future<void> appealFreeze(String text);
  Stream<Map<String, dynamic>> subscribeEvents();
  Future<List<Message>> fetchMessages(String chatId, {required int limit});
  Stream<Message> subscribeMessages(String chatId);
  Stream<Map<String, dynamic>> subscribeChatEvents(String chatId);
  Future<void> sendMessage(String chatId, String text, {String? replyToId, DateTime? sendAt, String contentType = 'text', int? voiceDuration, String? clientMessageId});
  Future<void> sendSavedMessage(String text);
  Future<void> forwardMessages(List<String> messageIds, List<String> targetChatIds);
  Future<Message> editMessage(String chatId, String messageId, String text);
  Future<void> deleteMessage(String chatId, String messageId);
  Future<void> deleteMessagesBatch(String chatId, List<String> messageIds);
  Future<Map<String, dynamic>> addReaction(String chatId, String messageId, String emoji);
  Future<Map<String, dynamic>> removeReaction(String chatId, String messageId, String emoji);
  Future<Map<String, dynamic>> pinMessage(String chatId, String messageId);
  Future<Map<String, dynamic>> unpinMessage(String chatId, String messageId);
  Future<void> saveDraft(String chatId, String text);
  Future<String> getDraft(String chatId);
  Future<void> markRead(String chatId, String lastMessageId);
  Future<void> typingStart(String chatId);
  Future<void> typingStop(String chatId);
  Future<List<Map<String, dynamic>>> getMessageHistory(String chatId, String messageId);
  Future<List<Message>> getMessageThread(String chatId, String messageId);
  Future<String> requestAiSummary(String chatId);
  Future<List<String>> requestSmartReplies(String chatId);
  Future<List<SearchResult>> searchMessages(SearchMessagesParams params);
}
