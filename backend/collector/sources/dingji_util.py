"""Utility helpers for parsing 77452.com (澳门顶级 / 顶级论坛) predictions."""

from __future__ import annotations

import html
import re
from pathlib import Path
from typing import Any

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.http import get
from common.period import normalize, year_of
from common.sites.dingji import api_hosts as dj_api_hosts, urls_for as dj_urls_for
from common.source_base import emit, fail, now_cn, parse_common_args

XIAO = "鼠牛虎兔龙蛇马羊猴鸡狗猪"
XIAO_SET = set(XIAO)
PERIOD_RE = re.compile(r"第?\s*(\d{1,7})\s*期")


def api_hosts() -> list[str]:
    return dj_api_hosts()


def urls_for(path: str) -> list[str]:
    return dj_urls_for(path)


def clean_html(text: str) -> str:
    cleaned = re.sub(r"(?i)<br\s*/?>", " ", text)
    cleaned = re.sub(r"(?i)</(?:p|div|tr|li|h[1-6]|table|td)>", " ", cleaned)
    cleaned = re.sub(r"<[^>]+>", " ", cleaned)
    return " ".join(html.unescape(cleaned).replace("\xa0", " ").split())


def atoms_xiao(text: str) -> list[dict[str, str]]:
    """Extract unique zodiac signs."""
    out, seen = [], set()
    for ch in text:
        if ch in XIAO_SET and ch not in seen:
            seen.add(ch)
            out.append({"kind": "xiao", "value": ch, "text": text})
    return out


def atoms_num(text: str) -> list[dict[str, str]]:
    """Extract numbers 01..49, formatted as 2-digit strings."""
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
    """Extract twoface attributes: size, odd, xiao (家/野/天/地),合单双, etc."""
    out = []
    clean = text

    # 大单, 大双, 小单, 小双
    if "大单" in clean:
        out.append({"kind": "size", "value": "大", "text": clean})
        out.append({"kind": "odd", "value": "单", "text": clean})
    if "大双" in clean:
        out.append({"kind": "size", "value": "大", "text": clean})
        out.append({"kind": "odd", "value": "双", "text": clean})
    if "小单" in clean:
        out.append({"kind": "size", "value": "小", "text": clean})
        out.append({"kind": "odd", "value": "单", "text": clean})
    if "小双" in clean:
        out.append({"kind": "size", "value": "小", "text": clean})
        out.append({"kind": "odd", "value": "双", "text": clean})

    if not out:
        # 单 / 双
        if "双" in clean and "单" not in clean:
            out.append({"kind": "odd", "value": "双", "text": clean})
        elif "单" in clean and "双" not in clean:
            out.append({"kind": "odd", "value": "单", "text": clean})

        # 大 / 小
        if "小" in clean and "大" not in clean:
            out.append({"kind": "size", "value": "小", "text": clean})
        elif "大" in clean and "小" not in clean:
            out.append({"kind": "size", "value": "大", "text": clean})

    # 家禽 / 野兽
    if "家禽" in clean or "家肖" in clean or "【家】" in clean:
        out.append({"kind": "xiao", "value": "家", "text": clean})
    elif "野兽" in clean or "野肖" in clean or "【野】" in clean:
        out.append({"kind": "xiao", "value": "野", "text": clean})

    # 天肖 / 地肖，以及判定规则已经接受的阴阳、男女、吉凶分组。
    group_labels = (
        ("天肖", "天"),
        ("地肖", "地"),
        ("阳肖", "阳"),
        ("阴肖", "阴"),
        ("男肖", "男"),
        ("女肖", "女"),
        ("吉肖", "吉"),
        ("凶肖", "凶"),
    )
    for label, value in group_labels:
        if label in clean:
            out.append({"kind": "xiao", "value": value, "text": clean})

    return out


def atoms_wei(text: str) -> list[dict[str, str]]:
    """Extract tails 0..9."""
    compact = re.sub(r"\s+", "", text)
    repeated = re.fullmatch(r"([0-9])\1{1,8}", compact)
    if repeated:
        return [{"kind": "wei", "value": repeated.group(1), "text": text}]
    out, seen = [], set()
    for m in re.finditer(r"\b([0-9])\b|([0-9])\s*[-－尾]", text):
        val = m.group(1) or m.group(2)
        if val not in seen:
            seen.add(val)
            out.append({"kind": "wei", "value": val, "text": text})
    return out


def atoms_head(text: str) -> list[dict[str, str]]:
    """Extract heads 0..4."""
    out, seen = [], set()
    for m in re.finditer(r"\b([0-4])\b|([0-4])\s*[-－头]", text):
        val = m.group(1) or m.group(2)
        if val not in seen:
            seen.add(val)
            out.append({"kind": "head", "value": val, "text": text})
    return out


def atoms_bose(text: str) -> list[dict[str, str]]:
    """Extract bose (红波/蓝波/绿波)."""
    out, seen = [], set()
    for color in ["红", "蓝", "绿"]:
        if color in text:
            name = f"{color}波"
            if name not in seen:
                seen.add(name)
                out.append({"kind": "bose", "value": name, "text": text})
    return out


def claimed_of(claim_raw: str, full_text: str, preds: list[dict[str, str]] | None = None) -> dict[str, Any]:
    """Determine claimed verification result."""
    combined = f"{claim_raw} {full_text}"
    status = "unknown"

    # Indicators of pending period
    if re.search(r"0000|\?00|？00|等待|更新中|下期|敬请期待", combined):
        status = "pending"
    elif "错" in combined or "挂" in combined or "未中" in combined:
        status = "miss"
    elif "准" in combined or "中" in combined:
        status = "hit"

    # Extract claimed xiao & num
    xiao_val = None
    num_val = None
    m_res = re.search(r"开\s*[:：]?\s*([^\s<准中错]+)", combined)
    if m_res:
        raw_res = m_res.group(1)
        for ch in raw_res:
            if ch in XIAO_SET:
                xiao_val = ch
                break
        m_num = re.search(r"\b(\d{1,2})\b", raw_res)
        if m_num:
            num_val = f"{int(m_num.group(1)):02d}"

    return {
        "status": status,
        "xiao": xiao_val,
        "num": num_val,
        "raw": claim_raw.strip()[:64],
    }


def parse_dj_amtz_rows(html_content: str) -> list[dict[str, Any]]:
    """Parse rows from /htm/tz/amtz/*.html pages."""
    # Find all <tr><td>...</td></tr>
    tr_matches = re.findall(r"<tr>\s*<td>(.*?)</td>\s*</tr>", html_content, flags=re.DOTALL)
    rows = []
    for tr in tr_matches:
        cleaned = clean_html(tr)
        p_m = PERIOD_RE.search(cleaned)
        if not p_m:
            continue
        period_raw = p_m.group(1)

        bracket_m = re.search(r"[【╠『\[（(]([^】╣』\]）)]+)[】╣』\]）)]", cleaned)
        pred_raw = bracket_m.group(1).strip() if bracket_m else ""

        claim_m = re.search(r"开\s*[:：]?\s*([^\s]+)", cleaned)
        claim_raw = claim_m.group(0) if claim_m else ""

        rows.append({
            "period_raw": period_raw,
            "pred_raw": pred_raw,
            "claim_raw": claim_raw,
            "full_text": cleaned,
        })
    return rows


def parse_dj_baota_rows(html_content: str, item_key: str) -> list[dict[str, Any]]:
    """Parse '宝塔镇河妖【澳门顶级】好料随你挑' section from /htm/."""
    # Find the stairs table
    m = re.search(r"宝塔镇河妖.*?<table[^>]*class=[\"']stairs[\"'][^>]*>(.*?)</table>", html_content, flags=re.DOTALL)
    if not m:
        return []
    table_content = m.group(1)

    # Extract period from e.g. 265期:今晚敢赌【蛇-02】明天开路虎
    p_m = re.search(r"(\d{1,7})\s*期", table_content)
    if not p_m:
        return []
    period_raw = p_m.group(1)

    # Extract target row based on item_key
    # item_key can be '1xiao', '1ma', '3xiao', '3ma', '5xiao', '5ma', '7xiao', '7ma'
    pattern_map = {
        "1xiao": r"一肖:</i>\s*<u>([^<]+)</u>",
        "1ma": r"①码:</i>\s*<u>([^<]+)</u>",
        "3xiao": r"三肖:</i>\s*<b>([^<]+)</b>",
        "3ma": r"③码:</i>\s*<b>([^<]+)</b>",
        "5xiao": r"五肖:</i>\s*<em>([^<]+)</em>",
        "5ma": r"⑤码:</i>\s*<em>([^<]+)</em>",
        "7xiao": r"七肖:</i>\s*([^\s<]+)",
        "7ma": r"⑦码:</i>\s*([^\s<]+)",
    }
    pat = pattern_map.get(item_key)
    if not pat:
        return []
    pred_m = re.search(pat, table_content)
    if not pred_m:
        return []
    pred_raw = pred_m.group(1).strip()

    return [{
        "period_raw": period_raw,
        "pred_raw": pred_raw,
        "claim_raw": "0000",
        "full_text": f"{period_raw}期 宝塔{item_key} 【{pred_raw}】",
    }]


def parse_dj_htm_section_rows(html_content: str, section_keyword: str) -> list[dict[str, Any]]:
    """Parse standard list sections like 怀中猫 (五不中), 阳光小逗比 (绝杀三肖) from /htm/."""
    idx = html_content.find(section_keyword)
    if idx == -1:
        return []
    next_idx = html_content.find("list-title", idx + len(section_keyword))
    snippet = html_content[idx:next_idx] if next_idx != -1 else html_content[idx : idx + 2500]
    # Remove HTML comments to ignore commented-out historical templates
    snippet = re.sub(r"<!--.*?-->", "", snippet, flags=re.DOTALL)

    # Look for <li...>{period}期...【{content}】...</li> or plain rows
    li_matches = re.findall(r"<li[^>]*>(.*?)</li>", snippet, flags=re.DOTALL)
    rows = []
    for li in li_matches:
        cleaned = clean_html(li)
        p_m = PERIOD_RE.search(cleaned)
        if not p_m:
            continue
        period_raw = p_m.group(1)

        bracket_m = re.search(r"[【╠『\[（(]([^】╣』\]）)]+)[】╣』\]）)]", cleaned)
        pred_raw = bracket_m.group(1).strip() if bracket_m else ""

        claim_m = re.search(r"开\s*[:：]?\s*([^\s]+)", cleaned)
        claim_raw = claim_m.group(0) if claim_m else ""

        rows.append({
            "period_raw": period_raw,
            "pred_raw": pred_raw,
            "claim_raw": claim_raw,
            "full_text": cleaned,
        })
    return rows


def fetch_dj_text(urls: list[str], fixture: str | Path | None = None) -> tuple[str, str, str]:
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
    raise RuntimeError(f"请求所有顶级论坛镜像节点失败: {last_err}")


def build_dj_pred(
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
    parsed_rows: list[dict[str, Any]] | None = None,
) -> PredV1:
    """Generic builder for dingji_77452 prediction sources."""
    if parsed_rows is None:
        raw_html, final_url, chash = fetch_dj_text(urls, fixture)
        parsed_rows = parse_dj_amtz_rows(raw_html)
    else:
        final_url = urls[0] if urls else "dynamic"
        chash = sha256_text(str(parsed_rows))

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
        elif kind == "bose":
            atom_dicts = atoms_bose(pred_text) or atoms_bose(full_text)
        else:
            atom_dicts = atoms_xiao(pred_text) + atoms_num(pred_text)

        c_info = claimed_of(row["claim_raw"], full_text, preds=atom_dicts)

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
        site_family="dingji_77452",
        lottery=lottery,
        play_type=play_type,
        hit_mode=hit_mode,
        fetched_at=now_cn(),
        final_url=final_url,
        content_hash=chash,
        items=items,
        error=None,
    )
