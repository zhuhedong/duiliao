"""Zodiac streak data extraction & pre-computation for multi-period analysis.

Queries N periods of draw results, extracts per-ball zodiac (生肖),
groups by period, and computes cross-period streak statistics (连肖走势).
"""
from __future__ import annotations

import logging
import sys
from datetime import date
from pathlib import Path
from typing import Any

COLLECTOR_DIR = Path(__file__).resolve().parent.parent.parent.parent / "collector"
if str(COLLECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(COLLECTOR_DIR))

log = logging.getLogger("duiliao.ai.zodiac_streak")

ALL_XIAO = ("鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪")
POSITIONS = ["正1", "正2", "正3", "正4", "正5", "正6", "特码"]
# 三连 / 四连 / 五连 are exact lengths. 6 and above collapse into N连,
# and the concrete length (7连, 10连, …) stays on the record itself.
_EXACT_KINDS = {2: "二连", 3: "三连", 4: "四连", 5: "五连"}
_PRIMARY_KINDS = ("三连", "四连", "五连", "N连")


def streak_kind(length: int) -> str:
    """Map a consecutive-period count to 二连/三连/四连/五连/N连."""
    return _EXACT_KINDS.get(length, "N连")


def _bucket_by_kind(items: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    """Group streak records into 三连/四连/五连/N连.

    二连 is included only when the caller asked for streaks shorter than 3.
    Empty primary buckets are kept so the report can say a class has no hit.
    """
    keys = list(_PRIMARY_KINDS)
    if any(int(item.get("length") or 0) == 2 for item in items):
        keys = ["二连", *keys]
    grouped: dict[str, list[dict[str, Any]]] = {key: [] for key in keys}
    for item in items:
        grouped.setdefault(streak_kind(int(item["length"])), []).append(item)
    return grouped


# ---------------------------------------------------------------------------
# 1. Data Extraction
# ---------------------------------------------------------------------------

def get_zodiac_by_periods(
    lottery: str = "macau",
    num_periods: int = 30,
) -> list[dict[str, Any]]:
    """Query the last *num_periods* draws and compute per-ball zodiac.

    Returns a list ordered from oldest to newest:
    [
      {"period": "260", "date": "2026-09-20",
       "balls": ["12","05","33","18","49","27","08"],
       "xiaos": ["鼠","虎","龙","马","猴","狗","鸡"],
       "tema_xiao": "鸡",
       "unique_xiaos": ["鼠","虎","龙","马","猴","狗","鸡"]},
      ...
    ]
    """
    from app import collector_bridge as cb

    cb.bootstrap()

    from sqlalchemy import select
    from db import session_scope
    from schema import Draw
    from common.xiao import num_to_xiao

    num_periods = max(1, min(num_periods, 500))

    with session_scope(guard=False) as s:
        stmt = (
            select(Draw)
            .where(Draw.lottery == lottery)
            .order_by(Draw.period.desc())
            .limit(num_periods)
        )
        rows = list(s.scalars(stmt))

    # Reverse to oldest-first for streak calculation
    rows.reverse()

    results: list[dict[str, Any]] = []
    for d in rows:
        dd: date | None = d.draw_date if isinstance(getattr(d, "draw_date", None), date) else None
        if not dd and getattr(d, "opened_at", None):
            dd = d.opened_at.date()
        if not dd:
            try:
                yr = int(d.period[:4]) if len(d.period) >= 4 else 2026
                dd = date(yr, 6, 1)
            except Exception:
                dd = date.today()

        balls = [d.z1, d.z2, d.z3, d.z4, d.z5, d.z6, d.tema]
        xiaos = [num_to_xiao(b, dd) for b in balls]
        unique_xiaos = list(dict.fromkeys(xiaos))  # preserve order, deduplicate

        results.append({
            "period": d.period,
            "date": dd.isoformat() if dd else None,
            "balls": balls,
            "xiaos": xiaos,
            "tema_xiao": xiaos[-1],
            "unique_xiaos": unique_xiaos,
        })

    return results


# ---------------------------------------------------------------------------
# 2. Streak Computation
# ---------------------------------------------------------------------------

def compute_streaks(
    period_data: list[dict[str, Any]],
    min_streak: int = 3,
) -> dict[str, Any]:
    """Compute cross-period zodiac streak statistics.

    A zodiac is "present" in a period if any of the 7 balls belongs to it.
    A "streak" means it appeared in N consecutive periods.

    Lengths are also classified for the AI report:
    - 三连 / 四连 / 五连: that exact run length
    - N连: a run of 6 or more (the record keeps the real length)
    - 复式: two or more zodiacs present together across the same run

    Returns:
    {
      "total_periods": 30,
      "period_range": {"from": "260", "to": "289"},
      "xiao_presence": {
        "鼠": [True, False, True, True, True, ...],  # per-period presence
        ...
      },
      "all_streaks": [
        {"xiao": "马", "start_period": "261", "end_period": "265",
         "length": 5, "kind": "五连", "is_active": False},
        ...
      ],
      "active_streaks": [...],
      "compound_streaks": [
        {"xiaos": ["马","虎"], "start_period": "261", "end_period": "265",
         "length": 5, "kind": "五连", "is_active": False},
        ...
      ],
      "buckets": {
        "三连": [...], "四连": [...], "五连": [...], "N连": [...],
        "复式": {"三连": [...], "四连": [...], "五连": [...], "N连": [...]},
      },
      "summary": {
        "鼠": {"total_appearances": 18, "max_streak": 5, "current_streak": 3},
        ...
      }
    }
    """
    if not period_data:
        return {
            "total_periods": 0,
            "period_range": {},
            "xiao_presence": {},
            "all_streaks": [],
            "active_streaks": [],
            "compound_streaks": [],
            "buckets": _empty_buckets(),
            "summary": {},
        }

    n = len(period_data)
    periods = [d["period"] for d in period_data]

    # Build presence matrix: xiao -> list[bool]
    xiao_presence: dict[str, list[bool]] = {}
    for xiao in ALL_XIAO:
        xiao_presence[xiao] = [
            xiao in d["unique_xiaos"] for d in period_data
        ]

    # Find all streaks per xiao
    all_streaks: list[dict[str, Any]] = []
    summary: dict[str, dict[str, Any]] = {}

    for xiao in ALL_XIAO:
        presence = xiao_presence[xiao]
        total_appearances = sum(presence)
        max_streak = 0
        current_streak = 0
        streaks_for_xiao: list[dict[str, Any]] = []

        i = 0
        while i < n:
            if presence[i]:
                # Start of a potential streak
                start = i
                while i < n and presence[i]:
                    i += 1
                length = i - start
                is_active = (i == n)  # ends at the latest period
                streak_info = {
                    "xiao": xiao,
                    "start_period": periods[start],
                    "end_period": periods[i - 1],
                    "start_idx": start,
                    "end_idx": i - 1,
                    "length": length,
                    "kind": streak_kind(length),
                    "is_active": is_active,
                }
                if length >= min_streak:
                    streaks_for_xiao.append(streak_info)
                max_streak = max(max_streak, length)
                if is_active:
                    current_streak = length
            else:
                i += 1

        all_streaks.extend(streaks_for_xiao)
        summary[xiao] = {
            "total_appearances": total_appearances,
            "appearance_rate": round(total_appearances / n * 100, 1),
            "max_streak": max_streak,
            "current_streak": current_streak,
        }

    # Sort streaks by length desc
    all_streaks.sort(key=lambda s: (-s["length"], s["start_idx"]))

    # Active streaks (currently ongoing, length >= min_streak)
    active_streaks = [s for s in all_streaks if s["is_active"] and s["length"] >= min_streak]

    # 复式: zodiacs that show up together across the same consecutive periods.
    compound_streaks = _compute_compound_streaks(xiao_presence, periods, min_streak)
    buckets = _build_buckets(all_streaks, compound_streaks)

    return {
        "total_periods": n,
        "period_range": {"from": periods[0], "to": periods[-1]},
        "xiao_presence": xiao_presence,
        "all_streaks": all_streaks,
        "active_streaks": active_streaks,
        "compound_streaks": compound_streaks,
        "buckets": buckets,
        "summary": summary,
    }


def _empty_buckets() -> dict[str, Any]:
    single = {kind: [] for kind in _PRIMARY_KINDS}
    return {**single, "复式": {kind: [] for kind in _PRIMARY_KINDS}}


def _build_buckets(
    all_streaks: list[dict[str, Any]],
    compound_streaks: list[dict[str, Any]],
) -> dict[str, Any]:
    single = _bucket_by_kind(all_streaks)
    compound = _bucket_by_kind(compound_streaks)
    buckets: dict[str, Any] = {}
    if "二连" in single:
        buckets["二连"] = single["二连"]
    for kind in _PRIMARY_KINDS:
        buckets[kind] = single.get(kind, [])
    fushi: dict[str, list[dict[str, Any]]] = {}
    if "二连" in compound:
        fushi["二连"] = compound["二连"]
    for kind in _PRIMARY_KINDS:
        fushi[kind] = compound.get(kind, [])
    buckets["复式"] = fushi
    return buckets


def _compute_compound_streaks(
    xiao_presence: dict[str, list[bool]],
    periods: list[str],
    min_streak: int,
) -> list[dict[str, Any]]:
    """Find 复式 runs: 2+ zodiacs present together for ``min_streak`` periods.

    A window is kept when its zodiac set is maximal: a longer run of the same
    set replaces the shorter one, and a larger set replaces a subset that
    covers the same periods.
    """
    n = len(periods)
    if n == 0:
        return []

    period_sets: list[set[str]] = [
        {xiao for xiao in ALL_XIAO if xiao_presence.get(xiao, [False] * n)[i]}
        for i in range(n)
    ]

    candidates: list[tuple[frozenset[str], int, int]] = []
    for start in range(n):
        inter = set(period_sets[start])
        if len(inter) < 2:
            continue
        for end in range(start + 1, n + 1):
            nxt = set() if end == n else inter & period_sets[end]
            if nxt == inter:
                continue
            length = end - start
            if length >= min_streak and len(inter) >= 2:
                candidates.append((frozenset(inter), start, end - 1))
            if len(nxt) < 2:
                break
            inter = nxt

    maximal = _maximal_compound_windows(candidates)
    compounds: list[dict[str, Any]] = []
    for xiaos, start, end in maximal:
        ordered = [xiao for xiao in ALL_XIAO if xiao in xiaos]
        length = end - start + 1
        compounds.append({
            "xiaos": ordered,
            "start_period": periods[start],
            "end_period": periods[end],
            "start_idx": start,
            "end_idx": end,
            "length": length,
            "kind": streak_kind(length),
            "is_active": end == n - 1,
        })

    compounds.sort(key=lambda item: (-item["length"], -len(item["xiaos"]), item["start_idx"]))
    return compounds[:50]


def _maximal_compound_windows(
    candidates: list[tuple[frozenset[str], int, int]],
) -> list[tuple[frozenset[str], int, int]]:
    """Drop nested windows of the same set, then drop subsets of a larger set."""
    by_set: dict[frozenset[str], list[tuple[int, int]]] = {}
    for xiaos, start, end in candidates:
        by_set.setdefault(xiaos, []).append((start, end))

    per_set: list[tuple[frozenset[str], int, int]] = []
    for xiaos, windows in by_set.items():
        unique = list(dict.fromkeys(windows))
        for start, end in unique:
            span = end - start
            covered = any(
                other_start <= start
                and other_end >= end
                and (other_end - other_start) > span
                for other_start, other_end in unique
            )
            if not covered:
                per_set.append((xiaos, start, end))

    kept: list[tuple[frozenset[str], int, int]] = []
    for xiaos, start, end in per_set:
        dominated = any(
            other > xiaos and other_start <= start and other_end >= end
            for other, other_start, other_end in per_set
        )
        if not dominated:
            kept.append((xiaos, start, end))
    return kept


# ---------------------------------------------------------------------------
# 3. AI Context Formatting
# ---------------------------------------------------------------------------

def format_zodiac_streak_for_ai(
    period_data: list[dict[str, Any]],
    streak_stats: dict[str, Any],
) -> str:
    """Format zodiac streak data as a readable text context for AI analysis."""
    lines: list[str] = []

    # Header
    pr = streak_stats.get("period_range", {})
    lines.append("【生肖连码走势数据】")
    lines.append(f"数据范围: 第 {pr.get('from', '?')} 期 至 第 {pr.get('to', '?')} 期")
    lines.append(f"总期数: {streak_stats.get('total_periods', 0)}")
    lines.append(
        "口径: 某一生肖只要出现在该期 7 个开奖号码中即记为该期开出。"
        "连续 3/4/5 期开出记为三连/四连/五连，6 期及以上记为 N 连并标明具体连数。"
        "两个及以上生肖在同一段连续期里一起开出，记为复式。"
    )
    lines.append("")

    # Per-period zodiac table
    lines.append("=" * 80)
    lines.append("一、各期开奖生肖明细（从旧到新）")
    lines.append("=" * 80)
    lines.append(f"{'期号':>8} | {'正1':>3} {'正2':>3} {'正3':>3} {'正4':>3} {'正5':>3} {'正6':>3} {'特码':>3} | 本期生肖集合")
    lines.append("-" * 80)

    for d in period_data:
        xiaos = d["xiaos"]
        unique = d["unique_xiaos"]
        balls_str = " ".join(f"{x:>3}" for x in xiaos[:6])
        tema_str = f"{xiaos[6]:>3}" if len(xiaos) > 6 else "  ?"
        unique_str = "、".join(unique)
        lines.append(f"{d['period']:>8} | {balls_str} {tema_str} | {unique_str}")

    lines.append("")

    # Presence heat map. Long histories stay in the period table above;
    # the grid only keeps the recent window so a 100-period run stays readable.
    heat_data = period_data[-40:] if len(period_data) > 40 else period_data
    heat_offset = len(period_data) - len(heat_data)
    lines.append("=" * 80)
    lines.append("二、十二生肖出现热力图（✓=出现, ·=缺席）")
    if heat_offset:
        lines.append(f"（共 {len(period_data)} 期，热力图仅展示最近 {len(heat_data)} 期）")
    lines.append("=" * 80)

    header_periods = [d["period"][-3:] for d in heat_data]
    lines.append(f"{'生肖':>4} | " + " ".join(f"{p:>3}" for p in header_periods))
    lines.append("-" * (7 + len(header_periods) * 4))

    xiao_presence = streak_stats.get("xiao_presence", {})
    summary = streak_stats.get("summary", {})
    for xiao in ALL_XIAO:
        presence = xiao_presence.get(xiao, [])[heat_offset:]
        marks = " ".join(f"{'✓':>3}" if p else f"{'·':>3}" for p in presence)
        s = summary.get(xiao, {})
        rate = s.get("appearance_rate", 0)
        cur = s.get("current_streak", 0)
        lines.append(f"{xiao:>4} | {marks}  ({rate}% 当前{cur}连)")

    lines.append("")

    # Summary statistics
    lines.append("=" * 80)
    lines.append("三、生肖出现统计概览")
    lines.append("=" * 80)
    lines.append(f"{'生肖':>4} | {'出现次数':>6} | {'出现率':>6} | {'最长连码':>6} | {'当前连码':>6}")
    lines.append("-" * 50)

    for xiao in ALL_XIAO:
        s = summary.get(xiao, {})
        lines.append(
            f"{xiao:>4} | {s.get('total_appearances', 0):>6} | "
            f"{s.get('appearance_rate', 0):>5.1f}% | "
            f"{s.get('max_streak', 0):>6} | "
            f"{s.get('current_streak', 0):>6}"
        )

    lines.append("")
    lines.extend(_format_length_buckets(streak_stats.get("buckets") or _empty_buckets()))
    lines.append("")

    return "\n".join(lines)


def _format_length_buckets(buckets: dict[str, Any]) -> list[str]:
    """Render 三连 / 四连 / 五连 / N连 / 复式 as the block the model must answer."""
    lines = [
        "=" * 80,
        "四、连长归类（三连 / 四连 / 五连 / N连 / 复式）",
        "=" * 80,
    ]
    kind_order = [key for key in ("二连", *_PRIMARY_KINDS) if key in buckets and key != "复式"]
    for kind in kind_order:
        rows = buckets.get(kind) or []
        lines.append(f"【{kind}】共 {len(rows)} 条")
        lines.extend(_format_bucket_rows(rows, compound=False))
        lines.append("")

    fushi = buckets.get("复式") or {}
    lines.append("【复式】多个生肖在同一段连续期里一起开出")
    fushi_order = [key for key in ("二连", *_PRIMARY_KINDS) if key in fushi]
    if not fushi_order:
        lines.append("  无")
    for kind in fushi_order:
        rows = fushi.get(kind) or []
        lines.append(f"  【复式{kind}】共 {len(rows)} 组")
        if not rows:
            lines.append("    无")
            continue
        shown = rows[:20]
        for row in shown:
            lines.append("  " + _format_streak_line(row, compound=True).rstrip())
        if len(rows) > len(shown):
            lines.append(f"    …其余 {len(rows) - len(shown)} 组略")
    return lines


def _format_bucket_rows(rows: list[dict[str, Any]], *, compound: bool) -> list[str]:
    if not rows:
        return ["  无"]
    shown = rows[:20]
    lines = [_format_streak_line(row, compound=compound) for row in shown]
    if len(rows) > len(shown):
        lines.append(f"  …其余 {len(rows) - len(shown)} 条略")
    return lines


def _format_streak_line(row: dict[str, Any], *, compound: bool) -> str:
    status = "活跃" if row.get("is_active") else "已断"
    length = int(row.get("length") or 0)
    label = f"{length}连" if length >= 6 else (row.get("kind") or streak_kind(length))
    if compound:
        name = "+".join(row.get("xiaos") or [])
        return (
            f"  - [{name}] {label}"
            f"（第 {row.get('start_period')} 期 → 第 {row.get('end_period')} 期，{status}）"
        )
    return (
        f"  - {row.get('xiao')} {label}"
        f"（第 {row.get('start_period')} 期 → 第 {row.get('end_period')} 期，{status}）"
    )
