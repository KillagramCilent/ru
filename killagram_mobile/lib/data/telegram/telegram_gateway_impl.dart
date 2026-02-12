import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/config/api_config.dart';
import '../../domain/entities/account_state.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';
import 'api_client.dart';
import 'auth_storage.dart';
import 'telegram_gateway.dart';

class TelegramGatewayImpl implements TelegramGateway {
  Message _mapMessageFromRaw(Map<String, dynamic> raw, String chatId) {
    return Message(
      id: raw['id'].toString(),
      chatId: chatId,
      sender: raw['sender'] as String? ?? '',
      text: raw['text'] as String? ?? '',
      timestamp: DateTime.tryParse(raw['date'] as String? ?? '') ?? DateTime.now(),
      isOutgoing: raw['is_outgoing'] as bool? ?? false,
      reactions: (raw['reactions'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
      myReactions: (raw['my_reactions'] as List<dynamic>? ?? []).map((it) => it.toString()).toList(),
      canEdit: raw['can_edit'] as bool? ?? false,
      isRead: raw['is_read'] as bool? ?? false,
      isPinned: raw['is_pinned'] as bool? ?? false,
      isSystem: raw['is_system'] as bool? ?? false,
      systemEventType: raw['system_event_type']?.toString(),
      systemPayload: (raw['system_payload'] as Map<String, dynamic>? ?? const {}),
      contentType: raw['content_type']?.toString() ?? 'text',
      hasDownloadableFile: raw['has_downloadable_file'] as bool? ?? false,
      replyToId: raw['reply_to_id']?.toString(),
      replyPreview: raw['reply_preview']?.toString(),
      forwardedFrom: raw['forwarded_from']?.toString(),
      scheduledAt: DateTime.tryParse(raw['scheduled_at']?.toString() ?? ''),
      voiceDuration: (raw['voice_duration'] as num?)?.toInt(),
      mentions: (raw['mentions'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
      hashtags: (raw['hashtags'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
      editVersionsCount: (raw['edit_versions_count'] as num?)?.toInt() ?? 0,
    );
  }
  TelegramGatewayImpl(this._client, this._authStorage);

  final ApiClient _client;
  final AuthStorage _authStorage;
  final Set<String> _seenEventIds = <String>{};

  @override
  Future<void> requestCode(String phone) async {
    await _client.post('/auth/request-code', data: {'phone': phone});
  }

  @override
  Future<String> confirmCode({
    required String phone,
    required String code,
    String? password,
  }) async {
    final response = await _client.post(
      '/auth/confirm',
      data: {
        'phone': phone,
        'code': code,
        if (password != null && password.isNotEmpty) 'password': password,
      },
    );
    final token = response.data['token'] as String;
    await _authStorage.saveToken(token);
    await _authStorage.savePhone(phone);
    return token;
  }

  @override
  Future<AccountState> fetchMe() async {
    final response = await _client.get('/me', authorized: true);
    final data = response.data as Map<String, dynamic>;
    return AccountState(
      id: data['id']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      status: data['status']?.toString() ?? 'active',
      freezeReason: data['freeze_reason'] as String?,
      premium: data['premium'] as bool? ?? false,
      starsBalance: data['stars_balance'] as int? ?? 0,
    );
  }

  @override
  Future<void> appealFreeze(String text) async {
    await _client.post('/auth/appeal-freeze', data: {'text': text}, authorized: true);
  }



  @override
  Future<List<Folder>> fetchFolders() async {
    final response = await _client.get('/folders', authorized: true);
    final data = response.data as List<dynamic>;
    return data
        .map((item) => Folder(
              id: item['id']?.toString() ?? '',
              title: item['title']?.toString() ?? '',
              includeTypes: (item['include_types'] as List<dynamic>? ?? []).map((it) => it.toString()).toList(),
              chatIds: (item['chat_ids'] as List<dynamic>? ?? []).map((it) => it.toString()).toList(),
              order: (item['order'] as num?)?.toInt() ?? 0,
              isSystem: item['is_system'] as bool? ?? false,
              emojiId: item['emoji_id']?.toString(),
              emojiFallback: item['emoji_fallback']?.toString(),
            ))
        .toList();
  }

  @override
  Future<List<Chat>> fetchFolderChats(String folderId) async {
    final response = await _client.get('/folders/$folderId/chats', authorized: true);
    final data = response.data as List<dynamic>;
    final chats = data
        .map((item) => Chat(
              id: item['id'].toString(),
              title: item['title'] as String? ?? '',
              lastMessage: item['last_message'] as String? ?? '',
              unreadCount: item['unread_count'] as int? ?? 0,
              avatarUrl: item['id'].toString() == '-1' ? 'saved' : '',
              isMuted: false,
              isSavedMessages: item['id'].toString() == '-1',
              verificationStatus: item['verification']?['status']?.toString() ?? 'unverified',
              verificationProvider: item['verification']?['provider']?.toString() ?? 'none',
              verificationProviderName: item['verification']?['provider_name']?.toString(),
              verificationBadgeIconUrl: item['verification']?['badge_icon_url']?.toString(),
            ))
        .toList();
    if (!chats.any((it) => it.isSavedMessages)) {
      chats.insert(
        0,
        const Chat(
          id: '-1',
          title: 'Saved Messages',
          lastMessage: '',
          unreadCount: 0,
          avatarUrl: 'saved',
          isMuted: false,
          isSavedMessages: true,
          verificationStatus: 'unverified',
          verificationProvider: 'none',
        ),
      );
    }
    return chats;
  }

  @override
  Future<List<Chat>> fetchChats({required int limit}) async {
    final response = await _client.get(
      '/chats',
      queryParameters: {'limit': limit},
      authorized: true,
    );
    final data = response.data as List<dynamic>;
    final messages = data
        .map(
          (item) => Chat(
            id: item['id'].toString(),
            title: item['title'] as String? ?? '',
            lastMessage: item['last_message'] as String? ?? '',
            unreadCount: item['unread_count'] as int? ?? 0,
            avatarUrl: item['id'].toString() == '-1' ? 'saved' : '',
            isMuted: false,
            isSavedMessages: item['id'].toString() == '-1',
            verificationStatus: item['verification']?['status']?.toString() ?? 'unverified',
            verificationProvider: item['verification']?['provider']?.toString() ?? 'none',
            verificationProviderName: item['verification']?['provider_name']?.toString(),
            verificationBadgeIconUrl: item['verification']?['badge_icon_url']?.toString(),
          ),
        )
        .toList();
    messages.sort((a, b) => (b.isSavedMessages ? 1 : 0) - (a.isSavedMessages ? 1 : 0));
    return messages;
  }

  @override
  Future<List<Message>> fetchMessages(String chatId, {required int limit}) async {
    final response = await _client.get(
      '/chats/$chatId/messages',
      queryParameters: {'limit': limit},
      authorized: true,
    );
    final data = response.data as List<dynamic>;
    final messages = data
        .map(
          (item) => Message(
            id: item['id'].toString(),
            chatId: chatId,
            sender: item['sender'] as String? ?? '',
            text: item['text'] as String? ?? '',
            timestamp: DateTime.tryParse(item['date'] as String? ?? '') ?? DateTime.now(),
            isOutgoing: item['is_outgoing'] as bool? ?? false,
            reactions: (item['reactions'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
            myReactions: (item['my_reactions'] as List<dynamic>? ?? []).map((it) => it.toString()).toList(),
            canEdit: item['can_edit'] as bool? ?? false,
            isRead: item['is_read'] as bool? ?? false,
            isPinned: item['is_pinned'] as bool? ?? false,
            isSystem: item['is_system'] as bool? ?? false,
            systemEventType: item['system_event_type']?.toString(),
            systemPayload: (item['system_payload'] as Map<String, dynamic>? ?? const {}),
            contentType: item['content_type']?.toString() ?? 'text',
            hasDownloadableFile: item['has_downloadable_file'] as bool? ?? false,
            replyToId: item['reply_to_id']?.toString(),
            replyPreview: item['reply_preview']?.toString(),
            forwardedFrom: item['forwarded_from']?.toString(),
            scheduledAt: DateTime.tryParse(item['scheduled_at']?.toString() ?? ''),
            voiceDuration: (item['voice_duration'] as num?)?.toInt(),
            mentions: (item['mentions'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
            hashtags: (item['hashtags'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
            editVersionsCount: (item['edit_versions_count'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
    return messages;
  }

  @override
  Stream<Map<String, dynamic>> subscribeEvents() async* {
    final token = await _authStorage.readToken();
    final phone = await _authStorage.readPhone();
    if (token == null || phone == null) {
      return;
    }

    final wsTokenResponse = await _client.post('/auth/ws-token', authorized: true);
    final wsToken = wsTokenResponse.data['ws_token'] as String;
    final wsUrl = '${ApiConfig.wsBaseUrl}/ws/events?token=$wsToken&phone=$phone';
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(wsUrl);
      await for (final event in socket) {
        final payload = jsonDecode(event.toString()) as Map<String, dynamic>;
        final eventId = payload['event_id']?.toString();
        if (eventId != null && eventId.isNotEmpty) {
          if (_seenEventIds.contains(eventId)) {
            continue;
          }
          _seenEventIds.add(eventId);
        }
        yield payload;
      }
    } catch (_) {
      // fallback covered by polling and explicit API refresh.
    } finally {
      await socket?.close();
    }
  }

  @override
  Stream<Message> subscribeMessages(String chatId) async* {
    await for (final event in subscribeEvents()) {
      final eventType = event['event_type']?.toString() ?? '';
      if (eventType != 'message_created' && eventType != 'message_edited') {
        continue;
      }
      final payload = event['payload'] as Map<String, dynamic>?;
      final eventChatId = payload?['chat_id']?.toString() ?? '';
      final normalizedChatId = chatId == '-1' ? 'saved' : chatId;
      if (payload == null || eventChatId != normalizedChatId) {
        continue;
      }
      final raw = payload['message'] as Map<String, dynamic>?;
      if (raw == null) {
        continue;
      }
      yield Message(
        id: raw['id'].toString(),
        chatId: chatId,
        sender: raw['sender'] as String? ?? '',
        text: raw['text'] as String? ?? '',
        timestamp: DateTime.tryParse(raw['date'] as String? ?? '') ?? DateTime.now(),
        isOutgoing: raw['is_outgoing'] as bool? ?? false,
        reactions: (raw['reactions'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
        myReactions: (raw['my_reactions'] as List<dynamic>? ?? []).map((it) => it.toString()).toList(),
        canEdit: raw['can_edit'] as bool? ?? false,
        isRead: raw['is_read'] as bool? ?? false,
        isPinned: raw['is_pinned'] as bool? ?? false,
        isSystem: raw['is_system'] as bool? ?? false,
        systemEventType: raw['system_event_type']?.toString(),
        systemPayload: (raw['system_payload'] as Map<String, dynamic>? ?? const {}),
        contentType: raw['content_type']?.toString() ?? 'text',
        hasDownloadableFile: raw['has_downloadable_file'] as bool? ?? false,
        replyToId: raw['reply_to_id']?.toString(),
        replyPreview: raw['reply_preview']?.toString(),
        forwardedFrom: raw['forwarded_from']?.toString(),
        scheduledAt: DateTime.tryParse(raw['scheduled_at']?.toString() ?? ''),
        voiceDuration: (raw['voice_duration'] as num?)?.toInt(),
        mentions: (raw['mentions'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
        hashtags: (raw['hashtags'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
        editVersionsCount: (raw['edit_versions_count'] as num?)?.toInt() ?? 0,
      );
    }
  }

  @override
  Stream<Map<String, dynamic>> subscribeChatEvents(String chatId) async* {
    final normalizedChatId = chatId == '-1' ? 'saved' : chatId;
    await for (final event in subscribeEvents()) {
      final payload = event['payload'] as Map<String, dynamic>?;
      final eventChatId = payload?['chat_id']?.toString() ?? '';
      if (eventChatId == normalizedChatId) {
        yield event;
      }
    }
  }

  @override
  Future<void> sendMessage(String chatId, String text, {String? replyToId, DateTime? sendAt, String contentType = 'text', int? voiceDuration, String? clientMessageId}) async {
    if (chatId == '-1') {
      await sendSavedMessage(text);
      return;
    }
    await _client.post(
      '/chats/$chatId/messages',
      data: {
        'text': text,
        if (replyToId != null) 'reply_to_id': int.tryParse(replyToId),
        if (sendAt != null) 'send_at': sendAt.toUtc().toIso8601String(),
        'content_type': contentType,
        if (voiceDuration != null) 'voice_duration': voiceDuration,
        if (clientMessageId != null) 'client_message_id': clientMessageId,
      },
      authorized: true,
    );
  }

  @override
  Future<String> requestAiSummary(String chatId) async {
    final response = await _client.post(
      '/ai/summarize',
      data: {'chat_id': int.tryParse(chatId) ?? 0, 'range': 'recent', 'mode': 'short'},
      authorized: true,
    );
    return response.data['summary'] as String? ?? 'Нет summary';
  }

  @override
  Future<List<String>> requestSmartReplies(String chatId) async {
    final response = await _client.post(
      '/ai/smart-replies',
      data: {'chat_id': int.tryParse(chatId) ?? 0, 'message_id': 0},
      authorized: true,
    );
    final replies = response.data['replies'] as List<dynamic>? ?? [];
    return replies.map((it) => it.toString()).toList();
  }


  @override
  Future<void> sendSavedMessage(String text) async {
    await _client.post('/messages/send', data: {'text': text}, authorized: true);
  }

  @override
  Future<void> forwardMessages(List<String> messageIds, List<String> targetChatIds) async {
    await _client.post('/messages/forward', data: {
      'message_ids': messageIds.map((it) => int.tryParse(it)).whereType<int>().toList(),
      'target_chat_ids': targetChatIds.map((it) => int.tryParse(it) ?? -1).toList(),
    }, authorized: true);
  }

  @override
  Future<Message> editMessage(String chatId, String messageId, String text) async {
    final response = await _client.post('/messages/$messageId/edit', data: {'chat_id': int.tryParse(chatId) ?? -1, 'text': text}, authorized: true);
    final raw = response.data['message'] as Map<String, dynamic>;
    return Message(
      id: raw['id'].toString(),
      chatId: chatId,
      sender: raw['sender'] as String? ?? '',
      text: raw['text'] as String? ?? '',
      timestamp: DateTime.tryParse(raw['date'] as String? ?? '') ?? DateTime.now(),
      isOutgoing: raw['is_outgoing'] as bool? ?? false,
      reactions: (raw['reactions'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
      myReactions: (raw['my_reactions'] as List<dynamic>? ?? []).map((it) => it.toString()).toList(),
      canEdit: raw['can_edit'] as bool? ?? false,
      isRead: raw['is_read'] as bool? ?? false,
      isPinned: raw['is_pinned'] as bool? ?? false,
      isSystem: raw['is_system'] as bool? ?? false,
      systemEventType: raw['system_event_type']?.toString(),
      systemPayload: (raw['system_payload'] as Map<String, dynamic>? ?? const {}),
      contentType: raw['content_type']?.toString() ?? 'text',
      hasDownloadableFile: raw['has_downloadable_file'] as bool? ?? false,
      replyToId: raw['reply_to_id']?.toString(),
      replyPreview: raw['reply_preview']?.toString(),
      forwardedFrom: raw['forwarded_from']?.toString(),
      scheduledAt: DateTime.tryParse(raw['scheduled_at']?.toString() ?? ''),
      voiceDuration: (raw['voice_duration'] as num?)?.toInt(),
        mentions: (raw['mentions'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
        hashtags: (raw['hashtags'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
        editVersionsCount: (raw['edit_versions_count'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> deleteMessage(String chatId, String messageId) async {
    await _client.post('/messages/$messageId/delete', data: {'chat_id': int.tryParse(chatId) ?? -1}, authorized: true);
  }

  @override
  Future<void> deleteMessagesBatch(String chatId, List<String> messageIds) async {
    await _client.post('/messages/delete-batch', data: {
      'chat_id': int.tryParse(chatId) ?? -1,
      'message_ids': messageIds.map((it) => int.tryParse(it)).whereType<int>().toList(),
    }, authorized: true);
  }

  @override
  Future<Map<String, dynamic>> addReaction(String chatId, String messageId, String emoji) async {
    final response = await _client.post('/messages/$messageId/reactions/add', data: {'chat_id': int.tryParse(chatId) ?? -1, 'emoji': emoji}, authorized: true);
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> removeReaction(String chatId, String messageId, String emoji) async {
    final response = await _client.post('/messages/$messageId/reactions/remove', data: {'chat_id': int.tryParse(chatId) ?? -1, 'emoji': emoji}, authorized: true);
    return response.data as Map<String, dynamic>;
  }


  @override
  Future<Map<String, dynamic>> pinMessage(String chatId, String messageId) async {
    final response = await _client.post('/messages/$messageId/pin', data: {'chat_id': int.tryParse(chatId) ?? -1}, authorized: true);
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> unpinMessage(String chatId, String messageId) async {
    final response = await _client.post('/messages/$messageId/unpin', data: {'chat_id': int.tryParse(chatId) ?? -1}, authorized: true);
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> saveDraft(String chatId, String text) async {
    await _client.post('/chats/$chatId/draft', data: {'text': text}, authorized: true);
  }

  @override
  Future<String> getDraft(String chatId) async {
    final response = await _client.get('/chats/$chatId/draft', authorized: true);
    return response.data['text']?.toString() ?? '';
  }

  @override
  Future<void> markRead(String chatId, String lastMessageId) async {
    await _client.post('/chats/$chatId/read', data: {'last_message_id': int.tryParse(lastMessageId) ?? 0}, authorized: true);
  }

  @override
  Future<void> typingStart(String chatId) async {
    await _client.post('/chats/$chatId/typing/start', data: {'scope': 'chat'}, authorized: true);
  }

  @override
  Future<void> typingStop(String chatId) async {
    await _client.post('/chats/$chatId/typing/stop', data: {'scope': 'chat'}, authorized: true);
  }

  @override
  Future<List<Map<String, dynamic>>> getMessageHistory(String chatId, String messageId) async {
    final response = await _client.get('/messages/$messageId/history', queryParameters: {'chat_id': int.tryParse(chatId) ?? -1}, authorized: true);
    final rows = response.data as List<dynamic>? ?? [];
    return rows.whereType<Map>().map((it) => Map<String, dynamic>.from(it as Map)).toList();
  }

  @override
  Future<List<Message>> getMessageThread(String chatId, String messageId) async {
    final response = await _client.get('/messages/$messageId/thread', queryParameters: {'chat_id': int.tryParse(chatId) ?? -1}, authorized: true);
    final rows = response.data as List<dynamic>? ?? [];
    return rows.whereType<Map>().map((it) => _mapMessageFromRaw(Map<String, dynamic>.from(it as Map), chatId)).toList();
  }

  @override
  Future<List<SearchResult>> searchMessages(SearchMessagesParams params) async {
    final response = await _client.post(
      '/search/messages',
      authorized: true,
      data: {
        'query': params.query,
        if (params.folderId != null && params.folderId!.isNotEmpty) 'folder_id': params.folderId,
        if (params.chatId != null && params.chatId!.isNotEmpty) 'chat_id': int.tryParse(params.chatId!),
        if (params.senderId != null && params.senderId!.isNotEmpty) 'sender_id': int.tryParse(params.senderId!),
        if (params.hasMedia != null) 'has_media': params.hasMedia,
        if (params.chatScope.isNotEmpty) 'chat_scope': params.chatScope.map((it) => it.name).toList(),
        if (params.contentTypes.isNotEmpty) 'content_types': params.contentTypes.map((it) => it.name).toList(),
        if (params.hasDownloadableFile != null) 'has_downloadable_file': params.hasDownloadableFile,
        'saved_only': params.savedOnly,
        'limit': params.limit,
        'offset': params.offset,
      },
    );
    final items = response.data['items'] as List<dynamic>? ?? [];
    return items.map((row) {
      final message = row['message'] as Map<String, dynamic>? ?? const {};
      return SearchResult(
        message: Message(
          id: message['id'].toString(),
          chatId: row['chat_id']?.toString() ?? '',
          sender: message['sender']?.toString() ?? '',
          text: message['text']?.toString() ?? '',
          timestamp: DateTime.tryParse(message['date']?.toString() ?? '') ?? DateTime.now(),
          isOutgoing: message['is_outgoing'] as bool? ?? false,
          reactions: (message['reactions'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
          myReactions: (message['my_reactions'] as List<dynamic>? ?? []).map((it) => it.toString()).toList(),
          canEdit: message['can_edit'] as bool? ?? false,
          isRead: message['is_read'] as bool? ?? false,
          isPinned: message['is_pinned'] as bool? ?? false,
          isSystem: message['is_system'] as bool? ?? false,
          systemEventType: message['system_event_type']?.toString(),
          systemPayload: (message['system_payload'] as Map<String, dynamic>? ?? const {}),
          contentType: message['content_type']?.toString() ?? 'text',
          hasDownloadableFile: message['has_downloadable_file'] as bool? ?? false,
          replyToId: message['reply_to_id']?.toString(),
          replyPreview: message['reply_preview']?.toString(),
          forwardedFrom: message['forwarded_from']?.toString(),
          scheduledAt: DateTime.tryParse(message['scheduled_at']?.toString() ?? ''),
          voiceDuration: (message['voice_duration'] as num?)?.toInt(),
          mentions: (message['mentions'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
          hashtags: (message['hashtags'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
          editVersionsCount: (message['edit_versions_count'] as num?)?.toInt() ?? 0,
        ),
        chatTitle: row['chat_title']?.toString() ?? '',
        chatId: row['chat_id']?.toString() ?? '',
        chatType: row['chat_type']?.toString() ?? 'private',
      );
    }).toList();
  }

}
