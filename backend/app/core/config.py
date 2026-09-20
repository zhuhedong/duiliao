"""Application configuration loaded from environment / .env file."""
from __future__ import annotations

from functools import lru_cache
from typing import Annotated, List

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
ROOT_DIR = BACKEND_DIR.parent
DEFAULT_SQLITE_PATH = (BACKEND_DIR / "duiliao.db").resolve()


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=[
            str(BACKEND_DIR / ".env"),
            str(ROOT_DIR / ".env"),
            ".env",
        ],
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- General ---
    APP_NAME: str = "Duiliao API"
    APP_ENV: str = "development"  # development | staging | production
    DEBUG: bool = True
    API_V1_PREFIX: str = "/api/v1"

    # --- Server ---
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # --- Database ---
    # Anchored to backend/duiliao.db by absolute path to prevent working directory shifts
    DATABASE_URL: str = f"sqlite:///{DEFAULT_SQLITE_PATH}"
    COLLECTOR_DATABASE_URL: str = ""
    MAX_UPLOAD_SIZE_MB: int = 100

    @field_validator("DATABASE_URL", "COLLECTOR_DATABASE_URL", mode="after")
    @classmethod
    def normalize_database_url(cls, v: str) -> str:
        if not v:
            return v
        v = v.strip()
        if v.startswith("sqlite:///./") or v.startswith("sqlite://./") or v in ("sqlite:///duiliao.db", "sqlite://duiliao.db"):
            db_name = v.split("/")[-1]
            abs_path = (BACKEND_DIR / db_name).resolve()
            return f"sqlite:///{abs_path}"
        if v.startswith("postgres://") or v.startswith("postgresql://"):
            try:
                from sqlalchemy.engine import make_url
                u = make_url(v)
                if u.drivername in ("postgresql", "postgres"):
                    return u.set(drivername="postgresql+psycopg").render_as_string(hide_password=False)
            except Exception:
                pass
        return v

    # --- CORS ---
    # Comma-separated list of allowed origins (web dev server, app schemes, etc.)
    CORS_ORIGINS: Annotated[List[str], NoDecode] = Field(
        default_factory=lambda: [
            "http://localhost:5173",
            "http://127.0.0.1:5173",
            "capacitor://localhost",  # iOS Capacitor
            "http://localhost",       # Android Capacitor
        ]
    )

    # --- JWT ---
    JWT_SECRET: str = "CHANGE_ME_super_secret_key_min_32_chars_long_0123456789"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # --- API transport encryption (application layer, on top of HTTPS) ---
    # RSA private key (PEM). If empty, one is generated on startup and printed
    # (dev only). In production, provide a stable key via env/secret manager so
    # deployed instances share the same keypair.
    RSA_PRIVATE_KEY_PEM: str = ""
    RSA_KEY_SIZE: int = 2048
    # Lifetime of a negotiated AES session key (seconds).
    SESSION_KEY_TTL_SECONDS: int = 3600

    # --- Request signing / anti-replay ---
    # Shared app secret used to sign requests (HMAC). Ship this baked into the
    # native app / web bundle. It is an integrity + anti-tamper layer, NOT a
    # substitute for auth. Rotate per client version.
    APP_SIGNING_SECRET: str = "CHANGE_ME_app_signing_secret_change_me"
    # Reject requests whose timestamp drifts more than this many seconds.
    REQUEST_TIMESTAMP_TOLERANCE_SECONDS: int = 300
    # Require request signing/anti-replay on encrypted endpoints.
    ENFORCE_REQUEST_SIGNATURE: bool = True

    # --- Rate limiting ---
    RATE_LIMIT_DEFAULT: str = "120/minute"
    RATE_LIMIT_AUTH: str = "10/minute"

    # --- Password policy ---
    PASSWORD_MIN_LENGTH: int = 8

    # --- First-run admin bootstrap ---
    # When no admin/staff account exists yet, allow creating the first admin
    # from a loopback client without auth. Always disabled in production and
    # once any admin exists. Set to False to disable entirely (use the CLI).
    ALLOW_LOCAL_BOOTSTRAP: bool = True

    # --- AI Model Configuration ---
    AI_DEFAULT_PROVIDER: str = "openai"  # openai | gemini | anthropic

    # OpenAI-compatible protocol (DeepSeek, Qwen, Kimi, OpenAI, Ollama, etc.)
    OPENAI_API_KEY: str = ""
    OPENAI_BASE_URL: str = "https://api.openai.com/v1"
    OPENAI_MODEL: str = "deepseek-chat"

    # Google Gemini
    GEMINI_API_KEY: str = ""
    GEMINI_BASE_URL: str = "https://generativelanguage.googleapis.com"
    GEMINI_MODEL: str = "gemini-2.5-flash"

    # Anthropic Claude
    ANTHROPIC_API_KEY: str = ""
    ANTHROPIC_BASE_URL: str = "https://api.anthropic.com"
    ANTHROPIC_MODEL: str = "claude-3-5-sonnet-20241022"


    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def _split_cors(cls, v):
        if isinstance(v, str):
            return [o.strip() for o in v.split(",") if o.strip()]
        return v

    @property
    def is_production(self) -> bool:
        return self.APP_ENV.lower() == "production"

    @model_validator(mode="after")
    def _validate_production_secrets(self) -> "Settings":
        if self.is_production:
            if self.JWT_SECRET.startswith("CHANGE_ME"):
                raise ValueError("JWT_SECRET must be changed in production")
            if self.APP_SIGNING_SECRET.startswith("CHANGE_ME"):
                raise ValueError("APP_SIGNING_SECRET must be changed in production")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
