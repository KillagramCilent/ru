import 'package:equatable/equatable.dart';
import 'message.dart';

class SearchResult extends Equatable {
  const SearchResult({
    required this.message,
    required this.chatTitle,
    required this.chatId,
    this.chatType = 'private',
  });

  final Message message;
  final String chatTitle;
  final String chatId;
  final String chatType;

  @override
  List<Object?> get props => [message, chatTitle, chatId, chatType];
}
