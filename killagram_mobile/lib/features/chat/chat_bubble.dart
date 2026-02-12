import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/entities/message.dart';
import '../../core/state/ui_settings_controller.dart';
import 'bubble_tail_painter.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isGroupedWithPrevious,
    required this.isGroupedWithNext,
    this.desktopMode = false,
    this.onReplyRequested,
    this.onJumpToMessage,
    this.onReact,
    this.onEdit,
    this.onDelete,
    this.onPin,
    this.onForward,
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
    this.highlighted = false,
  });

  final Message message;
  final bool isGroupedWithPrevious;
  final bool isGroupedWithNext;
  final bool desktopMode;
  final ValueChanged<Message>? onReplyRequested;
  final ValueChanged<String>? onJumpToMessage;
  final void Function(Message message, String emoji)? onReact;
  final void Function(Message message)? onEdit;
  final void Function(Message message)? onDelete;
  final void Function(Message message)? onPin;
  final void Function(Message message)? onForward;
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
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    final alignment = isOutgoing ? Alignment.centerRight : Alignment.centerLeft;
    Color bubbleColor = isOutgoing ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface;
    if (message.isSystem) bubbleColor = Theme.of(context).colorScheme.surfaceVariant;
    if (message.outgoingState == OutgoingMessageState.failed) bubbleColor = Colors.red.withOpacity(0.2);
    if (message.outgoingState == OutgoingMessageState.pending) bubbleColor = Theme.of(context).colorScheme.secondary.withOpacity(0.22);
    if (message.replyToId != null) bubbleColor = Color.alphaBlend(Colors.teal.withOpacity(0.08), bubbleColor);
    if (inThreadView) bubbleColor = Color.alphaBlend(Colors.purple.withOpacity(0.12), bubbleColor);
    final textColor = isOutgoing ? Colors.white : Colors.black87;
    final timeColor = isOutgoing ? Colors.white70 : Colors.black54;

    final spacingScale = densityMode == MessageDensityMode.compact
        ? 0.78
        : densityMode == MessageDensityMode.airy
            ? 1.25
            : 1.0;
    final bodySize = densityMode == MessageDensityMode.compact
        ? 13.0
        : densityMode == MessageDensityMode.airy
            ? 16.0
            : 14.0;

    final topRadius = isGroupedWithPrevious ? 12.0 : 18.0;
    final bottomRadius = isGroupedWithNext ? 12.0 : 18.0;
    final marginTop = (isGroupedWithPrevious ? 2.0 : 8.0) * spacingScale;
    final marginBottom = (isGroupedWithNext ? 2.0 : 8.0) * spacingScale;

    final bubble = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      margin: EdgeInsets.only(
        top: marginTop,
        bottom: marginBottom,
        left: isOutgoing ? 48 : 12,
        right: isOutgoing ? 12 : 48,
      ),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: highlighted ? Theme.of(context).colorScheme.primary.withOpacity(0.14) : Colors.transparent,
      ),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (message.isPinned)
            const Positioned(top: -10, right: 8, child: Icon(Icons.push_pin, size: 14)),
          if (message.isSystem)
            const Positioned(top: -10, left: 8, child: Icon(Icons.info_outline, size: 14)),
          if (message.isImportant)
            const Positioned(top: -10, left: 24, child: Icon(Icons.star, size: 14, color: Colors.amber)),
          if (message.isLocalPinned)
            const Positioned(top: -10, left: 40, child: Icon(Icons.push_pin_outlined, size: 14)),
          DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isOutgoing ? 18 : topRadius),
                topRight: Radius.circular(isOutgoing ? topRadius : 18),
                bottomLeft: Radius.circular(isOutgoing ? 18 : bottomRadius),
                bottomRight: Radius.circular(isOutgoing ? bottomRadius : 18),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14 * spacingScale, 10 * spacingScale, 14 * spacingScale, 20 * spacingScale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${localEmoji ?? ''} ${message.sender}'.trim(), style: TextStyle(color: textColor.withOpacity(0.72), fontSize: 11)),
                  if (message.forwardedFrom != null)
                    Text('Forwarded from ${message.forwardedFrom}', style: TextStyle(color: textColor.withOpacity(0.75), fontSize: 12)),
                  if (message.replyToId != null)
                    InkWell(
                      onTap: () => onJumpToMessage?.call(message.replyToId!),
                      child: Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: textColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(message.replyPreview ?? 'Reply', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontSize: 12)),
                      ),
                    ),
                  _buildRichText(textColor, bodySize),
                  if (message.appliedAutomationRuleIds.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 4 * spacingScale),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.auto_fix_high, size: 12, color: textColor.withOpacity(0.8)),
                        const SizedBox(width: 4),
                        Text('Automation', style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 10)),
                      ]),
                    ),
                  if (message.editVersionsCount > 0)
                    GestureDetector(onTap: () => onShowEditHistory?.call(message), child: Text('Edited', style: TextStyle(color: textColor.withOpacity(0.75), fontSize: 11))),
                  if ((message.localNote ?? '').isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('📝 ${message.localNote}', style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 11))),
                  if (message.contentType == 'voice')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow, size: 16, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text('${message.voiceDuration ?? 0}s', style: TextStyle(color: textColor.withOpacity(0.9), fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(fontSize: 11, color: timeColor),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 4),
                  if (message.outgoingState == OutgoingMessageState.pending) Icon(Icons.schedule, size: 12, color: timeColor),
                  if (message.outgoingState == OutgoingMessageState.sending) Icon(Icons.sync, size: 12, color: timeColor),
                  if (message.outgoingState == OutgoingMessageState.failed) GestureDetector(onTap: () => onRetrySend?.call(message), child: Icon(Icons.error_outline, size: 12, color: Colors.redAccent)),
                  if (message.outgoingState == OutgoingMessageState.sent) Icon(message.isRead ? Icons.done_all : Icons.done, size: 12, color: timeColor),
                ],
              ],
            ),
          ),
          Positioned(
            bottom: 8,
            left: isOutgoing ? null : -6,
            right: isOutgoing ? -6 : null,
            child: CustomPaint(
              painter: BubbleTailPainter(
                color: bubbleColor,
                isOutgoing: isOutgoing,
              ),
              size: const Size(12, 12),
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: alignment,
      child: Column(
        crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 220),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: 0.98 + value * 0.02,
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => _showReactionPicker(context),
              onTap: () => onTapMessage?.call(message),
              onHorizontalDragEnd: desktopMode ? null : (_) => onReplyRequested?.call(message),
              onSecondaryTapDown: desktopMode
                  ? (details) => _showMessageContextMenu(context, details.globalPosition)
                  : null,
              child: bubble,
            ),
          ),
          if (message.reactions.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: isOutgoing ? 0 : 20, right: isOutgoing ? 20 : 0),
              child: Wrap(
                spacing: 6,
                children: message.reactions.entries
                    .map((entry) => TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.9, end: 1),
                          duration: const Duration(milliseconds: 220),
                          builder: (context, value, child) => Transform.scale(scale: value, child: child),
                          child: ActionChip(
                            onPressed: () => onReact?.call(message, entry.key),
                            label: Text('${entry.key} ${entry.value}'),
                          ),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildRichText(Color textColor, double bodySize) {
    final text = _displayText();
    final parts = text.split(RegExp(r'(\s+)'));
    final spans = <InlineSpan>[];
    for (final part in parts) {
      if (part.startsWith('#') && part.length > 1) {
        spans.add(WidgetSpan(
          child: GestureDetector(
            onTap: () => onHashtagTap?.call(part.substring(1).toLowerCase()),
            child: Text(part, style: TextStyle(color: Colors.lightBlue.shade200, fontWeight: FontWeight.w600)),
          ),
        ));
      } else if (part.startsWith('@') && part.length > 1) {
        spans.add(TextSpan(text: part, style: TextStyle(color: Colors.lightBlue.shade100, fontWeight: FontWeight.w600)));
      } else {
        spans.add(TextSpan(text: part, style: TextStyle(color: textColor, fontSize: bodySize)));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  String _displayText() {
    if (!message.isSystem) {
      return message.text;
    }
    final type = message.systemEventType ?? 'event';
    if (message.text.isNotEmpty) {
      return message.text;
    }
    return '[${type.replaceAll('_', ' ')}]';
  }

  Future<void> _showReactionPicker(BuildContext context) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => Wrap(
        children: ['👍', '❤️', '🔥', '😂', '😮', '👏']
            .map((it) => ListTile(title: Text(it, style: const TextStyle(fontSize: 24)), onTap: () => Navigator.pop(context, it)))
            .toList(),
      ),
    );
    if (emoji != null) {
      onReact?.call(message, emoji);
    }
  }

  Future<void> _showMessageContextMenu(BuildContext context, Offset globalPosition) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('Copy text')),
        const PopupMenuItem(value: 'reply', child: Text('Reply')),
        if (message.isOutgoing && message.canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (message.isOutgoing && message.canEdit) const PopupMenuItem(value: 'delete', child: Text('Delete')),
        const PopupMenuItem(value: 'pin_toggle', child: Text('Pin / Unpin')),
        const PopupMenuItem(value: 'important', child: Text('Important ⭐')),
        const PopupMenuItem(value: 'local_pin', child: Text('Local pin 📌')),
        const PopupMenuItem(value: 'note', child: Text('Local note 📝')),
        if (message.editVersionsCount > 0) const PopupMenuItem(value: 'history', child: Text('Edit history')),
        if (message.replyToId != null) const PopupMenuItem(value: 'thread', child: Text('View thread')),
        const PopupMenuItem(value: 'inspect', child: Text('Inspect message')),
        const PopupMenuItem(value: 'forward', child: Text('Forward')),
        if (desktopMode) const PopupMenuDivider(),
        if (desktopMode) const PopupMenuItem(value: 'ai_summarize', child: Text('AI · Summarize conversation')),
        if (desktopMode) const PopupMenuItem(value: 'ai_reply', child: Text('AI · Generate reply')),
        if (desktopMode) const PopupMenuItem(value: 'ai_rewrite_formal', child: Text('AI · Rewrite formal')),
        if (desktopMode) const PopupMenuItem(value: 'ai_rewrite_short', child: Text('AI · Rewrite short')),
        if (desktopMode) const PopupMenuItem(value: 'ai_rewrite_clear', child: Text('AI · Rewrite clear')),
        if (desktopMode) const PopupMenuItem(value: 'ai_tasks', child: Text('AI · Extract tasks')),
      ],
    );

    if (result == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Текст сообщения скопирован')),
        );
      }
    }

    if (result == 'reply') {
      onReplyRequested?.call(message);
    }
    if (result == 'edit') {
      onEdit?.call(message);
    }
    if (result == 'delete') {
      onDelete?.call(message);
    }
    if (result == 'pin_toggle') {
      onPin?.call(message);
    }
    if (result == 'important') {
      onToggleImportant?.call(message);
    }
    if (result == 'local_pin') {
      onToggleLocalPin?.call(message);
    }
    if (result == 'note') {
      onAddLocalNote?.call(message);
    }
    if (result == 'history') {
      onShowEditHistory?.call(message);
    }
    if (result == 'thread') {
      onViewThread?.call(message);
    }
    if (result == 'inspect') {
      onOpenInspector?.call(message);
    }
    if (result == 'ai_summarize') {
      onAiAction?.call('summarize', target: message);
    }
    if (result == 'ai_reply') {
      onAiAction?.call('reply', target: message);
    }
    if (result == 'ai_rewrite_formal') {
      onAiAction?.call('rewrite_formal', target: message);
    }
    if (result == 'ai_rewrite_short') {
      onAiAction?.call('rewrite_short', target: message);
    }
    if (result == 'ai_rewrite_clear') {
      onAiAction?.call('rewrite_clear', target: message);
    }
    if (result == 'ai_tasks') {
      onAiAction?.call('tasks', target: message);
    }
  }

  String _formatTime(DateTime time) {
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}
