import '../../domain/entities/search_result.dart';
import '../../domain/repositories/search_repository.dart';
import 'telegram_gateway.dart';

class SearchRepositoryImpl implements SearchRepository {
  SearchRepositoryImpl(this._gateway);

  final TelegramGateway _gateway;

  @override
  Future<List<SearchResult>> searchMessages(SearchMessagesParams params) {
    return _gateway.searchMessages(params);
  }
}
