import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/message.dart';

class LocalMessageStore {
  static const _boxName = 'chat_local_store';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  Box get _box => Hive.box(_boxName);

  Future<List<Map<String, dynamic>>> getChatMessages(String chatId) async {
    final raw = _box.get('messages:$chatId', defaultValue: const <dynamic>[]);
    return (raw as List<dynamic>).whereType<Map>().map((it) => Map<String, dynamic>.from(it as Map)).toList();
  }

  Future<void> saveChatMessages(String chatId, List<Message> messages) async {
    final payload = messages
        .where((m) => m.id.startsWith('local_') || m.outgoingState != OutgoingMessageState.sent)
        .map((m) => {
              'id': m.id,
              'chat_id': m.chatId,
              'sender': m.sender,
              'text': m.text,
              'timestamp': m.timestamp.toIso8601String(),
              'is_outgoing': m.isOutgoing,
              'reply_to_id': m.replyToId,
              'content_type': m.contentType,
              'voice_duration': m.voiceDuration,
              'outgoing_state': m.outgoingState.name,
              'client_message_id': m.clientMessageId,
              'is_important': m.isImportant,
              'local_note': m.localNote,
              'is_local_pinned': m.isLocalPinned,
            })
        .toList();
    await _box.put('messages:$chatId', payload);
  }

  Future<Map<String, dynamic>> readFlags(String messageId) async {
    final raw = _box.get('flags:$messageId', defaultValue: const <String, dynamic>{});
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> saveFlags(String messageId, Map<String, dynamic> flags) async {
    await _box.put('flags:$messageId', flags);
  }

  Future<void> upsertSearchDocument(Message message) async {
    final key = 'search:${message.id}';
    final previousRaw = _box.get(key);
    final previous = previousRaw is Map ? Map<String, dynamic>.from(previousRaw) : null;

    final ts = message.timestamp.millisecondsSinceEpoch;
    final hasLinks = RegExp(r'https?://').hasMatch(message.text);
    final hasMedia = message.contentType != 'text';
    final tokens = message.text.toLowerCase().split(RegExp(r'[^\p{L}\p{N}_#@]+', unicode: true)).where((row) => row.isNotEmpty).toSet().toList();
    final next = {
      'id': message.id,
      'chat_id': message.chatId,
      'sender_id': message.sender,
      'text': message.text,
      'timestamp': ts,
      'is_outgoing': message.isOutgoing,
      'is_read': message.isRead,
      'content_type': message.contentType,
      'reply_to_id': message.replyToId,
      'mentions': message.mentions,
      'has_media': hasMedia,
      'has_links': hasLinks,
      'tokens': tokens,
      'blob': base64Encode(utf8.encode(message.text.toLowerCase())),
      'is_important': message.isImportant,
      'is_local_pinned': message.isLocalPinned,
      'local_note': message.localNote,
      'applied_rules': message.appliedAutomationRuleIds,
      'outgoing_state': message.outgoingState.name,
      'scheduled_at': message.scheduledAt?.toIso8601String(),
    };
    await _box.put(key, next);
    await _updateSmartViewCounts(previous: previous, next: next);
  }

  Future<void> removeSearchDocument(String messageId) async {
    final key = 'search:$messageId';
    final previousRaw = _box.get(key);
    final previous = previousRaw is Map ? Map<String, dynamic>.from(previousRaw) : null;
    await _box.delete(key);
    await _updateSmartViewCounts(previous: previous, next: null);
  }


  Future<List<Map<String, dynamic>>> getAllSearchDocuments() async {
    return _box
        .toMap()
        .entries
        .where((e) => e.key.toString().startsWith('search:'))
        .map((e) => Map<String, dynamic>.from(e.value as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchLocal({
    required String query,
    String? chatId,
    String? senderId,
    DateTime? from,
    DateTime? to,
    bool? hasMedia,
    bool? hasLinks,
    int limit = 50,
  }) async {
    final q = query.toLowerCase();
    final entries = _box.toMap().entries.where((e) => e.key.toString().startsWith('search:')).map((e) => Map<String, dynamic>.from(e.value as Map)).toList();
    final fromMs = from?.millisecondsSinceEpoch;
    final toMs = to?.millisecondsSinceEpoch;
    final filtered = entries.where((row) {
      if (chatId != null && chatId.isNotEmpty && row['chat_id']?.toString() != chatId) return false;
      if (senderId != null && senderId.isNotEmpty && row['sender_id']?.toString() != senderId) return false;
      final ts = (row['timestamp'] as num?)?.toInt() ?? 0;
      if (fromMs != null && ts < fromMs) return false;
      if (toMs != null && ts > toMs) return false;
      if (hasMedia != null && (row['has_media'] as bool? ?? false) != hasMedia) return false;
      if (hasLinks != null && (row['has_links'] as bool? ?? false) != hasLinks) return false;
      final text = utf8.decode(base64Decode(row['blob']?.toString() ?? ''));
      return text.contains(q);
    }).toList();
    filtered.sort((a, b) => ((b['timestamp'] as num?)?.toInt() ?? 0) - ((a['timestamp'] as num?)?.toInt() ?? 0));
    return filtered.take(limit).toList();
  }


  bool _isInSmartView(String viewId, Map<String, dynamic> row) {
    final hasMedia = row['has_media'] as bool? ?? false;
    final mentions = (row['mentions'] as List<dynamic>? ?? const []).map((it) => it.toString().toLowerCase()).toList();
    final replyToId = row['reply_to_id']?.toString();
    final isRead = row['is_read'] as bool? ?? false;
    final applied = (row['applied_rules'] as List<dynamic>? ?? const []).isNotEmpty;
    final state = row['outgoing_state']?.toString() ?? 'sent';
    final scheduledAt = row['scheduled_at']?.toString();
    switch (viewId) {
      case 'important':
        return row['is_important'] as bool? ?? false;
      case 'unread_thread_replies':
        return replyToId != null && replyToId.isNotEmpty && !isRead;
      case 'mentions_me':
        return mentions.contains('me') || mentions.contains('@me') || row['text']?.toString().contains('@me') == true;
      case 'files_media':
        return hasMedia;
      case 'automation':
        return applied;
      case 'delivery':
        return state == 'failed' || state == 'pending' || (scheduledAt != null && scheduledAt.isNotEmpty);
      default:
        return false;
    }
  }

  Future<Map<String, int>> getSmartViewCounts() async {
    final raw = _box.get('smart_view_counts', defaultValue: const <String, int>{});
    final map = Map<String, dynamic>.from(raw as Map);
    return map.map((key, value) => MapEntry(key, (value as num).toInt()));
  }

  Future<void> _setSmartViewCounts(Map<String, int> counts) async {
    await _box.put('smart_view_counts', counts);
  }

  Future<void> _updateSmartViewCounts({Map<String, dynamic>? previous, Map<String, dynamic>? next}) async {
    final ids = const ['important', 'unread_thread_replies', 'mentions_me', 'files_media', 'automation', 'delivery'];
    final counts = await getSmartViewCounts();
    for (final id in ids) {
      final prev = previous != null && _isInSmartView(id, previous);
      final now = next != null && _isInSmartView(id, next);
      if (prev == now) {
        continue;
      }
      final cur = counts[id] ?? 0;
      counts[id] = now ? cur + 1 : (cur - 1 < 0 ? 0 : cur - 1);
    }
    await _setSmartViewCounts(counts);
  }

  Future<List<Map<String, dynamic>>> openSmartView(String viewId, {int limit = 120}) async {
    final rows = _box
        .toMap()
        .entries
        .where((entry) => entry.key.toString().startsWith('search:'))
        .map((entry) => Map<String, dynamic>.from(entry.value as Map))
        .where((row) => _isInSmartView(viewId, row))
        .toList();
    rows.sort((a, b) => ((b['timestamp'] as num?)?.toInt() ?? 0) - ((a['timestamp'] as num?)?.toInt() ?? 0));
    return rows.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> allSearchDocuments() async {
    return _box
        .toMap()
        .entries
        .where((entry) => entry.key.toString().startsWith('search:'))
        .map((entry) => Map<String, dynamic>.from(entry.value as Map))
        .toList();
  }

  Future<List<String>> getPinnedSmartViews() async {
    final raw = _box.get('smart_view_pinned', defaultValue: const <dynamic>[]);
    return (raw as List<dynamic>).map((it) => it.toString()).toList();
  }

  Future<void> setPinnedSmartViews(List<String> ids) async {
    await _box.put('smart_view_pinned', ids);
  }

  Future<List<Map<String, dynamic>>> getCustomSmartViews() async {
    final raw = _box.get('smart_view_custom', defaultValue: const <dynamic>[]);
    return (raw as List<dynamic>).whereType<Map>().map((it) => Map<String, dynamic>.from(it as Map)).toList();
  }

  Future<void> saveCustomSmartViews(List<Map<String, dynamic>> defs) async {
    await _box.put('smart_view_custom', defs);
  }

  Future<void> saveLastSearchDefinition(Map<String, dynamic> definition) async {
    await _box.put('search_last_definition', definition);
  }

  Future<Map<String, dynamic>?> readLastSearchDefinition() async {
    final raw = _box.get('search_last_definition');
    if (raw is! Map) {
      return null;
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<Map<String, dynamic>> getRuleExecutionStats() async {
    final raw = _box.get('automation_rule_stats', defaultValue: const <String, dynamic>{});
    return Map<String, dynamic>.from(raw as Map);
  }

  Future<void> incrementRuleExecution(String ruleId) async {
    final stats = await getRuleExecutionStats();
    stats[ruleId] = (stats[ruleId] as num? ?? 0) + 1;
    await _box.put('automation_rule_stats', stats);
  }

  Future<bool> getLocalProEnabled() async {
    return _box.get('local_pro_enabled', defaultValue: false) == true;
  }

  Future<void> setLocalProEnabled(bool value) async {
    await _box.put('local_pro_enabled', value);
  }

  Future<String> getUserLocalEmoji() async {
    return _box.get('user_local_emoji', defaultValue: '')?.toString() ?? '';
  }

  Future<void> setUserLocalEmoji(String value) async {
    await _box.put('user_local_emoji', value);
  }

  Future<bool> getDesktopOnboardingCompleted() async {
    return _box.get('desktop_onboarding_completed', defaultValue: false) == true;
  }

  Future<void> setDesktopOnboardingCompleted(bool value) async {
    await _box.put('desktop_onboarding_completed', value);
  }

  Future<Map<String, bool>> getDesktopFirstRunChecklist() async {
    final raw = _box.get('desktop_first_run_checklist', defaultValue: const <String, bool>{});
    final map = Map<String, dynamic>.from(raw as Map);
    return map.map((key, value) => MapEntry(key, value == true));
  }

  Future<void> setDesktopFirstRunChecklist(Map<String, bool> value) async {
    await _box.put('desktop_first_run_checklist', value);
  }

  Future<List<Map<String, dynamic>>> getAutomationRules() async {
    final raw = _box.get('automation_rules', defaultValue: const <dynamic>[]);
    return (raw as List<dynamic>).whereType<Map>().map((it) => Map<String, dynamic>.from(it as Map)).toList();
  }

  Future<void> saveAutomationRules(List<Map<String, dynamic>> rules) async {
    await _box.put('automation_rules', rules);
  }

  Future<String?> getUiSetting(String key) async {
    return _box.get('ui:$key')?.toString();
  }

  Future<void> setUiSetting(String key, String value) async {
    await _box.put('ui:$key', value);
  }
}
