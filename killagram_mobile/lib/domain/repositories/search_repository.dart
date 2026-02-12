import '../entities/search_result.dart';

enum SearchChatScope { private, groups, channels }

enum SearchContentType { text, photo, video, voice, file, link }

class SearchMessagesParams {
  const SearchMessagesParams({
    required this.query,
    this.folderId,
    this.chatId,
    this.senderId,
    this.hasMedia,
    this.savedOnly = false,
    this.chatScope = const <SearchChatScope>{},
    this.contentTypes = const <SearchContentType>{},
    this.hasDownloadableFile,
    this.limit = 30,
    this.offset = 0,
  });

  final String query;
  final String? folderId;
  final String? chatId;
  final String? senderId;
  final bool? hasMedia;
  final bool savedOnly;
  final Set<SearchChatScope> chatScope;
  final Set<SearchContentType> contentTypes;
  final bool? hasDownloadableFile;
  final int limit;
  final int offset;
}

abstract class SearchRepository {
  Future<List<SearchResult>> searchMessages(SearchMessagesParams params);
}
