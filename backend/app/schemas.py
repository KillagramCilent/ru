from datetime import datetime
from typing import Literal
from pydantic import BaseModel, Field


class AuthRequest(BaseModel):
  phone: str = Field(..., examples=["+79991234567"])


class AuthConfirm(BaseModel):
  phone: str
  code: str
  password: str | None = None


class VerificationOut(BaseModel):
  status: Literal['verified', 'unverified'] = 'unverified'
  provider: Literal['telegram', 'third_party', 'none'] = 'none'
  provider_name: str | None = None
  badge_icon_url: str | None = None


class ChatSummary(BaseModel):
  id: int
  title: str
  unread_count: int
  last_message: str | None
  verification: VerificationOut = Field(default_factory=VerificationOut)


class MessagePayload(BaseModel):
  text: str = ''
  client_message_id: str | None = None
  reply_to_id: int | None = None
  send_at: datetime | None = None
  content_type: Literal['text', 'voice'] = 'text'
  voice_duration: int | None = None
  mentions: list[str] = Field(default_factory=list)
  hashtags: list[str] = Field(default_factory=list)


class MessageOut(BaseModel):
  id: int
  sender: str
  text: str
  date: str
  is_outgoing: bool
  reactions: dict[str, int] = Field(default_factory=dict)
  my_reactions: list[str] = Field(default_factory=list)
  can_edit: bool = False
  is_read: bool = False
  is_pinned: bool = False
  is_system: bool = False
  system_event_type: str | None = None
  system_payload: dict[str, str] = Field(default_factory=dict)
  content_type: str = 'text'
  has_downloadable_file: bool = False
  reply_to_id: int | None = None
  reply_preview: str | None = None
  forwarded_from: str | None = None
  scheduled_at: str | None = None
  voice_duration: int | None = None
  mentions: list[str] = Field(default_factory=list)
  hashtags: list[str] = Field(default_factory=list)
  edit_versions_count: int = 0


class MessageVersionOut(BaseModel):
  text: str
  date: str


class MeOut(BaseModel):
  id: str
  phone: str
  status: str
  freeze_reason: str | None
  premium: bool
  premium_until: datetime | None
  stars_balance: int


class FreezePayload(BaseModel):
  phone: str
  reason: str


class UnfreezePayload(BaseModel):
  phone: str


class AppealPayload(BaseModel):
  text: str


class AppealOut(BaseModel):
  id: str
  phone: str
  text: str
  created_at: datetime


class SummarizePayload(BaseModel):
  chat_id: int
  range: str = 'recent'
  mode: str = 'short'
  from_message_id: int | None = None
  to_message_id: int | None = None
  limit: int = 50


class SmartRepliesPayload(BaseModel):
  chat_id: int
  message_id: int


class GiftOut(BaseModel):
  id: str
  title: str
  rarity: str
  image: str
  premium_only: bool


class SendGiftPayload(BaseModel):
  gift_id: str
  chat_id: int | None = None
  to_user_id: str | None = None


class UserGiftOut(BaseModel):
  owner: str
  gift_id: str
  acquired_at: datetime


class MarketItemOut(BaseModel):
  id: str
  title: str
  type: str
  price_stars: int


class PurchasePayload(BaseModel):
  item_id: str
  quantity: int = 1


class WalletOut(BaseModel):
  stars_balance: int


class TransactionOut(BaseModel):
  id: str
  phone: str
  item_id: str
  quantity: int
  amount_stars: int
  created_at: datetime


class SearchOut(BaseModel):
  id: str
  title: str
  scope: str
  snippet: str


class MessageEditPayload(BaseModel):
  chat_id: int
  text: str


class MessageDeletePayload(BaseModel):
  chat_id: int


class MessageDeleteBatchPayload(BaseModel):
  chat_id: int
  message_ids: list[int]


class MessageReactionPayload(BaseModel):
  chat_id: int
  emoji: str


class SavedMessagePayload(BaseModel):
  text: str


class MessagePinPayload(BaseModel):
  chat_id: int


class MessageForwardPayload(BaseModel):
  message_ids: list[int]
  target_chat_ids: list[int]


class DraftPayload(BaseModel):
  text: str


class DraftOut(BaseModel):
  chat_id: int
  text: str


class ReadReceiptPayload(BaseModel):
  last_message_id: int


class TypingPayload(BaseModel):
  scope: str = 'chat'


class FolderPayload(BaseModel):
  title: str
  include_types: list[str] = Field(default_factory=list)
  chat_ids: list[str] = Field(default_factory=list)
  order: int = 0
  emoji_id: str | None = None
  emoji_fallback: str | None = None


class FolderOut(BaseModel):
  id: str
  title: str
  include_types: list[str] = Field(default_factory=list)
  chat_ids: list[str] = Field(default_factory=list)
  order: int = 0
  is_system: bool = False
  emoji_id: str | None = None
  emoji_fallback: str | None = None


class SearchMessagesPayload(BaseModel):
  query: str
  folder_id: str | None = None
  chat_id: int | None = None
  sender_id: int | None = None
  has_media: bool | None = None
  saved_only: bool = False
  chat_scope: list[Literal['private', 'groups', 'channels']] = Field(default_factory=list)
  content_types: list[Literal['text', 'photo', 'video', 'voice', 'file', 'link']] = Field(default_factory=list)
  has_downloadable_file: bool | None = None
  limit: int = 20
  offset: int = 0


class SearchMessageHitOut(BaseModel):
  message: MessageOut
  chat_title: str
  chat_id: str
  chat_type: str = 'private'


class SearchMessagesOut(BaseModel):
  items: list[SearchMessageHitOut]
  total_count: int
