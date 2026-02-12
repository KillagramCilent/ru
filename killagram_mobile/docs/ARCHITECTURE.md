# Architecture Overview

## Goals

- Telegram-like UX with high performance.
- Clean separation of UI, domain, and data layers.
- Pluggable modules (AI, plugins, automation).
- Secure storage for sessions and keys.

## Layers

- **Presentation** (`features/*`)
  - Stateless UI widgets + ViewModels/BLoC.
  - UI communicates only with domain interfaces.

- **Domain** (`domain/*`)
  - Entities, repository contracts, use-cases.
  - No Flutter-specific dependencies.

- **Data** (`data/*`)
  - MTProto gateway abstraction.
  - Local data sources (Hive, cache).
  - DTO mapping to domain entities.

- **Core** (`core/*`)
  - Dependency injection, config, theme, utilities.

## Telegram Integration

`TelegramGateway` encapsulates MTProto/TDLib calls. This allows the app to switch between:

- official MTProto SDK
- custom backend
- testing mock gateway

## Offline

- Hive stores chat list, message history, drafts.
- Encryption keys stored in secure storage.

## AI Module

- AI requests routed through `AiRepository`.
- Supports OpenAI API, local LLMs, or server proxy.

