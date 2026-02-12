import 'package:flutter/foundation.dart';

import '../../domain/entities/workspace.dart';
import '../../domain/repositories/workspace_repository.dart';

class WorkspaceController {
  WorkspaceController(this._repository);

  final WorkspaceRepository _repository;

  final ValueNotifier<List<Workspace>> workspaces = ValueNotifier<List<Workspace>>(const []);
  final ValueNotifier<String?> selectedWorkspaceId = ValueNotifier<String?>(null);
  final ValueNotifier<WorkspaceDashboard?> dashboard = ValueNotifier<WorkspaceDashboard?>(null);

  Future<void> init() async {
    final rows = await _repository.list();
    workspaces.value = rows;
    final selected = await _repository.selectedWorkspaceId() ?? (rows.isEmpty ? null : rows.first.id);
    selectedWorkspaceId.value = selected;
    if (selected != null) {
      await refreshDashboard();
    }
  }

  Future<void> refresh() async {
    final rows = await _repository.list();
    workspaces.value = rows;
  }

  Future<void> createWorkspace(String name, {String description = ''}) async {
    final item = await _repository.create(name: name, description: description);
    await refresh();
    await selectWorkspace(item.id);
  }

  Future<void> selectWorkspace(String? workspaceId) async {
    selectedWorkspaceId.value = workspaceId;
    await _repository.setSelectedWorkspaceId(workspaceId);
    await refreshDashboard();
  }

  Future<void> togglePinned(Workspace workspace) async {
    await _repository.pin(workspace.id, !workspace.pinned);
    await refresh();
    await refreshDashboard();
  }

  Future<void> bindChatToSelected(String chatId) async {
    final id = selectedWorkspaceId.value;
    if (id == null) return;
    await _repository.bindChat(id, chatId);
    await refreshDashboard();
  }

  Future<void> unbindChatFromSelected(String chatId) async {
    final id = selectedWorkspaceId.value;
    if (id == null) return;
    await _repository.unbindChat(id, chatId);
    await refreshDashboard();
  }

  Future<List<String>> selectedWorkspaceChatIds() async {
    final id = selectedWorkspaceId.value;
    if (id == null) return const [];
    return _repository.chatIds(id);
  }

  Future<void> refreshDashboard() async {
    final id = selectedWorkspaceId.value;
    if (id == null) {
      dashboard.value = null;
      return;
    }
    dashboard.value = await _repository.dashboard(id);
  }
}
