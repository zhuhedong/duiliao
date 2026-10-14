"""Persist complete scrape snapshots and load confined file references."""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import TYPE_CHECKING, Any
from uuid import uuid4

from app.core.config import BACKEND_DIR

if TYPE_CHECKING:
    from collector.fetch_588080 import FetchResult

SCRAPED_DATA_DIR = BACKEND_DIR / "collector" / "html"
STORAGE_DIR = BACKEND_DIR / "storage"
LATEST_META_NAME = "588080-latest.json"
DEFAULT_TTL_SEC = 30 * 60


def save_scraped_data(result: FetchResult, *, as_latest: bool = True) -> dict[str, str]:
    """Save both formatting modes without changing the collector's CLI output."""
    SCRAPED_DATA_DIR.mkdir(parents=True, exist_ok=True)
    stem = f"588080-{uuid4().hex}"
    html_path = SCRAPED_DATA_DIR / f"{stem}.html"
    data_path = SCRAPED_DATA_DIR / f"{stem}.json"
    html_path.write_text(result.html, encoding="utf-8")
    if result.raw_html:
        (SCRAPED_DATA_DIR / f"{stem}.raw.html").write_text(result.raw_html, encoding="utf-8")
    payload = {
        "summary": result.to_summary(),
        "site_title": result.site_title,
        "html": result.html,
        "raw_html": result.raw_html,
        "modules": result.modules,
        "saved_at": time.time(),
    }
    data_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    paths = {
        "file_path": data_path.relative_to(BACKEND_DIR).as_posix(),
        "html_file_path": html_path.relative_to(BACKEND_DIR).as_posix(),
    }
    if as_latest and result.ok:
        _write_latest_pointer(paths, payload["summary"], payload["saved_at"])
    return paths


def _write_latest_pointer(paths: dict[str, str], summary: dict[str, Any], saved_at: float) -> None:
    meta = {
        "schema": "588080-dump-cache.v1",
        "saved_at": saved_at,
        "saved_at_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(saved_at)),
        "file_path": paths["file_path"],
        "html_file_path": paths.get("html_file_path"),
        "summary": summary,
    }
    target = SCRAPED_DATA_DIR / LATEST_META_NAME
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(target)


def latest_cache_meta() -> dict[str, Any] | None:
    target = SCRAPED_DATA_DIR / LATEST_META_NAME
    try:
        payload = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return None
    if not isinstance(payload, dict) or payload.get("schema") != "588080-dump-cache.v1":
        return None
    return payload


def load_latest_scraped_data(*, max_age_sec: float = DEFAULT_TTL_SEC) -> dict[str, Any] | None:
    """Return the latest dump payload if it is within TTL; otherwise None."""
    meta = latest_cache_meta()
    if not meta:
        return None
    saved_at = float(meta.get("saved_at") or 0)
    if max_age_sec is not None and saved_at and (time.time() - saved_at) > max_age_sec:
        return None
    path = meta.get("file_path")
    if not path:
        return None
    try:
        data = load_scraped_data(path)
    except ValueError:
        return None
    data["_cache"] = {
        "saved_at": saved_at,
        "age_sec": round(time.time() - saved_at, 1) if saved_at else None,
        "file_path": path,
        "summary": meta.get("summary") or {},
        "fresh": True,
    }
    return data


def latest_cache_status(*, max_age_sec: float = DEFAULT_TTL_SEC) -> dict[str, Any]:
    meta = latest_cache_meta()
    if not meta:
        return {"ok": False, "fresh": False, "reason": "no_cache"}
    saved_at = float(meta.get("saved_at") or 0)
    age = (time.time() - saved_at) if saved_at else None
    fresh = age is not None and age <= max_age_sec
    return {
        "ok": True,
        "fresh": fresh,
        "age_sec": round(age, 1) if age is not None else None,
        "max_age_sec": max_age_sec,
        "saved_at": meta.get("saved_at_iso"),
        "file_path": meta.get("file_path"),
        "summary": meta.get("summary") or {},
    }


def load_scraped_data(file_path: str | Path) -> dict[str, Any]:
    """Resolve backend-relative paths, rejecting traversal and escaping symlinks."""
    candidate = Path(file_path)
    if not candidate.is_absolute():
        candidate = BACKEND_DIR / candidate
    candidate = candidate.resolve()
    if not any(candidate.is_relative_to(root.resolve()) for root in (SCRAPED_DATA_DIR, STORAGE_DIR)):
        raise ValueError("抓取数据文件必须位于 collector/html 或 storage 目录")
    if candidate.suffix.lower() not in {".json", ".html", ".htm", ".txt"}:
        raise ValueError("抓取数据文件必须为 JSON、HTML 或 TXT 格式")
    if not candidate.is_file():
        raise ValueError("抓取数据文件不存在，请重新抓取后再分析")
    try:
        text = candidate.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ValueError("抓取数据文件无法读取，请重新抓取后再分析") from exc

    if candidate.suffix.lower() == ".json":
        try:
            payload = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError("抓取数据 JSON 无法解析，请重新抓取后再分析") from exc
        if not isinstance(payload, dict):
            raise ValueError("抓取数据 JSON 必须是对象")
        return payload

    # Present a standalone file as one module to retain existing formatting
    # and period detection without changing the handling of inline objects.
    return {
        "html": text,
        "site_title": "顶尖大师",
        "modules": [{"id": 1, "name": "抓取页面文本", "type": "content", "content": text}],
    }
