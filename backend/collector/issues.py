import hashlib
from sqlalchemy import select
from audit import now_local, snapshot
from schema import AuditEvent, Issue


def log_change(s, issue, action):
    s.flush()
    s.add(AuditEvent(entity="issue", entity_id=issue.id, recorded_at=now_local(), phase=action, snapshot=snapshot(issue)))


def report(s, stage, identity, reason, payload=None, **fields):
    key = hashlib.sha256(f"{stage}:{identity}".encode()).hexdigest()
    row = s.scalar(select(Issue).where(Issue.key == key))
    if row is None:
        row = Issue(key=key, stage=stage, reason=str(reason)[:2000], payload=payload or {}, created_at=now_local(), updated_at=now_local(), **fields)
        s.add(row)
    else:
        row.reason = str(reason)[:2000]
        row.payload = payload or row.payload
        row.status = "open"
        row.occurrences += 1
        row.updated_at = now_local()
    log_change(s, row, "reported")
    return row


def resolve_judge(s, prediction_id):
    for row in s.scalars(select(Issue).where(Issue.stage == "judge", Issue.prediction_id == prediction_id, Issue.status != "resolved")):
        row.status = "resolved"
        row.note = "重新对奖成功，自动关闭"
        row.updated_at = now_local()
        log_change(s, row, "resolved")


def resolve_crawl(s, source_id, lottery, periods):
    for row in s.scalars(select(Issue).where(Issue.stage == "crawl", Issue.source_id == source_id,
                         Issue.lottery == lottery, Issue.status == "open")):
        if row.period is None or row.period in periods:
            row.status = "resolved"
            row.note = "后续采集成功，资料已入库"
            row.updated_at = now_local()
            log_change(s, row, "resolved")


def import_legacy():
    from db import session_scope
    from schema import CrawlRunSource, CrawlRun
    with session_scope() as s:
        for r, run in s.execute(select(CrawlRunSource, CrawlRun).join(CrawlRun, CrawlRun.run_id == CrawlRunSource.run_id).where(CrawlRunSource.ok == 0)):
            identity = f"{r.run_id}:{r.source_id}"
            key = hashlib.sha256(f"crawl:{identity}".encode()).hexdigest()
            if s.scalar(select(Issue.id).where(Issue.key == key)) is None:
                report(s, "crawl", identity, r.error_msg or r.error_code or "历史采集失败", {"run_id": r.run_id, "raw_path": r.raw_path}, source_id=r.source_id, lottery=run.lottery, period=run.period)
        import json
        from common import ROOT
        from schema import Prediction
        for path in (ROOT / "out" / "deadletter").glob("*.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                pred_id = int(path.stem.rsplit("_", 1)[-1])
                pred = s.get(Prediction, pred_id)
                if not pred or (pred.source_id, pred.period, pred.preds_json) != (data.get("source_id"), data.get("period"), data.get("preds_json")):
                    continue
                # Fixed or unrelated old files must not reopen current successful judgments.
                from schema import JudgeResult
                if s.scalar(select(JudgeResult.id).where(JudgeResult.prediction_id == pred.id)):
                    continue
                key = hashlib.sha256(f"judge:{pred.id}".encode()).hexdigest()
                if s.scalar(select(Issue.id).where(Issue.key == key)) is None:
                    report(s, "judge", str(pred.id), data.get("reason", "历史对奖异常"), data,
                           source_id=pred.source_id, lottery=pred.lottery, period=pred.period, prediction_id=pred.id)
            except (OSError, ValueError, TypeError):
                continue
