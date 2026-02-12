import 'command_model.dart';

class CommandRegistryService {
  List<CommandModel> _commands = const <CommandModel>[];

  void setCommands(List<CommandModel> commands) {
    _commands = commands;
  }

  List<CommandModel> all() => List<CommandModel>.unmodifiable(_commands);

  List<CommandModel> search(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return all();
    }
    final scored = <_ScoredCommand>[];
    for (final command in _commands) {
      final score = _score(command, trimmed);
      if (score > 0) {
        scored.add(_ScoredCommand(command, score));
      }
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.command.title.compareTo(b.command.title);
    });
    return scored.map((it) => it.command).toList(growable: false);
  }

  int _score(CommandModel command, String query) {
    final title = command.title.toLowerCase();
    final subtitle = (command.subtitle ?? '').toLowerCase();
    final keywords = command.keywords.join(' ').toLowerCase();
    if (title == query) return 120;
    if (title.startsWith(query)) return 90;
    if (title.contains(query)) return 75;
    if (subtitle.contains(query)) return 60;
    if (keywords.contains(query)) return 55;
    if (_isFuzzyMatch(title, query)) return 40;
    if (_isFuzzyMatch('$title $subtitle $keywords', query)) return 30;
    return 0;
  }

  bool _isFuzzyMatch(String source, String query) {
    if (query.isEmpty) return true;
    var index = 0;
    for (final rune in query.runes) {
      final char = String.fromCharCode(rune);
      index = source.indexOf(char, index);
      if (index < 0) return false;
      index += 1;
    }
    return true;
  }
}

class _ScoredCommand {
  const _ScoredCommand(this.command, this.score);

  final CommandModel command;
  final int score;
}
