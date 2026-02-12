import base64
import hashlib
import hmac
import json
import secrets
import time
from typing import Any, Optional

from fastapi import Header, HTTPException, status

from .config import settings
from .storage import SessionStorage


class TokenService:
  def __init__(self, storage: SessionStorage) -> None:
    self._storage = storage

  @staticmethod
  def _b64_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("utf-8")

  @staticmethod
  def _b64_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)

  @staticmethod
  def _account_version(record: dict[str, Any] | None) -> int:
    if not record:
      return 1
    return int(record.get("account_version", 1))

  def _sign(self, payload_b64: str) -> str:
    digest = hmac.new(
      settings.session_secret.encode("utf-8"),
      payload_b64.encode("utf-8"),
      hashlib.sha256,
    ).digest()
    return self._b64_encode(digest)

  def _build_token(self, phone: str, kind: str, ttl_seconds: int) -> str:
    record = self._storage.load(phone) or {}
    payload = {
      "phone": phone,
      "kind": kind,
      "version": self._account_version(record),
      "exp": int(time.time()) + ttl_seconds,
      "nonce": secrets.token_urlsafe(12),
    }
    payload_b64 = self._b64_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signature_b64 = self._sign(payload_b64)
    return f"{payload_b64}.{signature_b64}"

  def _verify_kind(self, token: str, phone: str, kind: str) -> bool:
    try:
      payload_b64, signature_b64 = token.split(".", 1)
    except ValueError:
      return False

    expected_signature = self._sign(payload_b64)
    if not hmac.compare_digest(signature_b64, expected_signature):
      return False

    try:
      payload = json.loads(self._b64_decode(payload_b64))
    except (json.JSONDecodeError, ValueError):
      return False

    if payload.get("phone") != phone or payload.get("kind") != kind:
      return False
    if int(payload.get("exp", 0)) < int(time.time()):
      return False

    record = self._storage.load(phone) or {}
    return int(payload.get("version", 0)) == self._account_version(record)

  def issue(self, phone: str) -> str:
    record = self._storage.load(phone) or {}
    record.setdefault("account_version", 1)
    if "session" not in record:
      record["session"] = ""
    self._storage.save(phone, record)
    return self._build_token(phone, kind="api", ttl_seconds=60 * 60 * 24 * 7)

  def issue_ws(self, phone: str) -> str:
    return self._build_token(phone, kind="ws", ttl_seconds=60)

  def bump_account_version(self, phone: str) -> int:
    record = self._storage.load(phone) or {}
    next_version = self._account_version(record) + 1
    record["account_version"] = next_version
    if "session" in record:
      self._storage.save(phone, record)
    else:
      self._storage.save(phone, {"session": "", "account_version": next_version})
    return next_version

  def verify(self, token: str, phone: str) -> bool:
    return self._verify_kind(token, phone, kind="api")

  def verify_ws(self, token: str, phone: str) -> bool:
    return self._verify_kind(token, phone, kind="ws")


def get_bearer_token(authorization: Optional[str] = Header(default=None)) -> str:
  if not authorization:
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing auth")
  if not authorization.startswith("Bearer "):
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid auth")
  return authorization.split(" ", 1)[1]
