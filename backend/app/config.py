from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
  model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

  api_id: int = Field(validation_alias="API_ID")
  api_hash: str = Field(validation_alias="API_HASH")
  session_secret: str = Field(validation_alias="SESSION_SECRET")
  session_dir: str = "backend/data"
  rate_limit_per_minute: int = Field(default=60, validation_alias="RATE_LIMIT_PER_MINUTE")


settings = Settings()
