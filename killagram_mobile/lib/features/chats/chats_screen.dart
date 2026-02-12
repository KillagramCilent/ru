import 'package:flutter/material.dart';
import '../../domain/entities/chat.dart';
import '../chat/chat_screen.dart';
import '../settings/settings_screen.dart';
import 'chats_list_pane.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  String? _selectedSearchMessageId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Killagram'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ChatsListPane(
          onSearchResultSelected: (chat, messageId) => _selectedSearchMessageId = messageId,
          onChatSelected: (Chat chat) {
            final initialMessageId = _selectedSearchMessageId;
            _selectedSearchMessageId = null;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(chat: chat, initialMessageId: initialMessageId),
              ),
            );
          },
        ),
      ),
    );
  }
}
