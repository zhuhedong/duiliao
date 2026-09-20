from collections import defaultdict
from types import SimpleNamespace
import os

from sqlalchemy import case, func, select
from schema import Source, Prediction, Draw, JudgeResult
from db import session_scope


def _monitor_list_limit() -> int:
    try:
        return max(1, min(int(os.getenv("PRED_MONITOR_LIST_LIMIT", "500")), 500))
    except ValueError:
        return 500


def monitor(lottery=None):
    with session_scope() as s:
        sources = list(s.scalars(select(Source).where(Source.lottery == lottery) if lottery else select(Source)))
        latest_draws = {
            draw_lottery: period
            for draw_lottery, period in s.execute(
                select(Draw.lottery, func.max(Draw.period)).group_by(Draw.lottery)
            )
        }
        list_limit = _monitor_list_limit()
        items = []
        for src in sources:
            pred_filter = (
                Prediction.source_id == src.source_id,
                Prediction.lottery == src.lottery,
                Prediction.play_type == src.play_type,
            )
            first_real, latest, last_seen = s.execute(
                select(
                    func.min(case((Prediction.claimed_status != "missing", Prediction.period))),
                    func.max(case((Prediction.claimed_status != "missing", Prediction.period))),
                    func.max(Prediction.last_seen_at),
                ).where(*pred_filter)
            ).one()
            confirmed_stmt = select(Prediction.period).where(
                *pred_filter, Prediction.claimed_status == "missing"
            )
            confirmed_total = s.scalar(
                select(func.count()).select_from(confirmed_stmt.subquery())
            ) or 0
            confirmed = list(s.scalars(confirmed_stmt.order_by(Prediction.period).limit(list_limit)))
            pending: list[str] = []
            pending_total = 0
            lag = None
            if first_real:
                known = select(Prediction.id).where(
                    *pred_filter, Prediction.period == Draw.period
                ).exists()
                pending_stmt = select(Draw.period).where(
                    Draw.lottery == src.lottery,
                    Draw.period >= first_real,
                    ~known,
                )
                pending_total = s.scalar(
                    select(func.count()).select_from(pending_stmt.subquery())
                ) or 0
                pending = list(s.scalars(pending_stmt.order_by(Draw.period).limit(list_limit)))
                lag = s.scalar(select(func.count()).select_from(Draw).where(
                    Draw.lottery == src.lottery, Draw.period > latest
                )) or 0
            items.append(dict(source_id=src.source_id, source_name=src.source_name, lottery=src.lottery,
                play_type=src.play_type, enabled=bool(src.enabled), latest_period=latest,
                latest_draw=latest_draws.get(src.lottery), lag=int(lag) if lag is not None else None,
                pending=pending, pending_total=int(pending_total),
                confirmed=confirmed, confirmed_total=int(confirmed_total),
                lists_truncated=pending_total > len(pending) or confirmed_total > len(confirmed),
                never_collected=not first_real, last_seen=last_seen))
        return {"items": items}


def confirm_missing(source_id, periods):
    from audit import now_local, record
    from missing_periods import missing_result
    from rules import save_result
    if not periods or len(periods) > 500:
        raise ValueError("请选择 1–500 个待补期号")
    with session_scope() as s:
        source = s.get(Source, source_id)
        if not source:
            raise ValueError("来源不存在")
        first_real = s.scalar(select(func.min(Prediction.period)).where(
            Prediction.source_id == source_id,
            Prediction.lottery == source.lottery,
            Prediction.play_type == source.play_type,
            Prediction.claimed_status != "missing",
        ))
        if not first_real:
            raise ValueError("该源尚无覆盖起点，请先采集资料")
        available = set(s.scalars(select(Draw.period).where(
            Draw.lottery == source.lottery,
            Draw.period >= first_real,
            Draw.period.in_(set(periods)),
        )))
        if set(periods) - available:
            raise ValueError("只能确认覆盖起点以后且已有开奖的期号")
        added = 0
        for period in sorted(set(periods)):
            row = s.scalar(select(Prediction).where(Prediction.source_id == source_id, Prediction.lottery == source.lottery,
                           Prediction.play_type == source.play_type, Prediction.period == period))
            if row:
                continue
            now = now_local()
            row = Prediction(source_id=source_id, lottery=source.lottery, play_type=source.play_type, hit_mode=source.hit_mode,
                period=period, period_raw=str(int(period[4:])), preds_json=[], claimed_status="missing", raw_text="人工确认缺期：默认按挂计入",
                content_hash="missing_period", fetched_at=now, first_seen_at=now, last_seen_at=now, last_run_id="confirm-missing")
            s.add(row)
            record(s, row, "confirmed_missing")
            save_result(s, row, missing_result(row), now)
            added += 1
        return {"ok": True, "added": added}


def streak(values):
    longest_hit = longest_miss = run_hit = run_miss = 0
    for v in values:
        run_hit = run_hit + 1 if v == 1 else 0
        run_miss = run_miss + 1 if v == 0 else 0
        longest_hit = max(longest_hit, run_hit)
        longest_miss = max(longest_miss, run_miss)
    current = 0
    if values and values[0] is not None:
        for v in values:
            if v != values[0]:
                break
            current += 1
    return dict(longest_hit=longest_hit, longest_miss=longest_miss,
                current_streak=current, current_result=values[0] if values else None)


def ratings(lottery, play_type, windows=(30, 50, 100), period_from=None, period_to=None):
    from audit import history
    from judge import judge_one, draw_view
    with session_scope() as s:
        draw_periods = select(Draw.period.label("period")).where(Draw.lottery == lottery)
        judged_periods = (
            select(Prediction.period.label("period"))
            .join(JudgeResult, JudgeResult.prediction_id == Prediction.id)
            .where(Prediction.lottery == lottery, Prediction.play_type == play_type)
        )
        calendar = draw_periods.union(judged_periods).subquery()
        period_stmt = select(calendar.c.period)
        if period_from:
            period_stmt = period_stmt.where(calendar.c.period >= period_from)
        if period_to:
            period_stmt = period_stmt.where(calendar.c.period <= period_to)
        periods = list(s.scalars(period_stmt.order_by(calendar.c.period.desc()).limit(max(windows))))
        draws = {
            draw.period: draw
            for draw in s.scalars(select(Draw).where(Draw.lottery == lottery, Draw.period.in_(periods)))
        } if periods else {}
        pairs = list(s.execute(
            select(Prediction, JudgeResult)
            .outerjoin(JudgeResult, JudgeResult.prediction_id == Prediction.id)
            .where(
                Prediction.lottery == lottery,
                Prediction.play_type == play_type,
                Prediction.period.in_(periods),
            )
        )) if periods else []
        by_source = defaultdict(lambda: defaultdict(list))
        for p, j in pairs:
            by_source[p.source_id][p.period].append((p, j))
        source_rows = list(s.scalars(select(Source).where(Source.lottery == lottery)))
        names = {row.source_id: row.source_name for row in source_rows}
        declared = {row.source_id for row in source_rows if row.play_type == play_type}
        table = []
        for sid in sorted(declared | set(by_source)):
            selected = by_source[sid]
            rec = dict(source_id=sid, source_name=names.get(sid, sid))
            chosen = [
                pair
                for period in periods
                for pair in sorted(selected.get(period, []), key=lambda value: value[0].group_key)
            ]
            rec["dirty_flags"] = sum(bool(j and isinstance(j.hit_detail, dict) and j.hit_detail.get("dirty_source")) for _, j in chosen)
            rec["missing"] = sum(p.claimed_status == "missing" for p, _ in chosen)
            rec["pending"] = sum(j is None for _, j in chosen)
            rec["uncovered"] = sum(period not in selected for period in periods)
            before_hits, after_hits, edits = [], [], 0
            for p, j in chosen:
                evidence = history(s, "prediction", p)
                before = evidence["before_draw_snapshot"]
                if before and p.period in draws:
                    snap = SimpleNamespace(**before["snapshot"])
                    try:
                        result = judge_one(snap, draw_view(draws[p.period]))
                        if result:
                            before_hits.append(result["official_hit"])
                    except (ValueError, TypeError, KeyError):
                        pass
                if evidence["items"] and evidence["items"][0]["phase"] == "after_draw" and j:
                    after_hits.append(j.official_hit)
                edits += sum(e["phase"] == "after_draw" and i > 0 and
                             e["snapshot"].get("preds_json") != evidence["items"][i-1]["snapshot"].get("preds_json") for i, e in enumerate(evidence["items"]))
            rec.update(before_n=len(before_hits), before_rate=sum(before_hits)/len(before_hits) if before_hits else None,
                       after_n=len(after_hits), after_rate=sum(after_hits)/len(after_hits) if after_hits else None, after_edits=edits)
            values = []
            for period in periods:
                period_rows = sorted(selected.get(period, []), key=lambda value: value[0].group_key)
                if not period_rows:
                    values.append(None)
                else:
                    values.extend(j.official_hit if j else None for _, j in period_rows)
            rec.update(streak(values))
            for w in windows:
                chunk = [v for v in values[:w] if v is not None]
                rec[f"n_{w}"] = len(chunk)
                rec[f"hit_{w}"] = round(sum(chunk)/len(chunk), 4) if chunk else None
            table.append(rec)
        table.sort(key=lambda r: (r[f"hit_{windows[0]}"] is None, -(r[f"hit_{windows[0]}"] if r[f"hit_{windows[0]}"] is not None else -1), r["source_id"]))
        return dict(ok=True, lottery=lottery, play_type=play_type, windows=windows, periods=periods,
                    period_from=min(periods) if periods else None, period_to=max(periods) if periods else None, sources=table)
