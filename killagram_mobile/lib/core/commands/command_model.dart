enum CommandCategory {
  navigation,
  smartViews,
  automation,
  localPro,
  settings,
  messageActions,
}

class CommandModel {
  const CommandModel({
    required this.id,
    required this.title,
    required this.category,
    required this.onExecute,
    this.subtitle,
    this.keywords = const <String>[],
    this.isEnabled = true,
    this.isLocked = false,
  });

  final String id;
  final String title;
  final String? subtitle;
  final CommandCategory category;
  final List<String> keywords;
  final Future<void> Function() onExecute;
  final bool isEnabled;
  final bool isLocked;
}
