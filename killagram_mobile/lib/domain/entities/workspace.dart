import 'package:equatable/equatable.dart';

class Workspace extends Equatable {
  const Workspace({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    this.pinned = false,
  });

  final String id;
  final String name;
  final String description;
  final DateTime createdAt;
  final bool pinned;

  Workspace copyWith({
    String? name,
    String? description,
    DateTime? createdAt,
    bool? pinned,
  }) {
    return Workspace(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      pinned: pinned ?? this.pinned,
    );
  }

  @override
  List<Object?> get props => [id, name, description, createdAt, pinned];
}

class WorkspaceDashboard extends Equatable {
  const WorkspaceDashboard({
    required this.workspace,
    required this.chatIds,
    required this.recentMessages,
    required this.smartViewCounts,
  });

  final Workspace workspace;
  final List<String> chatIds;
  final List<Map<String, dynamic>> recentMessages;
  final Map<String, int> smartViewCounts;

  @override
  List<Object?> get props => [workspace, chatIds, recentMessages, smartViewCounts];
}
