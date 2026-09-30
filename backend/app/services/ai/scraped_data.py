"""Persist complete scrape snapshots and load confined file references."""
from __future__ import annotations

import json
from pathlib import Path
from typing import TYPE_CHECKING, Any
from uuid import uuid4

from app.core.config import BACKEND_DIR

if TYPE_CHECKING:
    from collector.fetch_588080 import FetchResult

SCRAPED_DATA_DIR = BACKEND_DIR / "collector" / "html"
STORAGE_DIR = BACKEND_DIR / "storage"


def save_scraped_data(result: FetchResult) -> dict[str, str]:
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
    }
    data_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    return {
        "file_path": data_path.relative_to(BACKEND_DIR).as_posix(),
        "html_file_path": html_path.relative_to(BACKEND_DIR).as_posix(),
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
