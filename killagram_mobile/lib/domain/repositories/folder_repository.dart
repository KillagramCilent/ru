import '../entities/chat.dart';
import '../entities/folder.dart';

abstract class FolderRepository {
  Future<List<Folder>> getFolders();
  Future<List<Chat>> getFolderChats(String folderId);
}
