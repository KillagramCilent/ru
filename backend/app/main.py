import asyncio
import re
from datetime import datetime, timedelta, timezone
from typing import Any, List

from fastapi import Depends, FastAPI, Header, HTTPException, Request, WebSocket, WebSocketDisconnect, status
from fastapi.responses import JSONResponse
from telethon.errors import SessionPasswordNeededError
from telethon.tl.types import Message

from .rate_limit import rate_limit
from .schemas import (
  AppealOut,
  AppealPayload,
  AuthConfirm,
  AuthRequest,
  ChatSummary,
  FolderOut,
  FolderPayload,
  FreezePayload,
  GiftOut,
  MarketItemOut,
  MeOut,
  MessageOut,
  MessageDeletePayload,
  MessageDeleteBatchPayload,
  MessageEditPayload,
  MessagePayload,
  MessagePinPayload,
  MessageForwardPayload,
  MessageReactionPayload,
  MessageVersionOut,
  PurchasePayload,
  DraftOut,
  DraftPayload,
  ReadReceiptPayload,
  SavedMessagePayload,
  TypingPayload,
  SearchMessageHitOut,
  SearchMessagesOut,
  SearchMessagesPayload,
  SearchOut,
  SendGiftPayload,
  SmartRepliesPayload,
  SummarizePayload,
  TransactionOut,
  UnfreezePayload,
  UserGiftOut,
  WalletOut,
)
from .security import TokenService, get_bearer_token
from .config import settings
from .state_store import store
from .storage import SessionStorage
from .telegram_client import TelegramService

app = FastAPI(title="Killagram Backend", version="0.1.0")

storage = SessionStorage()
telegram = TelegramService(storage)
tokens = TokenService(storage)


def _normalize_json(value: Any) -> Any:
  if isinstance(value, dict):
    return {k: _normalize_json(v) for k, v in value.items()}
  if isinstance(value, list):
    return [_normalize_json(v) for v in value]
  if hasattr(value, 'isoformat'):
    return value.isoformat()
  return value


def _request_signature(method: str, path: str, body: bytes) -> str:
  import hashlib
  import hmac

  payload = b'|'.join([method.upper().encode('utf-8'), path.encode('utf-8'), body])
  return hmac.new(settings.session_secret.encode('utf-8'), payload, hashlib.sha256).hexdigest()


@app.middleware('http')
async def idempotency_middleware(request: Request, call_next):
  if request.method.upper() != 'POST':
    return await call_next(request)

  key = request.headers.get('X-Idempotency-Key')
  if not key:
    return await call_next(request)

  body = await request.body()
  signature = _request_signature(request.method, request.url.path, body)
  composite_key = f"{key}:{signature}"
  cached = store.get_request_idempotency(composite_key)
  if cached:
    return JSONResponse(content=cached['response'])

  async def receive() -> dict:
    return {'type': 'http.request', 'body': body, 'more_body': False}

  request = Request(request.scope, receive)
  response = await call_next(request)

  if response.status_code < 400:
    captured_body = b''
    async for chunk in response.body_iterator:
      captured_body += chunk

    response_body = {}
    if captured_body:
      import json
      response_body = json.loads(captured_body.decode('utf-8'))

    store.set_request_idempotency(composite_key, _normalize_json(response_body))
    return JSONResponse(content=_normalize_json(response_body), status_code=response.status_code, headers=dict(response.headers))

  return response






def _system_folders() -> list[dict[str, Any]]:
  return [
    {'id': 'all', 'title': 'All', 'include_types': [], 'chat_ids': [], 'order': -100, 'is_system': True, 'emoji_id': None, 'emoji_fallback': None},
    {'id': 'unread', 'title': 'Unread', 'include_types': [], 'chat_ids': [], 'order': -90, 'is_system': True, 'emoji_id': None, 'emoji_fallback': None},
    {'id': 'saved', 'title': 'Saved', 'include_types': [], 'chat_ids': ['-1'], 'order': -80, 'is_system': True, 'emoji_id': None, 'emoji_fallback': None},
  ]


def _dialog_kind(dialog: Any) -> str:
  if getattr(getattr(dialog, 'entity', None), 'bot', False):
    return 'bots'
  if getattr(dialog, 'is_group', False):
    return 'groups'
  if getattr(dialog, 'is_channel', False):
    return 'channels'
  return 'private'




def _verification_for_dialog(dialog: Any) -> dict[str, Any]:
  title = (dialog.name or '').lower()
  if 'official' in title:
    return {'status': 'verified', 'provider': 'telegram', 'provider_name': 'Telegram', 'badge_icon_url': None}
  if 'verified' in title or getattr(dialog, 'is_channel', False):
    return {'status': 'verified', 'provider': 'third_party', 'provider_name': 'Trusted Partner', 'badge_icon_url': None}
  return {'status': 'unverified', 'provider': 'none', 'provider_name': None, 'badge_icon_url': None}


def _detect_message_kind(msg: Any) -> tuple[str, bool]:
  if msg is None:
    return ('text', False)
  media = getattr(msg, 'media', None)
  if media is None:
    return ('link' if 'http' in (msg.message or '').lower() else 'text', False)
  kind_name = media.__class__.__name__.lower()
  if 'photo' in kind_name:
    return ('photo', True)
  if 'document' in kind_name:
    attrs = getattr(getattr(media, 'document', None), 'attributes', [])
    is_voice = any(getattr(a, 'voice', False) for a in attrs)
    return ('voice' if is_voice else 'file', True)
  if 'webpage' in kind_name:
    return ('link', False)
  return ('video', True)


def _is_system_message(msg: Any) -> tuple[bool, str | None, dict[str, str]]:
  action = getattr(msg, 'action', None)
  if action is None:
    return (False, None, {})
  name = action.__class__.__name__.lower()
  if 'adduser' in name or 'joined' in name:
    return (True, 'member_joined', {'action': name})
  if 'phonecall' in name or 'call' in name:
    return (True, 'call_started', {'action': name})
  if 'gift' in name:
    return (True, 'gift_received', {'action': name})
  return (True, 'system_event', {'action': name})

def _dialog_to_chat_summary(dialog: Any) -> ChatSummary:
  return ChatSummary(
    id=dialog.id,
    title=dialog.name or '',
    unread_count=dialog.unread_count or 0,
    last_message=dialog.message.message if dialog.message else None,
    verification=_verification_for_dialog(dialog),
  )


def _filter_chats_by_folder(dialogs: list[Any], folder: dict[str, Any]) -> list[ChatSummary]:
  folder_id = folder['id']
  if folder_id == 'saved':
    return [ChatSummary(id=-1, title='Saved Messages', unread_count=0, last_message='', verification={'status': 'unverified', 'provider': 'none'})]

  results: list[ChatSummary] = [ChatSummary(id=-1, title='Saved Messages', unread_count=0, last_message='', verification={'status': 'unverified', 'provider': 'none'})]
  include_types = set(folder.get('include_types', []))
  include_chat_ids = set(folder.get('chat_ids', []))

  for dialog in dialogs:
    if folder_id == 'unread' and (dialog.unread_count or 0) <= 0:
      continue

    if folder_id not in {'all', 'unread'}:
      by_type = _dialog_kind(dialog) in include_types if include_types else False
      by_id = str(dialog.id) in include_chat_ids if include_chat_ids else False
      if include_types or include_chat_ids:
        if not (by_type or by_id):
          continue

    results.append(_dialog_to_chat_summary(dialog))

  return results



def _search_score(text: str, query: str) -> int:
  left = text.strip().lower()
  q = query.strip().lower()
  if not q:
    return 0
  if left == q:
    return 8
  if left.startswith(q):
    return 6
  if q in left:
    return 4
  if all(part in left for part in q.split(' ') if part):
    return 2
  return 0


async def _resolve_folder_chat_ids(phone: str, folder_id: str) -> set[int]:
  folder = next((it for it in _system_folders() if it['id'] == folder_id), None)
  if folder is None:
    folder = store.get_folder(phone, folder_id)
  if folder is None:
    raise HTTPException(status_code=404, detail='FOLDER_NOT_FOUND')

  client = await telegram.get_client(phone)
  dialogs = await client.get_dialogs(limit=200)
  await client.disconnect()
  chats = _filter_chats_by_folder(dialogs, folder)
  ids: set[int] = set()
  for row in chats:
    ids.add(int(row.id))
  return ids



async def _resolve_reply_preview_async(client: Any, chat_id: int, reply_to_id: int | None) -> str | None:
  if reply_to_id is None:
    return None
  msg = await client.get_messages(_chat_target(chat_id), ids=reply_to_id)
  if not msg:
    return None
  text = (msg.message or '').strip()
  if text:
    return text[:72]
  content_type, _ = _detect_message_kind(msg)
  return f'[{content_type}]'



def _extract_mentions_hashtags(text: str) -> tuple[list[str], list[str]]:
  mentions = sorted(list({m.lower() for m in re.findall(r'(?<!\w)@([A-Za-z0-9_]{2,32})', text or '')}))
  hashtags = sorted(list({h.lower() for h in re.findall(r'(?<!\w)#([A-Za-z0-9_]{2,64})', text or '')}))
  return mentions, hashtags

def _chat_target(chat_id: int):
  return 'me' if chat_id == -1 else chat_id


def _chat_id_str(chat_id: int) -> str:
  return 'saved' if chat_id == -1 else str(chat_id)


def _is_editable_window(date_value: str) -> bool:
  dt = datetime.now(timezone.utc)
  parsed = None
  try:
    parsed = datetime.fromisoformat(date_value.replace('Z', '+00:00'))
  except ValueError:
    return False
  if parsed.tzinfo is None:
    parsed = parsed.replace(tzinfo=timezone.utc)
  return (dt - parsed) <= timedelta(hours=48)

def get_phone(x_phone: str | None = Header(default=None)) -> str:
  if not x_phone:
    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing X-Phone")
  return x_phone


def authorize(phone: str = Depends(get_phone), token: str = Depends(get_bearer_token)) -> str:
  if not tokens.verify(token, phone):
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
  store.get_user(phone)
  return phone


def require_active_account(phone: str = Depends(authorize)) -> str:
  user = store.get_user(phone)
  if user.status == 'frozen':
    raise HTTPException(
      status_code=status.HTTP_423_LOCKED,
      detail={
        'code': 'ACCOUNT_FROZEN',
        'reason': user.freeze_reason,
      },
    )
  return phone


@app.post("/auth/request-code", dependencies=[Depends(rate_limit)])
async def request_code(payload: AuthRequest):
  client = await telegram.get_client(payload.phone)
  await client.send_code_request(payload.phone)
  await client.disconnect()
  return {"status": "code_sent"}


@app.post("/auth/confirm", dependencies=[Depends(rate_limit)])
async def confirm_code(payload: AuthConfirm):
  client = await telegram.get_client(payload.phone)
  try:
    await client.sign_in(payload.phone, payload.code)
  except SessionPasswordNeededError:
    if not payload.password:
      await client.disconnect()
      raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="2FA password required",
      )
    await client.sign_in(password=payload.password)
  token = tokens.issue(payload.phone)
  await telegram.persist_session(payload.phone, client, token)
  await client.disconnect()
  user = store.get_user(payload.phone)
  return {
    "status": "authorized",
    "token": token,
    "account_status": user.status,
    "freeze_reason": user.freeze_reason,
  }


@app.get('/me', response_model=MeOut, dependencies=[Depends(rate_limit)])
async def me(phone: str = Depends(authorize)):
  user = store.get_user(phone)
  return MeOut(
    id=phone.replace('+', ''),
    phone=phone,
    status=user.status,
    freeze_reason=user.freeze_reason,
    premium=user.premium,
    premium_until=user.premium_until,
    stars_balance=user.stars_balance,
  )


@app.post('/auth/freeze', dependencies=[Depends(rate_limit)])
async def freeze_account(payload: FreezePayload):
  store.freeze(payload.phone, payload.reason)
  store.push_event(
    payload.phone,
    'account_status_updated',
    {'status': 'frozen', 'freeze_reason': payload.reason},
  )
  tokens.bump_account_version(payload.phone)
  return {'status': 'ok'}


@app.post('/auth/unfreeze', dependencies=[Depends(rate_limit)])
async def unfreeze_account(payload: UnfreezePayload):
  store.unfreeze(payload.phone)
  store.push_event(
    payload.phone,
    'account_status_updated',
    {'status': 'active', 'freeze_reason': None},
  )
  tokens.bump_account_version(payload.phone)
  return {'status': 'ok'}


@app.post('/auth/appeal-freeze', response_model=AppealOut, dependencies=[Depends(rate_limit)])
async def appeal_freeze(payload: AppealPayload, phone: str = Depends(authorize)):
  appeal = store.add_appeal(phone, payload.text)
  return AppealOut(**appeal)


@app.get('/auth/appeals/me', response_model=List[AppealOut], dependencies=[Depends(rate_limit)])
async def my_appeals(phone: str = Depends(authorize)):
  return [AppealOut(**it) for it in store.get_appeals(phone)]


@app.get('/premium/status', dependencies=[Depends(rate_limit)])
async def premium_status(phone: str = Depends(authorize)):
  user = store.get_user(phone)
  return {
    'premium': user.premium,
    'premium_until': user.premium_until,
    'features': {
      'ai_summary_limit_per_minute': 24 if user.premium else 8,
      'smart_replies': user.premium,
      'premium_gifts': user.premium,
      'market_access': user.premium,
    },
  }


@app.post('/premium/activate', dependencies=[Depends(rate_limit)])
async def premium_activate(phone: str = Depends(require_active_account)):
  user = store.set_premium(phone, True)
  return {
    'premium': user.premium,
    'premium_until': user.premium_until,
    'features': {
      'ai_summary_limit_per_minute': 24 if user.premium else 8,
      'smart_replies': user.premium,
      'premium_gifts': user.premium,
      'market_access': user.premium,
    },
  }


@app.post('/premium/cancel', dependencies=[Depends(rate_limit)])
async def premium_cancel(phone: str = Depends(require_active_account)):
  user = store.set_premium(phone, False)
  return {
    'premium': user.premium,
    'premium_until': user.premium_until,
    'features': {
      'ai_summary_limit_per_minute': 24 if user.premium else 8,
      'smart_replies': user.premium,
      'premium_gifts': user.premium,
      'market_access': user.premium,
    },
  }




@app.get('/folders', response_model=List[FolderOut], dependencies=[Depends(rate_limit)])
async def list_folders(phone: str = Depends(authorize)):
  return [FolderOut(**it) for it in [*_system_folders(), *store.list_folders(phone)]]


@app.post('/folders', response_model=FolderOut, dependencies=[Depends(rate_limit)])
async def create_folder(payload: FolderPayload, phone: str = Depends(authorize)):
  user = store.get_user(phone)
  if payload.emoji_id and not user.premium:
    raise HTTPException(status_code=403, detail='PREMIUM_REQUIRED')
  row = store.create_folder(phone, payload.title, payload.include_types, payload.chat_ids, payload.order, payload.emoji_id, payload.emoji_fallback)
  store.push_event(phone, 'folder_updated', {'action': 'created', 'folder': row})
  return FolderOut(**row)


@app.put('/folders/{folder_id}', response_model=FolderOut, dependencies=[Depends(rate_limit)])
async def update_folder(folder_id: str, payload: FolderPayload, phone: str = Depends(authorize)):
  if folder_id in {'all', 'unread', 'saved'}:
    raise HTTPException(status_code=400, detail='SYSTEM_FOLDER_IMMUTABLE')
  user = store.get_user(phone)
  if payload.emoji_id and not user.premium:
    raise HTTPException(status_code=403, detail='PREMIUM_REQUIRED')
  row = store.update_folder(phone, folder_id, payload.title, payload.include_types, payload.chat_ids, payload.order, payload.emoji_id, payload.emoji_fallback)
  if row is None:
    raise HTTPException(status_code=404, detail='FOLDER_NOT_FOUND')
  store.push_event(phone, 'folder_updated', {'action': 'updated', 'folder': row})
  return FolderOut(**row)


@app.delete('/folders/{folder_id}', dependencies=[Depends(rate_limit)])
async def delete_folder(folder_id: str, phone: str = Depends(authorize)):
  if folder_id in {'all', 'unread', 'saved'}:
    raise HTTPException(status_code=400, detail='SYSTEM_FOLDER_IMMUTABLE')
  deleted = store.delete_folder(phone, folder_id)
  if not deleted:
    raise HTTPException(status_code=404, detail='FOLDER_NOT_FOUND')
  store.push_event(phone, 'folder_updated', {'action': 'deleted', 'folder_id': folder_id})
  return {'status': 'deleted', 'folder_id': folder_id}


@app.get('/folders/{folder_id}/chats', response_model=List[ChatSummary], dependencies=[Depends(rate_limit)])
async def folder_chats(folder_id: str, phone: str = Depends(authorize)):
  folder = next((it for it in _system_folders() if it['id'] == folder_id), None)
  if folder is None:
    folder = store.get_folder(phone, folder_id)
  if folder is None:
    raise HTTPException(status_code=404, detail='FOLDER_NOT_FOUND')

  client = await telegram.get_client(phone)
  dialogs = await client.get_dialogs(limit=200)
  await client.disconnect()
  return _filter_chats_by_folder(dialogs, folder)

@app.get("/chats", response_model=List[ChatSummary], dependencies=[Depends(rate_limit)])
async def list_chats(phone: str = Depends(authorize)):
  client = await telegram.get_client(phone)
  dialogs = await client.get_dialogs(limit=50)
  results: list[ChatSummary] = [
    ChatSummary(
      id=-1,
      title='Saved Messages',
      unread_count=0,
      last_message='',
    ),
  ]
  for dialog in dialogs:
    results.append(_dialog_to_chat_summary(dialog))
  await client.disconnect()
  return results


@app.get(
  "/chats/{chat_id}/messages",
  response_model=List[MessageOut],
  dependencies=[Depends(rate_limit)],
)
async def list_messages(chat_id: int, phone: str = Depends(authorize)):
  client = await telegram.get_client(phone)
  messages = await client.get_messages(_chat_target(chat_id), limit=50)
  response: list[MessageOut] = []
  for msg in messages:
    response.append(_map_message(msg, phone=phone, chat_id=chat_id))
  await client.disconnect()
  return response


@app.post(
  "/chats/{chat_id}/messages",
  dependencies=[Depends(rate_limit)],
)
async def send_message(
  chat_id: int,
  payload: MessagePayload,
  phone: str = Depends(require_active_account),
):
  chat_key = _chat_id_str(chat_id)
  if payload.client_message_id:
    cached = store.get_sent_message_by_client_id(phone, chat_key, payload.client_message_id)
    if cached is not None:
      return {"status": "sent", 'message': cached, 'idempotent': True}

  if payload.send_at is not None and payload.send_at > datetime.utcnow():
    scheduled = store.enqueue_scheduled_message(phone, chat_id, payload.model_dump(), payload.send_at)
    return {"status": "scheduled", "scheduled_id": scheduled['id'], 'send_at': payload.send_at.isoformat()}

  client = await telegram.get_client(phone)
  body = payload.text
  if payload.content_type == 'voice':
    body = f"[voice:{payload.voice_duration or 0}]"
  sent = await client.send_message(_chat_target(chat_id), body, reply_to=payload.reply_to_id)
  reply_preview = await _resolve_reply_preview_async(client, chat_id, payload.reply_to_id)
  await client.disconnect()
  store.invalidate_summary_cache(chat_id)
  mapped = _map_message(sent, phone=phone, chat_id=chat_id).model_dump()
  mapped['reply_to_id'] = payload.reply_to_id
  mapped['reply_preview'] = reply_preview
  mapped['voice_duration'] = payload.voice_duration
  mapped['content_type'] = payload.content_type
  mentions, hashtags = _extract_mentions_hashtags(payload.text)
  mapped['mentions'] = mentions
  mapped['hashtags'] = hashtags
  if payload.client_message_id:
    store.store_sent_message_by_client_id(phone, chat_key, payload.client_message_id, mapped)
  store.push_event(
    phone,
    'message_created',
    {'chat_id': _chat_id_str(chat_id), 'scope': 'user', 'message': mapped},
  )
  return {"status": "sent", 'message': mapped}




@app.get('/chats/saved', response_model=ChatSummary, dependencies=[Depends(rate_limit)])
async def saved_chat(phone: str = Depends(authorize)):
  _ = phone
  return ChatSummary(id=-1, title='Saved Messages', unread_count=0, last_message='', verification={'status': 'unverified', 'provider': 'none'})


@app.post('/messages/send', dependencies=[Depends(rate_limit)])
async def send_saved_message(payload: SavedMessagePayload, phone: str = Depends(require_active_account)):
  client = await telegram.get_client(phone)
  sent = await client.send_message('me', payload.text)
  await client.disconnect()
  mapped = _map_message(sent, phone=phone, chat_id=-1).model_dump()
  store.push_event(phone, 'message_created', {'chat_id': 'saved', 'scope': 'user', 'message': mapped})
  return {'status': 'sent', 'message': mapped}

@app.post('/ai/summarize', dependencies=[Depends(rate_limit)])
async def ai_summarize(payload: SummarizePayload, phone: str = Depends(authorize)):
  user = store.get_user(phone)
  ai_limit = 24 if user.premium else 8
  if not store.allow_ai_summary(payload.chat_id, per_minute=ai_limit):
    raise HTTPException(status_code=429, detail='AI_SUMMARY_RATE_LIMIT')

  cache_key = (
    f"{payload.chat_id}:{payload.range}:{payload.mode}:"
    f"{payload.from_message_id}:{payload.to_message_id}:{payload.limit}"
  )
  cached = store.get_summary_cache(cache_key)
  if cached is not None:
    return {'summary': cached, 'cached': True}

  client = await telegram.get_client(phone)
  messages = await client.get_messages(payload.chat_id, limit=payload.limit)
  await client.disconnect()

  filtered = []
  for msg in messages:
    if payload.from_message_id is not None and msg.id < payload.from_message_id:
      continue
    if payload.to_message_id is not None and msg.id > payload.to_message_id:
      continue
    if msg.message:
      filtered.append(msg.message.strip())

  joined = ' '.join(filtered)
  summary = (joined[:300] + '...') if len(joined) > 300 else joined
  if not summary:
    summary = 'Нет данных для суммаризации.'

  store.set_summary_cache(cache_key, summary)
  return {'summary': summary, 'cached': False}


@app.post('/ai/smart-replies', dependencies=[Depends(rate_limit)])
async def ai_smart_replies(payload: SmartRepliesPayload, phone: str = Depends(authorize)):
  user = store.get_user(phone)
  if not user.premium:
    return {'replies': [], 'available': False, 'reason': 'PREMIUM_REQUIRED'}

  client = await telegram.get_client(phone)
  lang = 'en'
  try:
    messages = await client.get_messages(payload.chat_id, limit=15)
    source_text = ' '.join([(msg.message or '') for msg in messages if msg.message])
    if any('а' <= ch.lower() <= 'я' for ch in source_text):
      lang = 'ru'
  finally:
    await client.disconnect()

  try:
    if lang == 'ru':
      replies = ['Ок, понял', 'Спасибо!', 'Сделаю сегодня', 'Давайте уточним детали']
    else:
      replies = ['Got it', 'Thanks!', 'I will do it today', 'Let’s clarify details']
    return {'replies': replies[:5], 'available': True}
  except Exception:
    fallback = ['Ок', 'Принял', 'Спасибо'] if lang == 'ru' else ['OK', 'Noted', 'Thanks']
    return {'replies': fallback, 'available': True}


@app.get('/gifts', response_model=List[GiftOut], dependencies=[Depends(rate_limit)])
async def gifts(phone: str = Depends(authorize)):
  _ = phone
  return [GiftOut(**gift) for gift in store.gifts()]


@app.post('/gifts/send', dependencies=[Depends(rate_limit)])
async def gifts_send(payload: SendGiftPayload, phone: str = Depends(require_active_account)):
  gift = next((it for it in store.gifts() if it['id'] == payload.gift_id), None)
  if gift is None:
    raise HTTPException(status_code=404, detail='GIFT_NOT_FOUND')

  user = store.get_user(phone)
  if gift['premium_only'] and not user.premium:
    raise HTTPException(status_code=403, detail='PREMIUM_REQUIRED')

  owner = payload.to_user_id or phone
  row = store.add_user_gift(owner, payload.gift_id)
  store.push_event(owner, 'gift_received', {'gift_id': payload.gift_id, 'from': phone})
  return {'status': 'sent', 'gift': row}


@app.get('/users/{user_id}/gifts', response_model=List[UserGiftOut], dependencies=[Depends(rate_limit)])
async def user_gifts(user_id: str, phone: str = Depends(authorize)):
  _ = phone
  return [UserGiftOut(**gift) for gift in store.get_user_gifts(user_id)]


@app.get('/gifts/my', response_model=List[UserGiftOut], dependencies=[Depends(rate_limit)])
async def my_gifts(phone: str = Depends(authorize)):
  return [UserGiftOut(**gift) for gift in store.get_user_gifts(phone)]


@app.get('/wallet/balance', response_model=WalletOut, dependencies=[Depends(rate_limit)])
async def wallet_balance(phone: str = Depends(authorize)):
  user = store.get_user(phone)
  return WalletOut(stars_balance=user.stars_balance)


@app.get('/market/items', response_model=List[MarketItemOut], dependencies=[Depends(rate_limit)])
async def market_items(phone: str = Depends(authorize)):
  _ = phone
  return [MarketItemOut(**item) for item in store.market_items()]


@app.post('/market/purchase', response_model=TransactionOut, dependencies=[Depends(rate_limit)])
async def market_purchase(
  payload: PurchasePayload,
  phone: str = Depends(require_active_account),
  x_idempotency_key: str | None = Header(default=None),
):
  user = store.get_user(phone)
  item = next((it for it in store.market_items() if it['id'] == payload.item_id), None)
  if item and item.get('type') == 'plugin' and not user.premium:
    raise HTTPException(status_code=403, detail='PREMIUM_MARKET_REQUIRED')

  try:
    tx = store.purchase(phone, payload.item_id, payload.quantity, x_idempotency_key)
  except ValueError as error:
    code = str(error)
    if code == 'ITEM_NOT_FOUND':
      raise HTTPException(status_code=404, detail=code)
    if code == 'INSUFFICIENT_STARS':
      raise HTTPException(status_code=400, detail=code)
    raise

  store.push_event(phone, 'market_purchase', tx)
  return TransactionOut(**tx)


@app.get('/wallet/transactions', response_model=List[TransactionOut], dependencies=[Depends(rate_limit)])
async def wallet_transactions(phone: str = Depends(authorize)):
  return [TransactionOut(**tx) for tx in store.transactions(phone)]


@app.post('/search/messages', response_model=SearchMessagesOut, dependencies=[Depends(rate_limit)])
async def search_messages(payload: SearchMessagesPayload, phone: str = Depends(authorize)):
  query = payload.query.strip().lower()
  target_chat_ids: set[int] | None = None
  if payload.saved_only and payload.chat_scope and any(scope != 'private' for scope in payload.chat_scope):
    raise HTTPException(status_code=400, detail='INVALID_FILTER_COMBINATION')

  if payload.saved_only:
    target_chat_ids = {-1}
  elif payload.chat_id is not None:
    target_chat_ids = {payload.chat_id}
  elif payload.folder_id:
    target_chat_ids = await _resolve_folder_chat_ids(phone, payload.folder_id)

  client = await telegram.get_client(phone)
  dialogs = await client.get_dialogs(limit=200)
  dialog_map = {int(d.id): d for d in dialogs}
  allowed_scopes = set(payload.chat_scope) if payload.chat_scope else None
  allowed_content_types = set(payload.content_types) if payload.content_types else None

  candidate_chat_ids: list[int] = []
  if target_chat_ids is None:
    candidate_chat_ids = [-1, *dialog_map.keys()]
  else:
    candidate_chat_ids = [int(it) for it in target_chat_ids]

  hits: list[tuple[int, SearchMessageHitOut]] = []
  for chat_id in candidate_chat_ids:
    raw_target = _chat_target(chat_id)
    messages = await client.get_messages(raw_target, limit=100)
    for msg in messages:
      text = (msg.message or '').strip()
      score = _search_score(text, query)
      if score <= 0:
        continue
      if payload.sender_id is not None and int(msg.sender_id or 0) != int(payload.sender_id):
        continue
      if payload.has_media is not None and bool(msg.media is not None) != payload.has_media:
        continue
      content_type, downloadable = _detect_message_kind(msg)
      if payload.has_downloadable_file is not None and downloadable != payload.has_downloadable_file:
        continue
      if allowed_content_types is not None and content_type not in allowed_content_types:
        continue

      mapped = _map_message(msg, phone=phone, chat_id=chat_id)
      mapped.content_type = content_type
      mapped.has_downloadable_file = downloadable
      chat_dialog = dialog_map.get(chat_id)
      chat_type = 'private' if chat_id == -1 else (_dialog_kind(chat_dialog) if chat_dialog else 'private')
      if allowed_scopes is not None and chat_type not in allowed_scopes:
        continue
      hit = SearchMessageHitOut(
        message=mapped,
        chat_title='Saved Messages' if chat_id == -1 else ((dialog_map.get(chat_id).name if dialog_map.get(chat_id) else '') or ''),
        chat_id=_chat_id_str(chat_id),
        chat_type=chat_type,
      )
      hits.append((score, hit))

  await client.disconnect()

  hits.sort(key=lambda it: (it[0], int(it[1].message.id)), reverse=True)
  total_count = len(hits)
  sliced = [it[1] for it in hits[payload.offset:payload.offset + payload.limit]]
  return SearchMessagesOut(items=sliced, total_count=total_count)


@app.get('/search', response_model=List[SearchOut], dependencies=[Depends(rate_limit)])
async def search(
  q: str,
  scope: str = 'chats',
  phone: str = Depends(authorize),
):
  client = await telegram.get_client(phone)
  dialogs = await client.get_dialogs(limit=100)
  await client.disconnect()

  results: list[SearchOut] = []
  query = q.lower().strip()
  for dialog in dialogs:
    title = (dialog.name or '').strip()
    if not title:
      continue
    if query and query not in title.lower():
      continue

    if scope == 'groups' and not dialog.is_group:
      continue
    if scope == 'channels' and not dialog.is_channel:
      continue
    if scope == 'chats' and (dialog.is_channel or dialog.is_group):
      continue

    snippet = dialog.message.message if dialog.message and dialog.message.message else ''
    results.append(SearchOut(id=str(dialog.id), title=title, scope=scope, snippet=snippet))

  return results[:50]



@app.post('/messages/{message_id}/pin', dependencies=[Depends(rate_limit)])
async def pin_message(message_id: int, payload: MessagePinPayload, phone: str = Depends(require_active_account)):
  client = await telegram.get_client(phone)
  message = await client.get_messages(_chat_target(payload.chat_id), ids=message_id)
  await client.disconnect()
  if not message:
    raise HTTPException(status_code=404, detail='MESSAGE_NOT_FOUND')
  pin_payload = store.set_pinned_message(phone, _chat_id_str(payload.chat_id), str(message_id))
  store.push_event(phone, 'pin_updated', pin_payload)
  return pin_payload


@app.post('/messages/{message_id}/unpin', dependencies=[Depends(rate_limit)])
async def unpin_message(message_id: int, payload: MessagePinPayload, phone: str = Depends(require_active_account)):
  pin_payload = store.clear_pinned_message(phone, _chat_id_str(payload.chat_id), str(message_id))
  store.push_event(phone, 'pin_updated', pin_payload)
  return pin_payload


@app.post('/chats/{chat_id}/draft', response_model=DraftOut, dependencies=[Depends(rate_limit)])
async def save_draft(chat_id: int, payload: DraftPayload, phone: str = Depends(authorize)):
  draft = store.set_draft(phone, _chat_id_str(chat_id), payload.text)
  store.push_event(phone, 'draft_updated', draft)
  return DraftOut(chat_id=chat_id, text=draft['text'])


@app.get('/chats/{chat_id}/draft', response_model=DraftOut, dependencies=[Depends(rate_limit)])
async def get_draft(chat_id: int, phone: str = Depends(authorize)):
  text = store.get_draft(phone, _chat_id_str(chat_id))
  return DraftOut(chat_id=chat_id, text=text)


@app.post('/chats/{chat_id}/read', dependencies=[Depends(rate_limit)])
async def mark_chat_read(chat_id: int, payload: ReadReceiptPayload, phone: str = Depends(authorize)):
  read_payload = store.set_read_receipt(phone, _chat_id_str(chat_id), payload.last_message_id)
  store.push_event(phone, 'read_receipt_updated', read_payload)
  return read_payload


@app.post('/chats/{chat_id}/typing/start', dependencies=[Depends(rate_limit)])
async def typing_start(chat_id: int, payload: TypingPayload, phone: str = Depends(authorize)):
  _ = payload
  typing_payload = store.set_typing(phone, _chat_id_str(chat_id), True)
  store.push_event(phone, 'typing_updated', typing_payload)
  return typing_payload


@app.post('/chats/{chat_id}/typing/stop', dependencies=[Depends(rate_limit)])
async def typing_stop(chat_id: int, payload: TypingPayload, phone: str = Depends(authorize)):
  _ = payload
  typing_payload = store.set_typing(phone, _chat_id_str(chat_id), False)
  store.push_event(phone, 'typing_updated', typing_payload)
  return typing_payload



@app.post('/messages/{message_id}/reactions/add', dependencies=[Depends(rate_limit)])
async def add_reaction(message_id: int, payload: MessageReactionPayload, phone: str = Depends(authorize)):
  state = store.add_reaction(phone, _chat_id_str(payload.chat_id), str(message_id), payload.emoji)
  event_payload = {'chat_id': _chat_id_str(payload.chat_id), 'message_id': str(message_id), 'reactions': state['counters'], 'mine': state['mine']}
  store.push_event(phone, 'reaction_updated', event_payload)
  return event_payload


@app.post('/messages/{message_id}/reactions/remove', dependencies=[Depends(rate_limit)])
async def remove_reaction(message_id: int, payload: MessageReactionPayload, phone: str = Depends(authorize)):
  state = store.remove_reaction(phone, _chat_id_str(payload.chat_id), str(message_id), payload.emoji)
  event_payload = {'chat_id': _chat_id_str(payload.chat_id), 'message_id': str(message_id), 'reactions': state['counters'], 'mine': state['mine']}
  store.push_event(phone, 'reaction_updated', event_payload)
  return event_payload


@app.post('/messages/forward', dependencies=[Depends(rate_limit)])
async def forward_messages(payload: MessageForwardPayload, phone: str = Depends(require_active_account)):
  client = await telegram.get_client(phone)
  forwarded_total = 0
  for target_chat_id in payload.target_chat_ids:
    for source_message_id in payload.message_ids:
      source = await client.get_messages(_chat_target(target_chat_id), ids=source_message_id)
      if not source:
        continue
      body = (source.message or '').strip() or '[forwarded]'
      sent = await client.send_message(_chat_target(target_chat_id), body)
      mapped = _map_message(sent, phone=phone, chat_id=target_chat_id).model_dump()
      mapped['forwarded_from'] = str(source.sender_id or '')
      store.push_event(phone, 'message_created', {'chat_id': _chat_id_str(target_chat_id), 'scope': 'forward', 'message': mapped})
      forwarded_total += 1
  await client.disconnect()
  return {'status': 'forwarded', 'count': forwarded_total}


@app.post('/messages/{message_id}/edit', dependencies=[Depends(rate_limit)])
async def edit_message(message_id: int, payload: MessageEditPayload, phone: str = Depends(require_active_account)):
  client = await telegram.get_client(phone)
  message = await client.get_messages(_chat_target(payload.chat_id), ids=message_id)
  if not message:
    await client.disconnect()
    raise HTTPException(status_code=404, detail='MESSAGE_NOT_FOUND')
  mapped_existing = _map_message(message, phone=phone, chat_id=payload.chat_id)
  if not _is_editable_window(mapped_existing.date):
    await client.disconnect()
    raise HTTPException(status_code=400, detail='EDIT_WINDOW_EXPIRED')
  store.append_edit_version(phone, _chat_id_str(payload.chat_id), str(message_id), mapped_existing.text, mapped_existing.date)
  edited = await client.edit_message(_chat_target(payload.chat_id), message_id, payload.text)
  await client.disconnect()
  mapped = _map_message(edited, phone=phone, chat_id=payload.chat_id).model_dump()
  mentions, hashtags = _extract_mentions_hashtags(payload.text)
  mapped['mentions'] = mentions
  mapped['hashtags'] = hashtags
  store.push_event(phone, 'message_edited', {'chat_id': _chat_id_str(payload.chat_id), 'message': mapped})
  return {'status': 'edited', 'message': mapped}






@app.get('/messages/{message_id}/thread', response_model=List[MessageOut], dependencies=[Depends(rate_limit)])
async def message_thread(message_id: int, chat_id: int, phone: str = Depends(authorize)):
  client = await telegram.get_client(phone)
  messages = await client.get_messages(_chat_target(chat_id), limit=300)
  await client.disconnect()
  by_id: dict[int, Message] = {int(msg.id): msg for msg in messages if getattr(msg, 'id', None) is not None}
  root = by_id.get(message_id)
  if root is None:
    raise HTTPException(status_code=404, detail='MESSAGE_NOT_FOUND')
  thread_ids: set[int] = {message_id}
  changed = True
  while changed:
    changed = False
    for msg in messages:
      reply = getattr(getattr(msg, 'reply_to', None), 'reply_to_msg_id', None)
      if reply is None:
        continue
      reply_id = int(reply)
      if reply_id in thread_ids and int(msg.id) not in thread_ids:
        thread_ids.add(int(msg.id))
        changed = True
  ordered = sorted((by_id[mid] for mid in thread_ids if mid in by_id), key=lambda it: it.date or datetime.utcnow())
  return [_map_message(msg, phone=phone, chat_id=chat_id) for msg in ordered]

@app.get('/messages/{message_id}/history', response_model=List[MessageVersionOut], dependencies=[Depends(rate_limit)])
async def message_history(message_id: int, chat_id: int, phone: str = Depends(authorize)):
  history = store.edit_history(phone, _chat_id_str(chat_id), str(message_id))
  return [MessageVersionOut(text=row.get('text', ''), date=row.get('date', '')) for row in history]

@app.post('/messages/delete-batch', dependencies=[Depends(rate_limit)])
async def delete_messages_batch(payload: MessageDeleteBatchPayload, phone: str = Depends(require_active_account)):
  client = await telegram.get_client(phone)
  deleted: list[int] = []
  for message_id in payload.message_ids:
    message = await client.get_messages(_chat_target(payload.chat_id), ids=message_id)
    if not message:
      continue
    mapped_existing = _map_message(message, phone=phone, chat_id=payload.chat_id)
    if not _is_editable_window(mapped_existing.date):
      continue
    await client.delete_messages(_chat_target(payload.chat_id), message_id)
    deleted.append(message_id)
    event_payload = {'chat_id': _chat_id_str(payload.chat_id), 'message_id': str(message_id)}
    store.push_event(phone, 'message_deleted', event_payload)
  await client.disconnect()
  return {'status': 'deleted', 'message_ids': deleted}


@app.post('/messages/{message_id}/delete', dependencies=[Depends(rate_limit)])
async def delete_message(message_id: int, payload: MessageDeletePayload, phone: str = Depends(require_active_account)):
  client = await telegram.get_client(phone)
  message = await client.get_messages(_chat_target(payload.chat_id), ids=message_id)
  if not message:
    await client.disconnect()
    raise HTTPException(status_code=404, detail='MESSAGE_NOT_FOUND')
  mapped_existing = _map_message(message, phone=phone, chat_id=payload.chat_id)
  if not _is_editable_window(mapped_existing.date):
    await client.disconnect()
    raise HTTPException(status_code=400, detail='DELETE_WINDOW_EXPIRED')
  await client.delete_messages(_chat_target(payload.chat_id), message_id)
  await client.disconnect()
  chat_key = _chat_id_str(payload.chat_id)
  event_payload = {'chat_id': chat_key, 'message_id': str(message_id)}
  store.push_event(phone, 'message_deleted', event_payload)
  pin_payload = store.clear_pinned_message(phone, chat_key, str(message_id))
  if not pin_payload['is_pinned']:
    store.push_event(phone, 'pin_updated', pin_payload)
  return {'status': 'deleted', **event_payload}

@app.post('/auth/ws-token', dependencies=[Depends(rate_limit)])
async def issue_ws_token(phone: str = Depends(authorize)):
  return {'ws_token': tokens.issue_ws(phone), 'expires_in_seconds': 60}


@app.websocket('/ws/events')
async def ws_events(websocket: WebSocket):
  phone = websocket.query_params.get('phone')
  token = websocket.query_params.get('token')
  if not phone or not token or not tokens.verify_ws(token, phone):
    await websocket.close(code=4401)
    return

  await websocket.accept()
  client = await telegram.get_client(phone)
  seen_ids: set[int] = set()
  try:
    while True:
      due = store.pop_due_scheduled_messages(phone)
      for row in due:
        payload = row['payload']
        chat_id = int(row['chat_id'])
        text = payload.get('text', '')
        if payload.get('content_type') == 'voice':
          text = f"[voice:{payload.get('voice_duration') or 0}]"
        sent = await client.send_message(_chat_target(chat_id), text, reply_to=payload.get('reply_to_id'))
        mapped = _map_message(sent, phone=phone, chat_id=chat_id).model_dump()
        mapped['scheduled_at'] = row['send_at'].isoformat()
        mapped['reply_to_id'] = payload.get('reply_to_id')
        mapped['voice_duration'] = payload.get('voice_duration')
        mapped['content_type'] = payload.get('content_type') or 'text'
        store.push_event(phone, 'message_created', {'chat_id': _chat_id_str(chat_id), 'scope': 'scheduled', 'message': mapped})

      events = store.pop_events(phone)
      for event in events:
        await websocket.send_json(event)

      messages = await client.get_messages(int(websocket.query_params.get('chat_id', '0') or 0), limit=30) if websocket.query_params.get('chat_id') else []
      for msg in reversed(messages):
        if msg.id in seen_ids:
          continue
        seen_ids.add(msg.id)
        await websocket.send_json(
          {
            'event_type': 'message_created',
            'event_id': f'msg_{msg.id}',
            'payload': {
              'chat_id': _chat_id_str(int(msg.chat_id or 0)),
              'message': _map_message(msg, phone=phone, chat_id=int(msg.chat_id or 0)).model_dump(),
            },
          },
        )

      await asyncio.sleep(2)
  except WebSocketDisconnect:
    pass
  finally:
    await client.disconnect()


def _map_message(message: Message, phone: str, chat_id: int) -> MessageOut:
  sender = "unknown"
  if message.sender_id:
    sender = str(message.sender_id)
  chat_key = _chat_id_str(chat_id)
  reaction_state = store.reaction_state(phone, chat_key, str(message.id))
  pinned_message_id = store.pinned_message_id(phone, chat_key)
  last_read_message_id = store.last_read_message_id(phone, chat_key)
  is_system, system_event_type, system_payload = _is_system_message(message)
  content_type, downloadable = _detect_message_kind(message)
  reply_to_id = None
  reply_preview = None
  if getattr(message, 'reply_to', None) and getattr(message.reply_to, 'reply_to_msg_id', None):
    reply_to_id = int(message.reply_to.reply_to_msg_id)
    reply_preview = '[reply]'
  forwarded_from = str(getattr(getattr(message, 'fwd_from', None), 'from_id', '') or '') or None
  voice_duration = None
  if content_type == 'voice':
    attrs = getattr(getattr(getattr(message, 'media', None), 'document', None), 'attributes', [])
    for a in attrs:
      if getattr(a, 'duration', None) is not None:
        voice_duration = int(a.duration)
        break
  mentions, hashtags = _extract_mentions_hashtags(message.message or "")
  edit_versions_count = store.edit_versions_count(phone, chat_key, str(message.id))
  return MessageOut(
    id=message.id,
    sender=sender,
    text=message.message or "",
    date=message.date.isoformat() if message.date else "",
    is_outgoing=message.out,
    reactions=reaction_state['counters'],
    my_reactions=reaction_state['mine'],
    can_edit=_is_editable_window(message.date.isoformat() if message.date else ''),
    is_read=message.out and message.id <= last_read_message_id,
    is_pinned=(pinned_message_id == str(message.id)),
    is_system=is_system,
    system_event_type=system_event_type,
    system_payload=system_payload,
    content_type=content_type,
    has_downloadable_file=downloadable,
    reply_to_id=reply_to_id,
    reply_preview=reply_preview,
    forwarded_from=forwarded_from,
    voice_duration=voice_duration,
    mentions=mentions,
    hashtags=hashtags,
    edit_versions_count=edit_versions_count,
  )
