import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/commands/command_model.dart';
import '../../core/commands/command_registry_service.dart';

class CommandPaletteOverlay extends StatefulWidget {
  const CommandPaletteOverlay({
    super.key,
    required this.registry,
  });

  final CommandRegistryService registry;

  @override
  State<CommandPaletteOverlay> createState() => _CommandPaletteOverlayState();
}

class _CommandPaletteOverlayState extends State<CommandPaletteOverlay> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  List<CommandModel> _commands = const <CommandModel>[];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _commands = widget.registry.all();
    WidgetsBinding.instance.addPostFrameCallback((_) => _inputFocus.requestFocus());
    _queryController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_onQueryChanged)
      ..dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final next = widget.registry.search(_queryController.text);
    setState(() {
      _commands = next;
      if (_selectedIndex >= _commands.length) {
        _selectedIndex = _commands.isEmpty ? 0 : _commands.length - 1;
      }
    });
  }

  void _moveSelection(int delta) {
    if (_commands.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % _commands.length;
      if (_selectedIndex < 0) {
        _selectedIndex = _commands.length - 1;
      }
    });
  }

  Future<void> _runSelected() async {
    if (_commands.isEmpty) return;
    final command = _commands[_selectedIndex];
    if (!command.isEnabled || command.isLocked) return;
    Navigator.of(context).pop(command);
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): _PaletteNextIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): _PalettePrevIntent(),
        SingleActivator(LogicalKeyboardKey.enter): _PaletteExecuteIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _PaletteCloseIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PaletteNextIntent: CallbackAction<_PaletteNextIntent>(onInvoke: (_) {
            _moveSelection(1);
            return null;
          }),
          _PalettePrevIntent: CallbackAction<_PalettePrevIntent>(onInvoke: (_) {
            _moveSelection(-1);
            return null;
          }),
          _PaletteExecuteIntent: CallbackAction<_PaletteExecuteIntent>(onInvoke: (_) {
            _runSelected();
            return null;
          }),
          _PaletteCloseIntent: CallbackAction<_PaletteCloseIntent>(onInvoke: (_) {
            Navigator.of(context).pop();
            return null;
          }),
        },
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _queryController,
                    focusNode: _inputFocus,
                    decoration: const InputDecoration(
                      hintText: 'Type a command...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: _commands.isEmpty
                      ? const Center(child: Text('No commands found'))
                      : ListView.builder(
                          itemCount: _commands.length,
                          itemBuilder: (context, index) {
                            final command = _commands[index];
                            final selected = _selectedIndex == index;
                            return ListTile(
                              selected: selected,
                              enabled: command.isEnabled,
                              leading: Icon(_iconForCategory(command.category)),
                              title: Text(command.title),
                              subtitle: Text(command.subtitle ?? _categoryName(command.category)),
                              trailing: command.isLocked ? const Icon(Icons.lock_outline, color: Colors.orange) : null,
                              onTap: command.isEnabled && !command.isLocked ? () => Navigator.of(context).pop(command) : null,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForCategory(CommandCategory category) {
    switch (category) {
      case CommandCategory.navigation:
        return Icons.navigation_outlined;
      case CommandCategory.smartViews:
        return Icons.auto_awesome_mosaic_outlined;
      case CommandCategory.automation:
        return Icons.auto_fix_high_outlined;
      case CommandCategory.localPro:
        return Icons.workspace_premium_outlined;
      case CommandCategory.settings:
        return Icons.settings_outlined;
      case CommandCategory.messageActions:
        return Icons.message_outlined;
    }
  }

  String _categoryName(CommandCategory category) {
    switch (category) {
      case CommandCategory.navigation:
        return 'Navigation';
      case CommandCategory.smartViews:
        return 'Smart Views';
      case CommandCategory.automation:
        return 'Automation';
      case CommandCategory.localPro:
        return 'Local Pro';
      case CommandCategory.settings:
        return 'Settings';
      case CommandCategory.messageActions:
        return 'Message Actions';
    }
  }
}

class _PaletteNextIntent extends Intent {
  const _PaletteNextIntent();
}

class _PalettePrevIntent extends Intent {
  const _PalettePrevIntent();
}

class _PaletteExecuteIntent extends Intent {
  const _PaletteExecuteIntent();
}

class _PaletteCloseIntent extends Intent {
  const _PaletteCloseIntent();
}
