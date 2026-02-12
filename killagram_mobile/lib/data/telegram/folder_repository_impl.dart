import '../../domain/entities/chat.dart';
import '../../domain/entities/folder.dart';
import '../../domain/repositories/folder_repository.dart';
import 'telegram_gateway.dart';

class FolderRepositoryImpl implements FolderRepository {
  FolderRepositoryImpl(this._gateway);

  final TelegramGateway _gateway;

  @override
  Future<List<Folder>> getFolders() {
    return _gateway.fetchFolders();
  }

  @override
  Future<List<Chat>> getFolderChats(String folderId) {
    return _gateway.fetchFolderChats(folderId);
  }
}
