from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import yaml
from dotenv import load_dotenv

from common import ROOT

_configured_env = os.getenv("PRED_ENV_FILE", "").strip()
_env_path = Path(_configured_env).expanduser() if _configured_env else ROOT / ".env"
if not _env_path.is_absolute():
    _env_path = (Path.cwd() / _env_path).absolute()
load_dotenv(_env_path)


def database_url() -> str:
    raw = os.getenv("COLLECTOR_DATABASE_URL", "").strip() or os.getenv("DATABASE_URL", "").strip()
    if not raw:
        db_path = (ROOT / "data" / "pred.db").resolve()
        return "sqlite:///" + db_path.as_posix()
    if raw.startswith("sqlite:///"):
        rest = raw[len("sqlite:///") :]
        if rest == ":memory:" or rest.startswith("file:"):
            return raw
        path = Path(rest)
        if not path.is_absolute():
            path = (ROOT / path).resolve()
        path.parent.mkdir(parents=True, exist_ok=True)
        return "sqlite:///" + path.as_posix()
    if raw.startswith("postgres://") or raw.startswith("postgresql://"):
        try:
            from sqlalchemy.engine import make_url
            u = make_url(raw)
            if u.drivername in ("postgresql", "postgres"):
                return u.set(drivername="postgresql+psycopg").render_as_string(hide_password=False)
        except Exception:
            pass
    return raw


def is_postgres(url: str | None = None) -> bool:
    u = url or database_url()
    return u.startswith("postgresql")


def allow_fixture() -> bool:
    return os.getenv("PRED_ALLOW_FIXTURE", "0").strip() in {"1", "true", "TRUE", "yes"}


def http_timeout() -> float:
    return float(os.getenv("HTTP_TIMEOUT_SEC", "20"))


def http_retries() -> int:
    return int(os.getenv("HTTP_RETRIES", "2"))


def load_yaml(path: Path | None = None) -> dict[str, Any]:
    p = path or (ROOT / "sources.yaml")
    with p.open(encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise ValueError(f"invalid yaml: {p}")
    return data
