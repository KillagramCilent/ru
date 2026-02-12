import 'package:flutter/material.dart';
import '../../domain/entities/message.dart';
import '../../core/state/ui_settings_controller.dart';
import 'chat_bubble.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.isLoading,
    required this.errorMessage,
    required this.onRefresh,
    required this.scrollController,
    this.desktopMode = false,
    this.onReplyRequested,
    this.onReact,
    this.onEdit,
    this.onDelete,
    this.onPin,
    this.onForward,
    this.onJumpToMessage,
    this.onHashtagTap,
    this.onTapMessage,
    this.onRetrySend,
    this.onToggleImportant,
    this.onToggleLocalPin,
    this.onAddLocalNote,
    this.onShowEditHistory,
    this.onViewThread,
    this.onOpenInspector,
    this.onAiAction,
    this.densityMode = MessageDensityMode.comfortable,
    this.inThreadView = false,
    this.localEmoji,
    this.highlightedMessageId,
  });

  final List<Message> messages;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function() onRefresh;
  final ScrollController scrollController;
  final bool desktopMode;
  final ValueChanged<Message>? onReplyRequested;
  final void Function(Message message, String emoji)? onReact;
  final ValueChanged<Message>? onEdit;
  final ValueChanged<Message>? onDelete;
  final ValueChanged<Message>? onPin;
  final ValueChanged<Message>? onForward;
  final ValueChanged<String>? onJumpToMessage;
  final ValueChanged<String>? onHashtagTap;
  final ValueChanged<Message>? onTapMessage;
  final ValueChanged<Message>? onRetrySend;
  final ValueChanged<Message>? onToggleImportant;
  final ValueChanged<Message>? onToggleLocalPin;
  final ValueChanged<Message>? onAddLocalNote;
  final ValueChanged<Message>? onShowEditHistory;
  final ValueChanged<Message>? onViewThread;
  final ValueChanged<Message>? onOpenInspector;
  final void Function(String action, {Message? target})? onAiAction;
  final MessageDensityMode densityMode;
  final bool inThreadView;
  final String? localEmoji;
  final String? highlightedMessageId;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _MessageListSkeleton();
    }
    if (errorMessage != null) {
      return Center(child: Text(errorMessage!));
    }
    if (messages.isEmpty) {
      return const _MessageListSkeleton();
    }
    final listPadding = densityMode == MessageDensityMode.compact
        ? const EdgeInsets.all(10)
        : densityMode == MessageDensityMode.airy
            ? const EdgeInsets.all(20)
            : const EdgeInsets.all(16);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.custom(
        controller: scrollController,
        reverse: true,
        padding: listPadding,
        cacheExtent: 1200,
        childrenDelegate: SliverChildBuilderDelegate(
          childCount: messages.length,
          findChildIndexCallback: (key) {
            if (key is ValueKey<String>) {
              final index = messages.indexWhere((it) => it.id == key.value);
              return index >= 0 ? index : null;
            }
            return null;
          },
          (context, index) {
            final message = messages[index];
            final previous = index + 1 < messages.length ? messages[index + 1] : null;
            final next = index > 0 ? messages[index - 1] : null;
            final isSameAsPrevious = previous != null && previous.sender == message.sender;
            final isSameAsNext = next != null && next.sender == message.sender;
            return RepaintBoundary(
              child: ChatBubble(
                key: ValueKey<String>(message.id),
                message: message,
                isGroupedWithPrevious: isSameAsPrevious,
                isGroupedWithNext: isSameAsNext,
                desktopMode: desktopMode,
                onReplyRequested: onReplyRequested,
                onReact: onReact,
                onEdit: onEdit,
                onDelete: onDelete,
                onPin: onPin,
                onForward: onForward,
                onJumpToMessage: onJumpToMessage,
                onHashtagTap: onHashtagTap,
                onTapMessage: onTapMessage,
                onRetrySend: onRetrySend,
                onToggleImportant: onToggleImportant,
                onToggleLocalPin: onToggleLocalPin,
                onAddLocalNote: onAddLocalNote,
                onShowEditHistory: onShowEditHistory,
                onViewThread: onViewThread,
                onOpenInspector: onOpenInspector,
                onAiAction: onAiAction,
                densityMode: densityMode,
                inThreadView: inThreadView,
                localEmoji: localEmoji,
                highlighted: message.id == highlightedMessageId,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MessageListSkeleton extends StatelessWidget {
  const _MessageListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: 10,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final isOutgoing = index.isOdd;
        return Align(
          alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 180 + (index % 4) * 32,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
    );
  }
}
