from __future__ import annotations

import argparse
import json
import sys
import traceback
from datetime import datetime, timezone, timedelta
from typing import Any, Callable

from common.contract import PredV1, pred_dumps
from common.hash import sha256_text

TZ8 = timezone(timedelta(hours=8))


def _ensure_utf8_stdio() -> None:
    """Keep the pred.v1 CLI contract UTF-8 on legacy Windows consoles."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, OSError):
            pass


def now_cn() -> datetime:
    return datetime.now(TZ8)


def emit(obj: dict[str, Any] | PredV1, *, ok: bool) -> None:
    _ensure_utf8_stdio()
    if isinstance(obj, PredV1):
        text = pred_dumps(obj)
    else:
        text = json.dumps(obj, ensure_ascii=False, default=_json_default)
    sys.stdout.write(text)
    if not text.endswith("\n"):
        sys.stdout.write("\n")
    sys.stdout.flush()
    sys.exit(0 if ok else 1)


def fail(source_id: str, source_name: str, site_family: str, lottery: str,
         play_type: str, hit_mode: str, code: str, message: str,
         final_url: str | None = None) -> None:
    _ensure_utf8_stdio()
    body = {
        "ok": False,
        "schema": "pred.v1",
        "source_id": source_id,
        "source_name": source_name,
        "site_family": site_family,
        "lottery": lottery,
        "play_type": play_type,
        "hit_mode": hit_mode,
        "fetched_at": now_cn().isoformat(),
        "final_url": final_url,
        "content_hash": sha256_text(""),
        "items": [],
        "error": {"code": code, "message": message},
    }
    print(message, file=sys.stderr)
    emit(body, ok=False)


def parse_common_args(description: str) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=description)
    p.add_argument("--lottery", required=True, choices=["hk", "macau", "taiwan", "new"])
    p.add_argument("--period", default=None, help="canonical or raw period, optional")
    p.add_argument("--fixture", default=None, help="local fixture file, skip HTTP")
    return p.parse_args()


def run_source(fetch: Callable[[argparse.Namespace], PredV1]) -> None:
    # argv already parsed inside fetch via parse_common_args typically
    try:
        args = parse_common_args("source")
        pred = fetch(args)
        if not pred.ok:
            emit(pred, ok=False)
        emit(pred, ok=True)
    except SystemExit:
        raise
    except Exception as e:
        traceback.print_exc(file=sys.stderr)
        sys.stdout.write(json.dumps({
            "ok": False,
            "schema": "pred.v1",
            "source_id": "unknown",
            "source_name": "unknown",
            "site_family": "unknown",
            "lottery": "macau",
            "play_type": "pingte_xiao",
            "hit_mode": "any",
            "fetched_at": now_cn().isoformat(),
            "final_url": None,
            "content_hash": sha256_text(""),
            "items": [],
            "error": {"code": "crash", "message": str(e)},
        }, ensure_ascii=False) + "\n")
        sys.exit(1)


def _json_default(o: Any) -> Any:
    if isinstance(o, datetime):
        return o.isoformat()
    raise TypeError(type(o))
