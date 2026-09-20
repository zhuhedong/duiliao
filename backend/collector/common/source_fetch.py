"""Helpers for source scripts only. The HTTP service must not import this."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from common.hash import sha256_text
from common.http import get
from common.parse_pred import json_strings, likely_column_text, strip_html


@dataclass
class Page:
    url: str
    text: str
    content_hash: str


def load_page(*, urls: list[str], fixture: str | Path | None = None) -> Page:
    if fixture:
        path = Path(fixture)
        raw = path.read_text(encoding="utf-8")
        try:
            payload = json.loads(raw)
            text = likely_column_text(json_strings(payload))
        except json.JSONDecodeError:
            text = raw
        if not text.strip():
            text = raw
        return Page(url="file://" + path.as_posix(), text=text, content_hash=sha256_text(raw))

    clean = [u.strip() for u in urls if str(u).strip() and not str(u).strip().startswith("#")]
    if not clean:
        raise RuntimeError("脚本 URLS 为空。把要请求的地址写在本脚本的 URLS 里；服务不会代发任何请求。")
    last: Exception | None = None
    for url in clean:
        try:
            r = get(url)
            try:
                payload = r.json()
                text = likely_column_text(json_strings(payload))
            except Exception:
                text = strip_html(r.text)
            if not text.strip():
                text = r.text
            return Page(url=str(r.url), text=text, content_hash=sha256_text(r.text))
        except Exception as e:
            last = e
    raise RuntimeError(f"脚本请求失败: {last}")
