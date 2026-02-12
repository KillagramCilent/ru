import '../entities/chat.dart';
import '../entities/message.dart';

abstract class ChatRepository {
  Future<List<Chat>> getChats({required int limit});
  Future<List<Message>> getMessages(String chatId, {required int limit});
  Stream<Message> watchMessages(String chatId);
  Stream<Map<String, dynamic>> watchChatEvents(String chatId);
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
}
