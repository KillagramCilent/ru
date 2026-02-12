from telethon import TelegramClient
from telethon.sessions import StringSession

from .config import settings
from .storage import SessionStorage


class TelegramService:
  def __init__(self, storage: SessionStorage) -> None:
    self._storage = storage

  def _build_client(self, session: str) -> TelegramClient:
    return TelegramClient(StringSession(session), settings.api_id, settings.api_hash)

  async def get_client(self, phone: str) -> TelegramClient:
    record = self._storage.load(phone)
    session = record["session"] if record else ""
    client = self._build_client(session)
    await client.connect()
    return client

  async def persist_session(self, phone: str, client: TelegramClient, token: str) -> None:
    session = client.session.save()
    self._storage.save(phone, {"session": session, "token": token})
