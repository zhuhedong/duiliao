"""Service for per-user betting records CRUD, smart text parsing (including zodiac->number expansion like '龙兔各数5'), auto-settlement against official draws, and P&L statistics."""
from __future__ import annotations

import itertools
import logging
import re
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import collector_bridge as cb
from app.db.session import SessionLocal
from app.models.betting_record import UserBettingRecord

logger = logging.getLogger("app.services.betting_records")

# 2026 Year of the Horse (丙午年) number -> zodiac mapping
XIAO_NUMBERS_2026: dict[str, list[str]] = {
    "马": ["01", "13", "25", "37", "49"],
    "蛇": ["02", "14", "26", "38"],
    "龙": ["03", "15", "27", "39"],
    "兔": ["04", "16", "28", "40"],
    "虎": ["05", "17", "29", "41"],
    "牛": ["06", "18", "30", "42"],
    "鼠": ["07", "19", "31", "43"],
    "猪": ["08", "20", "32", "44"],
    "狗": ["09", "21", "33", "45"],
    "鸡": ["10", "22", "34", "46"],
    "猴": ["11", "23", "35", "47"],
    "羊": ["12", "24", "36", "48"],
}

XIAO_ORDER = ("鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪")

NUM_TO_XIAO_2026: dict[str, str] = {
    num: xiao for xiao, nums in XIAO_NUMBERS_2026.items() for num in nums
}

RED_BOSE = {
    "01", "02", "07", "08", "12", "13", "18", "19", "23", "24",
    "29", "30", "34", "35", "40", "45", "46",
}
BLUE_BOSE = {
    "03", "04", "09", "10", "14", "15", "20", "25", "26", "31",
    "36", "37", "41", "42", "47", "48",
}

DEFAULT_ODDS: dict[str, float] = {
    "特码": 47.0,
    "正码": 7.0,
    "平码": 7.0,
    "平特肖": 2.05,
    "平特一肖": 2.05,
    "特肖": 11.5,
    "2连肖": 4.2,
    "2连肖（复试）": 4.2,
    "3连肖": 11.2,
    "3连肖（复试）": 11.2,
    "3 连": 11.2,
    "4连肖": 33.0,
    "4连肖（复试）": 33.0,
    "4 连": 33.0,
    "5连肖": 95.0,
    "5连肖（复试）": 95.0,
    "5 连": 95.0,
    "5 不中": 2.12,
    "6 不中": 2.58,
    "7 不中": 3.15,
    "8 不中": 3.85,
    "五不中": 2.12,
    "六不中": 2.58,
    "七不中": 3.15,
    "八不中": 3.85,
    "九不中": 4.70,
    "十不中": 5.80,
}

NBUZHONG_K: dict[str, int] = {
    "五不中": 5,
    "六不中": 6,
    "七不中": 7,
    "八不中": 8,
    "九不中": 9,
    "十不中": 10,
}


def bose_for_number(num_str: str) -> str:
    n = _norm_num(num_str)
    if n in RED_BOSE:
        return "红波"
    if n in BLUE_BOSE:
        return "蓝波"
    return "绿波"


def default_odds_for(play_type: str, mode: str = "号码单式") -> float:
    if play_type in DEFAULT_ODDS:
        return DEFAULT_ODDS[play_type]
    if "不中" in play_type or mode == "不中码":
        return 2.58
    if "连肖" in play_type or "连" in play_type or mode == "连肖复试":
        if "2" in play_type or "二" in play_type:
            return 4.2
        if "3" in play_type or "三" in play_type:
            return 11.2
        if "5" in play_type or "五" in play_type:
            return 95.0
        return 33.0
    if "平特" in play_type:
        return 2.05
    if "特肖" in play_type:
        return 11.5
    if "正码" in play_type or "平码" in play_type:
        return 7.0
    return 47.0


def _norm_num(val: str) -> str:
    digits = "".join(ch for ch in str(val) if ch.isdigit())
    if not digits:
        return str(val).strip()
    n = int(digits)
    return f"{n:02d}"


_CN_LINK_NUMS = {"二": "2", "三": "3", "四": "4", "五": "5"}


def _normalize_cn_link_nums(text: str) -> str:
    out = text
    for cn, digit in _CN_LINK_NUMS.items():
        out = out.replace(cn, digit)
    return out


def _lianxiao_ks(play_type: str, raw_input: str = "") -> list[int]:
    """Extract one or more 连肖 link sizes (e.g. '复试3，4连' -> [3, 4], '复试4连' -> [4])."""
    norm_raw = _normalize_cn_link_nums(raw_input or "")
    norm_play = _normalize_cn_link_nums(play_type or "")
    ks: list[int] = []

    # 1) Prefer explicit link patterns in raw_input first, then play_type
    for source_text in (norm_raw, norm_play):
        if not source_text:
            continue
        for m in re.finditer(
            r"(?:复[试式]\s*)?([2-5](?:\s*[,，、./\-~～\s连]+\s*[2-5])*|[2-5]{2,4})\s*连",
            source_text,
        ):
            for ch in m.group(1):
                if ch in ("2", "3", "4", "5"):
                    val = int(ch)
                    if val not in ks:
                        ks.append(val)
        if ks:
            return ks
        for m in re.finditer(
            r"复[试式]\s*([2-5](?:\s*[,，、./\-~～\s]+\s*[2-5])*|[2-5]{2,4})",
            source_text,
        ):
            for ch in m.group(1):
                if ch in ("2", "3", "4", "5"):
                    val = int(ch)
                    if val not in ks:
                        ks.append(val)
        if ks:
            return ks

    for ch in norm_play:
        if ch in ("2", "3", "4", "5"):
            val = int(ch)
            if val not in ks:
                ks.append(val)
    return ks if ks else [4]


def _lianxiao_k(play_type: str, raw_input: str = "") -> int:
    ks = _lianxiao_ks(play_type, raw_input)
    return ks[0] if ks else 4


def _nbuzhong_k(play_type: str, raw_input: str = "") -> int:
    for name, k in NBUZHONG_K.items():
        if name in play_type:
            return k
    m = re.search(r"(\d+)\s*不中", f"{play_type} {raw_input}")
    if m:
        return max(5, min(10, int(m.group(1))))
    return 6


_STAKE_PREFIX_RE = re.compile(
    r"(?:各数|个数|各号|各码|每码|每注|每组|各组|每个|一组|1组|一注|1注|一个|1个|各|×|\*)\s*(\d+)\s*(?:块|元|米|蚊)?"
)
_STAKE_SUFFIX_RE = re.compile(
    r"(\d+)\s*(?:块|元|米|蚊)?\s*(?:/|每|一|1)\s*(?:组|注|个|码)"
)
_LIANXIAO_EXPR_RE = re.compile(
    r"(?:复[试式]\s*)?[2-5二三四五](?:\s*[,，、./\-~～\s连]*\s*[2-5二三四五])*\s*连(?:复[试式])?"
)


def parse_smart_bet_input(
    raw_input: str,
    mode: str = "号码单式",
    play_type: str = "正码",
) -> dict[str, Any]:
    """Parse shorthand betting input.

    Supports:
    - ``18.42.39个数5`` -> numbers=['18','42','39'], stake=5
    - ``龙兔各数5`` / ``龙兔个数5`` / ``龙兔各5`` -> in 号码单式 mode, expands 龙(03,15,27,39)
      and 兔(04,16,28,40) into 8 numbers, each ¥5 (8 notes, total ¥40).
    - ``龙牛猴鸡兔复试4连个数10`` -> xiaos=['龙','牛','猴','鸡','兔'], mode='连肖复试', ks=[4], stake=10
    - ``鼠虎马猴鸡 给我打复试3，4连一组5块`` -> xiaos=['鼠','虎','马','猴','鸡'], mode='连肖复试',
      ks=[3, 4], notes=C(5,3)+C(5,4)=15, stake=5, total=75
    - ``02.04.06.08.10.12·6不中个数10`` -> numbers=['02',...,'12'], mode='不中码', k=6, stake=10
    """
    text = (raw_input or "").strip()
    stake_match = _STAKE_PREFIX_RE.search(text) or _STAKE_SUFFIX_RE.search(text)
    parsed_stake = int(stake_match.group(1)) if stake_match else None

    mult_match = re.search(r"(?:倍\s*(\d+)|(\d+)\s*倍)", text)
    parsed_mult = int(mult_match.group(1) or mult_match.group(2)) if mult_match else None

    # Strip stake/multiplier/play descriptors so their digits aren't parsed as lottery numbers
    cleaned = _STAKE_PREFIX_RE.sub("", text)
    cleaned = _STAKE_SUFFIX_RE.sub("", cleaned)
    cleaned = re.sub(r"[·\s]*\d+\s*不中.*$", "", cleaned)
    cleaned = _LIANXIAO_EXPR_RE.sub("", cleaned)
    cleaned = re.sub(r"复[试式]\s*[2-5二三四五,，、./\-~～\s]*", "", cleaned)
    cleaned = re.sub(r"(?:倍\s*\d+|\d+\s*倍)", "", cleaned)

    explicit_numbers: list[str] = []
    for m in re.finditer(r"(?<!\d)([0-4]?\d)(?!\d)", cleaned):
        n = int(m.group(1))
        if 1 <= n <= 49:
            fmt = f"{n:02d}"
            if fmt not in explicit_numbers:
                explicit_numbers.append(fmt)

    extracted_xiaos: list[str] = []
    for ch in cleaned:
        if ch in XIAO_ORDER and ch not in extracted_xiaos:
            extracted_xiaos.append(ch)

    is_fushi = (
        mode == "连肖复试"
        or "连肖" in play_type
        or bool(re.search(r"复[试式]", text))
        or bool(_LIANXIAO_EXPR_RE.search(text))
    )
    is_nbuzhong = (
        mode == "不中码"
        or "不中" in play_type
        or "不中" in text
    )
    has_per_number_keyword = bool(re.search(r"(?:各数|个数|各号|各码|每码)", text))
    is_pure_xiao_play = (
        play_type in ("特肖", "平特肖", "平特一肖", "合肖", "正肖", "杀肖")
        and not has_per_number_keyword
    )

    numbers = list(explicit_numbers)
    xiaos: list[str] = []
    detected_mode = mode
    fushi_links: list[int] = []

    if is_fushi:
        detected_mode = "连肖复试"
        xiaos = extracted_xiaos
        numbers = []
        fushi_links = _lianxiao_ks(play_type, text)
    elif is_nbuzhong:
        detected_mode = "不中码"
        for x in extracted_xiaos:
            for num in XIAO_NUMBERS_2026.get(x, []):
                if num not in numbers:
                    numbers.append(num)
        xiaos = []
    elif is_pure_xiao_play:
        xiaos = extracted_xiaos
    else:
        # 号码单式 or '各数5' / '个数5' / '各5': expand any zodiacs (e.g. 龙兔) into their constituent numbers!
        for x in extracted_xiaos:
            for num in XIAO_NUMBERS_2026.get(x, []):
                if num not in numbers:
                    numbers.append(num)
        xiaos = []

    return {
        "detected_mode": detected_mode,
        "fushi_links": fushi_links,
        "numbers": numbers,
        "xiaos": xiaos,
        "extracted_xiaos": extracted_xiaos,
        "stake_per_note": parsed_stake,
        "multiplier": parsed_mult,
    }


def compute_notes_count(mode: str, play_type: str, numbers: list[str], xiaos: list[str], raw_input: str = "") -> int:
    if (
        mode == "连肖复试"
        or "连肖" in play_type
        or "连" in play_type
        or bool(re.search(r"复[试式]", raw_input or ""))
        or bool(_LIANXIAO_EXPR_RE.search(raw_input or ""))
    ):
        ks = _lianxiao_ks(play_type, raw_input)
        total_combos = 0
        for k in ks:
            if len(xiaos) >= k:
                total_combos += len(list(itertools.combinations(xiaos, k)))
        return max(1, total_combos)
    if mode == "不中码" or "不中" in play_type:
        return 1
    if xiaos and not numbers:
        return len(xiaos)
    return max(1, len(numbers))


def evaluate_record_against_draw(
    record: UserBettingRecord,
    draw: dict[str, Any],
) -> bool:
    """Evaluate a betting record against an official draw dict. Returns True if changed."""
    balls = [_norm_num(b) for b in (draw.get("balls") or []) if b]
    tema = _norm_num(draw.get("tema") or "") if draw.get("tema") else ""
    all_draw_nums = set(balls + ([tema] if tema else []))
    if not all_draw_nums:
        return False

    draw_xiaos = {NUM_TO_XIAO_2026.get(n, "") for n in all_draw_nums if NUM_TO_XIAO_2026.get(n)}
    tema_xiao = NUM_TO_XIAO_2026.get(tema, "")

    rec_nums = [_norm_num(n) for n in (record.numbers or []) if n]
    rec_xiaos = [str(x).strip() for x in (record.xiaos or []) if str(x).strip()]
    play_type = record.play_type or "正码"
    mode = record.mode or "号码单式"
    odds = record.odds if record.odds and record.odds > 0 else default_odds_for(play_type, mode)

    hit_items: list[str] = []
    hit_notes = 0
    custom_payout: int | None = None

    if (
        mode == "连肖复试"
        or "连肖" in play_type
        or ("连" in play_type and rec_xiaos)
        or (rec_xiaos and bool(_LIANXIAO_EXPR_RE.search(record.raw_input or "")))
    ):
        ks = _lianxiao_ks(play_type, record.raw_input or "")
        hit_items = [x for x in rec_xiaos if x in draw_xiaos]
        payout_accum = 0.0
        for k in ks:
            k_hits = 0
            if len(rec_xiaos) >= k:
                for combo in itertools.combinations(rec_xiaos, k):
                    if all(x in draw_xiaos for x in combo):
                        k_hits += 1
            elif rec_xiaos and all(x in draw_xiaos for x in rec_xiaos):
                k_hits = 1
            if k_hits > 0:
                hit_notes += k_hits
                k_odds = (
                    record.odds
                    if (record.odds and record.odds > 0 and len(ks) == 1)
                    else default_odds_for(f"{k}连", "连肖复试")
                )
                payout_accum += k_hits * record.stake_per_note * record.multiplier * k_odds
        custom_payout = int(round(payout_accum)) if hit_notes > 0 else 0
    elif mode == "不中码" or "不中" in play_type:
        # In N不中, if NONE of the selected numbers appeared in the 7 drawn numbers, the whole group wins
        hit_items = [n for n in rec_nums if n in all_draw_nums]
        if rec_nums and len(hit_items) == 0:
            hit_notes = record.notes_count or 1
    elif "平特" in play_type and rec_xiaos and not rec_nums:
        hit_items = [x for x in rec_xiaos if x in draw_xiaos]
        hit_notes = len(hit_items)
    elif "特肖" in play_type and rec_xiaos and not rec_nums:
        hit_items = [x for x in rec_xiaos if x == tema_xiao]
        hit_notes = len(hit_items)
    elif "特码" in play_type:
        hit_items = [n for n in rec_nums if n == tema]
        hit_notes = len(hit_items)
    else:
        # 正码 / 平码 / 号码单式 (matches any of the 7 drawn balls or 6 flat balls)
        hit_items = [n for n in rec_nums if n in all_draw_nums]
        hit_notes = len(hit_items)

    new_status = "won" if hit_notes > 0 else "lost"
    if custom_payout is not None:
        payout = custom_payout
    else:
        payout = int(round(hit_notes * record.stake_per_note * record.multiplier * odds)) if hit_notes > 0 else 0
    net_profit = payout - record.total_amount

    changed = (
        record.status != new_status
        or record.hit_numbers != hit_items
        or record.hit_notes != hit_notes
        or record.payout != payout
        or record.net_profit != net_profit
    )
    if changed:
        record.status = new_status
        record.hit_numbers = hit_items
        record.hit_notes = hit_notes
        record.payout = payout
        record.net_profit = net_profit
        record.updated_at = datetime.now(timezone.utc)
    return changed


def settle_all_users_records(
    lottery: str | None = None,
    period: str | None = None,
) -> int:
    """Automatically settle all pending (or matching) betting records across all users when a draw is synced/judged."""
    try:
        with SessionLocal() as db:
            stmt = select(UserBettingRecord)
            if lottery:
                stmt = stmt.where(UserBettingRecord.lottery == lottery)
            if period:
                stmt = stmt.where(UserBettingRecord.period == str(period))
            else:
                stmt = stmt.where(UserBettingRecord.status == "pending")
            rows = list(db.scalars(stmt))
            if not rows:
                return 0
            pairs = {(r.lottery, r.period) for r in rows}
            draws_map = _fetch_draws_map(pairs)
            if not draws_map:
                return 0
            settled_count = 0
            for r in rows:
                draw = draws_map.get((r.lottery, r.period))
                if draw is not None and evaluate_record_against_draw(r, draw):
                    settled_count += 1
            if settled_count > 0:
                db.commit()
                logger.info(
                    "Auto-settled %d user betting record(s) for lottery=%s period=%s",
                    settled_count,
                    lottery,
                    period,
                )
            return settled_count
    except Exception:
        logger.warning("Auto-settle user betting records failed", exc_info=True)
        return 0


def _fetch_draws_map(pairs: set[tuple[str, str]]) -> dict[tuple[str, str], dict[str, Any]]:
    out: dict[tuple[str, str], dict[str, Any]] = {}
    for lottery, period in pairs:
        if not lottery or not period:
            continue
        try:
            res = cb.list_draws(lottery=lottery, limit=1, offset=0, period_from=period, period_to=period)
            items = res.get("items") or []
            if items and str(items[0].get("period")) == str(period):
                out[(lottery, str(period))] = items[0]
        except Exception:
            logger.debug("draw lookup skipped for %s/%s", lottery, period, exc_info=True)
    return out


def serialize_record(
    record: UserBettingRecord,
    draw: dict[str, Any] | None = None,
) -> dict[str, Any]:
    created_iso = record.created_at.isoformat() if record.created_at else None
    time_label = (
        record.created_at.strftime("%m-%d %H:%M")
        if record.created_at
        else datetime.now(timezone.utc).strftime("%m-%d %H:%M")
    )
    draw_summary = None
    draw_balls: list[str] = []
    draw_tema = ""
    draw_time = ""
    if draw:
        draw_balls = [_norm_num(b) for b in (draw.get("balls") or []) if b]
        draw_tema = _norm_num(draw.get("tema") or "") if draw.get("tema") else ""
        draw_time = str(draw.get("opened_at") or draw.get("draw_date") or "")
        draw_summary = {
            "lottery": draw.get("lottery"),
            "period": draw.get("period"),
            "draw_date": draw.get("draw_date"),
            "opened_at": draw.get("opened_at"),
            "balls": draw_balls,
            "tema": draw_tema,
        }

    fushi_link = None
    fushi_links: list[int] = []
    if (
        record.mode == "连肖复试"
        or "连肖" in (record.play_type or "")
        or "连" in (record.play_type or "")
        or (record.xiaos and bool(_LIANXIAO_EXPR_RE.search(record.raw_input or "")))
    ):
        fushi_links = _lianxiao_ks(record.play_type or "", record.raw_input or "")
        fushi_link = fushi_links[0] if fushi_links else 4

    win_pill_label = None
    if record.status == "won":
        if "特码" in (record.play_type or ""):
            win_pill_label = f"特码中 +¥{record.net_profit}"
        elif "不中" in (record.play_type or "") or record.mode == "不中码":
            win_pill_label = f"全不中 +¥{record.net_profit}"
        elif fushi_link is not None:
            win_pill_label = f"中 {record.hit_notes} 注 +¥{record.net_profit}"
        else:
            win_pill_label = f"中 {len(record.hit_numbers or [])} 码 +¥{record.net_profit}"

    return {
        "id": record.id,
        "lottery": record.lottery,
        "period": record.period,
        "mode": record.mode,
        "play_type": record.play_type,
        "fushi_link": fushi_link,
        "fushi_links": fushi_links,
        "time_label": time_label,
        "created_at": created_iso,
        "numbers": list(record.numbers or []),
        "xiaos": list(record.xiaos or []),
        "stake_per_note": record.stake_per_note,
        "multiplier": record.multiplier,
        "notes_count": record.notes_count,
        "total_amount": record.total_amount,
        "odds": record.odds,
        "status": record.status,
        "hit_numbers": list(record.hit_numbers or []),
        "hit_notes": record.hit_notes,
        "payout": record.payout,
        "net_profit": record.net_profit,
        "win_pill_label": win_pill_label,
        "raw_input": record.raw_input or "",
        "note": record.note,
        "source_badge": record.source_badge,
        "draw_numbers": draw_balls,
        "special_number": draw_tema,
        "draw_time": draw_time,
        "draw": draw_summary,
    }


def list_user_records(
    db: Session,
    user_id: str,
    lottery: str | None = None,
    status_filter: str | None = None,
    auto_settle: bool = True,
) -> dict[str, Any]:
    stmt = select(UserBettingRecord).where(UserBettingRecord.user_id == user_id)
    if lottery:
        stmt = stmt.where(UserBettingRecord.lottery == lottery)
    stmt = stmt.order_by(UserBettingRecord.period.desc(), UserBettingRecord.created_at.desc())
    rows = list(db.scalars(stmt))

    pairs = {(r.lottery, r.period) for r in rows}
    draws_map = _fetch_draws_map(pairs) if pairs else {}

    dirty = False
    if auto_settle and draws_map:
        for r in rows:
            draw = draws_map.get((r.lottery, r.period))
            if draw is not None and evaluate_record_against_draw(r, draw):
                dirty = True
        if dirty:
            db.commit()

    filtered = [
        r for r in rows if not status_filter or status_filter == "all" or r.status == status_filter
    ]
    items = [serialize_record(r, draws_map.get((r.lottery, r.period))) for r in filtered]
    stats = compute_stats(rows)
    return {
        "ok": True,
        "count": len(items),
        "items": items,
        "stats": stats,
    }


def compute_stats(rows: list[UserBettingRecord]) -> dict[str, Any]:
    pending_rows = [r for r in rows if r.status == "pending"]
    settled_rows = [r for r in rows if r.status in ("won", "lost")]
    won_rows = [r for r in rows if r.status == "won"]
    lost_rows = [r for r in rows if r.status == "lost"]

    pending_stake = sum(r.total_amount for r in pending_rows)
    pending_notes = sum(r.notes_count for r in pending_rows)
    total_stake = sum(r.total_amount for r in settled_rows)
    total_payout = sum(r.payout for r in settled_rows)
    net_profit = total_payout - total_stake
    total_notes = sum(r.notes_count for r in settled_rows)
    hit_notes = sum(
        r.hit_notes if r.hit_notes > 0 else (1 if r.status == "won" else 0)
        for r in settled_rows
    )
    win_rate = round((hit_notes / total_notes) * 100, 1) if total_notes > 0 else 0.0
    roi_pct = round((net_profit / total_stake) * 100, 1) if total_stake > 0 else 0.0

    # Group by period for last 7 periods chart
    by_period: dict[str, int] = {}
    for r in settled_rows:
        by_period[r.period] = by_period.get(r.period, 0) + r.net_profit
    sorted_periods = sorted(by_period.keys())[-7:]
    period_bars = [
        {"period": p, "net_profit": by_period[p]}
        for p in sorted_periods
    ]

    # Group by play_type (include all rows for investment share, settled for profit)
    by_play: dict[str, dict[str, Any]] = {}
    all_stake = sum(r.total_amount for r in rows) or 1
    for r in rows:
        pt = r.play_type or "正码"
        entry = by_play.setdefault(
            pt,
            {"play_type": pt, "count": 0, "won_count": 0, "net_profit": 0, "stake": 0},
        )
        entry["count"] += 1
        if r.status == "won":
            entry["won_count"] += 1
        entry["net_profit"] += r.net_profit
        entry["stake"] += r.total_amount

    play_breakdown = []
    for pt, entry in sorted(by_play.items(), key=lambda kv: kv[1]["stake"], reverse=True):
        cnt = entry["count"]
        wr = int(round((entry["won_count"] / cnt) * 100)) if cnt > 0 else 0
        share = round((entry["stake"] / all_stake) * 100, 1)
        play_breakdown.append(
            {
                "play_type": pt,
                "count": cnt,
                "won_count": entry["won_count"],
                "win_rate": wr,
                "net_profit": entry["net_profit"],
                "stake": entry["stake"],
                "share_pct": share,
            }
        )

    # Frequent hit numbers across settled won records
    hit_counts: dict[str, dict[str, int]] = {}
    for r in won_rows:
        per_hit_profit = int(round(r.payout / max(1, len(r.hit_numbers or [1]))))
        for hn in (r.hit_numbers or []):
            if hn in NUM_TO_XIAO_2026:
                info = hit_counts.setdefault(hn, {"count": 0, "profit": 0})
                info["count"] += 1
                info["profit"] += per_hit_profit

    frequent_hits = [
        {
            "number": num,
            "bose": bose_for_number(num),
            "count": info["count"],
            "profit": info["profit"],
        }
        for num, info in sorted(
            hit_counts.items(),
            key=lambda kv: (kv[1]["count"], kv[1]["profit"]),
            reverse=True,
        )[:5]
    ]

    return {
        "total_records": len(rows),
        "settled_orders": len(settled_rows),
        "pending_count": len(pending_rows),
        "won_count": len(won_rows),
        "lost_count": len(lost_rows),
        "pending_stake": pending_stake,
        "pending_notes": pending_notes,
        "total_stake": total_stake,
        "total_payout": total_payout,
        "net_profit": net_profit,
        "total_notes": total_notes,
        "hit_notes": hit_notes,
        "win_rate": win_rate,
        "roi_pct": roi_pct,
        "period_bars": period_bars,
        "play_breakdown": play_breakdown,
        "frequent_hits": frequent_hits,
    }


def create_user_record(
    db: Session,
    user_id: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    lottery = str(payload.get("lottery") or "macau").strip()
    period = str(payload.get("period") or "").strip()
    mode = str(payload.get("mode") or "号码单式").strip()
    play_type = str(payload.get("play_type") or "正码").strip()
    raw_input = str(payload.get("raw_input") or "").strip()

    parsed = parse_smart_bet_input(raw_input, mode=mode, play_type=play_type) if raw_input else {}
    if parsed.get("detected_mode") in ("连肖复试", "不中码"):
        mode = str(parsed["detected_mode"])
        if mode == "连肖复试" and play_type in ("正码", "特码", "连肖"):
            ks = parsed.get("fushi_links") or _lianxiao_ks(play_type, raw_input)
            play_type = f"连肖 {','.join(str(k) for k in ks)}连" if len(ks) > 1 else "连肖"
        elif mode == "不中码" and play_type in ("正码", "特码"):
            play_type = f"{_nbuzhong_k(play_type, raw_input)} 不中"

    raw_numbers = payload.get("numbers")
    if raw_numbers:
        numbers = [_norm_num(n) for n in raw_numbers if str(n).strip()]
    else:
        numbers = list(parsed.get("numbers") or [])

    raw_xiaos = payload.get("xiaos")
    if raw_xiaos:
        xiaos = [str(x).strip() for x in raw_xiaos if str(x).strip()]
    else:
        xiaos = list(parsed.get("xiaos") or [])

    # If in 号码单式 mode (or 正码/特码) and xiaos were passed without numbers, expand xiaos to numbers!
    if mode != "连肖复试" and (mode == "号码单式" or play_type in ("正码", "特码")) and xiaos and not numbers:
        for x in xiaos:
            for num in XIAO_NUMBERS_2026.get(x, []):
                if num not in numbers:
                    numbers.append(num)
        xiaos = []

    stake_per_note = max(
        1,
        int(payload.get("stake_per_note") or parsed.get("stake_per_note") or 5),
    )
    multiplier = max(
        1,
        int(payload.get("multiplier") or parsed.get("multiplier") or 1),
    )
    notes_count = compute_notes_count(mode, play_type, numbers, xiaos, raw_input)
    notes_count = max(1, notes_count)
    total_amount = notes_count * stake_per_note * multiplier
    odds = float(payload.get("odds") or default_odds_for(play_type, mode))

    rec = UserBettingRecord(
        user_id=user_id,
        lottery=lottery,
        period=period,
        mode=mode,
        play_type=play_type,
        numbers=numbers,
        xiaos=xiaos,
        stake_per_note=stake_per_note,
        multiplier=multiplier,
        notes_count=notes_count,
        total_amount=total_amount,
        odds=odds,
        status="pending",
        hit_numbers=[],
        hit_notes=0,
        payout=0,
        net_profit=0,
        raw_input=raw_input,
        note=(str(payload.get("note")).strip() if payload.get("note") else None),
        source_badge=(str(payload.get("source_badge")).strip() if payload.get("source_badge") else None),
    )

    draws_map = _fetch_draws_map({(lottery, period)})
    draw = draws_map.get((lottery, period))
    if draw is not None:
        evaluate_record_against_draw(rec, draw)

    db.add(rec)
    db.commit()
    db.refresh(rec)
    return serialize_record(rec, draw)


def update_user_record(
    db: Session,
    user_id: str,
    record_id: str,
    payload: dict[str, Any],
) -> dict[str, Any] | None:
    rec = db.get(UserBettingRecord, record_id)
    if rec is None or rec.user_id != user_id:
        return None

    if "lottery" in payload and payload["lottery"]:
        rec.lottery = str(payload["lottery"]).strip()
    if "period" in payload and payload["period"]:
        rec.period = str(payload["period"]).strip()
    if "mode" in payload and payload["mode"]:
        rec.mode = str(payload["mode"]).strip()
    if "play_type" in payload and payload["play_type"]:
        rec.play_type = str(payload["play_type"]).strip()
    if "raw_input" in payload and payload["raw_input"] is not None:
        rec.raw_input = str(payload["raw_input"]).strip()

    parsed = (
        parse_smart_bet_input(rec.raw_input or "", mode=rec.mode, play_type=rec.play_type)
        if rec.raw_input
        else {}
    )
    if parsed.get("detected_mode") in ("连肖复试", "不中码") and "mode" not in payload:
        rec.mode = str(parsed["detected_mode"])

    if "numbers" in payload and payload["numbers"] is not None:
        rec.numbers = [_norm_num(n) for n in payload["numbers"] if str(n).strip()]
    elif parsed.get("numbers"):
        rec.numbers = list(parsed["numbers"])

    if "xiaos" in payload and payload["xiaos"] is not None:
        rec.xiaos = [str(x).strip() for x in payload["xiaos"] if str(x).strip()]
    elif "xiaos" in parsed:
        rec.xiaos = list(parsed["xiaos"])

    if rec.mode != "连肖复试" and (rec.mode == "号码单式" or rec.play_type in ("正码", "特码")) and rec.xiaos and not rec.numbers:
        expanded: list[str] = []
        for x in rec.xiaos:
            for num in XIAO_NUMBERS_2026.get(x, []):
                if num not in expanded:
                    expanded.append(num)
        rec.numbers = expanded
        rec.xiaos = []

    if "stake_per_note" in payload and payload["stake_per_note"] is not None:
        rec.stake_per_note = max(1, int(payload["stake_per_note"]))
    elif parsed.get("stake_per_note"):
        rec.stake_per_note = max(1, int(parsed["stake_per_note"]))

    if "multiplier" in payload and payload["multiplier"] is not None:
        rec.multiplier = max(1, int(payload["multiplier"]))
    elif parsed.get("multiplier"):
        rec.multiplier = max(1, int(parsed["multiplier"]))

    if "odds" in payload and payload["odds"] is not None:
        rec.odds = float(payload["odds"])
    else:
        rec.odds = default_odds_for(rec.play_type, rec.mode)

    rec.notes_count = compute_notes_count(
        rec.mode,
        rec.play_type,
        list(rec.numbers or []),
        list(rec.xiaos or []),
        rec.raw_input or "",
    )
    rec.notes_count = max(1, rec.notes_count)
    rec.total_amount = rec.notes_count * rec.stake_per_note * rec.multiplier

    if "note" in payload:
        rec.note = str(payload["note"]).strip() if payload.get("note") else None
    if "source_badge" in payload:
        rec.source_badge = str(payload["source_badge"]).strip() if payload.get("source_badge") else None

    draws_map = _fetch_draws_map({(rec.lottery, rec.period)})
    draw = draws_map.get((rec.lottery, rec.period))
    if draw is not None:
        evaluate_record_against_draw(rec, draw)
    else:
        rec.status = "pending"
        rec.hit_numbers = []
        rec.hit_notes = 0
        rec.payout = 0
        rec.net_profit = 0

    rec.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(rec)
    return serialize_record(rec, draw)


def delete_user_record(db: Session, user_id: str, record_id: str) -> bool:
    rec = db.get(UserBettingRecord, record_id)
    if rec is None or rec.user_id != user_id:
        return False
    db.delete(rec)
    db.commit()
    return True
