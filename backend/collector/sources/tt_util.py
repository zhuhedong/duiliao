"""Utility helpers for parsing 83191.com (通天) site family predictions."""

from __future__ import annotations

import html
import re
from pathlib import Path
from typing import Any

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.http import get
from common.period import normalize, year_of
from common.sites.tongtian import api_hosts as tt_api_hosts, urls_for as tt_urls_for
from common.source_base import emit, fail, now_cn, parse_common_args

XIAO = "鼠牛虎兔龙蛇马羊猴鸡狗猪"
XIAO_SET = set(XIAO)
PERIOD_RE = re.compile(r"第?\s*(\d{1,7})\s*期")
DOC_WRITE_RE = re.compile(r"""document\.write(?:ln)?\s*\(\s*([\"'])(.*?)\1\s*\)""", re.DOTALL)


def api_hosts() -> list[str]:
    return tt_api_hosts()


def urls_for(path: str) -> list[str]:
    return tt_urls_for(path)


def reconstruct_js_html(raw_js: str) -> str:
    """Extract strings passed to document.write / document.writeln and reconstruct HTML."""
    matches = DOC_WRITE_RE.findall(raw_js)
    if not matches:
        return raw_js
    lines = []
    for _, content in matches:
        unescaped = content.replace(r"\"", '"').replace(r"\'", "'")
        lines.append(unescaped)
    return "\n".join(lines)


def clean_html(text: str) -> str:
    cleaned = re.sub(r"(?i)<br\s*/?>", " ", text)
    cleaned = re.sub(r"(?i)</(?:p|div|tr|li|h[1-6])>", " ", cleaned)
    cleaned = re.sub(r"<[^>]+>", " ", cleaned)
    return html.unescape(cleaned).replace("\xa0", " ").strip()


def atoms_xiao(text: str) -> list[dict[str, str]]:
    """Extract unique zodiac signs, ignoring advertisement text."""
    # If the text is pure advertising (like 关注83191.com年赚百万), return empty
    if "关注" in text or "年赚" in text or "百万" in text:
        # Check if there is also zodiac brackets like ╠蛇龙马牛羊╣
        bracket_m = re.search(r"[【╠『\[（(]([^】╣』\]）)]+)[】╣』\]）)]", text)
        if bracket_m:
            text = bracket_m.group(1)
        else:
            return []
    out, seen = [], set()
    for ch in text:
        if ch in XIAO_SET and ch not in seen:
            seen.add(ch)
            out.append({"kind": "xiao", "value": ch, "text": text})
    return out


def atoms_num(text: str) -> list[dict[str, str]]:
    """Extract numbers 01..49, formatted as 2-digit strings."""
    if "关注" in text or "年赚" in text or "百万" in text:
        bracket_m = re.search(r"[【╠『\[（(]([^】╣』\]）)]+)[】╣』\]）)]", text)
        if bracket_m:
            text = bracket_m.group(1)
        else:
            return []
    out, seen = [], set()
    for m in re.finditer(r"\b\d{1,2}\b", text):
        val = int(m.group())
        if 1 <= val <= 49:
            num_str = f"{val:02d}"
            if num_str not in seen:
                seen.add(num_str)
                out.append({"kind": "num", "value": num_str, "text": text})
    return out


def atoms_twoface(text: str) -> list[dict[str, str]]:
    """Extract 大/小/单/双."""
    out = []
    # Strip ads if any
    clean = text
    bracket_m = re.search(r"[【╠『\[（(]([^】╣』\]）)]+)[】╣』\]）)]", text)
    if bracket_m:
        clean = bracket_m.group(1)
    if "大数" in clean or "【大" in clean or ("大" in clean and "小" not in clean and "关注" not in clean):
        out.append({"kind": "size", "value": "大", "text": clean})
    elif "小数" in clean or "【小" in clean or ("小" in clean and "大" not in clean and "关注" not in clean):
        out.append({"kind": "size", "value": "小", "text": clean})
    if "单数" in clean or "【单" in clean or ("单" in clean and "双" not in clean and "关注" not in clean):
        out.append({"kind": "odd", "value": "单", "text": clean})
    elif "双数" in clean or "【双" in clean or ("双" in clean and "单" not in clean and "关注" not in clean):
        out.append({"kind": "odd", "value": "双", "text": clean})
    return out


def atoms_wei(text: str) -> list[dict[str, str]]:
    """Extract wei numbers 0..9."""
    if "关注" in text or "年赚" in text or "百万" in text:
        bracket_m = re.search(r"[【╠『\[（(]([^】╣』\]）)]+)[】╣』\]）)]", text)
        if bracket_m:
            text = bracket_m.group(1)
        else:
            return []
    out, seen = [], set()
    for m in re.finditer(r"([0-9])\s*尾", text):
        w = m.group(1)
        if w not in seen:
            seen.add(w)
            out.append({"kind": "wei", "value": w, "text": text})
    if not out:
        for m in re.finditer(r"(?<!\d)([0-9])(?!\d)", text):
            w = m.group(1)
            if w not in seen:
                seen.add(w)
                out.append({"kind": "wei", "value": w, "text": text})
    return out


def atoms_head(text: str) -> list[dict[str, str]]:
    """Extract head numbers 0..4."""
    if "关注" in text or "年赚" in text or "百万" in text:
        bracket_m = re.search(r"[【╠『\[（(]([^】╣』\]）)]+)[】╣』\]）)]", text)
        if bracket_m:
            text = bracket_m.group(1)
        else:
            return []
    out, seen = [], set()
    for m in re.finditer(r"([0-4])\s*头", text):
        h = m.group(1)
        if h not in seen:
            seen.add(h)
            out.append({"kind": "head", "value": h, "text": text})
    return out


def claimed_of(
    claim_raw: str,
    full_text: str = "",
    preds: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    raw = (claim_raw or full_text).strip()
    status = "unknown"
    if any(q in raw for q in ["？", "?", "待开", "？？"]) or "00" in raw:
        status = "pending"
    elif any(k in raw for k in ["错", "挂", "未中"]):
        status = "miss"
    elif any(k in raw for k in ["准", "中", "赢"]):
        status = "hit"

    # Extract xiao and num from claim text if available, e.g. "牛30", "羊24", "羊36"
    xiao_val = None
    num_val = None
    for ch in raw:
        if ch in XIAO_SET:
            xiao_val = ch
            break
    num_m = re.search(r"(\d{1,2})", raw)
    if num_m and 1 <= int(num_m.group(1)) <= 49:
        num_val = f"{int(num_m.group(1)):02d}"

    # If status is still unknown, but we have a valid draw ball result (like 牛30),
    # check if xiao or num is in the prediction list:
    if status == "unknown" and (xiao_val or num_val) and preds:
        pred_vals = {p.get("value") for p in preds}
        if (xiao_val and xiao_val in pred_vals) or (num_val and num_val in pred_vals):
            status = "hit"
        else:
            status = "miss"

    return {
        "status": status,
        "xiao": xiao_val,
        "num": num_val,
        "raw": raw[:64],
    }


def parse_tt_rows(html_text: str) -> list[dict[str, Any]]:
    """Parse table rows or line blocks from reconstructed HTML into structured row items."""
    rows: list[dict[str, Any]] = []

    # 1. Look for <tr>...</tr>
    trs = re.findall(r"<tr[^>]*>(.*?)</tr>", html_text, re.DOTALL | re.I)
    for tr in trs:
        td_matches = re.findall(r"<td[^>]*>(.*?)</td>", tr, re.DOTALL | re.I)
        if not td_matches:
            continue
        td_texts = [clean_html(td) for td in td_matches]
        if not td_texts:
            continue

        # Case A: Multi-column [period, preds, ..., result]
        if len(td_texts) >= 2:
            p_match = PERIOD_RE.search(td_texts[0])
            if p_match:
                period_raw = p_match.group(1)
                pred_raw = td_texts[1]
                claim_raw = td_texts[-1] if len(td_texts) >= 3 else ""
                rows.append({
                    "period_raw": period_raw,
                    "pred_raw": pred_raw,
                    "claim_raw": claim_raw,
                    "full_text": f"{period_raw}期 {pred_raw} 开:{claim_raw}",
                })
                continue

        # Case B: Single column with full text
        line = " ".join(td_texts)
        p_match = PERIOD_RE.search(line)
        if p_match:
            period_raw = p_match.group(1)
            # Find claim part: e.g. 开: 羊36 准 or 开？00准
            claim_m = re.search(r"(?:开|開|结果)[:：]?\s*(.+)", line)
            claim_raw = claim_m.group(1) if claim_m else ""
            # Prediction text is between period and 开:
            pred_part = line
            if "期" in line:
                pred_part = line.split("期", 1)[1]
            if "开" in pred_part:
                pred_part = pred_part.split("开", 1)[0]
            rows.append({
                "period_raw": period_raw,
                "pred_raw": pred_part.strip(),
                "claim_raw": claim_raw.strip(),
                "full_text": line,
            })

    # 2. If no <tr> rows found, fall back to line by line
    if not rows:
        cleaned = clean_html(html_text)
        for line in cleaned.splitlines():
            line = line.strip()
            if not line:
                continue
            p_match = PERIOD_RE.search(line)
            if not p_match:
                continue
            period_raw = p_match.group(1)
            claim_m = re.search(r"(?:开|開|结果)[:：]?\s*(.+)", line)
            claim_raw = claim_m.group(1) if claim_m else ""
            pred_part = line.split("期", 1)[1] if "期" in line else line
            if "开" in pred_part:
                pred_part = pred_part.split("开", 1)[0]
            rows.append({
                "period_raw": period_raw,
                "pred_raw": pred_part.strip(),
                "claim_raw": claim_raw.strip(),
                "full_text": line,
            })

    return rows


def fetch_tt_text(urls: list[str], fixture: str | Path | None = None) -> tuple[str, str, str]:
    """Fetch raw text from urls or fixture. Returns (raw_text, final_url, content_hash)."""
    if fixture:
        path = Path(fixture)
        raw = path.read_text(encoding="utf-8")
        return raw, "file://" + path.as_posix(), sha256_text(raw)

    clean = [u.strip() for u in urls if str(u).strip() and not str(u).strip().startswith("#")]
    if not clean:
        raise RuntimeError("URL 列表为空")

    last_err: Exception | None = None
    for url in clean:
        try:
            r = get(url, timeout=12, retries=1)
            raw = r.text
            if raw and len(raw) > 20:
                return raw, str(r.url), sha256_text(raw)
        except Exception as e:
            last_err = e
    raise RuntimeError(f"请求所有通天镜像节点失败: {last_err}")


def build_tt_pred(
    *,
    source_id: str,
    source_name: str,
    play_type: str,
    hit_mode: str,
    urls: list[str],
    kind: str,
    lottery: str = "macau",
    period: str | None = None,
    fixture: str | None = None,
) -> PredV1:
    """Generic builder for tongtian_83191 prediction sources."""
    raw_js, final_url, chash = fetch_tt_text(urls, fixture)
    reconstructed_html = reconstruct_js_html(raw_js)
    parsed_rows = parse_tt_rows(reconstructed_html)

    if not parsed_rows:
        raise ValueError(f"{source_name} 未能解析出任何期数数据")

    year = year_of(period) if period else None
    items: list[PredItem] = []
    seen = set()

    for row in parsed_rows:
        try:
            per = normalize(lottery, row["period_raw"], year=year)
        except ValueError:
            continue

        if period and per != period and not str(period).endswith(str(row["period_raw"])):
            continue

        if per in seen:
            continue

        # Extract atoms based on kind
        pred_text = row["pred_raw"]
        full_text = row["full_text"]

        if kind == "xiao":
            atom_dicts = atoms_xiao(pred_text) or atoms_xiao(full_text)
        elif kind == "num":
            atom_dicts = atoms_num(pred_text) or atoms_num(full_text)
        elif kind == "twoface":
            atom_dicts = atoms_twoface(pred_text) or atoms_twoface(full_text)
        elif kind == "wei":
            atom_dicts = atoms_wei(pred_text) or atoms_wei(full_text)
        elif kind == "head":
            atom_dicts = atoms_head(pred_text) or atoms_head(full_text)
        else:
            atom_dicts = atoms_xiao(pred_text) + atoms_num(pred_text)

        c_info = claimed_of(row["claim_raw"], full_text, preds=atom_dicts)

        # If it's a pending period, atoms can be empty or present; for closed periods with no atoms, skip
        if not atom_dicts and c_info["status"] != "pending":
            continue

        seen.add(per)
        preds = [
            PredAtom(kind=a["kind"], value=str(a["value"]), text=a.get("text"))
            for a in atom_dicts
        ]

        items.append(
            PredItem(
                period_raw=str(row["period_raw"]),
                period=per,
                published_at=None,
                preds=preds,
                claimed=Claimed(
                    status=c_info["status"],
                    xiao=c_info["xiao"],
                    num=c_info["num"],
                    raw=c_info["raw"],
                ),
                raw_text=full_text[:1024],
            )
        )

    if not items:
        raise ValueError(f"{source_name} 解析条目为空")

    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=source_id,
        source_name=source_name,
        site_family="tongtian_83191",
        lottery=lottery,
        play_type=play_type,
        hit_mode=hit_mode,
        fetched_at=now_cn(),
        final_url=final_url,
        content_hash=chash,
        items=items,
        error=None,
    )
