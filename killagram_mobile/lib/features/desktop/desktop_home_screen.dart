import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/commands/command_action_dispatcher.dart';
import '../../core/commands/command_model.dart';
import '../../core/commands/command_registry_service.dart';
import '../../core/config/layout_breakpoints.dart';
import '../../core/di/service_locator.dart';
import '../../core/state/local_pro_controller.dart';
import '../../core/state/ui_settings_controller.dart';
import '../../core/state/workspace_controller.dart';
import '../../data/local/local_message_store.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/workspace.dart';
import '../../domain/repositories/smart_view_repository.dart';
import '../chat/chat_screen.dart';
import '../chat/chat_screen_controller.dart';
import '../chats/chats_list_pane.dart';
import '../chats/chats_list_pane_controller.dart';
import '../settings/settings_screen.dart';
import 'command_palette_overlay.dart';
import 'workspace_dashboard_screen.dart';

class DesktopHomeScreen extends StatefulWidget {
  const DesktopHomeScreen({super.key});

  @override
  State<DesktopHomeScreen> createState() => _DesktopHomeScreenState();
}

class _DesktopHomeScreenState extends State<DesktopHomeScreen> {
  final LocalMessageStore _store = ServiceLocator.get<LocalMessageStore>();
  bool _ready = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final completed = await _store.getDesktopOnboardingCompleted();
    if (!mounted) return;
    setState(() {
      _completed = completed;
      _ready = true;
    });
  }

  Future<void> _finishOnboarding() async {
    await _store.setDesktopOnboardingCompleted(true);
    if (!mounted) return;
    setState(() => _completed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_completed) {
      return _DesktopOnboardingScreen(onComplete: _finishOnboarding);
    }
    return const _DesktopMainShell();
  }
}

class _DesktopMainShell extends StatefulWidget {
  const _DesktopMainShell();

  @override
  State<_DesktopMainShell> createState() => _DesktopMainShellState();
}

class _DesktopMainShellState extends State<_DesktopMainShell> {
  final LocalProController _localProController = ServiceLocator.get<LocalProController>();
  final UiSettingsController _uiSettingsController = ServiceLocator.get<UiSettingsController>();
  final SmartViewRepository _smartViewRepository = ServiceLocator.get<SmartViewRepository>();
  final CommandRegistryService _commandRegistry = CommandRegistryService();
  final CommandActionDispatcher _commandDispatcher = CommandActionDispatcher();
  final ChatsListPaneController _chatsListPaneController = ChatsListPaneController();
  final ChatScreenController _chatScreenController = ChatScreenController();
  final WorkspaceController _workspaceController = ServiceLocator.get<WorkspaceController>();

  Chat? _selectedChat;
  String? _selectedMessageId;
  String _activeFolderId = 'all';
  int _clearHighlightToken = 0;
  Set<String>? _workspaceAllowedChatIds;

  @override
  void initState() {
    super.initState();
    _localProController.enabled.addListener(_onLocalProUpdated);
    _localProController.userLocalEmoji.addListener(_onLocalProUpdated);
    _workspaceController.selectedWorkspaceId.addListener(_onWorkspaceChanged);
    _workspaceController.workspaces.addListener(_onWorkspaceChanged);
    _workspaceController.init().then((_) => _onWorkspaceChanged());
  }

  @override
  void dispose() {
    _localProController.enabled.removeListener(_onLocalProUpdated);
    _localProController.userLocalEmoji.removeListener(_onLocalProUpdated);
    _workspaceController.selectedWorkspaceId.removeListener(_onWorkspaceChanged);
    _workspaceController.workspaces.removeListener(_onWorkspaceChanged);
    super.dispose();
  }

  void _onLocalProUpdated() {
    if (!mounted) return;
    setState(() => _clearHighlightToken++);
  }


  Future<void> _onWorkspaceChanged() async {
    final ids = await _workspaceController.selectedWorkspaceChatIds();
    if (!mounted) return;
    setState(() {
      _workspaceAllowedChatIds = ids.toSet();
      _selectedChat = (_selectedChat != null && _workspaceAllowedChatIds != null && _workspaceAllowedChatIds!.isNotEmpty && !_workspaceAllowedChatIds!.contains(_selectedChat!.id))
          ? null
          : _selectedChat;
    });
  }

  Future<void> _createWorkspace() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New workspace'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (save != true) return;
    await _workspaceController.createWorkspace(nameController.text.trim(), description: descController.text.trim());
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Future<void> _toggleLocalPro() async {
    await _localProController.setEnabled(!_localProController.enabled.value);
  }

  Future<void> _toggleDensityMode() async {
    final current = _uiSettingsController.densityMode.value;
    final next = switch (current) {
      MessageDensityMode.compact => MessageDensityMode.comfortable,
      MessageDensityMode.comfortable => MessageDensityMode.airy,
      MessageDensityMode.airy => MessageDensityMode.compact,
    };
    await _uiSettingsController.setDensityMode(next);
  }

  Future<void> _showCommandPalette() async {
    final commands = await _buildCommands();
    _commandRegistry.setCommands(commands);
    if (!mounted) return;
    final selected = await showDialog<CommandModel>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CommandPaletteOverlay(registry: _commandRegistry),
    );
    if (selected == null) return;
    await _commandDispatcher.dispatch(selected.onExecute);
  }

  Future<List<CommandModel>> _buildCommands() async {
    final localProEnabled = _localProController.enabled.value;
    final commands = <CommandModel>[
      CommandModel(
        id: 'workspace.create',
        title: 'Create Workspace',
        category: CommandCategory.navigation,
        subtitle: 'Create a new desktop workspace',
        onExecute: _createWorkspace,
      ),
      CommandModel(
        id: 'settings.open',
        title: 'Open Settings',
        category: CommandCategory.settings,
        subtitle: 'Open app settings screen',
        keywords: const ['preferences', 'config'],
        onExecute: _openSettings,
      ),
      CommandModel(
        id: 'localpro.toggle',
        title: localProEnabled ? 'Disable Local Pro' : 'Enable Local Pro',
        category: CommandCategory.localPro,
        subtitle: 'Toggle Killagram Pro (Local)',
        keywords: const ['premium', 'local'],
        onExecute: _toggleLocalPro,
      ),
      CommandModel(
        id: 'navigation.jump_unread',
        title: 'Jump to Unread',
        category: CommandCategory.navigation,
        subtitle: 'Focus next unread message',
        onExecute: () async => _chatScreenController.jumpNextUnread(),
      ),
      CommandModel(
        id: 'settings.toggle_density',
        title: 'Toggle Density Mode',
        category: CommandCategory.settings,
        subtitle: 'Compact / Comfortable / Airy',
        keywords: const ['compact', 'comfortable', 'airy'],
        onExecute: _toggleDensityMode,
      ),
      CommandModel(
        id: 'automation.panel',
        title: 'Open Automation Panel',
        category: CommandCategory.automation,
        subtitle: 'Open local automation rules editor',
        onExecute: () async => _chatScreenController.openAutomationPanel(),
      ),
      CommandModel(
        id: 'message.inspector',
        title: 'Open Inspector',
        category: CommandCategory.messageActions,
        subtitle: 'Open inspector for focused message',
        onExecute: () async => _chatScreenController.openInspector(),
      ),
      CommandModel(
        id: 'message.mark_important',
        title: 'Mark Message Important',
        category: CommandCategory.messageActions,
        subtitle: 'Toggle local important flag for focused message',
        onExecute: () async => _chatScreenController.markFocusedImportant(),
      ),
      CommandModel(
        id: 'message.pin_local',
        title: 'Pin Message (local)',
        category: CommandCategory.messageActions,
        subtitle: 'Toggle local pin for focused message',
        onExecute: () async => _chatScreenController.pinFocusedLocal(),
      ),
    ];

    final views = await _smartViewRepository.listViews();
    for (final view in views) {
      commands.add(
        CommandModel(
          id: 'smart_view.open.${view.id}',
          title: 'Open Smart View: ${view.title}',
          category: CommandCategory.smartViews,
          subtitle: 'Open virtual message list (${view.count})',
          keywords: [view.title, 'view', 'smart'],
          onExecute: () async => _chatsListPaneController.openSmartView(view.id),
        ),
      );
    }
    return commands;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true): _OpenCommandPaletteIntent(),
        SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true): _OpenCommandPaletteIntent(),
      },
      child: Actions(
        actions: {
          _OpenCommandPaletteIntent: CallbackAction<_OpenCommandPaletteIntent>(
            onInvoke: (_) {
              _showCommandPalette();
              return null;
            },
          ),
        },
        child: Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  child: _WorkspaceSidebar(
                    controller: _workspaceController,
                    onCreateWorkspace: _createWorkspace,
                    onSelectWorkspace: (id) async {
                      await _workspaceController.selectWorkspace(id);
                      await _onWorkspaceChanged();
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: LayoutBreakpoints.desktopLeftPaneWidth,
                  child: ChatsListPane(
                    desktopMode: true,
                    controller: _chatsListPaneController,
                    activeFolderId: _activeFolderId,
                    allowedChatIds: _workspaceAllowedChatIds,
                    localProEnabled: _localProController.enabled.value,
                    localEmoji: _localProController.userLocalEmoji.value,
                    onFolderSelected: (folderId) => setState(() => _activeFolderId = folderId),
                    onSearchResultSelected: (chat, messageId) {
                      _selectedMessageId = messageId;
                    },
                    onChatSelected: (chat) async {
                      await _workspaceController.bindChatToSelected(chat.id);
                      setState(() => _selectedChat = chat);
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selectedChat == null
                      ? ValueListenableBuilder<WorkspaceDashboard?>(
                          valueListenable: _workspaceController.dashboard,
                          builder: (context, dash, _) => dash == null ? const _DesktopEmptyChatState() : WorkspaceDashboardScreen(dashboard: dash),
                        )
                      : ChatScreen(
                          chat: _selectedChat!,
                          desktopMode: true,
                          controller: _chatScreenController,
                          localProEnabled: _localProController.enabled.value,
                          localEmoji: _localProController.userLocalEmoji.value,
                          initialMessageId: _selectedMessageId,
                          clearHighlightToken: _clearHighlightToken,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _WorkspaceSidebar extends StatelessWidget {
  const _WorkspaceSidebar({
    required this.controller,
    required this.onCreateWorkspace,
    required this.onSelectWorkspace,
  });

  final WorkspaceController controller;
  final Future<void> Function() onCreateWorkspace;
  final Future<void> Function(String id) onSelectWorkspace;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Workspace>>(
      valueListenable: controller.workspaces,
      builder: (context, workspaces, _) => ValueListenableBuilder<String?>(
        valueListenable: controller.selectedWorkspaceId,
        builder: (context, selected, __) => Column(
          children: [
            ListTile(
              title: const Text('Workspaces', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: IconButton(onPressed: onCreateWorkspace, icon: const Icon(Icons.add)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: workspaces.length,
                itemBuilder: (context, index) {
                  final ws = workspaces[index];
                  return ListTile(
                    selected: ws.id == selected,
                    leading: Icon(ws.pinned ? Icons.push_pin : Icons.workspaces_outline),
                    title: Text(ws.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: ws.description.isEmpty ? null : Text(ws.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => onSelectWorkspace(ws.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopOnboardingScreen extends StatefulWidget {
  const _DesktopOnboardingScreen({required this.onComplete});

  final Future<void> Function() onComplete;

  @override
  State<_DesktopOnboardingScreen> createState() => _DesktopOnboardingScreenState();
}

class _DesktopOnboardingScreenState extends State<_DesktopOnboardingScreen> {
  final PageController _controller = PageController();
  final LocalProController _localProController = ServiceLocator.get<LocalProController>();
  final LocalMessageStore _store = ServiceLocator.get<LocalMessageStore>();

  int _index = 0;
  Map<String, bool> _checklist = const {
    'enable_local_pro': false,
    'try_smart_views': false,
    'try_automation': false,
  };

  @override
  void initState() {
    super.initState();
    _loadChecklist();
  }

  Future<void> _loadChecklist() async {
    final checklist = await _store.getDesktopFirstRunChecklist();
    if (!mounted) return;
    if (checklist.isNotEmpty) {
      setState(() => _checklist = {
            'enable_local_pro': checklist['enable_local_pro'] == true,
            'try_smart_views': checklist['try_smart_views'] == true,
            'try_automation': checklist['try_automation'] == true,
          });
    }
  }

  Future<void> _setChecklist(String key, bool value) async {
    final next = {..._checklist, key: value};
    setState(() => _checklist = next);
    await _store.setDesktopFirstRunChecklist(next);
  }

  Future<void> _next() async {
    if (_index >= 3) {
      await widget.onComplete();
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  void _prev() {
    if (_index == 0) return;
    _controller.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<void> _skip() async {
    await widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowRight): _OnboardingNextIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): _OnboardingPrevIntent(),
        SingleActivator(LogicalKeyboardKey.enter): _OnboardingNextIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _OnboardingSkipIntent(),
      },
      child: Actions(
        actions: {
          _OnboardingNextIntent: CallbackAction<_OnboardingNextIntent>(onInvoke: (_) {
            _next();
            return null;
          }),
          _OnboardingPrevIntent: CallbackAction<_OnboardingPrevIntent>(onInvoke: (_) {
            _prev();
            return null;
          }),
          _OnboardingSkipIntent: CallbackAction<_OnboardingSkipIntent>(onInvoke: (_) {
            _skip();
            return null;
          }),
        },
        child: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Expanded(
                      child: PageView(
                        controller: _controller,
                        onPageChanged: (value) => setState(() => _index = value),
                        children: [
                          _OnboardingSlide(
                            title: 'Welcome to Killagram Desktop',
                            subtitle: 'Keyboard-first chat workflow with local power-features.',
                            icon: Icons.desktop_windows,
                          ),
                          _OnboardingSlide(
                            title: 'Smart Views',
                            subtitle: 'Virtual local views across chats with instant filtering and live counters.',
                            icon: Icons.auto_awesome_mosaic,
                          ),
                          _OnboardingSlide(
                            title: 'Local Pro',
                            subtitle: 'Функции работают только на этом устройстве. Backend premium не меняется.',
                            icon: Icons.workspace_premium,
                          ),
                          _ChecklistSlide(
                            checklist: _checklist,
                            onEnableLocalPro: () async {
                              await _localProController.setEnabled(true);
                              await _setChecklist('enable_local_pro', true);
                            },
                            onTrySmartViews: () => _setChecklist('try_smart_views', true),
                            onTryAutomation: () => _setChecklist('try_automation', true),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Row(
                        children: [
                          TextButton(onPressed: _skip, child: const Text('Skip')),
                          const Spacer(),
                          Text('Step ${_index + 1}/4'),
                          const Spacer(),
                          FilledButton(onPressed: _next, child: Text(_index == 3 ? 'Continue' : 'Next')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72),
          const SizedBox(height: 20),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(subtitle, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ChecklistSlide extends StatelessWidget {
  const _ChecklistSlide({
    required this.checklist,
    required this.onEnableLocalPro,
    required this.onTrySmartViews,
    required this.onTryAutomation,
  });

  final Map<String, bool> checklist;
  final Future<void> Function() onEnableLocalPro;
  final Future<void> Function() onTrySmartViews;
  final Future<void> Function() onTryAutomation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('First-run checklist', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          _ChecklistItem(
            done: checklist['enable_local_pro'] == true,
            title: 'Enable Local Pro',
            actionLabel: 'Enable',
            onAction: onEnableLocalPro,
          ),
          _ChecklistItem(
            done: checklist['try_smart_views'] == true,
            title: 'Try Smart Views',
            actionLabel: 'Mark done',
            onAction: onTrySmartViews,
          ),
          _ChecklistItem(
            done: checklist['try_automation'] == true,
            title: 'Try Automation',
            actionLabel: 'Mark done',
            onAction: onTryAutomation,
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.done,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final bool done;
  final String title;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? Colors.green : null),
      title: Text(title),
      trailing: OutlinedButton(onPressed: done ? null : onAction, child: Text(actionLabel)),
    );
  }
}

class _OnboardingNextIntent extends Intent {
  const _OnboardingNextIntent();
}

class _OnboardingPrevIntent extends Intent {
  const _OnboardingPrevIntent();
}

class _OnboardingSkipIntent extends Intent {
  const _OnboardingSkipIntent();
}

class _OpenCommandPaletteIntent extends Intent {
  const _OpenCommandPaletteIntent();
}

class _DesktopEmptyChatState extends StatelessWidget {
  const _DesktopEmptyChatState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Select a chat',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}
