"""Pingte (平特 7码: 正码1-6 + 特码) per-zodiac draw history & streak/omission segment analytics."""
from __future__ import annotations

from datetime import date
from typing import Any

from common.attr import bose, pad_num
from common.wuxing import num_to_wuxing
from common.xiao import XIAO, normalize_xiao, num_to_xiao

POSITIONS = ("正1", "正2", "正3", "正4", "正5", "正6", "特码")


def _format_date(d: Any) -> str:
    if isinstance(d, date):
        return d.isoformat()
    if isinstance(d, str):
        return d
    return ""


def format_segment_text(seg_type: str, start_period: str, end_period: str, length: int) -> str:
    """Format human-readable segment description, e.g. '2026001~2026005 连开5期' or '2026006~2026008 没出3期'."""
    action = "连开" if seg_type == "hit" else "没出"
    return f"{start_period}~{end_period} {action}{length}期"


def _parse_date(val: Any, fallback: date | None = None, period: str = "") -> date:
    if isinstance(val, date):
        return val
    if isinstance(val, str) and len(val) >= 10:
        try:
            return date.fromisoformat(val[:10])
        except ValueError:
            pass
    p = str(period or "").strip()
    if len(p) == 7 and p.isdigit():
        try:
            from common.period import date_for_period

            return date_for_period(p)
        except Exception:
            try:
                return date(int(p[:4]), 6, 1)
            except Exception:
                pass
    return fallback if fallback is not None else date.today()


def build_periods_data(chronological_draws: list[Any], ref_date: date | None = None) -> list[dict[str, Any]]:
    """Convert chronological Draw ORM objects or dicts into normalized period records (oldest to newest)."""
    if ref_date is None:
        if chronological_draws:
            last = chronological_draws[-1]
            last_period = str(getattr(last, "period", "") if not isinstance(last, dict) else (last.get("period") or ""))
            raw_last_dd = (
                getattr(last, "draw_date", None)
                if not isinstance(last, dict)
                else (last.get("date") or last.get("draw_date"))
            )
            ref_date = _parse_date(raw_last_dd, date.today(), period=last_period)
        else:
            ref_date = date.today()

    periods_data: list[dict[str, Any]] = []
    for d in chronological_draws:
        if isinstance(d, dict):
            period = str(d.get("period") or "")
            raw_dd = d.get("date") or d.get("draw_date")
            dd = _parse_date(raw_dd, ref_date, period=period)
            if "all_7" in d and len(d["all_7"]) >= 7:
                all_7 = [pad_num(x) for x in d["all_7"][:7]]
                b_list = all_7[:6]
                tema_num = all_7[6]
            elif "numbers" in d and isinstance(d["numbers"], (list, tuple)) and len(d["numbers"]) >= 7:
                all_7 = [pad_num(x) for x in d["numbers"][:7]]
                b_list = all_7[:6]
                tema_num = all_7[6]
            else:
                balls = d.get("balls") or [d.get("z1"), d.get("z2"), d.get("z3"), d.get("z4"), d.get("z5"), d.get("z6")]
                b_list = [pad_num(x) for x in balls]
                tema_num = pad_num(d.get("tema"))
                all_7 = b_list + [tema_num]
        else:
            period = str(d.period)
            dd = _parse_date(getattr(d, "draw_date", None), ref_date, period=period)
            b_list = [pad_num(x) for x in [d.z1, d.z2, d.z3, d.z4, d.z5, d.z6]]
            tema_num = pad_num(d.tema)
            all_7 = b_list + [tema_num]

        xiaos = [num_to_xiao(x, dd) for x in all_7]
        boses = [bose(x) for x in all_7]
        wuxs = [num_to_wuxing(x, dd) or "" for x in all_7]
        periods_data.append({
            "period": period,
            "date": dd,
            "date_str": _format_date(dd),
            "all_7": all_7,
            "ping_6": b_list,
            "tema": tema_num,
            "xiaos": xiaos,
            "boses": boses,
            "wuxings": wuxs,
        })
    return periods_data


def compute_single_zodiac_history(
    z: str,
    periods_data: list[dict[str, Any]],
    zodiac_numbers: list[str] | None = None,
    include_period_history: bool = True,
) -> dict[str, Any]:
    """Compute full Pingte draw history, hit/miss segments, and distributions for one zodiac ``z``."""
    N = len(periods_data)
    if N == 0:
        return {
            "name": z,
            "label": f"{z}肖",
            "numbers": zodiac_numbers or [],
            "sample_periods": 0,
            "count": 0,
            "ping_count": 0,
            "tema_count": 0,
            "periods_count": 0,
            "miss_periods_count": 0,
            "multi_ball_periods_count": 0,
            "frequency": 0.0,
            "current_omission": 0,
            "max_omission": 0,
            "max_consecutive": 0,
            "current_consecutive": 0,
            "current_range": None,
            "max_consecutive_range": None,
            "max_omission_range": None,
            "segments_count": 0,
            "hit_segments_count": 0,
            "miss_segments_count": 0,
            "recent_segments": [],
            "streak_distribution": [],
            "omission_distribution": [],
            "segments": [],
            "period_history": [],
        }

    total_ball_count = 0
    ping_ball_count = 0
    tema_ball_count = 0
    periods_count = 0
    multi_ball_periods_count = 0

    chronological_records: list[dict[str, Any]] = []
    for idx, p in enumerate(periods_data):
        matched_balls: list[dict[str, Any]] = []
        all_balls_detail: list[dict[str, Any]] = []
        for pos_i in range(7):
            num_str = p["all_7"][pos_i]
            ball_xiao = p["xiaos"][pos_i]
            ball_bose = p["boses"][pos_i]
            ball_wuxing = p["wuxings"][pos_i]
            pos_label = POSITIONS[pos_i]
            is_tema = pos_i == 6
            is_match = ball_xiao == z
            if is_match:
                matched_balls.append({
                    "num": num_str,
                    "number": num_str,
                    "pos": pos_label,
                    "position": pos_i + 1,
                    "bose": ball_bose,
                    "wuxing": ball_wuxing,
                    "is_tema": is_tema,
                })
            if include_period_history:
                all_balls_detail.append({
                    "num": num_str,
                    "number": num_str,
                    "xiao": ball_xiao,
                    "bose": ball_bose,
                    "wuxing": ball_wuxing,
                    "pos": pos_label,
                    "position": pos_i + 1,
                    "is_tema": is_tema,
                    "is_match": is_match,
                    "is_target": is_match,
                })

        c = len(matched_balls)
        p_cnt = sum(1 for b in matched_balls if not b["is_tema"])
        t_cnt = sum(1 for b in matched_balls if b["is_tema"])
        is_hit = c > 0
        matched_numbers = [b["num"] for b in matched_balls]
        date_str = p.get("date_str") or _format_date(p.get("date"))

        total_ball_count += c
        ping_ball_count += p_cnt
        tema_ball_count += t_cnt
        if is_hit:
            periods_count += 1
        if c >= 2:
            multi_ball_periods_count += 1

        chronological_records.append({
            "idx": idx,
            "period": p["period"],
            "date": date_str,
            "draw_date": date_str,
            "hit": is_hit,
            "is_hit": is_hit,
            "ball_count": c,
            "ping_count": p_cnt,
            "tema_hit": t_cnt > 0,
            "has_tema": t_cnt > 0,
            "matched_numbers": matched_numbers,
            "matched_balls": matched_balls,
            "all_balls": all_balls_detail if include_period_history else [],
        })

    # Partition chronological_records into contiguous hit/miss segments
    chronological_segments: list[dict[str, Any]] = []
    i = 0
    seg_id = 0
    while i < N:
        is_hit = chronological_records[i]["hit"]
        start = i
        while i < N and chronological_records[i]["hit"] == is_hit:
            i += 1
        end = i - 1
        length = end - start + 1
        seg_id += 1
        seg_type = "hit" if is_hit else "miss"
        seg_type_label = "连开" if is_hit else "没出"
        start_rec = chronological_records[start]
        end_rec = chronological_records[end]
        start_period = start_rec["period"]
        end_period = end_rec["period"]
        is_current = end == N - 1

        seg_records = chronological_records[start : end + 1]
        seg_total_balls = sum(r["ball_count"] for r in seg_records)
        seg_tema_hits = sum(1 for r in seg_records if r["tema_hit"])
        summary_text = format_segment_text(seg_type, start_period, end_period, length)

        # Annotate each period record with its segment context
        for step_idx, r in enumerate(seg_records):
            step_no = step_idx + 1
            r["segment_id"] = seg_id
            r["run_type"] = seg_type
            r["segment_type"] = seg_type
            r["run_type_label"] = seg_type_label
            r["segment_type_label"] = seg_type_label
            r["run_step"] = step_no
            r["segment_step"] = step_no
            r["segment_length"] = length
            r["segment_start"] = start_period
            r["segment_start_period"] = start_period
            r["segment_end"] = end_period
            r["segment_end_period"] = end_period
            r["segment_is_current"] = is_current
            r["segment_text"] = summary_text
            r["running_text"] = f"{seg_type_label}第{step_no}期"

        seg_period_items = (
            [
                {
                    "period": r["period"],
                    "date": r["date"],
                    "draw_date": r["date"],
                    "hit": r["hit"],
                    "is_hit": r["hit"],
                    "ball_count": r["ball_count"],
                    "tema_hit": r["tema_hit"],
                    "has_tema": r["tema_hit"],
                    "matched_numbers": r["matched_numbers"],
                    "matched_balls": r["matched_balls"],
                }
                for r in seg_records
            ]
            if is_hit
            else []
        )

        chronological_segments.append({
            "segment_id": seg_id,
            "type": seg_type,
            "type_label": seg_type_label,
            "start_period": start_period,
            "end_period": end_period,
            "start_date": start_rec["date"],
            "end_date": end_rec["date"],
            "length": length,
            "total_balls": seg_total_balls,
            "tema_hits": seg_tema_hits,
            "is_current": is_current,
            "text": summary_text,
            "periods": seg_period_items,
        })

    # Compute streak & omission summary metrics
    hit_segments = [s for s in chronological_segments if s["type"] == "hit"]
    miss_segments = [s for s in chronological_segments if s["type"] == "miss"]

    max_consecutive = max((s["length"] for s in hit_segments), default=0)
    max_omission = max((s["length"] for s in miss_segments), default=0)

    last_seg = chronological_segments[-1]
    if last_seg["type"] == "hit":
        current_consecutive = last_seg["length"]
        current_omission = 0
    else:
        current_consecutive = 0
        current_omission = last_seg["length"]

    def _compact_range(seg: dict[str, Any] | None) -> dict[str, Any] | None:
        if not seg:
            return None
        return {
            "type": seg["type"],
            "type_label": seg["type_label"],
            "start_period": seg["start_period"],
            "end_period": seg["end_period"],
            "start_date": seg["start_date"],
            "end_date": seg["end_date"],
            "length": seg["length"],
            "total_balls": seg["total_balls"],
            "is_current": seg["is_current"],
            "text": seg["text"],
        }

    # For max_consecutive_range / max_omission_range, pick the most recent segment achieving the max
    best_hit_seg = None
    for s in reversed(hit_segments):
        if s["length"] == max_consecutive:
            best_hit_seg = s
            break

    best_miss_seg = None
    for s in reversed(miss_segments):
        if s["length"] == max_omission:
            best_miss_seg = s
            break

    # Build distributions (grouped by length, descending)
    def _build_distribution(segs: list[dict[str, Any]], label_prefix: str) -> list[dict[str, Any]]:
        by_len: dict[int, list[dict[str, Any]]] = {}
        for s in segs:
            by_len.setdefault(s["length"], []).append(s)
        dist = []
        for length in sorted(by_len.keys(), reverse=True):
            group = by_len[length]
            ranges = [
                {
                    "start_period": g["start_period"],
                    "end_period": g["end_period"],
                    "start_date": g["start_date"],
                    "end_date": g["end_date"],
                    "total_balls": g["total_balls"],
                    "is_current": g["is_current"],
                    "text": g["text"],
                }
                for g in reversed(group)
            ]
            latest_r = ranges[0] if ranges else {}
            dist.append({
                "length": length,
                "label": f"{label_prefix}{length}期",
                "count": len(group),
                "latest_start_period": latest_r.get("start_period", ""),
                "latest_end_period": latest_r.get("end_period", ""),
                "latest_text": latest_r.get("text", ""),
                "is_current": bool(latest_r.get("is_current", False)),
                "ranges": ranges,
            })
        return dist

    streak_distribution = _build_distribution(hit_segments, "连开")
    omission_distribution = _build_distribution(miss_segments, "没出")

    # Segments ordered newest-first for display
    segments_newest_first = list(reversed(chronological_segments))
    recent_segments = [_compact_range(s) for s in segments_newest_first[:8] if s is not None]

    period_history_newest_first = (
        list(reversed(chronological_records)) if include_period_history else []
    )

    freq = round((periods_count / N) * 100, 1)
    return {
        "name": z,
        "label": f"{z}肖",
        "numbers": zodiac_numbers or [],
        "sample_periods": N,
        "count": total_ball_count,
        "ping_count": ping_ball_count,
        "tema_count": tema_ball_count,
        "periods_count": periods_count,
        "miss_periods_count": N - periods_count,
        "multi_ball_periods_count": multi_ball_periods_count,
        "frequency": freq,
        "current_omission": current_omission,
        "max_omission": max_omission,
        "max_consecutive": max_consecutive,
        "current_consecutive": current_consecutive,
        "current_range": _compact_range(last_seg),
        "max_consecutive_range": _compact_range(best_hit_seg),
        "max_omission_range": _compact_range(best_miss_seg),
        "segments_count": len(chronological_segments),
        "hit_segments_count": len(hit_segments),
        "miss_segments_count": len(miss_segments),
        "recent_segments": recent_segments,
        "streak_distribution": streak_distribution,
        "omission_distribution": omission_distribution,
        "segments": segments_newest_first,
        "period_history": period_history_newest_first,
    }


def format_prev_tema_segment_text(start_period: str, end_period: str, is_hit: bool, length: int) -> str:
    """Format human-readable segment text for previous-tema-in-pingte (e.g. ``2026273~2026278 连续出现6期``)."""
    action = "连续出现" if is_hit else "连续缺失"
    return f"{start_period}~{end_period} {action}{length}期"


def compute_prev_tema_in_pingte(
    chronological_draws: list[Any],
    ref_date: date | None = None,
    include_period_history: bool = True,
) -> dict[str, Any]:
    """Compute whether the previous period's special ball zodiac (``上一期特码生肖``)
    appears in the current period's 7 Pingte balls (``正1..正6 + 特码``).

    Starts from the 2nd draw in ``chronological_draws`` (comparing period ``i`` against period ``i-1``).
    Returns appearance probability, contiguous hit/miss segments (``xxx~xxx 连续出现N期`` / ``连续缺失N期``),
    streak/omission distributions, per-period details, and the latest period's 特码 reference for the next draw.
    """
    if (
        chronological_draws
        and isinstance(chronological_draws[0], dict)
        and "xiaos" in chronological_draws[0]
        and "date_str" in chronological_draws[0]
        and "tema" in chronological_draws[0]
    ):
        periods_data = chronological_draws
    else:
        periods_data = build_periods_data(chronological_draws, ref_date=ref_date)

    total_draws = len(periods_data)
    if ref_date is None:
        ref_date = periods_data[-1]["date"] if total_draws > 0 else date.today()

    latest_tema_ref: dict[str, Any] | None = None
    latest_numbers: list[str] = []
    if total_draws > 0:
        last_p = periods_data[-1]
        latest_tema_xiao = last_p["xiaos"][6]
        latest_numbers = [
            f"{n:02d}"
            for n in range(1, 50)
            if num_to_xiao(f"{n:02d}", ref_date) == latest_tema_xiao
        ]
        latest_tema_ref = {
            "period": last_p["period"],
            "date": last_p["date_str"],
            "tema": last_p["tema"],
            "tema_xiao": latest_tema_xiao,
            "tema_bose": last_p["boses"][6],
            "tema_wuxing": last_p["wuxings"][6],
            "numbers": latest_numbers,
        }

    evaluated_periods = max(0, total_draws - 1)
    if evaluated_periods == 0:
        only_period = periods_data[0]["period"] if total_draws == 1 else None
        return {
            "name": "前特肖",
            "label": "上期特码生肖落当期平特",
            "numbers": latest_numbers,
            "total_draws": total_draws,
            "sample_periods": 0,
            "evaluated_periods": 0,
            "earliest_draw_period": only_period,
            "earliest_period": only_period,
            "latest_period": only_period,
            "count": 0,
            "ping_count": 0,
            "tema_count": 0,
            "exact_tema_num_count": 0,
            "exact_tema_num_rate": 0.0,
            "periods_count": 0,
            "miss_periods_count": 0,
            "multi_ball_periods_count": 0,
            "frequency": 0.0,
            "probability": 0.0,
            "miss_probability": 0.0,
            "current_omission": 0,
            "max_omission": 0,
            "max_consecutive": 0,
            "current_consecutive": 0,
            "current_range": None,
            "max_consecutive_range": None,
            "max_omission_range": None,
            "segments_count": 0,
            "hit_segments_count": 0,
            "miss_segments_count": 0,
            "recent_segments": [],
            "streak_distribution": [],
            "omission_distribution": [],
            "segments": [],
            "period_history": [],
            "latest_tema_ref": latest_tema_ref,
        }

    total_ball_count = 0
    ping_ball_count = 0
    tema_ball_count = 0
    exact_tema_num_count = 0
    periods_count = 0
    multi_ball_periods_count = 0

    chronological_records: list[dict[str, Any]] = []
    for idx in range(evaluated_periods):
        prev_p = periods_data[idx]
        cur_p = periods_data[idx + 1]
        period = cur_p["period"]
        date_str = cur_p["date_str"]
        prev_period = prev_p["period"]
        prev_date_str = prev_p["date_str"]
        prev_tema = prev_p["tema"]
        prev_tema_xiao = prev_p["xiaos"][6]
        prev_tema_bose = prev_p["boses"][6]
        prev_tema_wuxing = prev_p["wuxings"][6]

        matched_balls: list[dict[str, Any]] = []
        all_balls_detail: list[dict[str, Any]] = []

        for pos_i in range(7):
            num_str = cur_p["all_7"][pos_i]
            ball_xiao = cur_p["xiaos"][pos_i]
            ball_bose = cur_p["boses"][pos_i]
            ball_wuxing = cur_p["wuxings"][pos_i]
            pos_label = POSITIONS[pos_i]
            is_tema = pos_i == 6
            is_match = ball_xiao == prev_tema_xiao
            is_exact_tema_num = num_str == prev_tema

            if is_match:
                matched_balls.append({
                    "num": num_str,
                    "number": num_str,
                    "xiao": ball_xiao,
                    "pos": pos_label,
                    "position": pos_i + 1,
                    "bose": ball_bose,
                    "wuxing": ball_wuxing,
                    "is_tema": is_tema,
                    "is_exact_tema_num": is_exact_tema_num,
                })
            if include_period_history:
                all_balls_detail.append({
                    "num": num_str,
                    "number": num_str,
                    "xiao": ball_xiao,
                    "bose": ball_bose,
                    "wuxing": ball_wuxing,
                    "pos": pos_label,
                    "position": pos_i + 1,
                    "is_tema": is_tema,
                    "is_match": is_match,
                    "is_target": is_match,
                    "is_exact_tema_num": is_exact_tema_num,
                })

        c = len(matched_balls)
        p_cnt = sum(1 for b in matched_balls if not b["is_tema"])
        t_cnt = sum(1 for b in matched_balls if b["is_tema"])
        exact_num_hit = any(b["is_exact_tema_num"] for b in matched_balls) or (prev_tema in cur_p["all_7"])
        is_hit = c > 0
        matched_numbers = [b["num"] for b in matched_balls]

        total_ball_count += c
        ping_ball_count += p_cnt
        tema_ball_count += t_cnt
        if exact_num_hit:
            exact_tema_num_count += 1
        if is_hit:
            periods_count += 1
        if c >= 2:
            multi_ball_periods_count += 1

        chronological_records.append({
            "idx": idx,
            "period": period,
            "date": date_str,
            "draw_date": date_str,
            "prev_period": prev_period,
            "prev_date": prev_date_str,
            "prev_tema": prev_tema,
            "prev_tema_xiao": prev_tema_xiao,
            "prev_tema_bose": prev_tema_bose,
            "prev_tema_wuxing": prev_tema_wuxing,
            "target_xiao": prev_tema_xiao,
            "hit": is_hit,
            "is_hit": is_hit,
            "ball_count": c,
            "ping_count": p_cnt,
            "tema_hit": t_cnt > 0,
            "has_tema": t_cnt > 0,
            "exact_tema_num_hit": exact_num_hit,
            "matched_numbers": matched_numbers,
            "matched_balls": matched_balls,
            "all_balls": all_balls_detail if include_period_history else [],
        })

    # Partition into contiguous hit/miss segments
    chronological_segments: list[dict[str, Any]] = []
    i = 0
    seg_id = 0
    while i < evaluated_periods:
        is_hit = chronological_records[i]["hit"]
        start = i
        while i < evaluated_periods and chronological_records[i]["hit"] == is_hit:
            i += 1
        end = i - 1
        length = end - start + 1
        seg_id += 1
        seg_type = "hit" if is_hit else "miss"
        seg_label = "连续出现" if is_hit else "连续缺失"
        start_period = chronological_records[start]["period"]
        end_period = chronological_records[end]["period"]
        start_date = chronological_records[start]["date"]
        end_date = chronological_records[end]["date"]
        is_current = end == evaluated_periods - 1
        summary_text = format_prev_tema_segment_text(start_period, end_period, is_hit, length)

        seg_total_balls = 0
        seg_tema_hits = 0
        for offset, rec in enumerate(chronological_records[start : end + 1]):
            step_no = offset + 1
            seg_total_balls += rec["ball_count"]
            if rec["tema_hit"]:
                seg_tema_hits += 1
            rec["segment_id"] = seg_id
            rec["run_type"] = seg_type
            rec["segment_type"] = seg_type
            rec["run_type_label"] = seg_label
            rec["segment_type_label"] = seg_label
            rec["run_step"] = step_no
            rec["segment_step"] = step_no
            rec["segment_length"] = length
            rec["segment_start"] = start_period
            rec["segment_start_period"] = start_period
            rec["segment_end"] = end_period
            rec["segment_end_period"] = end_period
            rec["segment_is_current"] = is_current
            rec["segment_text"] = summary_text
            rec["running_text"] = f"{seg_label}第{step_no}期"

        seg_periods = [
            {
                "period": r["period"],
                "date": r["date"],
                "draw_date": r["draw_date"],
                "prev_period": r["prev_period"],
                "prev_date": r["prev_date"],
                "prev_tema": r["prev_tema"],
                "prev_tema_xiao": r["prev_tema_xiao"],
                "prev_tema_bose": r["prev_tema_bose"],
                "prev_tema_wuxing": r["prev_tema_wuxing"],
                "hit": r["hit"],
                "is_hit": r["is_hit"],
                "ball_count": r["ball_count"],
                "tema_hit": r["tema_hit"],
                "has_tema": r["has_tema"],
                "exact_tema_num_hit": r["exact_tema_num_hit"],
                "matched_numbers": r["matched_numbers"],
                "matched_balls": r["matched_balls"],
            }
            for r in chronological_records[start : end + 1]
        ]

        chronological_segments.append({
            "segment_id": seg_id,
            "type": seg_type,
            "type_label": seg_label,
            "start_period": start_period,
            "end_period": end_period,
            "start_date": start_date,
            "end_date": end_date,
            "length": length,
            "total_balls": seg_total_balls,
            "tema_hits": seg_tema_hits,
            "is_current": is_current,
            "text": summary_text,
            "periods": seg_periods,
        })

    def _compact_range(seg: dict[str, Any] | None) -> dict[str, Any] | None:
        if not seg:
            return None
        return {
            "type": seg["type"],
            "type_label": seg["type_label"],
            "start_period": seg["start_period"],
            "end_period": seg["end_period"],
            "start_date": seg["start_date"],
            "end_date": seg["end_date"],
            "length": seg["length"],
            "total_balls": seg["total_balls"],
            "is_current": seg["is_current"],
            "text": seg["text"],
        }

    last_seg = chronological_segments[-1] if chronological_segments else None
    current_consecutive = last_seg["length"] if (last_seg and last_seg["type"] == "hit") else 0
    current_omission = last_seg["length"] if (last_seg and last_seg["type"] == "miss") else 0

    hit_segments = [s for s in chronological_segments if s["type"] == "hit"]
    miss_segments = [s for s in chronological_segments if s["type"] == "miss"]

    max_consecutive = max((s["length"] for s in hit_segments), default=0)
    max_omission = max((s["length"] for s in miss_segments), default=0)

    best_hit_seg = None
    for s in reversed(hit_segments):
        if s["length"] == max_consecutive:
            best_hit_seg = s
            break

    best_miss_seg = None
    for s in reversed(miss_segments):
        if s["length"] == max_omission:
            best_miss_seg = s
            break

    def _build_distribution(segs: list[dict[str, Any]], label_prefix: str) -> list[dict[str, Any]]:
        by_len: dict[int, list[dict[str, Any]]] = {}
        for s in segs:
            by_len.setdefault(s["length"], []).append(s)
        dist = []
        for length in sorted(by_len.keys(), reverse=True):
            group = by_len[length]
            ranges = [
                {
                    "start_period": g["start_period"],
                    "end_period": g["end_period"],
                    "start_date": g["start_date"],
                    "end_date": g["end_date"],
                    "total_balls": g["total_balls"],
                    "is_current": g["is_current"],
                    "text": g["text"],
                }
                for g in reversed(group)
            ]
            latest_r = ranges[0] if ranges else {}
            dist.append({
                "length": length,
                "label": f"{label_prefix}{length}期",
                "count": len(group),
                "latest_start_period": latest_r.get("start_period", ""),
                "latest_end_period": latest_r.get("end_period", ""),
                "latest_text": latest_r.get("text", ""),
                "is_current": bool(latest_r.get("is_current", False)),
                "ranges": ranges,
            })
        return dist

    streak_distribution = _build_distribution(hit_segments, "连续出现")
    omission_distribution = _build_distribution(miss_segments, "连续缺失")

    segments_newest_first = list(reversed(chronological_segments))
    recent_segments = [_compact_range(s) for s in segments_newest_first[:8] if s is not None]
    period_history_newest_first = (
        list(reversed(chronological_records)) if include_period_history else []
    )

    miss_periods_count = evaluated_periods - periods_count
    probability = round((periods_count / evaluated_periods) * 100, 2)
    miss_probability = round((miss_periods_count / evaluated_periods) * 100, 2)
    freq = round((periods_count / evaluated_periods) * 100, 1)
    exact_tema_num_rate = round((exact_tema_num_count / evaluated_periods) * 100, 2)

    return {
        "name": "前特肖",
        "label": "上期特码生肖落当期平特",
        "numbers": latest_numbers,
        "total_draws": total_draws,
        "sample_periods": evaluated_periods,
        "evaluated_periods": evaluated_periods,
        "earliest_draw_period": periods_data[0]["period"],
        "earliest_period": chronological_records[0]["period"],
        "latest_period": chronological_records[-1]["period"],
        "count": total_ball_count,
        "ping_count": ping_ball_count,
        "tema_count": tema_ball_count,
        "exact_tema_num_count": exact_tema_num_count,
        "exact_tema_num_rate": exact_tema_num_rate,
        "periods_count": periods_count,
        "miss_periods_count": miss_periods_count,
        "multi_ball_periods_count": multi_ball_periods_count,
        "frequency": freq,
        "probability": probability,
        "miss_probability": miss_probability,
        "current_omission": current_omission,
        "max_omission": max_omission,
        "max_consecutive": max_consecutive,
        "current_consecutive": current_consecutive,
        "current_range": _compact_range(last_seg),
        "max_consecutive_range": _compact_range(best_hit_seg),
        "max_omission_range": _compact_range(best_miss_seg),
        "segments_count": len(chronological_segments),
        "hit_segments_count": len(hit_segments),
        "miss_segments_count": len(miss_segments),
        "recent_segments": recent_segments,
        "streak_distribution": streak_distribution,
        "omission_distribution": omission_distribution,
        "segments": segments_newest_first,
        "period_history": period_history_newest_first,
        "latest_tema_ref": latest_tema_ref,
    }


def compute_all_zodiacs_pingte_history(
    chronological_draws: list[Any],
    ref_date: date | None = None,
    target_xiao: str | None = None,
    include_period_history: bool = True,
) -> dict[str, Any]:
    """Compute Pingte history across all 12 zodiacs (or focused on ``target_xiao``)."""
    periods_data = build_periods_data(chronological_draws, ref_date=ref_date)
    N = len(periods_data)
    if ref_date is None:
        ref_date = periods_data[-1]["date"] if N > 0 else date.today()

    zodiac_nums_map: dict[str, list[str]] = {z: [] for z in XIAO}
    for n in range(1, 50):
        pn = f"{n:02d}"
        zx = num_to_xiao(pn, ref_date)
        zodiac_nums_map[zx].append(pn)

    normalized_target: str | None = None
    if target_xiao and target_xiao.strip() and target_xiao.strip().lower() != "all":
        raw_t = target_xiao.strip()
        if raw_t.lower() in ("prev_tema", "prev-tema", "上期特码", "前特肖", "上期特肖"):
            normalized_target = "前特肖"
        else:
            normalized_target = normalize_xiao(raw_t.replace("肖", ""))

    zodiacs_map: dict[str, dict[str, Any]] = {}
    zodiac_list: list[dict[str, Any]] = []

    for z in XIAO:
        want_full_periods = include_period_history and (normalized_target is None or normalized_target == z)
        z_data = compute_single_zodiac_history(
            z,
            periods_data,
            zodiac_numbers=zodiac_nums_map.get(z, []),
            include_period_history=want_full_periods,
        )
        zodiacs_map[z] = z_data
        zodiac_list.append(z_data)

    want_prev_tema_periods = include_period_history and (normalized_target is None or normalized_target == "前特肖")
    prev_tema_pingte = compute_prev_tema_in_pingte(
        periods_data,
        ref_date=ref_date,
        include_period_history=want_prev_tema_periods,
    )

    return {
        "sample_periods": N,
        "earliest_period": periods_data[0]["period"] if N > 0 else None,
        "latest_period": periods_data[-1]["period"] if N > 0 else None,
        "target_xiao": normalized_target,
        "zodiacs": zodiac_list,
        "zodiacs_map": zodiacs_map,
        "prev_tema_pingte": prev_tema_pingte,
    }

