import '../entities/workspace.dart';

abstract class WorkspaceRepository {
  Future<List<Workspace>> list();
  Future<Workspace> create({required String name, String description = ''});
  Future<void> update(Workspace workspace);
  Future<void> delete(String workspaceId);
  Future<void> pin(String workspaceId, bool pinned);
  Future<void> bindChat(String workspaceId, String chatId);
  Future<void> unbindChat(String workspaceId, String chatId);
  Future<List<String>> chatIds(String workspaceId);
  Future<WorkspaceDashboard> dashboard(String workspaceId, {int limit = 30});
  Future<String?> selectedWorkspaceId();
  Future<void> setSelectedWorkspaceId(String? workspaceId);
}
