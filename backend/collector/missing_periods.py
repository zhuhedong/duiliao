"""Internal gap records: missing source content counts as a miss, never a vote."""
from collections import defaultdict
from datetime import datetime

from sqlalchemy import select

from schema import Draw, JudgeResult, Prediction


def missing_result(pred: Prediction) -> dict:
    from rules import VERSION
    return dict(prediction_id=pred.id, source_id=pred.source_id, lottery=pred.lottery,
                play_type=pred.play_type, period=pred.period, official_hit=0, claimed_hit=None,
                hit_detail={"missing_period": True, "reason": "已确认缺少该期预测，按挂计入统计", "rule_version": VERSION,
                            "explanation": "已确认缺期，按缺期默认挂规则计入统计，不作为来源自称错误。",
                            "dirty_source": False, "n": 0})


def fill_missing(s, source_id: str, lottery: str, play_type: str, now: datetime, run_id: str) -> int:
    s.flush()
    rows = s.scalars(select(Prediction).where(
        Prediction.source_id == source_id, Prediction.lottery == lottery, Prediction.play_type == play_type
    )).all()
    real = [r for r in rows if r.claimed_status != "missing" and len(r.period) == 7 and r.period.isdigit()]
    if len(real) < 2:
        return 0
    existing = {r.period for r in rows}
    by_year = defaultdict(list)
    for row in real:
        by_year[row.period[:4]].append(int(row.period[4:]))
    expected = set()
    for year, seqs in by_year.items():
        expected.update(f"{year}{n:03d}" for n in range(min(seqs), max(seqs) + 1))
    # Across year boundaries only use known draw periods; never invent 367..999.
    lower, upper = min(r.period for r in real), max(r.period for r in real)
    expected.update(s.scalars(select(Draw.period).where(
        Draw.lottery == lottery, Draw.period > lower, Draw.period < upper
    )).all())
    template = max(real, key=lambda r: r.period)
    added = 0
    for period in sorted(expected - existing):
        pred = Prediction(source_id=source_id, lottery=lottery, play_type=play_type,
                          hit_mode=template.hit_mode, period=period, period_raw=str(int(period[4:])),
                          preds_json=[], claimed_status="missing", raw_text="缺期：覆盖范围内未采集到该期预测",
                          content_hash="missing_period", final_url=None, fetched_at=now,
                          first_seen_at=now, last_seen_at=now, last_run_id=run_id)
        s.add(pred)
        s.flush()
        s.add(JudgeResult(**missing_result(pred), judged_at=now))
        added += 1
    return added
