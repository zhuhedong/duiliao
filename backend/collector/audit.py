"""Append-only observed versions. Legacy data is never claimed as pre-draw evidence."""
from datetime import date, datetime, timedelta, timezone
from sqlalchemy import exists, select
from schema import AuditEvent, Draw, Prediction


def now_local():
    return datetime.now(timezone(timedelta(hours=8))).replace(tzinfo=None)


def snapshot(row):
    return {c.name: (getattr(row, c.name).isoformat() if isinstance(getattr(row, c.name), (datetime, date)) else getattr(row, c.name))
            for c in row.__table__.columns}


def record(s, row, phase=None, raw_text=None):
    if getattr(row, "id", None) is None:
        s.flush()
    now = now_local()
    entity = "draw" if isinstance(row, Draw) else "prediction"
    if phase is None:
        draw = s.scalar(select(Draw).where(Draw.lottery == row.lottery, Draw.period == row.period))
        phase = "after_draw" if draw else "unconfirmed"
    data = snapshot(row)
    if raw_text is not None:
        data["raw_text"] = raw_text
    s.add(AuditEvent(entity=entity, entity_id=row.id, recorded_at=now,
                     phase=phase, snapshot=data))


def ensure_baseline(s, row):
    entity = "draw" if isinstance(row, Draw) else "prediction"
    if s.scalar(select(AuditEvent.id).where(AuditEvent.entity == entity, AuditEvent.entity_id == row.id).limit(1)) is None:
        record(s, row, "legacy")


def history(s, entity, row):
    events = s.scalars(select(AuditEvent).where(AuditEvent.entity == entity, AuditEvent.entity_id == row.id).order_by(AuditEvent.id)).all()
    draw = row if entity == "draw" else s.scalar(select(Draw).where(Draw.lottery == row.lottery, Draw.period == row.period))
    # The first recorded draw fixes the cutoff; later corrections cannot rewrite evidence.
    first_draw = s.scalar(select(AuditEvent).where(AuditEvent.entity == "draw", AuditEvent.entity_id == draw.id).order_by(AuditEvent.id)) if draw else None
    cutoff_date = date.fromisoformat(first_draw.snapshot["draw_date"]) if first_draw else (draw.draw_date if draw else None)
    raw_time = first_draw.snapshot.get("opened_at") if first_draw else (draw.opened_at.isoformat() if draw and draw.opened_at else None)
    cutoff_time = datetime.fromisoformat(raw_time) if raw_time else None
    items = []
    for event in events:
        phase = event.phase
        if entity == "prediction" and phase == "unconfirmed" and draw:
            # We only know the calendar day, not the precise opening time.
            if cutoff_time:
                phase = "before_draw" if event.recorded_at < cutoff_time else "after_draw"
            else:
                phase = "before_draw" if event.recorded_at.date() < cutoff_date else ("after_draw" if event.recorded_at.date() > cutoff_date else "same_day_unknown")
        items.append(dict(id=event.id, recorded_at=event.recorded_at.isoformat(), phase=phase, snapshot=event.snapshot))
    before = [x for x in items if x["phase"] == "before_draw" and x["snapshot"].get("claimed_status") != "missing"]
    return {"items": items, "before_draw_snapshot": before[-1] if before else None}


def backfill():
    from db import session_scope
    with session_scope() as s:
        for model in (Prediction, Draw):
            entity = "draw" if model is Draw else "prediction"
            last_id = 0
            while True:
                missing = (
                    select(model)
                    .where(
                        model.id > last_id,
                        ~exists(select(AuditEvent.id).where(
                            AuditEvent.entity == entity, AuditEvent.entity_id == model.id
                        )),
                    )
                    .order_by(model.id)
                    .limit(500)
                )
                rows = list(s.scalars(missing))
                if not rows:
                    break
                for row in rows:
                    record(s, row, "legacy")
                last_id = rows[-1].id
                s.flush()
