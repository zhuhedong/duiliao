from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

from sqlalchemy import delete, select

from common import ROOT
from common.contract import Claimed, PredItem, PredV1, pred_loads, run_loads
from common.hash import sha256_json
from db import session_scope
from schema import CrawlRun, CrawlRunSource, Draw, JudgeResult, Prediction, create_all, seed_sources
from missing_periods import fill_missing
from audit import record, ensure_baseline, now_local
from common.period import _naive


def _split_items(envelope: PredV1, item: PredItem) -> list[tuple[str, PredItem]]:
    """一肖+三码 → two Prediction rows keyed by play_type."""
    kinds = {p.kind for p in item.preds}
    play = envelope.play_type
    if kinds <= {"xiao"} or kinds <= {"num"} or kinds <= {"wei"} or len(kinds) <= 1:
        return [(play, item)]
    out: list[tuple[str, PredItem]] = []
    xiao = [p for p in item.preds if p.kind == "xiao"]
    nums = [p for p in item.preds if p.kind == "num"]
    weis = [p for p in item.preds if p.kind == "wei"]
    rest = [p for p in item.preds if p.kind not in {"xiao", "num", "wei"}]

    def split_claim(kind: str, atoms) -> Claimed:
        claim = item.claimed
        if claim.status != "hit":
            return claim
        observed = claim.xiao if kind == "xiao" else claim.num
        if not observed:
            return claim.model_copy(update={"status": "unknown"})
        try:
            if kind == "num":
                observed = observed.zfill(2)[-2:]
            elif kind == "wei":
                observed = str(int(observed) % 10)
        except (ValueError, TypeError):
            return claim.model_copy(update={"status": "unknown"})
        matched = observed in {atom.value for atom in atoms}
        return claim.model_copy(update={"status": "hit" if matched else "miss"})

    if xiao:
        pt = play if play.startswith("pingte_xiao") or play in {"texiao", "hexiao", "lianxiao_n", "zhengxiao", "buzhong_xiao"} else "pingte_xiao"
        out.append((pt, item.model_copy(update={"preds": xiao, "claimed": split_claim("xiao", xiao)})))
    if nums:
        pt = "tema_n" if play.startswith("tema") else ("zhengma_n" if "zheng" in play else "tema_n")
        out.append((pt, item.model_copy(update={"preds": nums, "claimed": split_claim("num", nums)})))
    if weis:
        pt = "pingte_wei" if "pingte" in play or play.startswith("lianwei") else "tema_wei_n"
        out.append((pt, item.model_copy(update={"preds": weis, "claimed": split_claim("wei", weis)})))
    if rest and not out:
        out.append((play, item))
    return out or [(play, item)]


def _preds_payload(item: PredItem) -> list[dict[str, Any]]:
    return [p.model_dump() for p in item.preds]


def _item_sig(preds: list[dict[str, Any]], item: PredItem) -> str:
    return sha256_json(
        {
            "preds": preds,
            "group_key": item.group_key,
            "claimed": item.claimed.model_dump(),
            "raw_text": item.raw_text,
        }
    )


def auto_judge(s, pred, draw_cache: dict | None = None):
    from judge import draw_view, judge_one, write_deadletter
    if getattr(pred, "id", None) is None:
        s.flush()
    key = (pred.lottery, pred.period)
    if draw_cache is not None and key in draw_cache:
        draw = draw_cache[key]
    else:
        draw = s.scalar(select(Draw).where(Draw.lottery == pred.lottery, Draw.period == pred.period))
        if draw_cache is not None:
            draw_cache[key] = draw
    if draw is None:
        return False
    from rules import archive_current
    archive_current(s, pred.id)
    try:
        result = judge_one(pred, draw_view(draw))
        if result is None:
            raise ValueError("unimplemented_play_type")
    except (ValueError, TypeError, KeyError) as e:
        from issues import report
        s.execute(delete(JudgeResult).where(JudgeResult.prediction_id == pred.id))
        report(s, "judge", str(pred.id), str(e), {"preds": pred.preds_json, "raw_text": pred.raw_text}, prediction_id=pred.id, source_id=pred.source_id, lottery=pred.lottery, period=pred.period)
        write_deadletter(pred.lottery, pred.period, pred, str(e))
        return False
    from rules import save_result
    save_result(s, pred, result, now_local())
    return True


def upsert_prediction(s, envelope: PredV1, item: PredItem, play_type: str, run_id: str, draw_cache: dict | None = None) -> str:
    preds = _preds_payload(item)
    sig = _item_sig(preds, item)
    fetched = _naive(envelope.fetched_at)
    existing = s.scalar(
        select(Prediction).where(
            Prediction.source_id == envelope.source_id,
            Prediction.lottery == envelope.lottery,
            Prediction.play_type == play_type,
            Prediction.period == item.period,
            Prediction.group_key == item.group_key,
        )
    )
    claimed_num = item.claimed.num
    if claimed_num:
        claimed_num = claimed_num.zfill(2)[-2:]
    if existing is None:
        created = Prediction(
                source_id=envelope.source_id,
                lottery=envelope.lottery,
                play_type=play_type,
                hit_mode=envelope.hit_mode,
                period=item.period,
                group_key=item.group_key,
                period_raw=item.period_raw,
                preds_json=preds,
                claimed_status=item.claimed.status,
                claimed_xiao=item.claimed.xiao,
                claimed_num=claimed_num,
                claimed_raw=item.claimed.raw,
                raw_text=item.raw_text[:1024],
                content_hash=envelope.content_hash or sig,
                final_url=envelope.final_url,
                fetched_at=fetched,
                first_seen_at=fetched,
                last_seen_at=fetched,
                last_run_id=run_id,
            )
        s.add(created)
        record(s, created, raw_text=item.raw_text, draw_cache=draw_cache)
        auto_judge(s, created, draw_cache=draw_cache)
        return "inserted"
    ensure_baseline(s, existing)
    old_sig = sha256_json(
        {
            "preds": existing.preds_json,
            "group_key": existing.group_key,
            "claimed": {
                "status": existing.claimed_status,
                "xiao": existing.claimed_xiao,
                "num": existing.claimed_num,
                "raw": existing.claimed_raw,
            },
            "raw_text": existing.raw_text,
        }
    )
    existing.last_seen_at = fetched
    existing.last_run_id = run_id
    if old_sig == sig and existing.hit_mode == envelope.hit_mode:
        auto_judge(s, existing, draw_cache=draw_cache)
        return "unchanged"
    was_missing = existing.claimed_status == "missing"
    from rules import archive_current
    archive_current(s, existing.id)
    s.execute(delete(JudgeResult).where(JudgeResult.prediction_id == existing.id))
    existing.preds_json = preds
    existing.hit_mode = envelope.hit_mode
    existing.period_raw = item.period_raw
    existing.group_key = item.group_key
    existing.claimed_status = item.claimed.status
    existing.claimed_xiao = item.claimed.xiao
    existing.claimed_num = claimed_num
    existing.claimed_raw = item.claimed.raw
    existing.raw_text = item.raw_text[:1024]
    existing.content_hash = envelope.content_hash or sig
    existing.final_url = envelope.final_url
    existing.fetched_at = fetched
    if was_missing:
        existing.first_seen_at = fetched
    record(s, existing, raw_text=item.raw_text, draw_cache=draw_cache)
    auto_judge(s, existing, draw_cache=draw_cache)
    return "updated"


def ingest_run(payload: dict[str, Any]) -> dict[str, Any]:
    run = run_loads(payload)
    counts = {"inserted": 0, "updated": 0, "unchanged": 0, "source_ok": 0, "source_fail": 0, "items": 0, "missing_added": 0}
    draw_cache: dict[tuple[str, str], Any] = {}
    with session_scope() as s:
        s.merge(
            CrawlRun(
                run_id=run.run_id,
                lottery=run.lottery,
                period=run.period,
                run_at=_naive(run.run_at),
                ok=1 if run.ok else 0,
                source_total=len(run.results),
                source_ok=sum(1 for r in run.results if r.ok),
                raw_path=None,
            )
        )
        for r in run.results:
            extra = {}
            if isinstance(payload, dict):
                raw_hit = next(
                    (x for x in payload.get("results") or [] if x.get("source_id") == r.source_id),
                    {},
                )
                extra = raw_hit
            envelope: PredV1 | None = None
            if r.data:
                try:
                    envelope = pred_loads(r.data)
                except Exception:
                    envelope = None
            crs = s.scalar(
                select(CrawlRunSource).where(
                    CrawlRunSource.run_id == run.run_id,
                    CrawlRunSource.source_id == r.source_id,
                )
            )
            crs_fields = dict(
                ok=1 if r.ok else 0,
                exit_code=r.exit_code,
                elapsed_ms=r.elapsed_ms,
                item_count=r.item_count,
                error_code=r.error_code or extra.get("error_code"),
                error_msg=(r.error_msg or extra.get("error_msg") or "")[:512] or None,
                final_url=envelope.final_url if envelope else None,
                content_hash=envelope.content_hash if envelope else None,
                raw_path=extra.get("raw_path"),
                result_json=r.data or ({"raw_output": extra.get("raw_output")} if extra.get("raw_output") else None),
            )
            if crs is None:
                s.add(CrawlRunSource(run_id=run.run_id, source_id=r.source_id, **crs_fields))
            else:
                for k, v in crs_fields.items():
                    setattr(crs, k, v)
            if not r.ok or envelope is None or not envelope.ok or not envelope.items:
                from issues import report
                report(s, "crawl", f"{run.run_id}:{r.source_id}", r.error_msg or r.error_code or "空响应或解析失败", {"data": r.data, "raw_output": extra.get("raw_output"), "raw_path": extra.get("raw_path"), "run_id": run.run_id}, source_id=r.source_id, lottery=envelope.lottery if envelope else run.lottery, period=run.period)
                counts["source_fail"] += 1
                continue
            counts["source_ok"] += 1
            plays = set()
            for item in envelope.items:
                for play_type, split in _split_items(envelope, item):
                    plays.add(play_type)
                    counts["items"] += 1
                    action = upsert_prediction(s, envelope, split, play_type, run.run_id, draw_cache=draw_cache)
                    counts[action] += 1
            for play_type in plays:
                counts["missing_added"] += fill_missing(s, envelope.source_id, envelope.lottery,
                                                       play_type, _naive(envelope.fetched_at), run.run_id)
            from issues import resolve_crawl
            resolve_crawl(s, envelope.source_id, envelope.lottery, {item.period for item in envelope.items})
    return {"ok": True, "run_id": run.run_id, **counts}


def main() -> None:
    p = argparse.ArgumentParser(description="upsert run.v1 into prediction / crawl_*")
    p.add_argument("--in", dest="inp", required=True)
    p.add_argument("--init-db", action="store_true")
    args = p.parse_args()
    create_all()
    if args.init_db:
        seed_sources()
    path = Path(args.inp)
    if not path.is_absolute():
        path = ROOT / path
    payload = json.loads(path.read_text(encoding="utf-8"))
    stats = ingest_run(payload)
    sys.stdout.write(json.dumps(stats, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
