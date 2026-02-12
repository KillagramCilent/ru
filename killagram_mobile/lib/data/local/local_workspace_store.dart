import 'package:hive_flutter/hive_flutter.dart';

import '../../domain/entities/workspace.dart';

class LocalWorkspaceStore {
  static const _boxName = 'workspace_local_store';

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  Box get _box => Hive.box(_boxName);

  Future<List<Workspace>> listWorkspaces() async {
    final raw = _box.get('workspaces', defaultValue: const <dynamic>[]);
    final rows = (raw as List<dynamic>).whereType<Map>().map((it) => Map<String, dynamic>.from(it as Map)).toList();
    final items = rows
        .map(
          (row) => Workspace(
            id: row['id']?.toString() ?? '',
            name: row['name']?.toString() ?? 'Workspace',
            description: row['description']?.toString() ?? '',
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ?? DateTime.now(),
            pinned: row['pinned'] == true,
          ),
        )
        .where((it) => it.id.isNotEmpty)
        .toList();
    items.sort((a, b) {
      final byPin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
      if (byPin != 0) return byPin;
      return b.createdAt.compareTo(a.createdAt);
    });
    return items;
  }

  Future<void> saveWorkspaces(List<Workspace> items) async {
    await _box.put(
      'workspaces',
      items
          .map(
            (it) => {
              'id': it.id,
              'name': it.name,
              'description': it.description,
              'created_at': it.createdAt.toIso8601String(),
              'pinned': it.pinned,
            },
          )
          .toList(),
    );
  }

  Future<List<String>> chatIdsForWorkspace(String workspaceId) async {
    final raw = _box.get('workspace_chats:$workspaceId', defaultValue: const <dynamic>[]);
    return (raw as List<dynamic>).map((it) => it.toString()).where((it) => it.isNotEmpty).toSet().toList();
  }

  Future<void> setChatIdsForWorkspace(String workspaceId, List<String> chatIds) async {
    await _box.put('workspace_chats:$workspaceId', chatIds.toSet().toList());
  }

  Future<String?> selectedWorkspaceId() async {
    final raw = _box.get('workspace_selected_id');
    final value = raw?.toString();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> setSelectedWorkspaceId(String? workspaceId) async {
    if (workspaceId == null || workspaceId.isEmpty) {
      await _box.delete('workspace_selected_id');
      return;
    }
    await _box.put('workspace_selected_id', workspaceId);
  }
}
