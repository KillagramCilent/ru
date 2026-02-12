# Killagram Mobile (Flutter)

Killagram — production-ready мобильный клиент Telegram, вдохновлённый официальными приложениями, но расширенный AI-ассистентом, системой плагинов и глубокими настройками.

## Возможности

- Авторизация Telegram (MTProto через backend-адаптер).
- Высокая производительность, оффлайн-кэш, мультиаккаунт.
- AI-ассистент: резюме чатов, умные ответы, перевод, анализ настроения.
- Модульная архитектура с плагинами и песочницей.
- Надёжное локальное хранилище и безопасные ключи.

## Архитектура

- **Clean Architecture + MVVM** (слои: `data`, `domain`, `features`, `core`).
- Управление состоянием: BLoC/Cubit.
- Сетевой слой: `TelegramGateway` (абстракция MTProto / совместимого backend).
- Локальная БД: Hive + шифрование.

## Запуск

```bash
flutter pub get
flutter run
```

### iOS

```bash
cd ios
pod install
cd ..
flutter run
```

### Android

```bash
flutter run
```

## Структура

```
lib/
  app.dart
  main.dart
  core/
  data/
  domain/
  features/
```

## Документация

- [Architecture Overview](docs/ARCHITECTURE.md)
- [Security Model](docs/SECURITY.md)
- [Plugin System](docs/PLUGINS.md)
