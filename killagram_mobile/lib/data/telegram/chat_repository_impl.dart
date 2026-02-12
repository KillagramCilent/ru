import '../../domain/entities/chat.dart';
import '../../domain/entities/message.dart';
import '../../domain/repositories/chat_repository.dart';
import 'telegram_gateway.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl(this._gateway);

  final TelegramGateway _gateway;

  @override
  Future<List<Chat>> getChats({required int limit}) {
    return _gateway.fetchChats(limit: limit);
  }

  @override
  Future<List<Message>> getMessages(String chatId, {required int limit}) {
    return _gateway.fetchMessages(chatId, limit: limit);
  }

  @override
  Stream<Message> watchMessages(String chatId) {
    return _gateway.subscribeMessages(chatId);
  }

  @override
  Stream<Map<String, dynamic>> watchChatEvents(String chatId) {
    return _gateway.subscribeChatEvents(chatId);
  }

  @override
  Future<void> sendMessage(String chatId, String text, {String? replyToId, DateTime? sendAt, String contentType = 'text', int? voiceDuration, String? clientMessageId}) {
    return _gateway.sendMessage(chatId, text, replyToId: replyToId, sendAt: sendAt, contentType: contentType, voiceDuration: voiceDuration, clientMessageId: clientMessageId);
  }

  @override
  Future<void> sendSavedMessage(String text) {
    return _gateway.sendSavedMessage(text);
  }

  @override
  Future<void> forwardMessages(List<String> messageIds, List<String> targetChatIds) {
    return _gateway.forwardMessages(messageIds, targetChatIds);
  }

  @override
  Future<Message> editMessage(String chatId, String messageId, String text) {
    return _gateway.editMessage(chatId, messageId, text);
  }

  @override
  Future<void> deleteMessage(String chatId, String messageId) {
    return _gateway.deleteMessage(chatId, messageId);
  }

  @override
  Future<void> deleteMessagesBatch(String chatId, List<String> messageIds) {
    return _gateway.deleteMessagesBatch(chatId, messageIds);
  }

  @override
  Future<Map<String, dynamic>> addReaction(String chatId, String messageId, String emoji) {
    return _gateway.addReaction(chatId, messageId, emoji);
  }

  @override
  Future<Map<String, dynamic>> removeReaction(String chatId, String messageId, String emoji) {
    return _gateway.removeReaction(chatId, messageId, emoji);
  }

  @override
  Future<Map<String, dynamic>> pinMessage(String chatId, String messageId) {
    return _gateway.pinMessage(chatId, messageId);
  }

  @override
  Future<Map<String, dynamic>> unpinMessage(String chatId, String messageId) {
    return _gateway.unpinMessage(chatId, messageId);
  }

  @override
  Future<void> saveDraft(String chatId, String text) {
    return _gateway.saveDraft(chatId, text);
  }

  @override
  Future<String> getDraft(String chatId) {
    return _gateway.getDraft(chatId);
  }

  @override
  Future<void> markRead(String chatId, String lastMessageId) {
    return _gateway.markRead(chatId, lastMessageId);
  }

  @override
  Future<void> typingStart(String chatId) {
    return _gateway.typingStart(chatId);
  }

  @override
  Future<void> typingStop(String chatId) {
    return _gateway.typingStop(chatId);
  }

  @override
  Future<List<Map<String, dynamic>>> getMessageHistory(String chatId, String messageId) {
    return _gateway.getMessageHistory(chatId, messageId);
  }

  @override
  Future<List<Message>> getMessageThread(String chatId, String messageId) {
    return _gateway.getMessageThread(chatId, messageId);
  }

}
