import '../../domain/entities/workspace.dart';
import '../../domain/repositories/workspace_repository.dart';
import 'local_message_store.dart';
import 'local_workspace_store.dart';

class WorkspaceRepositoryImpl implements WorkspaceRepository {
  WorkspaceRepositoryImpl(this._store, this._messageStore);

  final LocalWorkspaceStore _store;
  final LocalMessageStore _messageStore;

  @override
  Future<List<Workspace>> list() async {
    final items = await _store.listWorkspaces();
    if (items.isNotEmpty) {
      return items;
    }
    final fallback = Workspace(
      id: 'workspace_default',
      name: 'My Workspace',
      description: 'Default workspace',
      createdAt: DateTime.now(),
      pinned: true,
    );
    await _store.saveWorkspaces([fallback]);
    await _store.setSelectedWorkspaceId(fallback.id);
    return [fallback];
  }

  @override
  Future<Workspace> create({required String name, String description = ''}) async {
    final all = await list();
    final item = Workspace(
      id: 'ws_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Workspace' : name.trim(),
      description: description.trim(),
      createdAt: DateTime.now(),
      pinned: false,
    );
    await _store.saveWorkspaces([item, ...all]);
    return item;
  }

  @override
  Future<void> update(Workspace workspace) async {
    final all = await list();
    final next = all.map((it) => it.id == workspace.id ? workspace : it).toList();
    await _store.saveWorkspaces(next);
  }

  @override
  Future<void> delete(String workspaceId) async {
    final all = await list();
    final next = all.where((it) => it.id != workspaceId).toList();
    await _store.saveWorkspaces(next);
    final selected = await _store.selectedWorkspaceId();
    if (selected == workspaceId) {
      await _store.setSelectedWorkspaceId(next.isEmpty ? null : next.first.id);
    }
  }

  @override
  Future<void> pin(String workspaceId, bool pinned) async {
    final all = await list();
    final next = all.map((it) => it.id == workspaceId ? it.copyWith(pinned: pinned) : it).toList();
    await _store.saveWorkspaces(next);
  }

  @override
  Future<void> bindChat(String workspaceId, String chatId) async {
    final ids = await _store.chatIdsForWorkspace(workspaceId);
    if (!ids.contains(chatId)) {
      ids.add(chatId);
      await _store.setChatIdsForWorkspace(workspaceId, ids);
    }
  }

  @override
  Future<void> unbindChat(String workspaceId, String chatId) async {
    final ids = await _store.chatIdsForWorkspace(workspaceId);
    ids.remove(chatId);
    await _store.setChatIdsForWorkspace(workspaceId, ids);
  }

  @override
  Future<List<String>> chatIds(String workspaceId) {
    return _store.chatIdsForWorkspace(workspaceId);
  }

  @override
  Future<WorkspaceDashboard> dashboard(String workspaceId, {int limit = 30}) async {
    final workspaces = await list();
    final workspace = workspaces.firstWhere((it) => it.id == workspaceId, orElse: () => workspaces.first);
    final boundChatIds = await chatIds(workspace.id);
    final docs = await _messageStore.getAllSearchDocuments();
    final filtered = docs.where((row) => boundChatIds.isEmpty || boundChatIds.contains(row['chat_id']?.toString() ?? '')).toList();
    filtered.sort((a, b) => ((b['timestamp'] as num?)?.toInt() ?? 0) - ((a['timestamp'] as num?)?.toInt() ?? 0));
    final recent = filtered.take(limit).toList();

    final counts = <String, int>{
      'important': 0,
      'mentions_me': 0,
      'files_media': 0,
      'automation': 0,
      'failed_pending': 0,
    };

    for (final row in filtered) {
      if (row['is_important'] == true) counts['important'] = (counts['important'] ?? 0) + 1;
      final mentions = (row['mentions'] as List<dynamic>? ?? const []).map((it) => it.toString().toLowerCase()).toList();
      if (mentions.contains('me') || mentions.contains('@me') || (row['text']?.toString().contains('@me') ?? false)) {
        counts['mentions_me'] = (counts['mentions_me'] ?? 0) + 1;
      }
      if (row['has_media'] == true) counts['files_media'] = (counts['files_media'] ?? 0) + 1;
      if ((row['applied_rules'] as List<dynamic>? ?? const []).isNotEmpty) counts['automation'] = (counts['automation'] ?? 0) + 1;
      final state = row['outgoing_state']?.toString() ?? 'sent';
      if (state == 'pending' || state == 'failed') counts['failed_pending'] = (counts['failed_pending'] ?? 0) + 1;
    }

    return WorkspaceDashboard(
      workspace: workspace,
      chatIds: boundChatIds,
      recentMessages: recent,
      smartViewCounts: counts,
    );
  }

  @override
  Future<String?> selectedWorkspaceId() {
    return _store.selectedWorkspaceId();
  }

  @override
  Future<void> setSelectedWorkspaceId(String? workspaceId) {
    return _store.setSelectedWorkspaceId(workspaceId);
  }
}
