"""Service for per-user betting records CRUD, auto-settlement against official draws, and P&L statistics."""
from __future__ import annotations

import itertools
import logging
import re
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import collector_bridge as cb
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

NUM_TO_XIAO_2026: dict[str, str] = {
    num: xiao for xiao, nums in XIAO_NUMBERS_2026.items() for num in nums
}

DEFAULT_ODDS: dict[str, float] = {
    "特码": 47.0,
    "平码": 7.6,
    "平特肖": 2.05,
    "平特一肖": 2.05,
    "特肖": 11.5,
    "2连肖": 4.2,
    "2连肖（复试）": 4.2,
    "3连肖": 11.2,
    "3连肖（复试）": 11.2,
    "4连肖": 33.0,
    "4连肖（复试）": 33.0,
    "5连肖": 95.0,
    "5连肖（复试）": 95.0,
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


def default_odds_for(play_type: str, mode: str = "号码单式") -> float:
    if play_type in DEFAULT_ODDS:
        return DEFAULT_ODDS[play_type]
    if "不中" in play_type or mode == "不中码":
        return 2.12
    if "连肖" in play_type or mode == "连肖复试":
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
    return 47.0


def _norm_num(val: str) -> str:
    digits = "".join(ch for ch in str(val) if ch.isdigit())
    if not digits:
        return str(val).strip()
    n = int(digits)
    return f"{n:02d}"


def _lianxiao_k(play_type: str) -> int:
    for digit in ("2", "3", "4", "5"):
        if digit in play_type:
            return int(digit)
    for cn, k in (("二", 2), ("三", 3), ("四", 4), ("五", 5)):
        if cn in play_type:
            return k
    return 4


def _nbuzhong_k(play_type: str) -> int:
    for name, k in NBUZHONG_K.items():
        if name in play_type:
            return k
    m = re.search(r"(\d+)\s*不中", play_type)
    if m:
        return max(5, min(10, int(m.group(1))))
    return 5


def compute_notes_count(mode: str, play_type: str, numbers: list[str], xiaos: list[str]) -> int:
    if mode == "连肖复试" or "连肖" in play_type:
        k = _lianxiao_k(play_type)
        if len(xiaos) >= k:
            return len(list(itertools.combinations(xiaos, k)))
        return 1
    if mode == "不中码" or "不中" in play_type:
        k = _nbuzhong_k(play_type)
        if len(numbers) >= k:
            return len(list(itertools.combinations(numbers, k)))
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
    play_type = record.play_type or "特码"
    mode = record.mode or "号码单式"
    odds = record.odds if record.odds and record.odds > 0 else default_odds_for(play_type, mode)

    hit_items: list[str] = []
    hit_notes = 0

    if mode == "连肖复试" or "连肖" in play_type:
        k = _lianxiao_k(play_type)
        hit_items = [x for x in rec_xiaos if x in draw_xiaos]
        if len(rec_xiaos) >= k:
            for combo in itertools.combinations(rec_xiaos, k):
                if all(x in draw_xiaos for x in combo):
                    hit_notes += 1
        elif rec_xiaos and all(x in draw_xiaos for x in rec_xiaos):
            hit_notes = 1
    elif mode == "不中码" or "不中" in play_type:
        k = _nbuzhong_k(play_type)
        # In N不中, hit_items records which selected numbers accidentally appeared in the draw
        hit_items = [n for n in rec_nums if n in all_draw_nums]
        if len(rec_nums) >= k:
            for combo in itertools.combinations(rec_nums, k):
                if all(n not in all_draw_nums for n in combo):
                    hit_notes += 1
        elif rec_nums and all(n not in all_draw_nums for n in rec_nums):
            hit_notes = 1
    elif "平特" in play_type and rec_xiaos:
        hit_items = [x for x in rec_xiaos if x in draw_xiaos]
        hit_notes = len(hit_items)
    elif "特肖" in play_type and rec_xiaos:
        hit_items = [x for x in rec_xiaos if x == tema_xiao]
        hit_notes = len(hit_items)
    elif "平码" in play_type or "平特" in play_type:
        hit_items = [n for n in rec_nums if n in all_draw_nums]
        hit_notes = len(hit_items)
    else:
        # Default 特码
        hit_items = [n for n in rec_nums if n == tema]
        hit_notes = len(hit_items)

    new_status = "won" if hit_notes > 0 else "lost"
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
        record.created_at.strftime("%Y-%m-%d %H:%M")
        if record.created_at
        else datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")
    )
    draw_summary = None
    if draw:
        draw_summary = {
            "lottery": draw.get("lottery"),
            "period": draw.get("period"),
            "draw_date": draw.get("draw_date"),
            "opened_at": draw.get("opened_at"),
            "balls": draw.get("balls") or [],
            "tema": draw.get("tema"),
        }
    return {
        "id": record.id,
        "lottery": record.lottery,
        "period": record.period,
        "mode": record.mode,
        "play_type": record.play_type,
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
        "raw_input": record.raw_input or "",
        "note": record.note,
        "source_badge": record.source_badge,
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
    win_rate = round((len(won_rows) / len(settled_rows)) * 100, 1) if settled_rows else 0.0
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

    # Group by play_type
    by_play: dict[str, dict[str, Any]] = {}
    for r in settled_rows:
        pt = r.play_type or "特码"
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
    for pt, entry in sorted(by_play.items(), key=lambda kv: kv[1]["net_profit"], reverse=True):
        cnt = entry["count"]
        wr = int(round((entry["won_count"] / cnt) * 100)) if cnt > 0 else 0
        play_breakdown.append(
            {
                "play_type": pt,
                "count": cnt,
                "won_count": entry["won_count"],
                "win_rate": wr,
                "net_profit": entry["net_profit"],
                "stake": entry["stake"],
            }
        )

    return {
        "total_records": len(rows),
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
    }


def create_user_record(
    db: Session,
    user_id: str,
    payload: dict[str, Any],
) -> dict[str, Any]:
    lottery = str(payload.get("lottery") or "macau").strip()
    period = str(payload.get("period") or "").strip()
    mode = str(payload.get("mode") or "号码单式").strip()
    play_type = str(payload.get("play_type") or "特码").strip()
    numbers = [_norm_num(n) for n in (payload.get("numbers") or []) if str(n).strip()]
    xiaos = [str(x).strip() for x in (payload.get("xiaos") or []) if str(x).strip()]
    stake_per_note = max(1, int(payload.get("stake_per_note") or 10))
    multiplier = max(1, int(payload.get("multiplier") or 1))
    notes_count = int(payload.get("notes_count") or compute_notes_count(mode, play_type, numbers, xiaos))
    notes_count = max(1, notes_count)
    total_amount = int(payload.get("total_amount") or (notes_count * stake_per_note * multiplier))
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
        raw_input=str(payload.get("raw_input") or ""),
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
    if "numbers" in payload and payload["numbers"] is not None:
        rec.numbers = [_norm_num(n) for n in payload["numbers"] if str(n).strip()]
    if "xiaos" in payload and payload["xiaos"] is not None:
        rec.xiaos = [str(x).strip() for x in payload["xiaos"] if str(x).strip()]
    if "stake_per_note" in payload and payload["stake_per_note"] is not None:
        rec.stake_per_note = max(1, int(payload["stake_per_note"]))
    if "multiplier" in payload and payload["multiplier"] is not None:
        rec.multiplier = max(1, int(payload["multiplier"]))
    if "odds" in payload and payload["odds"] is not None:
        rec.odds = float(payload["odds"])
    else:
        rec.odds = default_odds_for(rec.play_type, rec.mode)

    rec.notes_count = int(
        payload.get("notes_count")
        or compute_notes_count(rec.mode, rec.play_type, list(rec.numbers or []), list(rec.xiaos or []))
    )
    rec.notes_count = max(1, rec.notes_count)
    rec.total_amount = int(
        payload.get("total_amount") or (rec.notes_count * rec.stake_per_note * rec.multiplier)
    )
    if "raw_input" in payload:
        rec.raw_input = str(payload.get("raw_input") or "")
    if "note" in payload:
        rec.note = str(payload["note"]).strip() if payload.get("note") else None
    if "source_badge" in payload:
        rec.source_badge = str(payload["source_badge"]).strip() if payload.get("source_badge") else None

    # Re-evaluate against draw or reset to pending
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
