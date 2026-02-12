# Killagram Backend (FastAPI + Telethon)

Backend-сервис для Killagram, который держит Telegram API ключи на сервере, хранит сессии и предоставляет HTTP + WebSocket API для клиента.

## Требования

- Python 3.11+
- Переменные окружения:
  - `API_ID`
  - `API_HASH`
  - `SESSION_SECRET`

## Запуск

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r backend/requirements.txt

export API_ID=123456
export API_HASH=your_hash
export SESSION_SECRET=supersecret

uvicorn backend.app.main:app --reload
```

## Основные API

### Auth

- `POST /auth/request-code`
- `POST /auth/confirm`
- `POST /auth/ws-token`
- `GET /me`

### Account safety (freeze)

- `POST /auth/freeze`
- `POST /auth/unfreeze`
- `POST /auth/appeal-freeze`
- `GET /auth/appeals/me`

`frozen` аккаунт получает `423 ACCOUNT_FROZEN` на write-операциях.

### Premium

- `GET /premium/status`
- `POST /premium/activate`
- `POST /premium/cancel`

### Chats

- `GET /chats`
- `GET /chats/{chat_id}/messages`
- `POST /chats/{chat_id}/messages`

### AI

- `POST /ai/summarize`
- `POST /ai/smart-replies`

### Gifts

- `GET /gifts`
- `POST /gifts/send`
- `GET /users/{id}/gifts`
- `GET /gifts/my`

### Market / Stars

- `GET /wallet/balance`
- `GET /market/items`
- `POST /market/purchase`
- `GET /wallet/transactions`

### Search

- `GET /search?q=<query>&scope=chats|groups|channels`

## Realtime event bus (WebSocket)

```http
GET ws://localhost:8000/ws/events?token=<ws_token>&phone=+79991234567
```

Event envelope:

```json
{
  "event_type": "message_created | account_status_updated | gift_received | market_purchase",
  "event_id": "...",
  "payload": {}
}
```

## Безопасность

- Сессии Telegram хранятся на сервере (`backend/data/*.json`).
- Токены авторизации выдаются сервером и проверяются на каждом запросе.

- HTTP POST idempotency middleware поддерживает `X-Idempotency-Key` и кэширует успешные ответы на короткий TTL.
- WebSocket использует отдельный короткоживущий `ws_token` (`/auth/ws-token`) вместо bearer-токена API.
- Токены подписаны HMAC (`SESSION_SECRET`) и содержат `account_version`; freeze/unfreeze повышает версию и инвалидирует ранее выданные токены/WS-сессии.
- Rate limit по IP (`RATE_LIMIT_PER_MINUTE`).
