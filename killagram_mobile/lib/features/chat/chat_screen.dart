import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/di/service_locator.dart';
import '../../core/state/ui_settings_controller.dart';
import '../../core/state/ai_controller.dart';
import '../../data/telegram/api_exception.dart';
import '../../data/local/local_message_store.dart';
import '../../domain/entities/account_state.dart';
import '../../domain/entities/chat.dart';
import '../../domain/entities/message.dart';
import '../../domain/repositories/account_repository.dart';
import '../../domain/repositories/ai_repository.dart';
import '../../domain/repositories/chat_repository.dart';
import 'chat_input_bar.dart';
import 'chat_screen_controller.dart';
import 'chat_message_list.dart';
import 'ai_assistant_panel.dart';

enum WsSyncState { connected, reconnecting, degraded }

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chat,
    this.desktopMode = false,
    this.initialMessageId,
    this.clearHighlightToken = 0,
    this.localProEnabled = false,
    this.localEmoji,
    this.controller,
  });

  final Chat chat;
  final bool desktopMode;
  final String? initialMessageId;
  final int clearHighlightToken;
  final bool localProEnabled;
  final String? localEmoji;
  final ChatScreenController? controller;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final ChatRepository _chatRepository = ServiceLocator.get<ChatRepository>();
  final AiRepository _aiRepository = ServiceLocator.get<AiRepository>();
  final AccountRepository _accountRepository = ServiceLocator.get<AccountRepository>();
  final LocalMessageStore _localStore = ServiceLocator.get<LocalMessageStore>();
  final UiSettingsController _uiSettings = ServiceLocator.get<UiSettingsController>();
  final AiController _aiController = ServiceLocator.get<AiController>();

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Message> _localMessages = [];
  final Set<String> _messageIds = <String>{};

  StreamSubscription<AccountState>? _accountSubscription;
  StreamSubscription<Map<String, dynamic>>? _chatEventSubscription;
  StreamSubscription<Message>? _messageSubscription;

  List<Message> _serverMessages = [];
  List<String> _smartReplies = [];
  Timer? _pollingTimer;
  Timer? _retryTimer;
  Timer? _draftSaveTimer;
  Timer? _typingStopTimer;
  int _retryAttempts = 0;
  bool _isActive = true;
  bool _isLoading = true;
  String? _errorMessage;
  bool _showJumpToBottom = false;
  String? _highlightedMessageId;
  AccountState? _accountState;
  bool _isRepliesLoading = false;
  String? _repliesError;
  Message? _pinnedMessage;
  bool _isTyping = false;
  Message? _replyToMessage;
  DateTime? _scheduledAt;
  int? _voiceDuration;
  final Set<String> _selectedForForward = <String>{};
  bool _selectionMode = false;
  List<String> _mentionSuggestions = const [];
  WsSyncState _wsSyncState = WsSyncState.connected;
  Timer? _wsDegradedTimer;
  final List<Message> _pendingIncomingMessages = <Message>[];
  bool _incomingFlushScheduled = false;
  List<Map<String, dynamic>> _automationRules = const [];
  MessageDensityMode _densityMode = MessageDensityMode.comfortable;
  String? _focusedMessageId;

  List<Message> get _messages => [..._localMessages, ..._serverMessages];

  bool get _isFrozen => _accountState?.isFrozen ?? false;
  bool get _isPremium => _accountState?.isPremium ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScroll);
    _densityMode = _uiSettings.densityMode.value;
    _uiSettings.densityMode.addListener(_handleDensityModeChanged);
    _controller.addListener(_onInputChanged);
    widget.controller?.bind(
      jumpNextUnread: _jumpNextUnread,
      toggleDensityMode: _cycleDensityMode,
      openAutomationPanel: _openAutomationRulesEditor,
      openInspector: () {
        final current = _currentFocusedMessage();
        if (current != null) _openInspector(current);
      },
      markFocusedImportant: () {
        final current = _currentFocusedMessage();
        if (current != null) _toggleImportant(current);
      },
      pinFocusedLocal: () {
        final current = _currentFocusedMessage();
        if (current != null) _toggleLocalPin(current);
      },
    );
    _loadAccountState();
    _accountSubscription = _accountRepository.watchAccountUpdates().listen((state) {
      if (!mounted) return;
      setState(() => _accountState = state);
    });

    _loadMessages();
    _loadAutomationRules();
    _loadDraft();
    _loadSmartReplies();
    _startPolling();
    _chatEventSubscription = _chatRepository.watchChatEvents(widget.chat.id).listen(
      _handleChatEvent,
      onError: (_, __) => _onWsDisconnected(),
      onDone: _onWsDisconnected,
    );
    _messageSubscription = _chatRepository.watchMessages(widget.chat.id).listen(
      _queueIncomingMessage,
      onError: (_, __) => _onWsDisconnected(),
      onDone: _onWsDisconnected,
    );
  }


  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clearHighlightToken != widget.clearHighlightToken && _highlightedMessageId != null) {
      setState(() => _highlightedMessageId = null);
    }
  }

  @override
  void dispose() {
    widget.controller?.unbind();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_handleScroll);
    _uiSettings.densityMode.removeListener(_handleDensityModeChanged);
    _accountSubscription?.cancel();
    _chatEventSubscription?.cancel();
    _messageSubscription?.cancel();
    _controller.removeListener(_onInputChanged);
    _controller.dispose();
    _scrollController.dispose();
    _pollingTimer?.cancel();
    _retryTimer?.cancel();
    _draftSaveTimer?.cancel();
    _updateMentionSuggestions();
    _typingStopTimer?.cancel();
    _wsDegradedTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isActive = true;
      _startPolling();
      _loadMessages(silent: true);
      _loadAccountState();
      _loadSmartReplies(silent: true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _isActive = false;
      _stopPolling();
    }
  }

  Future<void> _loadAccountState() async {
    try {
      final me = await _accountRepository.getMe();
      if (!mounted) return;
      setState(() => _accountState = me);
    } catch (_) {
      // non-fatal: message flow still works.
    }
  }

  Future<void> _loadSmartReplies({bool silent = false}) async {
    if (_isFrozen || !_isPremium) {
      setState(() {
        _smartReplies = [];
        _repliesError = null;
        _isRepliesLoading = false;
      });
      return;
    }

    if (!silent) {
      setState(() {
        _isRepliesLoading = true;
        _repliesError = null;
      });
    }

    try {
      final replies = await _aiRepository.smartReplies(widget.chat.id);
      if (!mounted) return;
      setState(() {
        _smartReplies = replies;
        _repliesError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _repliesError = error.message;
      });
      if (!silent) {
        _showToast(error.message);
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _isRepliesLoading = false;
      });
    }
  }


  Future<void> _cycleDensityMode() async {
    final current = _uiSettings.densityMode.value;
    final next = switch (current) {
      MessageDensityMode.compact => MessageDensityMode.comfortable,
      MessageDensityMode.comfortable => MessageDensityMode.airy,
      MessageDensityMode.airy => MessageDensityMode.compact,
    };
    await _uiSettings.setDensityMode(next);
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadMessages(silent: true),
    );
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!_isActive) {
      return;
    }
    if (!silent && _isLoading != true) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final messages = await _chatRepository.getMessages(widget.chat.id, limit: 200);
      if (!mounted) return;
      final decoratedMessages = <Message>[];
      for (final message in messages) {
        final flags = await _localStore.readFlags(message.id);
        final enhanced = _applyAutomationRulesToMessage(message.copyWith(
          isImportant: flags['is_important'] as bool? ?? false,
          localNote: flags['local_note']?.toString(),
          isLocalPinned: flags['is_local_pinned'] as bool? ?? false,
        ));
        decoratedMessages.add(enhanced);
        await _localStore.upsertSearchDocument(enhanced);
      }
      final cached = await _localStore.getChatMessages(widget.chat.id);
      final pending = cached.map((row) => Message(
        id: row['id']?.toString() ?? '',
        chatId: row['chat_id']?.toString() ?? widget.chat.id,
        sender: row['sender']?.toString() ?? 'me',
        text: row['text']?.toString() ?? '',
        timestamp: DateTime.tryParse(row['timestamp']?.toString() ?? '') ?? DateTime.now(),
        isOutgoing: row['is_outgoing'] as bool? ?? true,
        replyToId: row['reply_to_id']?.toString(),
        contentType: row['content_type']?.toString() ?? 'text',
        voiceDuration: (row['voice_duration'] as num?)?.toInt(),
        outgoingState: OutgoingMessageState.values.firstWhere((s) => s.name == row['outgoing_state'], orElse: () => OutgoingMessageState.pending),
        clientMessageId: row['client_message_id']?.toString(),
        isImportant: row['is_important'] as bool? ?? false,
        localNote: row['local_note']?.toString(),
        isLocalPinned: row['is_local_pinned'] as bool? ?? false,
      )).toList();
      setState(() {
        _serverMessages = decoratedMessages;
        _localMessages
          ..clear()
          ..addAll(pending);
        _messageIds
          ..clear()
          ..addAll(_serverMessages.map((it) => it.id))
          ..addAll(_localMessages.map((it) => it.id));
        _pinnedMessage = _serverMessages.where((it) => it.isPinned).cast<Message?>().firstWhere((it) => it != null, orElse: () => null);
        _errorMessage = null;
        _isLoading = false;
        _wsSyncState = WsSyncState.connected;
      });
      await _flushPendingQueue();
      _retryAttempts = 0;
      _scrollToBottomIfNeeded();
      if (widget.initialMessageId != null) {
        _scrollToMessage(widget.initialMessageId!);
      }
      if (messages.isNotEmpty) {
        await _chatRepository.markRead(widget.chat.id, messages.first.id);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
        _wsSyncState = WsSyncState.reconnecting;
      });
      _showToast(error.message);
      _scheduleRetry();
    }
  }

  Future<void> _send() async {
    if (_isFrozen) {
      _showToast(_accountState?.freezeReason ?? 'Аккаунт заморожен');
      return;
    }
    if (_controller.text.trim().isEmpty) {
      return;
    }

    final text = _controller.text.trim();
    final clientMessageId = 'cm_${DateTime.now().microsecondsSinceEpoch}';
    final localMessage = Message(
      id: 'local_$clientMessageId',
      chatId: widget.chat.id,
      sender: 'me',
      text: text,
      timestamp: DateTime.now(),
      isOutgoing: true,
      replyToId: _replyToMessage?.id,
      contentType: _voiceDuration != null ? 'voice' : 'text',
      voiceDuration: _voiceDuration,
      outgoingState: OutgoingMessageState.pending,
      clientMessageId: clientMessageId,
    );
    setState(() {
      _localMessages.insert(0, localMessage);
      _messageIds.add(localMessage.id);
      _smartReplies = [];
      _replyToMessage = null;
      _scheduledAt = null;
      _voiceDuration = null;
    });
    await _persistLocalMessages();
    _scrollToBottomIfNeeded(force: true);
    _controller.clear();
    await _chatRepository.saveDraft(widget.chat.id, "");
    await _chatRepository.typingStop(widget.chat.id);
    _loadSmartReplies(silent: true);
    await _flushPendingQueue();
  }

  Future<void> _showSummary() async {
    try {
      final summary = await _aiRepository.summarizeChat(widget.chat.id);
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(20),
          child: Text(summary, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    } on ApiException catch (error) {
      _showToast(error.message);
    }
  }


  Future<void> _runAiAction(String action, {Message? target}) async {
    if (!widget.desktopMode || !_isPremium) {
      _showToast('FEATURE_LOCKED');
      return;
    }
    final contextLines = _messages.take(60).map((it) => '${it.sender}: ${it.text}').toList();
    switch (action) {
      case 'summarize':
        await _aiController.summarizeConversation(contextLines);
        break;
      case 'reply':
        final text = target?.text ?? _controller.text.trim();
        if (text.isEmpty) {
          _showToast('Select or type a message');
          return;
        }
        await _aiController.generateReplySuggestion(message: text, context: contextLines);
        break;
      case 'rewrite_formal':
        final text = target?.text ?? _controller.text.trim();
        if (text.isEmpty) {
          _showToast('Select or type a message');
          return;
        }
        await _aiController.rewriteMessage(text: text, style: 'formal');
        break;
      case 'rewrite_short':
        final text = target?.text ?? _controller.text.trim();
        if (text.isEmpty) {
          _showToast('Select or type a message');
          return;
        }
        await _aiController.rewriteMessage(text: text, style: 'short');
        break;
      case 'rewrite_clear':
        final text = target?.text ?? _controller.text.trim();
        if (text.isEmpty) {
          _showToast('Select or type a message');
          return;
        }
        await _aiController.rewriteMessage(text: text, style: 'clear');
        break;
      case 'tasks':
        await _aiController.extractTasks(contextLines);
        break;
    }
    if (!_aiController.panelExpanded.value) {
      _aiController.togglePanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyA, control: true): _SelectAllIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, meta: true): _SelectAllIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, alt: true): _NextUnreadIntent(),
        SingleActivator(LogicalKeyboardKey.keyI, alt: true): _ToggleImportantIntent(),
        SingleActivator(LogicalKeyboardKey.keyP, alt: true): _ToggleLocalPinIntent(),
        SingleActivator(LogicalKeyboardKey.keyH, alt: true): _OpenHistoryIntent(),
        SingleActivator(LogicalKeyboardKey.keyT, alt: true): _OpenThreadIntent(),
        SingleActivator(LogicalKeyboardKey.keyM, alt: true): _OpenInspectorIntent(),
      },
      child: Actions(
        actions: {
          _SelectAllIntent: CallbackAction<_SelectAllIntent>(
            onInvoke: (_) {
              setState(() {
                _selectionMode = true;
                _selectedForForward
                  ..clear()
                  ..addAll(_messages.map((e) => e.id));
              });
              return null;
            },
          ),
          _NextUnreadIntent: CallbackAction<_NextUnreadIntent>(onInvoke: (_) {
            _jumpNextUnread();
            return null;
          }),
          _ToggleImportantIntent: CallbackAction<_ToggleImportantIntent>(onInvoke: (_) {
            final m = _currentFocusedMessage();
            if (m != null) {
              _toggleImportant(m);
            }
            return null;
          }),
          _ToggleLocalPinIntent: CallbackAction<_ToggleLocalPinIntent>(onInvoke: (_) {
            final m = _currentFocusedMessage();
            if (m != null) {
              _toggleLocalPin(m);
            }
            return null;
          }),
          _OpenHistoryIntent: CallbackAction<_OpenHistoryIntent>(onInvoke: (_) {
            final m = _currentFocusedMessage();
            if (m != null && m.editVersionsCount > 0) {
              _showEditHistory(m);
            }
            return null;
          }),
          _OpenThreadIntent: CallbackAction<_OpenThreadIntent>(onInvoke: (_) {
            final m = _currentFocusedMessage();
            if (m != null && (m.replyToId != null || m.text.isNotEmpty)) {
              _showThread(m);
            }
            return null;
          }),
          _OpenInspectorIntent: CallbackAction<_OpenInspectorIntent>(onInvoke: (_) {
            final m = _currentFocusedMessage();
            if (m != null) {
              _openInspector(m);
            }
            return null;
          }),
        },
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${widget.localEmoji ?? ''} ${widget.chat.title}'.trim(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.chat.isVerified)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              widget.chat.verificationProvider == 'telegram' ? Icons.verified : Icons.verified_user,
                              size: 14,
                              color: widget.chat.verificationProvider == 'telegram' ? Colors.blue : Colors.green,
                            ),
                          ),
                      ],
                    ),
                    if (_isTyping) const Text('typing...', style: TextStyle(fontSize: 12)),
                  ],
                ),
                if (_isPremium) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('PREMIUM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
            actions: [
              if (widget.desktopMode)
                ValueListenableBuilder<bool>(
                  valueListenable: _aiController.panelExpanded,
                  builder: (context, expanded, _) => IconButton(
                    tooltip: 'AI Assistant',
                    icon: Icon(expanded ? Icons.auto_awesome : Icons.auto_awesome_outlined),
                    onPressed: _aiController.togglePanel,
                  ),
                ),
              if (_selectionMode) ...[
                IconButton(icon: const Icon(Icons.copy), onPressed: _selectedForForward.isEmpty ? null : _copySelected),
                IconButton(icon: const Icon(Icons.delete), onPressed: _selectedForForward.isEmpty ? null : _deleteSelected),
                IconButton(icon: const Icon(Icons.forward), onPressed: _selectedForForward.isEmpty ? null : _forwardSelected),
              ],
              IconButton(
                icon: Icon(_selectionMode ? Icons.close : Icons.select_all),
                onPressed: () => setState(() {
                  _selectionMode = !_selectionMode;
                  if (!_selectionMode) _selectedForForward.clear();
                }),
              ),
              IconButton(icon: const Icon(Icons.rule), onPressed: _openRulesEditor),
              IconButton(icon: const Icon(Icons.auto_awesome), onPressed: _showSummary),
            ],
          ),
          body: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      if (_isFrozen)
                        MaterialBanner(
                          backgroundColor: Colors.orange.withOpacity(0.16),
                          content: Text('Аккаунт временно заморожен. ${_accountState?.freezeReason ?? ''}'),
                          actions: [
                            TextButton(onPressed: () => _openAppealDialog(context), child: const Text('Обжаловать')),
                          ],
                        ),
                      _buildWsSyncBanner(),
                      _buildPinnedBanner(),
                      Expanded(
                        child: Stack(
                          children: [
                            ChatMessageList(
                              messages: _messages,
                              isLoading: _isLoading,
                              errorMessage: _errorMessage,
                              onRefresh: () => _loadMessages(),
                              scrollController: _scrollController,
                              desktopMode: widget.desktopMode,
                              onReplyRequested: _handleReplyRequested,
                              onReact: _handleReaction,
                              onEdit: _handleEditMessage,
                              onDelete: _handleDeleteMessage,
                              onPin: _handlePinToggle,
                              onForward: _handleForwardSingle,
                              onJumpToMessage: _scrollToMessage,
                              onHashtagTap: _openHashtagSearch,
                              onTapMessage: _handleMessageTap,
                              onRetrySend: (_) => _flushPendingQueue(),
                              onToggleImportant: _toggleImportant,
                              onToggleLocalPin: _toggleLocalPin,
                              onAddLocalNote: _addLocalNote,
                              onShowEditHistory: _showEditHistory,
                              onViewThread: _showThread,
                              onOpenInspector: _openInspector,
                              onAiAction: _runAiAction,
                              densityMode: _densityMode,
                              localEmoji: widget.localEmoji,
                              highlightedMessageId: _highlightedMessageId,
                            ),
                            if (_showJumpToBottom)
                              Positioned(
                                right: 16,
                                bottom: 16,
                                child: FloatingActionButton.small(
                                  onPressed: () => _scrollToBottomIfNeeded(force: true),
                                  child: const Icon(Icons.arrow_downward),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _buildSmartRepliesSection(),
                      ChatInputBar(
                        controller: _controller,
                        onSend: _send,
                        enabled: !_isFrozen,
                        replyPreview: _replyToMessage?.text,
                        onCancelReply: () => setState(() => _replyToMessage = null),
                        onScheduleRequested: (value) => setState(() => _scheduledAt = value),
                        onVoiceRecorded: (seconds) => setState(() => _voiceDuration = seconds),
                        mentionSuggestions: _mentionSuggestions,
                        onMentionSelected: _applyMention,
                      ),
                    ],
                  ),
                ),
                if (widget.desktopMode)
                  ValueListenableBuilder<bool>(
                    valueListenable: _aiController.panelExpanded,
                    builder: (context, expanded, _) => ValueListenableBuilder<bool>(
                      valueListenable: _aiController.loading,
                      builder: (context, loading, __) => ValueListenableBuilder<String?>(
                        valueListenable: _aiController.output,
                        builder: (context, output, ___) => ValueListenableBuilder<String?>(
                          valueListenable: _aiController.error,
                          builder: (context, error, ____) => AiAssistantPanel(
                            collapsed: !expanded,
                            proEnabled: _isPremium,
                            loading: loading,
                            output: output,
                            error: error,
                            onToggle: _aiController.togglePanel,
                            onSummarize: () => _runAiAction('summarize'),
                            onGenerateReply: () => _runAiAction('reply', target: _currentFocusedMessage()),
                            onRewriteFormal: () => _runAiAction('rewrite_formal', target: _currentFocusedMessage()),
                            onRewriteShort: () => _runAiAction('rewrite_short', target: _currentFocusedMessage()),
                            onRewriteClear: () => _runAiAction('rewrite_clear', target: _currentFocusedMessage()),
                            onExtractTasks: () => _runAiAction('tasks'),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSmartRepliesSection() {
    if (_isFrozen) {
      return const SizedBox.shrink();
    }

    if (!_isPremium) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Smart Replies доступны в Premium',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.amber.shade800),
              ),
            ),
            TextButton(
              onPressed: () => _showToast('Откройте Premium в профиле'),
              child: const Text('Открыть Premium'),
            ),
          ],
        ),
      );
    }

    if (_isRepliesLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: const [
            _ReplySkeleton(),
            SizedBox(width: 8),
            _ReplySkeleton(),
            SizedBox(width: 8),
            _ReplySkeleton(width: 72),
          ],
        ),
      );
    }

    if (_repliesError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _repliesError!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.red.shade400),
              ),
            ),
            TextButton(
              onPressed: _isFrozen ? null : _loadSmartReplies,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_smartReplies.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _smartReplies.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final reply = _smartReplies[index];
          return ActionChip(
            onPressed: _isFrozen
                ? null
                : () {
                    _controller.text = reply;
                    _controller.selection = TextSelection.collapsed(offset: reply.length);
                  },
            label: Text(reply),
          );
        },
      ),
    );
  }

  Future<void> _openAppealDialog(BuildContext context) async {
    final appealController = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обжалование заморозки'),
        content: TextField(
          controller: appealController,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Опишите ситуацию'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Отправить')),
        ],
      ),
    );

    if (submit == true && appealController.text.trim().isNotEmpty) {
      try {
        await _accountRepository.appealFreeze(appealController.text.trim());
        _showToast('Апелляция отправлена');
      } on ApiException catch (error) {
        _showToast(error.message);
      }
    }
  }

  void _scrollToBottomIfNeeded({bool force = false}) {
    if (!_scrollController.hasClients) {
      return;
    }
    final atBottom = _scrollController.offset <= 80;
    if (!atBottom && _showJumpToBottom != true) {
      setState(() => _showJumpToBottom = true);
    }
    if (force || atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
      if (_showJumpToBottom) {
        setState(() => _showJumpToBottom = false);
      }
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final atBottom = _scrollController.offset <= 80;
    if (atBottom && _showJumpToBottom) {
      setState(() => _showJumpToBottom = false);
    } else if (!atBottom && !_showJumpToBottom) {
      setState(() => _showJumpToBottom = true);
    }
  }

  void _scheduleRetry() {
    if (!_isActive) {
      return;
    }
    _retryTimer?.cancel();
    final delaySeconds = (2 << _retryAttempts).clamp(2, 32);
    _retryAttempts = (_retryAttempts + 1).clamp(0, 5);
    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      _loadMessages(silent: true);
    });
  }

  void _handleReplyRequested(Message message) {
    if (_selectionMode) {
      setState(() {
        if (_selectedForForward.contains(message.id)) {
          _selectedForForward.remove(message.id);
        } else {
          _selectedForForward.add(message.id);
        }
      });
      return;
    }
    setState(() => _replyToMessage = message);
  }

  Future<void> _handleForwardSingle(Message message) async {
    await _forwardMessages([message.id]);
  }

  Future<void> _forwardSelected() async {
    await _forwardMessages(_selectedForForward.toList());
    setState(() {
      _selectedForForward.clear();
      _selectionMode = false;
    });
  }

  Future<void> _forwardMessages(List<String> messageIds) async {
    final controller = TextEditingController();
    final target = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forward to chat id'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: '-1 or chat id')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Forward')),
        ],
      ),
    );
    if (target == null || target.isEmpty) return;
    try {
      await _chatRepository.forwardMessages(messageIds, [target]);
    } on ApiException catch (error) {
      _showToast(error.message);
    }
  }



  Future<void> _handleReaction(Message message, String emoji) async {
    final existed = message.myReactions.contains(emoji);
    final optimisticReactions = Map<String, int>.from(message.reactions);
    final optimisticMine = List<String>.from(message.myReactions);
    if (existed) {
      final next = (optimisticReactions[emoji] ?? 0) - 1;
      if (next <= 0) {
        optimisticReactions.remove(emoji);
      } else {
        optimisticReactions[emoji] = next;
      }
      optimisticMine.remove(emoji);
    } else {
      optimisticReactions[emoji] = (optimisticReactions[emoji] ?? 0) + 1;
      optimisticMine.add(emoji);
    }
    _patchMessage(message.id, (it) => it.copyWith(reactions: optimisticReactions, myReactions: optimisticMine));
    try {
      if (existed) {
        await _chatRepository.removeReaction(widget.chat.id, message.id, emoji);
      } else {
        await _chatRepository.addReaction(widget.chat.id, message.id, emoji);
      }
    } on ApiException catch (error) {
      _showToast(error.message);
      _loadMessages(silent: true);
    }
  }

  Future<void> _handleEditMessage(Message message) async {
    final controller = TextEditingController(text: message.text);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: controller, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (edited == null || edited.isEmpty || edited == message.text) {
      return;
    }
    final original = message.text;
    _patchMessage(message.id, (it) => it.copyWith(text: edited));
    try {
      await _chatRepository.editMessage(widget.chat.id, message.id, edited);
    } on ApiException catch (error) {
      _patchMessage(message.id, (it) => it.copyWith(text: original));
      _showToast(error.message);
    }
  }

  Future<void> _handleDeleteMessage(Message message) async {
    final backup = _messages.where((it) => it.id == message.id).toList();
    setState(() {
      _localMessages.removeWhere((it) => it.id == message.id);
      _serverMessages.removeWhere((it) => it.id == message.id);
      _messageIds.remove(message.id);
    });
    try {
      await _chatRepository.deleteMessage(widget.chat.id, message.id);
    } on ApiException catch (error) {
      if (backup.isNotEmpty) {
        setState(() {
          _serverMessages.insert(0, backup.first);
          _messageIds.add(backup.first.id);
        });
      }
      _showToast(error.message);
    }
  }

  void _handleChatEvent(Map<String, dynamic> event) {
    final type = event['event_type']?.toString() ?? '';
    final payload = event['payload'] as Map<String, dynamic>?;
    if (payload == null) return;
    if (type == 'reaction_updated') {
      final messageId = payload['message_id']?.toString();
      if (messageId == null) return;
      final reactions = (payload['reactions'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toInt()));
      final mine = (payload['mine'] as List<dynamic>? ?? []).map((it) => it.toString()).toList();
      _patchMessage(messageId, (it) => it.copyWith(reactions: reactions, myReactions: mine));
    }
    if (type == 'pin_updated') {
      final messageId = payload['message_id']?.toString() ?? '';
      final pinned = payload['is_pinned'] as bool? ?? false;
      setState(() {
        _pinnedMessage = pinned ? _messages.where((it) => it.id == messageId).cast<Message?>().firstWhere((it) => it != null, orElse: () => null) : null;
      });
      _patchMessage(messageId, (it) => it.copyWith(isPinned: pinned));
    }
    if (type == 'draft_updated') {
      final text = payload['text']?.toString() ?? '';
      if (_controller.text != text) {
        _controller.text = text;
        _controller.selection = TextSelection.collapsed(offset: text.length);
      }
    }
    if (type == 'read_receipt_updated') {
      final lastMessageId = int.tryParse(payload['last_message_id']?.toString() ?? '0') ?? 0;
      setState(() {
        _localMessages.replaceRange(0, _localMessages.length, _localMessages.map((it) => it.isOutgoing && int.tryParse(it.id) != null && int.parse(it.id) <= lastMessageId ? it.copyWith(isRead: true) : it));
        _serverMessages.replaceRange(0, _serverMessages.length, _serverMessages.map((it) => it.isOutgoing && int.tryParse(it.id) != null && int.parse(it.id) <= lastMessageId ? it.copyWith(isRead: true) : it));
      });
    }
    if (type == 'typing_updated') {
      final isTyping = payload['is_typing'] as bool? ?? false;
      setState(() => _isTyping = isTyping);
    }
    if (type == 'message_deleted') {
      final messageId = payload['message_id']?.toString();
      if (messageId == null) return;
      setState(() {
        _localMessages.removeWhere((it) => it.id == messageId);
        _serverMessages.removeWhere((it) => it.id == messageId);
        _messageIds.remove(messageId);
      });
    }
  }

  void _patchMessage(String messageId, Message Function(Message current) update) {
    setState(() {
      for (var i = 0; i < _localMessages.length; i++) {
        if (_localMessages[i].id == messageId) {
          _localMessages[i] = update(_localMessages[i]);
        }
      }
      for (var i = 0; i < _serverMessages.length; i++) {
        if (_serverMessages[i].id == messageId) {
          _serverMessages[i] = update(_serverMessages[i]);
        }
      }
    });
  }



  void _onWsDisconnected() {
    if (!mounted) return;
    setState(() => _wsSyncState = WsSyncState.reconnecting);
    _wsDegradedTimer?.cancel();
    _wsDegradedTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _wsSyncState != WsSyncState.reconnecting) return;
      setState(() => _wsSyncState = WsSyncState.degraded);
    });
  }

  void _queueIncomingMessage(Message message) {
    if (_messageIds.contains(message.id)) {
      return;
    }
    _pendingIncomingMessages.add(message);
    if (_incomingFlushScheduled) {
      return;
    }
    _incomingFlushScheduled = true;
    scheduleMicrotask(_flushIncomingMessages);
  }

  void _flushIncomingMessages() {
    _incomingFlushScheduled = false;
    if (!mounted || _pendingIncomingMessages.isEmpty) {
      return;
    }

    final incoming = List<Message>.from(_pendingIncomingMessages);
    _pendingIncomingMessages.clear();

    setState(() {
      for (final message in incoming) {
        if (_messageIds.contains(message.id)) continue;
        final enhanced = _applyAutomationRulesToMessage(message);
        _localMessages.insert(0, enhanced);
        _messageIds.add(enhanced.id);
        _localStore.upsertSearchDocument(enhanced);
      }
      _wsSyncState = WsSyncState.connected;
    });

    _wsDegradedTimer?.cancel();
    _scrollToBottomIfNeeded();
    if (widget.initialMessageId != null) {
      _scrollToMessage(widget.initialMessageId!);
    }
    _loadSmartReplies(silent: true);
  }

  Widget _buildWsSyncBanner() {
    if (_wsSyncState == WsSyncState.connected) {
      return const SizedBox.shrink();
    }

    final isDegraded = _wsSyncState == WsSyncState.degraded;
    return MaterialBanner(
      backgroundColor: isDegraded ? Colors.red.withOpacity(0.12) : Colors.amber.withOpacity(0.14),
      content: Text(isDegraded ? 'Синхронизация ограничена. Пробуем восстановить...' : 'Восстанавливаем подключение...'),
      actions: [
        TextButton(
          onPressed: () => _loadMessages(silent: true),
          child: const Text('Обновить'),
        ),
      ],
    );
  }


  Future<void> _loadDraft() async {
    try {
      final text = await _chatRepository.getDraft(widget.chat.id);
      if (!mounted) return;
      if (text.isEmpty) return;
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    } catch (_) {}
  }

  Widget _buildPinnedBanner() {
    final pinned = _pinnedMessage;
    if (pinned == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.push_pin),
        title: Text(pinned.text, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => _scrollToMessage(pinned.id),
      ),
    );
  }

  void _scrollToMessage(String messageId) {
    final index = _messages.indexWhere((it) => it.id == messageId);
    if (index < 0 || !_scrollController.hasClients) return;

    setState(() => _highlightedMessageId = messageId);
    _scrollController.animateTo(index * 80.0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted || _highlightedMessageId != messageId) {
        return;
      }
      setState(() => _highlightedMessageId = null);
    });
  }

  void _onInputChanged() {
    final text = _controller.text;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 450), () {
      _chatRepository.saveDraft(widget.chat.id, text);
    });

    _updateMentionSuggestions();
    _typingStopTimer?.cancel();
    _wsDegradedTimer?.cancel();
    if (text.trim().isEmpty) {
      _chatRepository.typingStop(widget.chat.id);
      return;
    }
    _chatRepository.typingStart(widget.chat.id);
    _typingStopTimer = Timer(const Duration(milliseconds: 1500), () {
      _chatRepository.typingStop(widget.chat.id);
    });
  }

  void _updateMentionSuggestions() {
    final match = RegExp(r'@([A-Za-z0-9_]*)$').firstMatch(_controller.text);
    if (match == null) {
      if (_mentionSuggestions.isNotEmpty) setState(() => _mentionSuggestions = const []);
      return;
    }
    final q = (match.group(1) ?? '').toLowerCase();
    final next = _messages.map((m) => m.sender).where((s) => s.toLowerCase().contains(q)).toSet().take(6).toList();
    setState(() => _mentionSuggestions = next);
  }

  void _applyMention(String value) {
    final updated = _controller.text.replaceFirst(RegExp(r'@([A-Za-z0-9_]*)$'), '@$value ');
    _controller.text = updated;
    _controller.selection = TextSelection.collapsed(offset: updated.length);
    setState(() => _mentionSuggestions = const []);
  }

  Future<void> _copySelected() async {
    final joined = _messages.where((m) => _selectedForForward.contains(m.id)).map((m) => m.text).join('\n');
    await Clipboard.setData(ClipboardData(text: joined));
    _showToast('Copied');
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedForForward.toList();
    setState(() {
      _localMessages.removeWhere((m) => _selectedForForward.contains(m.id));
      _serverMessages.removeWhere((m) => _selectedForForward.contains(m.id));
      _messageIds.removeAll(_selectedForForward);
    });
    try {
      await _chatRepository.deleteMessagesBatch(widget.chat.id, ids);
    } on ApiException catch (error) {
      _showToast(error.message);
      _loadMessages(silent: true);
    }
    setState(() {
      _selectedForForward.clear();
      _selectionMode = false;
    });
  }

  void _handleMessageTap(Message message) {
    _focusedMessageId = message.id;
    if (!_selectionMode) return;
    final shift = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
    setState(() {
      if (shift && _selectedForForward.isNotEmpty) {
        final ids = _messages.map((e) => e.id).toList();
        final last = ids.indexOf(_selectedForForward.last);
        final cur = ids.indexOf(message.id);
        if (last >= 0 && cur >= 0) {
          final a = last < cur ? last : cur;
          final b = last < cur ? cur : last;
          _selectedForForward.addAll(ids.sublist(a, b + 1));
        }
      } else if (_selectedForForward.contains(message.id)) {
        _selectedForForward.remove(message.id);
      } else {
        _selectedForForward.add(message.id);
      }
    });
  }

  void _openHashtagSearch(String tag) {
    final filtered = _messages.where((m) => m.hashtags.contains(tag.toLowerCase())).toList();
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(filtered[index].text),
          onTap: () {
            Navigator.pop(context);
            _scrollToMessage(filtered[index].id);
          },
        ),
      ),
    );
  }

  Future<void> _handlePinToggle(Message message) async {
    try {
      if (message.isPinned) {
        await _chatRepository.unpinMessage(widget.chat.id, message.id);
      } else {
        await _chatRepository.pinMessage(widget.chat.id, message.id);
      }
    } on ApiException catch (error) {
      _showToast(error.message);
    }
  }



  Future<void> _persistLocalMessages() async {
    await _localStore.saveChatMessages(widget.chat.id, _localMessages);
  }

  Future<void> _flushPendingQueue() async {
    final queue = _localMessages.where((m) => m.outgoingState == OutgoingMessageState.pending || m.outgoingState == OutgoingMessageState.failed).toList();
    for (final message in queue) {
      _patchMessage(message.id, (it) => it.copyWith(outgoingState: OutgoingMessageState.sending));
      try {
        if (widget.chat.isSavedMessages) {
          await _chatRepository.sendSavedMessage(message.text);
        } else {
          await _chatRepository.sendMessage(widget.chat.id, message.text, replyToId: message.replyToId, contentType: message.contentType, voiceDuration: message.voiceDuration, clientMessageId: message.clientMessageId);
        }
        setState(() {
          _localMessages.removeWhere((it) => it.id == message.id);
          _messageIds.remove(message.id);
        });
      } on ApiException {
        _patchMessage(message.id, (it) => it.copyWith(outgoingState: OutgoingMessageState.failed));
      }
    }
    await _persistLocalMessages();
  }

  Future<void> _toggleImportant(Message message) async {
    final next = !message.isImportant;
    _patchMessage(message.id, (it) => it.copyWith(isImportant: next));
    await _localStore.saveFlags(message.id, {'is_important': next, 'local_note': message.localNote, 'is_local_pinned': message.isLocalPinned});
  }

  Future<void> _toggleLocalPin(Message message) async {
    final next = !message.isLocalPinned;
    _patchMessage(message.id, (it) => it.copyWith(isLocalPinned: next));
    await _localStore.saveFlags(message.id, {'is_important': message.isImportant, 'local_note': message.localNote, 'is_local_pinned': next});
  }

  Future<void> _addLocalNote(Message message) async {
    final controller = TextEditingController(text: message.localNote ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local note'),
        content: TextField(controller: controller, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (note == null) return;
    _patchMessage(message.id, (it) => it.copyWith(localNote: note));
    await _localStore.saveFlags(message.id, {'is_important': message.isImportant, 'local_note': note, 'is_local_pinned': message.isLocalPinned});
  }

  Future<void> _showEditHistory(Message message) async {
    final res = await ServiceLocator.get<ChatRepository>().getMessageHistory(widget.chat.id, message.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: res.length,
        itemBuilder: (context, index) => ListTile(title: Text(res[index]['text']?.toString() ?? ''), subtitle: Text(res[index]['date']?.toString() ?? '')),
      ),
    );
  }



  Future<void> _loadAutomationRules() async {
    _automationRules = await _localStore.getAutomationRules();
  }

  Message _applyAutomationRulesToMessage(Message message) {
    var next = message;
    final applied = <String>[];
    for (final rule in _automationRules.where((r) => r['enabled'] == true)) {
      final sender = rule['sender']?.toString();
      final senderGroup = rule['sender_group']?.toString();
      final chat = rule['chat_id']?.toString();
      final textContains = rule['text_contains']?.toString();
      final regex = rule['regex']?.toString();
      final media = rule['has_media'] as bool?;
      final startHour = (rule['time_start_hour'] as num?)?.toInt();
      final endHour = (rule['time_end_hour'] as num?)?.toInt();
      final hour = next.timestamp.hour;
      if (sender != null && sender.isNotEmpty && next.sender != sender) continue;
      if (senderGroup != null && senderGroup.isNotEmpty && !next.sender.startsWith(senderGroup)) continue;
      if (chat != null && chat.isNotEmpty && next.chatId != chat) continue;
      if (textContains != null && textContains.isNotEmpty && !next.text.toLowerCase().contains(textContains.toLowerCase())) continue;
      if (regex != null && regex.isNotEmpty && !RegExp(regex, caseSensitive: false).hasMatch(next.text)) continue;
      if (media != null && ((next.contentType != 'text') != media)) continue;
      if (startHour != null && hour < startHour) continue;
      if (endHour != null && hour > endHour) continue;

      final ruleId = rule['id']?.toString() ?? '';
      if (rule['action_important'] == true) {
        next = next.copyWith(isImportant: true);
      }
      if (rule['action_pin'] == true) {
        next = next.copyWith(isLocalPinned: true);
      }
      final note = rule['action_note']?.toString();
      if (note != null && note.isNotEmpty) {
        next = next.copyWith(localNote: note);
      }
      final label = rule['action_label']?.toString();
      if (label != null && label.isNotEmpty) {
        final prev = (next.localNote ?? '').trim();
        final merged = prev.isEmpty ? '[label:$label]' : '$prev [label:$label]';
        next = next.copyWith(localNote: merged);
      }
      if ((rule['action_auto_forward'] as bool? ?? false) == true) {
        final prev = (next.localNote ?? '').trim();
        next = next.copyWith(localNote: prev.isEmpty ? '[auto-forward]' : '$prev [auto-forward]');
      }
      final autoReply = rule['action_draft_auto_reply']?.toString();
      if (autoReply != null && autoReply.isNotEmpty) {
        Future.microtask(() => _chatRepository.saveDraft(next.chatId, autoReply));
      }
      if (ruleId.isNotEmpty) {
        applied.add(ruleId);
        Future.microtask(() => _localStore.incrementRuleExecution(ruleId));
      }
    }
    return next.copyWith(appliedAutomationRuleIds: applied);
  }

  Future<void> _openRulesEditor() async {
    if (!(widget.localProEnabled || _isPremium) && _automationRules.length >= 3) {
      _showToast('FEATURE_LOCKED');
      return;
    }
    final senderController = TextEditingController();
    final senderGroupController = TextEditingController();
    final textController = TextEditingController();
    final regexController = TextEditingController();
    final noteController = TextEditingController();
    final labelController = TextEditingController();
    final autoReplyController = TextEditingController();
    bool important = false;
    bool pin = false;
    bool hasMedia = false;
    bool enabled = true;
    bool autoForward = false;
    int? startHour;
    int? endHour;

    final stats = await _localStore.getRuleExecutionStats();

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Automation rule${(widget.localProEnabled || _isPremium) ? ' · Pro' : ''}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: senderController, decoration: const InputDecoration(labelText: 'Sender id (optional)')),
              TextField(controller: textController, decoration: const InputDecoration(labelText: 'Text contains (optional)')),
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note action (optional)')),
              CheckboxListTile(value: important, onChanged: (v) => setDialogState(() => important = v ?? false), title: const Text('Mark important')),
              CheckboxListTile(value: pin, onChanged: (v) => setDialogState(() => pin = v ?? false), title: const Text('Set local pin')),
              CheckboxListTile(value: hasMedia, onChanged: (v) => setDialogState(() => hasMedia = v ?? false), title: const Text('Has media condition')),
              const Divider(),
              Align(alignment: Alignment.centerLeft, child: Text('Automation Pro', style: TextStyle(fontWeight: FontWeight.w700, color: _isPremium ? null : Colors.orange))),
              TextField(controller: regexController, enabled: (widget.localProEnabled || _isPremium), decoration: const InputDecoration(labelText: 'Regex condition')),
              TextField(controller: senderGroupController, enabled: (widget.localProEnabled || _isPremium), decoration: const InputDecoration(labelText: 'Sender group prefix')),
              Row(children: [
                Expanded(child: DropdownButtonFormField<int>(value: startHour, decoration: const InputDecoration(labelText: 'Start hour'), items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text('$i'))), onChanged: (widget.localProEnabled || _isPremium) ? (v) => setDialogState(() => startHour = v) : null)),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<int>(value: endHour, decoration: const InputDecoration(labelText: 'End hour'), items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text('$i'))), onChanged: (widget.localProEnabled || _isPremium) ? (v) => setDialogState(() => endHour = v) : null)),
              ]),
              TextField(controller: labelController, enabled: (widget.localProEnabled || _isPremium), decoration: const InputDecoration(labelText: 'Action: auto-label')),
              CheckboxListTile(value: autoForward, onChanged: (widget.localProEnabled || _isPremium) ? (v) => setDialogState(() => autoForward = v ?? false) : null, title: const Text('Action: auto-forward marker')),
              TextField(controller: autoReplyController, enabled: (widget.localProEnabled || _isPremium), decoration: const InputDecoration(labelText: 'Action: draft auto-reply')),
              if (!(widget.localProEnabled || _isPremium))
                const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.only(top: 6), child: Text('FEATURE_LOCKED for Pro controls', style: TextStyle(color: Colors.orange)))),
              if (stats.isNotEmpty)
                Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 10), child: Text('Rule stats tracked locally: ${stats.length}'))),
              SwitchListTile(value: enabled, onChanged: (v) => setDialogState(() => enabled = v), title: const Text('Enabled')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (save != true) return;
    if (!(widget.localProEnabled || _isPremium) && (regexController.text.trim().isNotEmpty || senderGroupController.text.trim().isNotEmpty || labelController.text.trim().isNotEmpty || autoReplyController.text.trim().isNotEmpty || autoForward || startHour != null || endHour != null)) {
      _showToast('FEATURE_LOCKED');
      return;
    }
    final next = [..._automationRules, {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'sender': senderController.text.trim(),
      'sender_group': senderGroupController.text.trim(),
      'chat_id': widget.chat.id,
      'text_contains': textController.text.trim(),
      'regex': regexController.text.trim(),
      'has_media': hasMedia,
      'time_start_hour': startHour,
      'time_end_hour': endHour,
      'action_note': noteController.text.trim(),
      'action_important': important,
      'action_pin': pin,
      'action_label': labelController.text.trim(),
      'action_auto_forward': autoForward,
      'action_draft_auto_reply': autoReplyController.text.trim(),
      'enabled': enabled,
    }];
    _automationRules = next;
    await _localStore.saveAutomationRules(next);
    _loadMessages(silent: true);
  }

  Future<void> _showThread(Message message) async {
    final rootId = message.replyToId ?? message.id;
    final thread = await _chatRepository.getMessageThread(widget.chat.id, rootId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: ChatMessageList(
          messages: thread,
          isLoading: false,
          errorMessage: null,
          onRefresh: () async {},
          scrollController: ScrollController(),
          desktopMode: widget.desktopMode,
          onReplyRequested: _handleReplyRequested,
          onReact: _handleReaction,
          onEdit: _handleEditMessage,
          onDelete: _handleDeleteMessage,
          onPin: _handlePinToggle,
          onForward: _handleForwardSingle,
          onJumpToMessage: _scrollToMessage,
          onHashtagTap: _openHashtagSearch,
          onTapMessage: (it) {
            _focusedMessageId = it.id;
          },
          onRetrySend: (_) => _flushPendingQueue(),
          onToggleImportant: _toggleImportant,
          onToggleLocalPin: _toggleLocalPin,
          onAddLocalNote: _addLocalNote,
          onShowEditHistory: _showEditHistory,
          onViewThread: (_) {},
          onOpenInspector: _openInspector,
          densityMode: _densityMode,
          inThreadView: true,
        ),
      ),
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _NextUnreadIntent extends Intent { const _NextUnreadIntent(); }
class _ToggleImportantIntent extends Intent { const _ToggleImportantIntent(); }
class _ToggleLocalPinIntent extends Intent { const _ToggleLocalPinIntent(); }
class _OpenHistoryIntent extends Intent { const _OpenHistoryIntent(); }
class _OpenThreadIntent extends Intent { const _OpenThreadIntent(); }
class _OpenInspectorIntent extends Intent { const _OpenInspectorIntent(); }

class _ReplySkeleton extends StatelessWidget {
  const _ReplySkeleton({this.width = 92});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 30,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
