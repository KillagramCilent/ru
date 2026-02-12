import 'package:flutter/material.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.enabled = true,
    this.replyPreview,
    this.onCancelReply,
    this.onScheduleRequested,
    this.onVoiceRecorded,
    this.mentionSuggestions = const [],
    this.onMentionSelected,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final String? replyPreview;
  final VoidCallback? onCancelReply;
  final ValueChanged<DateTime>? onScheduleRequested;
  final ValueChanged<int>? onVoiceRecorded;
  final List<String> mentionSuggestions;
  final ValueChanged<String>? onMentionSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyPreview != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(replyPreview!, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(onPressed: onCancelReply, icon: const Icon(Icons.close, size: 16)),
                ],
              ),
            ),
          if (mentionSuggestions.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: mentionSuggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) => ActionChip(
                  label: Text('@${mentionSuggestions[index]}'),
                  onPressed: () => onMentionSelected?.call(mentionSuggestions[index]),
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                onPressed: enabled ? () {} : null,
                icon: const Icon(Icons.emoji_emotions_outlined),
              ),
              IconButton(
                onPressed: enabled ? () {} : null,
                icon: const Icon(Icons.attach_file),
              ),
              Expanded(
                child: TextField(
                  enabled: enabled,
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: enabled ? 'Сообщение' : 'Отправка недоступна',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                onPressed: enabled
                    ? () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDate: DateTime.now(),
                        );
                        if (picked == null || !context.mounted) return;
                        final now = TimeOfDay.now();
                        onScheduleRequested?.call(DateTime(picked.year, picked.month, picked.day, now.hour, now.minute).toUtc());
                      }
                    : null,
                icon: const Icon(Icons.schedule_send),
              ),
              GestureDetector(
                onLongPressStart: enabled ? (_) => onVoiceRecorded?.call(5) : null,
                child: IconButton(
                  onPressed: enabled ? onSend : null,
                  icon: const Icon(Icons.send),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
