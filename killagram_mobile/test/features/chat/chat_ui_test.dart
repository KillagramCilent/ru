import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:killagram_mobile/domain/entities/chat.dart';
import 'package:killagram_mobile/domain/entities/message.dart';
import 'package:killagram_mobile/domain/repositories/ai_repository.dart';
import 'package:killagram_mobile/domain/repositories/chat_repository.dart';
import 'package:killagram_mobile/features/chat/chat_message_list.dart';
import 'package:killagram_mobile/features/chat/chat_screen.dart';

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({required List<Message> messages}) : _messages = messages;

  final List<Message> _messages;
  final StreamController<Message> _streamController =
      StreamController<Message>.broadcast();

  @override
  Future<List<Chat>> getChats({required int limit}) async => [];

  @override
  Future<List<Message>> getMessages(String chatId, {required int limit}) async {
    return _messages;
  }

  @override
  Future<void> sendMessage(String chatId, String text) async {}

  @override
  Stream<Message> watchMessages(String chatId) => _streamController.stream;
}

class FakeAiRepository implements AiRepository {
  @override
  Future<List<String>> smartReplies(String chatId) async => [];

  @override
  Future<String> summarizeChat(String chatId) async => 'summary';
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('ChatMessageList', () {
    testWidgets('shows empty state', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ChatMessageList(
            messages: const [],
            isLoading: false,
            errorMessage: null,
            onRefresh: () async {},
            scrollController: ScrollController(),
          ),
        ),
      );

      expect(find.text('Сообщений пока нет'), findsOneWidget);
    });

    testWidgets('shows loading state', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ChatMessageList(
            messages: const [],
            isLoading: true,
            errorMessage: null,
            onRefresh: () async {},
            scrollController: ScrollController(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ChatMessageList(
            messages: const [],
            isLoading: false,
            errorMessage: 'Ошибка сети',
            onRefresh: () async {},
            scrollController: ScrollController(),
          ),
        ),
      );

      expect(find.text('Ошибка сети'), findsOneWidget);
    });

    testWidgets('shows message list', (tester) async {
      final messages = [
        Message(
          id: '1',
          chatId: 'chat_1',
          sender: 'me',
          text: 'Привет',
          timestamp: DateTime(2026, 1, 1, 10, 0),
          isOutgoing: true,
        ),
        Message(
          id: '2',
          chatId: 'chat_1',
          sender: 'user_2',
          text: 'Как дела?',
          timestamp: DateTime(2026, 1, 1, 10, 1),
          isOutgoing: false,
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          ChatMessageList(
            messages: messages,
            isLoading: false,
            errorMessage: null,
            onRefresh: () async {},
            scrollController: ScrollController(),
          ),
        ),
      );

      expect(find.text('Привет'), findsOneWidget);
      expect(find.text('Как дела?'), findsOneWidget);
    });
  });

  group('ChatScreen with mocked repository', () {
    setUp(() async {
      await GetIt.instance.reset();
    });

    testWidgets('renders messages from ChatRepository', (tester) async {
      final repo = FakeChatRepository(
        messages: [
          Message(
            id: '11',
            chatId: 'chat_11',
            sender: 'me',
            text: 'Тест из репозитория',
            timestamp: DateTime(2026, 2, 1, 14, 30),
            isOutgoing: true,
          ),
        ],
      );

      GetIt.instance.registerSingleton<ChatRepository>(repo);
      GetIt.instance.registerSingleton<AiRepository>(FakeAiRepository());

      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(
            chat: const Chat(
              id: 'chat_11',
              title: 'QA Chat',
              lastMessage: '',
              unreadCount: 0,
              avatarUrl: '',
              isMuted: false,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Тест из репозитория'), findsOneWidget);
    });
  });
}
