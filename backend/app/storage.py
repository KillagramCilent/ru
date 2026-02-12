import json
from pathlib import Path
from typing import Optional

from .config import settings


class SessionStorage:
  def __init__(self) -> None:
    self._root = Path(settings.session_dir)
    self._root.mkdir(parents=True, exist_ok=True)

  def _path(self, phone: str) -> Path:
    safe = phone.replace("+", "")
    return self._root / f"{safe}.json"

  def load(self, phone: str) -> Optional[dict]:
    path = self._path(phone)
    if not path.exists():
      return None
    return json.loads(path.read_text(encoding="utf-8"))

  def save(self, phone: str, payload: dict) -> None:
    path = self._path(phone)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

  def delete(self, phone: str) -> None:
    path = self._path(phone)
    if path.exists():
      path.unlink()
