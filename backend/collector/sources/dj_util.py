from __future__ import annotations

import html
import json
import os
import re
from dataclasses import dataclass

from common.parse_pred import parse_claimed
from common.sites.dingjian import STATIC_API_HOSTS, load_cached_api_hosts, origin

XIAO = "鼠牛虎兔龙蛇马羊猴鸡狗猪"
ANY_PERIOD_RE = re.compile(r"^\s*第?\s*(\d{1,7})\s*期")
HOSTS = list(STATIC_API_HOSTS)


def api_hosts() -> list[str]:
    """Use the catalog watcher's validated routes before bundled fallbacks."""
    configured = re.split(r"[,;\s]+", os.getenv("PRED_DINGJIAN_HOSTS", "").strip())
    values = [*configured, *load_cached_api_hosts(), *HOSTS]
    result: list[str] = []
    for value in values:
        host = origin(str(value))
        if host and host not in result:
            result.append(host)
    return result


def urls_for(path: str) -> list[str]:
    suffix = "/" + path.lstrip("/")
    return [host + suffix for host in api_hosts()]


def html_to_lines(raw: str) -> list[str]:
    text = raw
    if raw.strip().startswith("{"):
        try:
            data = json.loads(raw)
            text = (data.get("data") or {}).get("content") or raw
        except Exception:
            text = raw
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</(?:p|div|tr|li|h[1-6])>", "\n", text)
    text = re.sub(r"(?i)<[^>]+>", "", text)
    text = html.unescape(text).replace("\xa0", " ")
    return [ln.strip() for ln in text.splitlines() if ln.strip()]


def period_blocks(raw: str, header_re: re.Pattern[str]) -> list[tuple[re.Match[str], list[str]]]:
    """Return matching headers with body lines up to the next period header."""
    lines = html_to_lines(raw)
    found: list[tuple[re.Match[str], list[str]]] = []
    for start, line in enumerate(lines):
        match = header_re.search(line)
        if match is None:
            continue
        end = next(
            (i for i in range(start + 1, len(lines)) if ANY_PERIOD_RE.match(lines[i])),
            len(lines),
        )
        found.append((match, lines[start:end]))
    return found


def claimed_from(text: str) -> dict[str, str | None]:
    match = re.search(
        r"(?:开奖?|開獎?)\s*[:：]?\s*([^\n]*?(?:准|準|中|错|錯|挂|掛|未中|没中))(?=\s|$)",
        text,
    )
    if not match:
        match = re.search(r"(?:开奖?|開獎?|开)\s*[:：]?\s*([^\n]{1,30})", text)
    return parse_claimed(match.group(1) if match else "")


def xiao_atoms(values: list[str], evidence: str) -> list[dict[str, str]]:
    return [{"kind": "xiao", "value": value, "text": evidence} for value in values]


def num_atoms(values: list[str], evidence: str) -> list[dict[str, str]]:
    return [{"kind": "num", "value": f"{int(value):02d}", "text": evidence} for value in values]


def isolate_title(raw: str, title: str, extra_ok: tuple[str, ...] = ()) -> str:
    rows = []
    for line in html_to_lines(raw):
        if title not in line and not any(x in line for x in extra_ok):
            continue
        if not re.search(r"\d+\s*期", line):
            continue
        rows.append(line)
    return "\n".join(rows)


def atoms_xiao(text: str) -> list[dict]:
    out, seen = [], set()
    for ch in text:
        if ch in XIAO and ch not in seen:
            seen.add(ch)
            out.append({"kind": "xiao", "value": ch, "text": text})
    return out


def atoms_num(text: str) -> list[dict]:
    out, seen = [], set()
    for m in re.finditer(r"\d{1,2}", text):
        n = int(m.group())
        if 1 <= n <= 49:
            v = f"{n:02d}"
            if v not in seen:
                seen.add(v)
                out.append({"kind": "num", "value": v, "text": text})
    return out


def claimed_of(text: str) -> dict:
    raw = text
    m = re.search(r"开奖?[:：]?\s*([^\n]{0,20})", text)
    if m:
        raw = m.group(1)
    status = "unknown"
    if re.search(r"[？?发發猫]|00", raw) and "准" not in raw and "中" not in raw:
        status = "pending"
    elif "错" in raw:
        status = "miss"
    elif "准" in raw or "中" in raw:
        status = "hit"
    elif re.search(r"[？?发發猫]|00", text):
        status = "pending"
    return {"status": status, "xiao": None, "num": None, "raw": raw[:64]}


def twoface(text: str) -> list[dict]:
    out = []
    if "大单" in text:
        out.append({"kind": "size", "value": "大", "text": "大单"})
        out.append({"kind": "odd", "value": "单", "text": "大单"})
    if "小单" in text:
        out.append({"kind": "size", "value": "小", "text": "小单"})
        out.append({"kind": "odd", "value": "单", "text": "小单"})
    if "大双" in text:
        out.append({"kind": "size", "value": "大", "text": "大双"})
        out.append({"kind": "odd", "value": "双", "text": "大双"})
    if "小双" in text:
        out.append({"kind": "size", "value": "小", "text": "小双"})
        out.append({"kind": "odd", "value": "双", "text": "小双"})
    if "大数" in text or ( "【大" in text and "单" not in text and "双" not in text):
        if "大" in text:
            out.append({"kind": "size", "value": "大", "text": text})
    if "小数" in text:
        out.append({"kind": "size", "value": "小", "text": text})
    if "单数" in text:
        out.append({"kind": "odd", "value": "单", "text": text})
    if "双数" in text:
        out.append({"kind": "odd", "value": "双", "text": text})
    if "家禽" in text:
        out.append({"kind": "xiao", "value": "家", "text": "家禽"})
    if "野兽" in text:
        out.append({"kind": "xiao", "value": "野", "text": "野兽"})
    return out
