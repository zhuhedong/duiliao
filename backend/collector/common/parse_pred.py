from __future__ import annotations

import html
import re
from typing import Iterable

from common.attr import pad_num
from common.xiao import XIAO_NORM, extract_xiao, normalize_xiao

PENDING_MARKS = ("猫00", "貓00", "？00", "?00", "發00", "发00", "准00", "00准")

# 248期:海哥平特【猪猪猪】开奖:猫00准
LINE_RE = re.compile(
    r"(?:第)?\s*(?P<period>\d{1,7})\s*期\s*[:：]?\s*"
    r"(?P<title>[^【\[\d开]{0,20})?"
    r"[【\[]?(?P<body>.+?)[】\]]?"
    r"(?:开奖|開獎|开[:：]|开)\s*[:：]?\s*(?P<claimed>.+)?$",
    re.DOTALL,
)

ALT_LINE_RE = re.compile(
    r"(?:第)?\s*(?P<period>\d{1,7})\s*期\s*[:：]?\s*(?P<rest>.+)$"
)

CLAIM_HIT_RE = re.compile(
    r"(?P<xiao>[鼠牛虎兔龙龍蛇马馬羊猴鸡雞狗猪豬])?\s*(?P<num>\d{1,2})\s*(?P<flag>准|準|中|对|對)?"
)
CLAIM_MISS_RE = re.compile(r"(错|錯|挂|掛|否|没中|未中)")


def strip_html(text: str) -> str:
    t = re.sub(r"(?is)<script[^>]*>.*?</script>", " ", text)
    t = re.sub(r"(?is)<style[^>]*>.*?</style>", " ", t)
    t = re.sub(r"(?i)<br\s*/?>", "\n", t)
    t = re.sub(r"(?i)</p>", "\n", t)
    t = re.sub(r"(?i)</div>", "\n", t)
    t = re.sub(r"(?i)</li>", "\n", t)
    t = re.sub(r"(?i)</?(?:span|b|strong|font|em|i|u|s|small|a)(?:\s+[^>]*)?>", "", t)
    t = re.sub(r"<[^>]+>", " ", t)
    t = html.unescape(t)
    t = t.replace("\xa0", " ").replace("\u3000", " ")
    t = re.sub(r"[ \t]+", " ", t)
    t = re.sub(r"\n{2,}", "\n", t)
    return t.strip()


def json_strings(obj: object) -> list[str]:
    out: list[str] = []
    if isinstance(obj, str):
        if len(obj) >= 8:
            out.append(obj)
    elif isinstance(obj, dict):
        for v in obj.values():
            out.extend(json_strings(v))
    elif isinstance(obj, list):
        for v in obj:
            out.extend(json_strings(v))
    return out


def likely_column_text(chunks: Iterable[str]) -> str:
    scored: list[tuple[int, str]] = []
    for c in chunks:
        t = strip_html(c) if "<" in c else c
        n = len(re.findall(r"\d{1,4}\s*期", t))
        if n:
            scored.append((n, t))
    if not scored:
        return "\n".join(strip_html(c) if "<" in c else c for c in chunks)
    scored.sort(key=lambda x: (-x[0], -len(x[1])))
    return scored[0][1]


def parse_claimed(raw: str | None) -> dict[str, str | None]:
    text = (raw or "").strip()
    compact = re.sub(r"\s+", "", text)
    if not compact:
        return {"status": "unknown", "xiao": None, "num": None, "raw": text or None}
    if (
        any(m in compact for m in PENDING_MARKS)
        or re.search(r"[猫貓發发？?]\s*(?:0{1,2}|88)", compact)
        or "發88" in compact
        or "发88" in compact
    ):
        return {"status": "pending", "xiao": None, "num": None, "raw": text}
    if CLAIM_MISS_RE.search(compact):
        return {"status": "miss", "xiao": None, "num": None, "raw": text}
    m = CLAIM_HIT_RE.search(compact)
    if m and (m.group("xiao") or m.group("flag")):
        xiao = normalize_xiao(m.group("xiao")) if m.group("xiao") else None
        try:
            num = pad_num(m.group("num")) if m.group("num") else None
        except ValueError:
            num = None
        if xiao or num:
            status = "hit" if m.group("flag") else "unknown"
            return {"status": status, "xiao": xiao, "num": num, "raw": text}
    return {"status": "unknown", "xiao": None, "num": None, "raw": text}


def parse_pred_body(body: str, prefer: str = "xiao") -> list[dict[str, str]]:
    """Atoms from a column body. prefer=xiao|num|wei|head."""
    body = body.strip()
    atoms: list[dict[str, str]] = []
    xiaos = extract_xiao(body)
    nums = [pad_num(n) for n in re.findall(r"(?<!\d)([0-4]?\d)(?!\d)", body) if 1 <= int(n) <= 49]
    weis = []
    for m in re.findall(r"([0-9])\s*尾", body):
        weis.append(m)
    heads = []
    for m in re.findall(r"([0-4])\s*头", body):
        heads.append(m)

    if prefer == "xiao" and xiaos:
        for x in xiaos:
            atoms.append({"kind": "xiao", "value": x, "text": body})
        return atoms
    if prefer == "wei" and weis:
        return [{"kind": "wei", "value": w, "text": body} for w in weis]
    if prefer == "head" and heads:
        return [{"kind": "head", "value": h, "text": body} for h in heads]
    if prefer == "num" and nums:
        return [{"kind": "num", "value": n, "text": body} for n in nums]

    if xiaos:
        atoms.extend({"kind": "xiao", "value": x, "text": body} for x in xiaos)
    if nums:
        atoms.extend({"kind": "num", "value": n, "text": body} for n in nums)
    if weis:
        atoms.extend({"kind": "wei", "value": w, "text": body} for w in weis)
    if heads:
        atoms.extend({"kind": "head", "value": h, "text": body} for h in heads)
    return atoms


def split_lines(text: str) -> list[str]:
    t = text.replace("\r\n", "\n").replace("\r", "\n")
    # some pages glue records: "247期:...248期:"
    t = re.sub(r"(?<![0-9第])(?=第?\d{1,7}\s*期)", "\n", t)
    return [ln.strip() for ln in t.split("\n") if ln.strip()]


def parse_column_text(
    text: str,
    *,
    title_hint: str | None = None,
    prefer: str = "xiao",
) -> list[dict]:
    items: list[dict] = []
    for line in split_lines(text):
        if title_hint and title_hint not in line and "期" not in line:
            continue
        m = LINE_RE.search(line) or ALT_LINE_RE.search(line)
        if not m:
            continue
        period_raw = m.group("period")
        if "body" in m.groupdict() and m.group("body"):
            body = m.group("body")
            claimed_raw = m.group("claimed")
        else:
            rest = m.groupdict().get("rest") or ""
            if "开奖" in rest or "開獎" in rest or "开:" in rest or "开：" in rest:
                body, claimed_raw = re.split(r"开奖|開獎|开[:：]|开", rest, maxsplit=1)
            else:
                body, claimed_raw = rest, ""
            if title_hint:
                body = body.replace(title_hint, "")
        body = re.sub(r"^[【\[\s]+|[】\]\s]+$", "", body.strip())
        claimed = parse_claimed(claimed_raw)
        preds = parse_pred_body(body, prefer=prefer)
        if not preds:
            continue
        items.append(
            {
                "period_raw": period_raw,
                "body": body,
                "preds": preds,
                "claimed": claimed,
                "raw_text": line,
            }
        )
    return items
