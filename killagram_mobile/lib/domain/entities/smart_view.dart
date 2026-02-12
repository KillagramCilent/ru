import 'package:equatable/equatable.dart';

class SmartView extends Equatable {
  const SmartView({
    required this.id,
    required this.title,
    required this.icon,
    required this.count,
    this.pinned = false,
    this.isPremium = false,
    this.isCustom = false,
    this.definition = const {},
  });

  final String id;
  final String title;
  final String icon;
  final int count;
  final bool pinned;
  final bool isPremium;
  final bool isCustom;
  final Map<String, dynamic> definition;

  SmartView copyWith({
    int? count,
    bool? pinned,
    bool? isPremium,
    bool? isCustom,
    Map<String, dynamic>? definition,
  }) {
    return SmartView(
      id: id,
      title: title,
      icon: icon,
      count: count ?? this.count,
      pinned: pinned ?? this.pinned,
      isPremium: isPremium ?? this.isPremium,
      isCustom: isCustom ?? this.isCustom,
      definition: definition ?? this.definition,
    );
  }

  @override
  List<Object?> get props => [id, title, icon, count, pinned, isPremium, isCustom, definition];
}
