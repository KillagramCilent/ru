import time
from collections import defaultdict, deque
from typing import Deque

from fastapi import HTTPException, Request, status

from .config import settings


class RateLimiter:
  def __init__(self) -> None:
    self._events: dict[str, Deque[float]] = defaultdict(deque)

  def check(self, key: str) -> None:
    now = time.time()
    window = 60
    bucket = self._events[key]
    while bucket and now - bucket[0] > window:
      bucket.popleft()
    if len(bucket) >= settings.rate_limit_per_minute:
      raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail="Rate limit exceeded",
      )
    bucket.append(now)


limiter = RateLimiter()


def rate_limit(request: Request) -> None:
  client = request.client
  key = client.host if client else "unknown"
  limiter.check(key)
