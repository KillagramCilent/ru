import '../../domain/entities/message.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/smart_view.dart';
import '../../domain/repositories/smart_view_repository.dart';
import 'local_message_store.dart';

class SmartViewRepositoryImpl implements SmartViewRepository {
  SmartViewRepositoryImpl(this._localStore);

  final LocalMessageStore _localStore;

  static const _defs = <Map<String, dynamic>>[
    {'id': 'important', 'title': 'Important messages', 'icon': '⭐', 'premium': false},
    {'id': 'unread_thread_replies', 'title': 'Unread thread replies', 'icon': '🧵', 'premium': false},
    {'id': 'mentions_me', 'title': 'Mentions me', 'icon': '@', 'premium': false},
    {'id': 'files_media', 'title': 'Files & media', 'icon': '📎', 'premium': false},
    {'id': 'automation', 'title': 'Automation-applied', 'icon': '🤖', 'premium': false},
    {'id': 'delivery', 'title': 'Failed / pending / scheduled', 'icon': '⏳', 'premium': false},
  ];

  @override
  Future<List<SmartView>> listViews() async {
    final pinned = await _localStore.getPinnedSmartViews();
    final counts = await _localStore.getSmartViewCounts();
    final custom = await _localStore.getCustomSmartViews();

    final baseViews = _defs
        .map(
          (it) => SmartView(
            id: it['id'].toString(),
            title: it['title'].toString(),
            icon: it['icon'].toString(),
            count: counts[it['id']] as int? ?? 0,
            pinned: pinned.contains(it['id']),
            isPremium: it['premium'] as bool? ?? false,
          ),
        )
        .toList();

    final docs = await _localStore.allSearchDocuments();
    final customViews = custom.map((it) {
      final id = it['id']?.toString() ?? '';
      final count = docs.where((row) => _matchesCustomDefinition(row, it)).length;
      return SmartView(
        id: id,
        title: it['title']?.toString() ?? 'Custom view',
        icon: it['icon']?.toString() ?? '✨',
        count: count,
        pinned: pinned.contains(id),
        isPremium: true,
        isCustom: true,
        definition: it,
      );
    }).toList();

    final views = [...baseViews, ...customViews];
    views.sort((a, b) {
      if (a.pinned == b.pinned) return a.title.compareTo(b.title);
      return a.pinned ? -1 : 1;
    });
    return views;
  }

  @override
  Future<void> pinView(String viewId, bool pinned) async {
    final current = await _localStore.getPinnedSmartViews();
    final next = <String>{...current};
    if (pinned) {
      next.add(viewId);
    } else {
      next.remove(viewId);
    }
    await _localStore.setPinnedSmartViews(next.toList());
  }

  @override
  Future<void> activateView(String? viewId) async {
    if (viewId == null || viewId.isEmpty) {
      await _localStore.setUiSetting('smart_view_active', '');
      return;
    }
    await _localStore.setUiSetting('smart_view_active', viewId);
  }

  @override
  Future<String?> activeViewId() async {
    final value = await _localStore.getUiSetting('smart_view_active');
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<List<SearchResult>> openView(String viewId, {int limit = 120}) async {
    final rows = await _localStore.openSmartView(viewId, limit: limit);
    if (rows.isNotEmpty) {
      return _rowsToResults(rows);
    }

    final custom = await _localStore.getCustomSmartViews();
    final def = custom.where((it) => it['id']?.toString() == viewId).cast<Map<String, dynamic>?>().firstWhere((it) => it != null, orElse: () => null);
    if (def == null) {
      return const [];
    }
    final docs = await _localStore.allSearchDocuments();
    final filtered = docs.where((row) => _matchesCustomDefinition(row, def)).toList();
    filtered.sort((a, b) => ((b['timestamp'] as num?)?.toInt() ?? 0) - ((a['timestamp'] as num?)?.toInt() ?? 0));
    return _rowsToResults(filtered.take(limit).toList());
  }

  @override
  Future<void> saveCustomView(Map<String, dynamic> definition) async {
    final defs = await _localStore.getCustomSmartViews();
    final id = definition['id']?.toString() ?? 'custom_${DateTime.now().microsecondsSinceEpoch}';
    final normalized = {
      'id': id,
      'title': definition['title']?.toString() ?? 'Custom view',
      'icon': definition['icon']?.toString() ?? '✨',
      'sender': definition['sender']?.toString() ?? '',
      'keyword': definition['keyword']?.toString() ?? '',
      'regex': definition['regex']?.toString() ?? '',
      'media_type': definition['media_type']?.toString() ?? '',
      'from_ts': definition['from_ts'],
      'to_ts': definition['to_ts'],
      'automation_required': definition['automation_required'] == true,
    };
    final next = defs.where((it) => it['id']?.toString() != id).toList()..add(normalized);
    await _localStore.saveCustomSmartViews(next);
  }

  @override
  Future<void> deleteCustomView(String viewId) async {
    final defs = await _localStore.getCustomSmartViews();
    await _localStore.saveCustomSmartViews(defs.where((it) => it['id']?.toString() != viewId).toList());
  }

  @override
  Future<void> saveSearchAsSmartView(Map<String, dynamic> searchDefinition) async {
    await saveCustomView({
      'title': searchDefinition['title']?.toString() ?? 'Saved search',
      'icon': '🔎',
      'sender': searchDefinition['sender']?.toString() ?? '',
      'keyword': searchDefinition['query']?.toString() ?? '',
      'from_ts': searchDefinition['from_ts'],
      'to_ts': searchDefinition['to_ts'],
      'media_type': searchDefinition['has_media'] == true ? 'media' : '',
      'automation_required': searchDefinition['automation_required'] == true,
    });
  }

  bool _matchesCustomDefinition(Map<String, dynamic> row, Map<String, dynamic> definition) {
    final sender = definition['sender']?.toString() ?? '';
    if (sender.isNotEmpty && row['sender_id']?.toString() != sender) {
      return false;
    }

    final keyword = definition['keyword']?.toString() ?? '';
    if (keyword.isNotEmpty && !(row['text']?.toString().toLowerCase().contains(keyword.toLowerCase()) ?? false)) {
      return false;
    }

    final regex = definition['regex']?.toString() ?? '';
    if (regex.isNotEmpty) {
      final text = row['text']?.toString() ?? '';
      if (!RegExp(regex, caseSensitive: false).hasMatch(text)) {
        return false;
      }
    }

    final fromTs = (definition['from_ts'] as num?)?.toInt();
    final toTs = (definition['to_ts'] as num?)?.toInt();
    final ts = (row['timestamp'] as num?)?.toInt() ?? 0;
    if (fromTs != null && ts < fromTs) {
      return false;
    }
    if (toTs != null && ts > toTs) {
      return false;
    }

    final mediaType = definition['media_type']?.toString() ?? '';
    if (mediaType.isNotEmpty) {
      if (mediaType == 'media' && (row['has_media'] as bool? ?? false) != true) {
        return false;
      }
      if (mediaType != 'media' && row['content_type']?.toString() != mediaType) {
        return false;
      }
    }

    if (definition['automation_required'] == true) {
      final applied = (row['applied_rules'] as List<dynamic>? ?? const []);
      if (applied.isEmpty) {
        return false;
      }
    }

    return true;
  }

  List<SearchResult> _rowsToResults(List<Map<String, dynamic>> rows) {
    return rows
        .map(
          (row) => SearchResult(
            chatId: row['chat_id']?.toString() ?? '',
            chatTitle: row['chat_id']?.toString() == '-1' ? 'Saved Messages' : 'Chat ${row['chat_id']}',
            message: Message(
              id: row['id']?.toString() ?? '',
              chatId: row['chat_id']?.toString() ?? '',
              sender: row['sender_id']?.toString() ?? '',
              text: row['text']?.toString() ?? '',
              timestamp: DateTime.fromMillisecondsSinceEpoch((row['timestamp'] as num?)?.toInt() ?? 0),
              isOutgoing: row['is_outgoing'] as bool? ?? false,
              isRead: row['is_read'] as bool? ?? false,
              contentType: row['content_type']?.toString() ?? 'text',
              replyToId: row['reply_to_id']?.toString(),
              mentions: (row['mentions'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
              outgoingState: OutgoingMessageState.values.firstWhere(
                (it) => it.name == (row['outgoing_state']?.toString() ?? 'sent'),
                orElse: () => OutgoingMessageState.sent,
              ),
              isImportant: row['is_important'] as bool? ?? false,
              isLocalPinned: row['is_local_pinned'] as bool? ?? false,
              localNote: row['local_note']?.toString(),
              appliedAutomationRuleIds: (row['applied_rules'] as List<dynamic>? ?? const []).map((it) => it.toString()).toList(),
            ),
          ),
        )
        .toList();
  }
}
