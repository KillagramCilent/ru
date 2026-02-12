import 'package:equatable/equatable.dart';

class Folder extends Equatable {
  const Folder({
    required this.id,
    required this.title,
    required this.includeTypes,
    required this.chatIds,
    required this.order,
    required this.isSystem,
    this.emojiId,
    this.emojiFallback,
  });

  final String id;
  final String title;
  final List<String> includeTypes;
  final List<String> chatIds;
  final int order;
  final bool isSystem;
  final String? emojiId;
  final String? emojiFallback;

  String get titleWithEmoji => '${emojiFallback ?? ''}${emojiFallback == null ? '' : ' '}$title';

  @override
  List<Object?> get props => [id, title, includeTypes, chatIds, order, isSystem, emojiId, emojiFallback];
}
