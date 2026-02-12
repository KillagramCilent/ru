import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/service_locator.dart';
import '../../core/ai/semantic_search_service.dart';
import '../../core/state/ai_controller.dart';
import '../../data/local/local_message_store.dart';
import '../../data/telegram/api_exception.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/folder.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/smart_view.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/folder_repository.dart';
import '../../domain/repositories/search_repository.dart';
import '../../domain/repositories/smart_view_repository.dart';
import '../qr/qr_scanner_dialog.dart';
import 'chats_list_pane_controller.dart';

class ChatsListPane extends StatefulWidget {
  const ChatsListPane({
    super.key,
    required this.onChatSelected,
    this.selectedChatId,
    this.desktopMode = false,
    this.searchFocusNode,
    this.onChatsLoaded,
    this.onFoldersLoaded,
    this.onSelectionChanged,
    this.onSearchResultSelected,
    this.activeFolderId,
    this.onFolderSelected,
    this.localProEnabled = false,
    this.localEmoji,
    this.controller,
    this.allowedChatIds,
  });

  final ValueChanged<Chat> onChatSelected;
  final String? selectedChatId;
  final bool desktopMode;
  final FocusNode? searchFocusNode;
  final ValueChanged<List<Chat>>? onChatsLoaded;
  final ValueChanged<List<Folder>>? onFoldersLoaded;
  final ValueChanged<Chat>? onSelectionChanged;
  final void Function(Chat chat, String messageId)? onSearchResultSelected;
  final String? activeFolderId;
  final ValueChanged<String>? onFolderSelected;
  final bool localProEnabled;
  final String? localEmoji;
  final ChatsListPaneController? controller;
  final Set<String>? allowedChatIds;

  @override
  State<ChatsListPane> createState() => _ChatsListPaneState();
}

class _ChatsListPaneState extends State<ChatsListPane> {
  final FolderRepository _folderRepository = ServiceLocator.get<FolderRepository>();
  final SearchRepository _searchRepository = ServiceLocator.get<SearchRepository>();
  final SmartViewRepository _smartViewRepository = ServiceLocator.get<SmartViewRepository>();
  final AccountRepository _accountRepository = ServiceLocator.get<AccountRepository>();
  final LocalMessageStore _localStore = ServiceLocator.get<LocalMessageStore>();
  final AiController _aiController = ServiceLocator.get<AiController>();
  final SemanticSearchService _semanticSearchService = ServiceLocator.get<SemanticSearchService>();

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _senderIdController = TextEditingController();

  late Future<List<Folder>> _foldersFuture;
  late Future<List<Chat>> _chatsFuture;

  DateTimeRange? _dateRange;
  int? _hoveredIndex;
  String _activeFolderId = 'all';
  bool _isPremium = false;
  bool _semanticSearchEnabled = false;

  bool _filterSavedOnly = false;
  bool _filterHasMedia = false;
  bool _filterDownloadsOnly = false;
  bool _scopePrivate = true;
  bool _scopeGroups = true;
  bool _scopeChannels = true;
  bool _contentFiles = false;
  bool _contentLinks = false;
  bool _contentVoice = false;

  List<SearchResult> _searchResults = const [];
  bool _isSearchLoading = false;

  List<SmartView> _smartViews = const [];
  List<SearchResult> _smartViewResults = const [];
  String? _activeSmartViewId;
  int _activeSmartViewIndex = 0;

  @override
  void initState() {
    super.initState();
    _activeFolderId = widget.activeFolderId ?? 'all';
    _foldersFuture = _folderRepository.getFolders();
    _chatsFuture = _folderRepository.getFolderChats(_activeFolderId);
    _smartViewRepository.activeViewId().then((value) {
      if (!mounted) return;
      setState(() => _activeSmartViewId = value);
      _refreshSmartViews();
      if (value != null && value.isNotEmpty) {
        _openSmartView(value);
      }
    });
    widget.controller?.bind(openSmartView: _openSmartView);
    _accountRepository.getMe().then((value) {
      if (!mounted) return;
      setState(() => _isPremium = value.isPremium);
    }).catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant ChatsListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextFolderId = widget.activeFolderId;
    if (nextFolderId != null && nextFolderId != _activeFolderId) {
      _switchFolder(nextFolderId, notifyParent: false);
    }
  }

  @override
  void dispose() {
    widget.controller?.unbind();
    _searchController.dispose();
    _senderIdController.dispose();
    super.dispose();
  }

  void _showLocked() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('FEATURE_LOCKED · Upgrade to Premium')));
  }

  void _switchFolder(String folderId, {bool notifyParent = true}) {
    if (_activeFolderId == folderId) return;
    setState(() {
      _activeFolderId = folderId;
      _chatsFuture = _folderRepository.getFolderChats(folderId);
    });
    if (notifyParent) widget.onFolderSelected?.call(folderId);
  }

  Future<void> _refreshSmartViews() async {
    final views = await _smartViewRepository.listViews();
    if (!mounted) return;
    setState(() {
      _smartViews = views;
      if (_activeSmartViewId != null) {
        final idx = views.indexWhere((it) => it.id == _activeSmartViewId);
        if (idx >= 0) _activeSmartViewIndex = idx;
      }
    });
  }

  Future<void> _openSmartView(String viewId) async {
    final rows = await _smartViewRepository.openView(viewId, limit: 120);
    if (!mounted) return;
    setState(() {
      _activeSmartViewId = viewId;
      _smartViewResults = rows;
    });
    await _smartViewRepository.activateView(viewId);
    _refreshSmartViews();
  }

  Future<void> _togglePinSmartView(SmartView view) async {
    final pinnedCount = _smartViews.where((it) => it.pinned).length;
    if (!(widget.localProEnabled || _isPremium) && !view.pinned && pinnedCount >= 2) {
      _showLocked();
      return;
    }
    await _smartViewRepository.pinView(view.id, !view.pinned);
    await _refreshSmartViews();
  }

  void _focusNextSmartView() {
    if (_smartViews.isEmpty) return;
    setState(() => _activeSmartViewIndex = (_activeSmartViewIndex + 1) % _smartViews.length);
  }

  void _focusPrevSmartView() {
    if (_smartViews.isEmpty) return;
    setState(() => _activeSmartViewIndex = (_activeSmartViewIndex - 1) < 0 ? _smartViews.length - 1 : _activeSmartViewIndex - 1);
  }

  Future<void> _activateFocusedSmartView() async {
    if (_smartViews.isEmpty) return;
    await _openSmartView(_smartViews[_activeSmartViewIndex].id);
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _isSearchLoading = false;
      });
      return;
    }
    setState(() => _isSearchLoading = true);
    try {
      final fromTs = _dateRange?.start.millisecondsSinceEpoch;
      final toTs = _dateRange?.end.millisecondsSinceEpoch;
      await _localStore.saveLastSearchDefinition({
        'title': query,
        'query': query,
        'sender': _senderIdController.text.trim(),
        'from_ts': fromTs,
        'to_ts': toTs,
        'has_media': _filterHasMedia,
        'automation_required': false,
        'mode': _semanticSearchEnabled ? 'semantic' : 'keyword',
      });

      final local = await (_semanticSearchEnabled ? _runSemanticSearch(query) : _runKeywordSearch(query));
      final mapped = local
          .map(
            (row) => SearchResult(
              chatId: row['chat_id']?.toString() ?? '',
              chatTitle: row['chat_id']?.toString() == '-1' ? 'Saved Messages' : 'Chat ${row['chat_id']}',
              message: Message(
                id: row['id']?.toString() ?? '',
                chatId: row['chat_id']?.toString() ?? '',
                sender: row['sender_id']?.toString() ?? '',
                text: row['text']?.toString() ?? '',
                timestamp: DateTime.fromMillisecondsSinceEpoch((row['timestamp'] as num?)?.toInt() ?? 0),
                isOutgoing: false,
                contentType: (row['has_media'] as bool? ?? false) ? 'photo' : 'text',
              ),
            ),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _searchResults = mapped;
        _isSearchLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchResults = const [];
        _isSearchLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _runKeywordSearch(String query) {
    return _localStore.searchLocal(
      query: query,
      chatId: _activeFolderId == 'all' ? null : _activeFolderId,
      senderId: _senderIdController.text.trim().isEmpty ? null : _senderIdController.text.trim(),
      from: _dateRange?.start,
      to: _dateRange?.end,
      hasMedia: _filterHasMedia ? true : null,
      hasLinks: _contentLinks ? true : null,
      limit: 30,
    );
  }

  Future<List<Map<String, dynamic>>> _runSemanticSearch(String query) async {
    if (!_isPremium) {
      _showLocked();
      return const [];
    }
    final provider = _aiController.provider.value;
    final apiKey = await _aiController.getApiKey(provider);
    final intent = await _semanticSearchService.buildIntent(
      provider: provider,
      apiKey: apiKey,
      naturalLanguageQuery: query,
    );
    final ranked = await _semanticSearchService.search(
      intent: intent,
      store: _localStore,
      chatId: _activeFolderId == 'all' ? null : _activeFolderId,
      senderId: _senderIdController.text.trim().isEmpty ? null : _senderIdController.text.trim(),
      from: _dateRange?.start,
      to: _dateRange?.end,
      hasMedia: _filterHasMedia ? true : null,
      hasLinks: _contentLinks ? true : null,
      limit: 30,
    );
    return ranked.map((it) => it.row).toList();
  }

  Future<void> _saveSearchAsSmartView() async {
    if (!(widget.localProEnabled || _isPremium)) {
      _showLocked();
      return;
    }
    final def = await _localStore.readLastSearchDefinition();
    if (def == null) return;
    await _smartViewRepository.saveSearchAsSmartView(def);
    await _refreshSmartViews();
  }

  Future<void> _openSmartViewBuilder() async {
    final titleController = TextEditingController();
    final senderController = TextEditingController();
    final keywordController = TextEditingController();
    final regexController = TextEditingController();
    String mediaType = '';
    bool automationRequired = false;
    DateTimeRange? range;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Smart View builder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleController, enabled: (widget.localProEnabled || _isPremium), decoration: const InputDecoration(labelText: 'Title')),
                TextField(controller: senderController, enabled: (widget.localProEnabled || _isPremium), decoration: const InputDecoration(labelText: 'Sender filter')),
                TextField(controller: keywordController, enabled: (widget.localProEnabled || _isPremium), decoration: const InputDecoration(labelText: 'Keyword')),
                TextField(controller: regexController, enabled: (widget.localProEnabled || _isPremium), decoration: const InputDecoration(labelText: 'Regex')),
                DropdownButtonFormField<String>(
                  value: mediaType,
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Any media type')),
                    DropdownMenuItem(value: 'media', child: Text('Any media')),
                    DropdownMenuItem(value: 'voice', child: Text('Voice')),
                    DropdownMenuItem(value: 'photo', child: Text('Photo')),
                  ],
                  onChanged: (widget.localProEnabled || _isPremium) ? (v) => setDialogState(() => mediaType = v ?? '') : null,
                ),
                CheckboxListTile(
                  value: automationRequired,
                  onChanged: (widget.localProEnabled || _isPremium) ? (v) => setDialogState(() => automationRequired = v ?? false) : null,
                  title: const Text('Automation-applied only'),
                ),
                OutlinedButton(
                  onPressed: _isPremium
                      ? () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2018),
                            lastDate: DateTime.now().add(const Duration(days: 1)),
                            initialDateRange: range,
                          );
                          if (picked == null) return;
                          setDialogState(() => range = picked);
                        }
                      : null,
                  child: Text(range == null ? 'Date range' : 'Date range selected'),
                ),
                if (!(widget.localProEnabled || _isPremium))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Premium only controls are locked.', style: TextStyle(color: Colors.orange)),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            FilledButton(
              onPressed: () async {
                if (!(widget.localProEnabled || _isPremium)) {
                  _showLocked();
                  return;
                }
                await _smartViewRepository.saveCustomView({
                  'title': titleController.text.trim().isEmpty ? 'Custom view' : titleController.text.trim(),
                  'sender': senderController.text.trim(),
                  'keyword': keywordController.text.trim(),
                  'regex': regexController.text.trim(),
                  'media_type': mediaType,
                  'automation_required': automationRequired,
                  'from_ts': range?.start.millisecondsSinceEpoch,
                  'to_ts': range?.end.millisecondsSinceEpoch,
                });
                if (context.mounted) Navigator.pop(context);
                _refreshSmartViews();
              },
              child: const Text('Save view'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openQrScanner() async {
    final result = await showQrScannerDialog(context);
    if (!mounted || result == null) return;
    final raw = result.trim();
    if (!(raw.startsWith('tg://') || raw.startsWith('https://t.me/'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unsupported QR link')));
      return;
    }
    _searchController.text = raw;
    _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): _SmartViewNextIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _SmartViewPrevIntent(),
        SingleActivator(LogicalKeyboardKey.enter, alt: true): _SmartViewActivateIntent(),
      },
      child: Actions(
        actions: {
          _SmartViewNextIntent: CallbackAction<_SmartViewNextIntent>(onInvoke: (_) { _focusNextSmartView(); return null; }),
          _SmartViewPrevIntent: CallbackAction<_SmartViewPrevIntent>(onInvoke: (_) { _focusPrevSmartView(); return null; }),
          _SmartViewActivateIntent: CallbackAction<_SmartViewActivateIntent>(onInvoke: (_) { _activateFocusedSmartView(); return null; }),
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                focusNode: widget.searchFocusNode,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Поиск сообщений',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: _openQrScanner),
                      IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _runSearch),
                    ],
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
            ),
            if (widget.desktopMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Keyword'),
                      selected: !_semanticSearchEnabled,
                      onSelected: (v) {
                        if (!v) return;
                        setState(() => _semanticSearchEnabled = false);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      avatar: !_isPremium ? const Icon(Icons.lock_outline, size: 14, color: Colors.orange) : null,
                      label: const Text('Semantic (AI)'),
                      selected: _semanticSearchEnabled,
                      onSelected: (v) {
                        if (!v) return;
                        if (!_isPremium) {
                          _showLocked();
                          return;
                        }
                        setState(() => _semanticSearchEnabled = true);
                      },
                    ),
                    const SizedBox(width: 8),
                    if (_semanticSearchEnabled)
                      Text('Pro', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _senderIdController,
                      onSubmitted: (_) => _runSearch(),
                      decoration: const InputDecoration(hintText: 'Sender id filter'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2018),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                        initialDateRange: _dateRange,
                      );
                      if (picked == null) return;
                      setState(() => _dateRange = picked);
                      _runSearch();
                    },
                    child: Text(_dateRange == null ? 'Date range' : 'Range set'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  const Text('Views', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _openSmartViewBuilder, child: const Text('Builder')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _saveSearchAsSmartView, child: const Text('Save search → view')),
                  const Spacer(),
                  if (_activeSmartViewId != null)
                    TextButton(
                      onPressed: () async {
                        await _smartViewRepository.activateView(null);
                        setState(() {
                          _activeSmartViewId = null;
                          _smartViewResults = const [];
                        });
                      },
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _smartViews.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final view = _smartViews[index];
                  final locked = view.isPremium && !(widget.localProEnabled || _isPremium);
                  return InputChip(
                    selected: _activeSmartViewId == view.id || _activeSmartViewIndex == index,
                    label: Text('${view.icon} ${view.title} (${view.count})${locked ? ' 🔒' : ''}'),
                    onPressed: locked ? _showLocked : () => _openSmartView(view.id),
                    onLongPress: locked ? _showLocked : () => _togglePinSmartView(view),
                  );
                },
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  FilterChip(label: const Text('Saved only'), selected: _filterSavedOnly, onSelected: (v) { setState(() => _filterSavedOnly = v); _runSearch(); }),
                  const SizedBox(width: 8),
                  FilterChip(label: const Text('Has media'), selected: _filterHasMedia, onSelected: (v) { setState(() => _filterHasMedia = v); _runSearch(); }),
                  const SizedBox(width: 8),
                  FilterChip(label: const Text('Downloads'), selected: _filterDownloadsOnly, onSelected: (v) { setState(() => _filterDownloadsOnly = v); _runSearch(); }),
                  const SizedBox(width: 8),
                  FilterChip(label: const Text('Links'), selected: _contentLinks, onSelected: (v) { setState(() => _contentLinks = v); _runSearch(); }),
                ],
              ),
            ),
            FutureBuilder<List<Folder>>(
              future: _foldersFuture,
              builder: (context, snapshot) {
                final folders = snapshot.data ?? const <Folder>[];
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  widget.onFoldersLoaded?.call(folders);
                });
                if (snapshot.connectionState == ConnectionState.waiting || folders.isEmpty) {
                  return const SizedBox.shrink();
                }
                return SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      final selected = folder.id == _activeFolderId;
                      return ChoiceChip(
                        label: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (folder.emojiFallback != null) Text(folder.emojiFallback!),
                          if (folder.emojiFallback != null) const SizedBox(width: 4),
                          Text(folder.title),
                        ]),
                        selected: selected,
                        onSelected: (_) => _switchFolder(folder.id),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemCount: folders.length,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            if (_isSearchLoading)
              const SizedBox(height: 180, child: _SearchResultsSkeleton())
            else if (_activeSmartViewId != null && _smartViewResults.isNotEmpty)
              _ResultsList(results: _smartViewResults, onOpen: widget.onChatSelected, onSelect: widget.onSearchResultSelected, query: _searchController.text, localEmoji: widget.localEmoji)
            else if (_searchResults.isNotEmpty)
              SizedBox(height: 180, child: _ResultsList(results: _searchResults, onOpen: widget.onChatSelected, onSelect: widget.onSearchResultSelected, query: _searchController.text, localEmoji: widget.localEmoji)),
            Expanded(
              child: FutureBuilder<List<Chat>>(
                future: _chatsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const _ChatsListSkeleton();
                  if (snapshot.hasError) {
                    final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'Не удалось загрузить чаты';
                    return Center(child: Text(message));
                  }
                  final allChats = snapshot.data ?? [];
                  final chats = widget.allowedChatIds == null || widget.allowedChatIds!.isEmpty
                      ? allChats
                      : allChats.where((it) => widget.allowedChatIds!.contains(it.id)).toList();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    widget.onChatsLoaded?.call(chats);
                  });
                  return ListView.separated(
                    itemCount: chats.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      final isSelected = widget.selectedChatId == chat.id;
                      final isHovered = _hoveredIndex == index;
                      final highlight = isSelected || (widget.desktopMode && isHovered);
                      return MouseRegion(
                        cursor: widget.desktopMode ? SystemMouseCursors.click : MouseCursor.defer,
                        onEnter: (_) { if (widget.desktopMode) setState(() => _hoveredIndex = index); },
                        onExit: (_) { if (widget.desktopMode) setState(() => _hoveredIndex = null); },
                        child: ListTile(
                          tileColor: highlight ? Theme.of(context).colorScheme.primary.withOpacity(isSelected ? 0.16 : 0.08) : null,
                          leading: CircleAvatar(child: Text(chat.title.characters.first)),
                          title: Text('${widget.localEmoji ?? ''} ${chat.title}'.trim()),
                          subtitle: Text(chat.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            widget.onSelectionChanged?.call(chat);
                            widget.onChatSelected(chat);
                          },
                        ),
                      );
                    },
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

class _SmartViewNextIntent extends Intent { const _SmartViewNextIntent(); }
class _SmartViewPrevIntent extends Intent { const _SmartViewPrevIntent(); }
class _SmartViewActivateIntent extends Intent { const _SmartViewActivateIntent(); }

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.results,
    required this.onOpen,
    required this.onSelect,
    required this.query,
    this.localEmoji,
  });

  final List<SearchResult> results;
  final ValueChanged<Chat> onOpen;
  final void Function(Chat chat, String messageId)? onSelect;
  final String query;
  final String? localEmoji;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, index) {
          final result = results[index];
          final chat = Chat(
            id: result.chatId == 'saved' ? '-1' : result.chatId,
            title: result.chatTitle,
            lastMessage: '',
            unreadCount: 0,
            avatarUrl: '',
            isMuted: false,
            isSavedMessages: result.chatId == 'saved',
          );
          return ListTile(
            dense: true,
            title: Text('${localEmoji ?? ''} ${result.chatTitle}'.trim()),
            subtitle: _HighlightedText(text: result.message.text, query: query),
            onTap: () {
              onSelect?.call(chat, result.message.id);
              onOpen(chat);
            },
          );
        },
      ),
    );
  }
}

class _ChatsListSkeleton extends StatelessWidget {
  const _ChatsListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 8,
      itemBuilder: (context, index) => const ListTile(title: Text('...')),
    );
  }
}

class _SearchResultsSkeleton extends StatelessWidget {
  const _SearchResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) => const ListTile(title: Text('...')),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    final source = text;
    final lower = source.toLowerCase();
    final q = query.toLowerCase();
    final i = lower.indexOf(q);
    if (i < 0) return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: source.substring(0, i)),
          TextSpan(text: source.substring(i, i + q.length), style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: source.substring(i + q.length)),
        ],
      ),
    );
  }
}
