from collections import defaultdict, deque
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any
import uuid


@dataclass
class UserState:
  phone: str
  status: str = 'active'
  freeze_reason: str | None = None
  premium: bool = False
  premium_until: datetime | None = None
  stars_balance: int = 100


class StateStore:
  def __init__(self) -> None:
    self._users: dict[str, UserState] = {}
    self._appeals: dict[str, list[dict]] = defaultdict(list)
    self._gifts = [
      {
        'id': 'gift_rose',
        'title': 'Rose',
        'rarity': 'common',
        'image': 'https://cdn.killagram/gifts/rose.png',
        'premium_only': False,
      },
      {
        'id': 'gift_phoenix',
        'title': 'Phoenix',
        'rarity': 'legendary',
        'image': 'https://cdn.killagram/gifts/phoenix.png',
        'premium_only': True,
      },
    ]
    self._user_gifts: dict[str, list[dict]] = defaultdict(list)
    self._market_items = [
      {'id': 'premium_month', 'title': 'Premium 1 month', 'type': 'premium', 'price_stars': 50},
      {'id': 'gift_box', 'title': 'Gift Box', 'type': 'gift', 'price_stars': 20},
    ]
    self._transactions: dict[str, list[dict]] = defaultdict(list)
    self._idempotency: dict[tuple[str, str], dict] = {}
    self._request_idempotency: dict[str, dict[str, Any]] = {}
    self._summary_cache: dict[str, str] = {}
    self._events: dict[str, deque[dict]] = defaultdict(deque)
    self._ai_requests: dict[str, deque[datetime]] = defaultdict(deque)
    self._reactions: dict[tuple[str, str, str], dict[str, int]] = defaultdict(dict)
    self._my_reactions: dict[tuple[str, str, str], set[str]] = defaultdict(set)
    self._pinned: dict[tuple[str, str], str] = {}
    self._drafts: dict[tuple[str, str], str] = {}
    self._read_receipts: dict[tuple[str, str], int] = {}
    self._typing: dict[tuple[str, str], bool] = {}
    self._folders: dict[str, list[dict[str, Any]]] = defaultdict(list)
    self._scheduled_messages: dict[str, list[dict[str, Any]]] = defaultdict(list)
    self._sent_messages_by_client_id: dict[tuple[str, str, str], dict[str, Any]] = {}
    self._message_edit_history: dict[tuple[str, str, str], list[dict[str, Any]]] = defaultdict(list)

  def get_user(self, phone: str) -> UserState:
    if phone not in self._users:
      self._users[phone] = UserState(phone=phone)
    return self._users[phone]

  def freeze(self, phone: str, reason: str) -> None:
    user = self.get_user(phone)
    user.status = 'frozen'
    user.freeze_reason = reason

  def unfreeze(self, phone: str) -> None:
    user = self.get_user(phone)
    user.status = 'active'
    user.freeze_reason = None

  def add_appeal(self, phone: str, text: str) -> dict:
    appeal = {
      'id': str(uuid.uuid4()),
      'phone': phone,
      'text': text,
      'created_at': datetime.utcnow(),
    }
    self._appeals[phone].append(appeal)
    return appeal

  def get_appeals(self, phone: str) -> list[dict]:
    return self._appeals[phone]

  def set_premium(self, phone: str, active: bool) -> UserState:
    user = self.get_user(phone)
    user.premium = active
    user.premium_until = datetime.utcnow() + timedelta(days=30) if active else None
    return user

  def gifts(self) -> list[dict]:
    return self._gifts

  def add_user_gift(self, owner: str, gift_id: str) -> dict:
    row = {'owner': owner, 'gift_id': gift_id, 'acquired_at': datetime.utcnow()}
    self._user_gifts[owner].append(row)
    return row

  def get_user_gifts(self, owner: str) -> list[dict]:
    return self._user_gifts[owner]

  def market_items(self) -> list[dict]:
    return self._market_items

  def purchase(self, phone: str, item_id: str, quantity: int, idempotency_key: str | None) -> dict:
    if idempotency_key:
      key = (phone, idempotency_key)
      if key in self._idempotency:
        return self._idempotency[key]

    user = self.get_user(phone)
    item = next((it for it in self._market_items if it['id'] == item_id), None)
    if item is None:
      raise ValueError('ITEM_NOT_FOUND')
    amount = item['price_stars'] * quantity
    if user.stars_balance < amount:
      raise ValueError('INSUFFICIENT_STARS')

    user.stars_balance -= amount
    tx = {
      'id': str(uuid.uuid4()),
      'phone': phone,
      'item_id': item_id,
      'quantity': quantity,
      'amount_stars': amount,
      'created_at': datetime.utcnow(),
    }
    self._transactions[phone].append(tx)
    if idempotency_key:
      self._idempotency[(phone, idempotency_key)] = tx
    return tx

  def transactions(self, phone: str) -> list[dict]:
    return self._transactions[phone]

  def get_summary_cache(self, key: str) -> str | None:
    return self._summary_cache.get(key)

  def set_summary_cache(self, key: str, value: str) -> None:
    self._summary_cache[key] = value

  def invalidate_summary_cache(self, chat_id: int) -> None:
    prefix = f'{chat_id}:'
    keys = [k for k in self._summary_cache if k.startswith(prefix)]
    for key in keys:
      del self._summary_cache[key]


  def allow_ai_summary(self, chat_id: int, per_minute: int = 8) -> bool:
    key = str(chat_id)
    now = datetime.utcnow()
    bucket = self._ai_requests[key]
    while bucket and (now - bucket[0]).total_seconds() > 60:
      bucket.popleft()
    if len(bucket) >= per_minute:
      return False
    bucket.append(now)
    return True

  def push_event(self, phone: str, event_type: str, payload: dict) -> None:
    self._events[phone].append({
      'event_type': event_type,
      'event_id': str(uuid.uuid4()),
      'payload': payload,
    })

  def pop_events(self, phone: str) -> list[dict]:
    events = list(self._events[phone])
    self._events[phone].clear()
    return events

  def get_request_idempotency(self, key: str) -> dict[str, Any] | None:
    row = self._request_idempotency.get(key)
    if not row:
      return None
    expires_at = row.get('expires_at')
    if isinstance(expires_at, datetime) and expires_at < datetime.utcnow():
      del self._request_idempotency[key]
      return None
    return row

  def set_request_idempotency(self, key: str, response: dict[str, Any], ttl_seconds: int = 300) -> None:
    self._request_idempotency[key] = {
      'response': response,
      'expires_at': datetime.utcnow() + timedelta(seconds=ttl_seconds),
    }




  def get_sent_message_by_client_id(self, phone: str, chat_id: str, client_message_id: str) -> dict[str, Any] | None:
    return self._sent_messages_by_client_id.get((phone, chat_id, client_message_id))

  def store_sent_message_by_client_id(self, phone: str, chat_id: str, client_message_id: str, message: dict[str, Any]) -> None:
    self._sent_messages_by_client_id[(phone, chat_id, client_message_id)] = dict(message)

  def append_edit_version(self, phone: str, chat_id: str, message_id: str, text: str, date: str) -> None:
    self._message_edit_history[(phone, chat_id, message_id)].append({'text': text, 'date': date})

  def edit_versions_count(self, phone: str, chat_id: str, message_id: str) -> int:
    return len(self._message_edit_history.get((phone, chat_id, message_id), []))

  def edit_history(self, phone: str, chat_id: str, message_id: str) -> list[dict[str, Any]]:
    history = self._message_edit_history.get((phone, chat_id, message_id), [])
    return list(reversed(history))

  def reaction_state(self, phone: str, chat_id: str, message_id: str) -> dict[str, Any]:
    key = (phone, chat_id, message_id)
    counters = self._reactions.get(key, {})
    mine = self._my_reactions.get(key, set())
    return {
      'counters': dict(counters),
      'mine': sorted(list(mine)),
    }

  def add_reaction(self, phone: str, chat_id: str, message_id: str, emoji: str) -> dict[str, Any]:
    key = (phone, chat_id, message_id)
    mine = self._my_reactions[key]
    counters = self._reactions[key]
    if emoji in mine:
      return self.reaction_state(phone, chat_id, message_id)
    mine.add(emoji)
    counters[emoji] = counters.get(emoji, 0) + 1
    return self.reaction_state(phone, chat_id, message_id)

  def remove_reaction(self, phone: str, chat_id: str, message_id: str, emoji: str) -> dict[str, Any]:
    key = (phone, chat_id, message_id)
    mine = self._my_reactions[key]
    counters = self._reactions[key]
    if emoji not in mine:
      return self.reaction_state(phone, chat_id, message_id)
    mine.remove(emoji)
    current = counters.get(emoji, 0)
    if current <= 1:
      counters.pop(emoji, None)
    else:
      counters[emoji] = current - 1
    return self.reaction_state(phone, chat_id, message_id)


  def set_pinned_message(self, phone: str, chat_id: str, message_id: str) -> dict[str, Any]:
    self._pinned[(phone, chat_id)] = message_id
    return {'chat_id': chat_id, 'message_id': message_id, 'is_pinned': True}

  def clear_pinned_message(self, phone: str, chat_id: str, message_id: str | None = None) -> dict[str, Any]:
    key = (phone, chat_id)
    current = self._pinned.get(key)
    if message_id is not None and current != message_id:
      return {'chat_id': chat_id, 'message_id': current or '', 'is_pinned': bool(current)}
    self._pinned.pop(key, None)
    return {'chat_id': chat_id, 'message_id': message_id or '', 'is_pinned': False}

  def pinned_message_id(self, phone: str, chat_id: str) -> str | None:
    return self._pinned.get((phone, chat_id))

  def set_draft(self, phone: str, chat_id: str, text: str) -> dict[str, Any]:
    key = (phone, chat_id)
    if text:
      self._drafts[key] = text
    else:
      self._drafts.pop(key, None)
    return {'chat_id': chat_id, 'text': text}

  def get_draft(self, phone: str, chat_id: str) -> str:
    return self._drafts.get((phone, chat_id), '')

  def set_read_receipt(self, phone: str, chat_id: str, last_message_id: int) -> dict[str, Any]:
    self._read_receipts[(phone, chat_id)] = last_message_id
    return {'chat_id': chat_id, 'last_message_id': last_message_id}

  def last_read_message_id(self, phone: str, chat_id: str) -> int:
    return self._read_receipts.get((phone, chat_id), 0)

  def set_typing(self, phone: str, chat_id: str, is_typing: bool) -> dict[str, Any]:
    self._typing[(phone, chat_id)] = is_typing
    return {'chat_id': chat_id, 'is_typing': is_typing}

  def typing_state(self, phone: str, chat_id: str) -> bool:
    return self._typing.get((phone, chat_id), False)


  def list_folders(self, phone: str) -> list[dict[str, Any]]:
    return sorted(self._folders[phone], key=lambda it: int(it.get('order', 0)))

  def create_folder(self, phone: str, title: str, include_types: list[str], chat_ids: list[str], order: int, emoji_id: str | None = None, emoji_fallback: str | None = None) -> dict[str, Any]:
    row = {
      'id': str(uuid.uuid4()),
      'title': title,
      'include_types': include_types,
      'chat_ids': chat_ids,
      'order': order,
      'is_system': False,
      'emoji_id': emoji_id,
      'emoji_fallback': emoji_fallback,
    }
    self._folders[phone].append(row)
    return row

  def get_folder(self, phone: str, folder_id: str) -> dict[str, Any] | None:
    return next((it for it in self._folders[phone] if it['id'] == folder_id), None)

  def update_folder(self, phone: str, folder_id: str, title: str, include_types: list[str], chat_ids: list[str], order: int, emoji_id: str | None = None, emoji_fallback: str | None = None) -> dict[str, Any] | None:
    row = self.get_folder(phone, folder_id)
    if row is None:
      return None
    row['title'] = title
    row['include_types'] = include_types
    row['chat_ids'] = chat_ids
    row['order'] = order
    row['emoji_id'] = emoji_id
    row['emoji_fallback'] = emoji_fallback
    return row

  def delete_folder(self, phone: str, folder_id: str) -> bool:
    before = len(self._folders[phone])
    self._folders[phone] = [it for it in self._folders[phone] if it['id'] != folder_id]
    return len(self._folders[phone]) != before


  def enqueue_scheduled_message(self, phone: str, chat_id: int, payload: dict[str, Any], send_at: datetime) -> dict[str, Any]:
    row = {
      'id': str(uuid.uuid4()),
      'chat_id': chat_id,
      'payload': payload,
      'send_at': send_at,
    }
    self._scheduled_messages[phone].append(row)
    self._scheduled_messages[phone].sort(key=lambda it: it['send_at'])
    return row

  def pop_due_scheduled_messages(self, phone: str, now: datetime | None = None) -> list[dict[str, Any]]:
    now = now or datetime.utcnow()
    due: list[dict[str, Any]] = []
    pending: list[dict[str, Any]] = []
    for row in self._scheduled_messages[phone]:
      if row['send_at'] <= now:
        due.append(row)
      else:
        pending.append(row)
    self._scheduled_messages[phone] = pending
    return due


store = StateStore()
