from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from common.hash import sha256_json, sha256_text
from common.xiao import XIAO, XIAO_NORM
from db import session_scope
from schema import AuditEvent, ConsensusSnapshot, Draw, Prediction, Source


FREQUENCY_ALGORITHM_VERSION = "frequency-v1"


def _naive_datetime(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is not None:
        return value.astimezone(timezone(timedelta(hours=8))).replace(tzinfo=None)
    return value


def _draw_quality(s, draw: Draw) -> str:
    """Classify whether the draw has a trustworthy first-observed boundary."""
    if draw.opened_at:
        return "exact"
    first_event = s.scalar(
        select(AuditEvent)
        .where(
            AuditEvent.entity == "draw",
            AuditEvent.entity_id == draw.id,
            AuditEvent.phase == "created",
        )
        .order_by(AuditEvent.id.asc())
        .limit(1)
    )
    if first_event and first_event.recorded_at:
        return "exact"
    # Imported legacy draws can lack an audit row, so disclose approximate
    # provenance even though the ranking itself is frozen at capture time.
    return "approximate"


def _prediction_versions(s, lottery: str, period: str, cutoff: datetime | None) -> list[dict[str, Any]]:
    """Read prediction versions as of ``cutoff`` (not today's mutable rows)."""
    rows = list(
        s.execute(
            select(Prediction, Source)
            .outerjoin(Source, Source.source_id == Prediction.source_id)
            .where(Prediction.lottery == lottery, Prediction.period == period)
        ).all()
    )
    if not rows:
        return []

    events_by_prediction: dict[int, list[AuditEvent]] = defaultdict(list)
    if cutoff is not None:
        ids = [pred.id for pred, _ in rows]
        if ids:
            events = s.scalars(
                select(AuditEvent)
                .where(
                    AuditEvent.entity == "prediction",
                    AuditEvent.entity_id.in_(ids),
                    AuditEvent.recorded_at <= cutoff,
                )
                .order_by(AuditEvent.id.asc())
            )
            for event in events:
                events_by_prediction[event.entity_id].append(event)

    out: list[dict[str, Any]] = []
    for pred, source in rows:
        data: dict[str, Any]
        if cutoff is not None and events_by_prediction.get(pred.id):
            data = dict(events_by_prediction[pred.id][-1].snapshot or {})
        else:
            first_seen = _naive_datetime(pred.first_seen_at)
            if cutoff is not None and first_seen and first_seen > cutoff:
                continue
            data = {
                "source_id": pred.source_id,
                "play_type": pred.play_type,
                "group_key": pred.group_key,
                "preds_json": pred.preds_json,
                "claimed_status": pred.claimed_status,
            }
        if data.get("claimed_status") == "missing":
            continue
        out.append(
            {
                "source_id": str(data.get("source_id") or pred.source_id),
                "source_name": source.source_name if source else str(data.get("source_id") or pred.source_id),
                "play_type": str(data.get("play_type") or pred.play_type),
                "group_key": str(data.get("group_key") or ""),
                "preds": data.get("preds_json") or [],
            }
        )
    return out


def _frequency_payload(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Build the exact source+group frequency semantics used by the UI."""
    result: dict[str, list[dict[str, Any]]] = {"tema_n": [], "texiao": []}
    totals: dict[str, int] = {"tema_n": 0, "texiao": 0}
    for play_type in ("tema_n", "texiao"):
        selected = [r for r in rows if r["play_type"] in ({"tema_n", "特码"} if play_type == "tema_n" else {"texiao", "特肖"})]
        voters: dict[tuple[str, str], dict[str, Any]] = {}
        values: dict[str, dict[str, Any]] = defaultdict(lambda: {"votes": 0, "sources": []})
        for row in selected:
            voter_key = (row["source_id"], row.get("group_key") or "")
            voter = voters.setdefault(
                voter_key,
                {"id": row["source_id"], "name": row["source_name"], "group_key": row.get("group_key") or ""},
            )
            seen: set[str] = set()
            for atom in row.get("preds") or []:
                if not isinstance(atom, dict):
                    continue
                value = str(atom.get("value") or "").strip()
                if play_type == "tema_n":
                    if not value.isdigit():
                        continue
                    try:
                        number = int(value)
                    except ValueError:
                        continue
                    if not 1 <= number <= 49:
                        continue
                    value = f"{number:02d}"
                else:
                    value = XIAO_NORM.get(value, value)
                    if value not in XIAO:
                        continue
                if not value or value in seen:
                    continue
                seen.add(value)
                values[value]["votes"] += 1
                values[value]["sources"].append(dict(voter))
        totals[play_type] = len(voters)
        ordered = sorted(
            values.items(),
            key=lambda pair: (-int(pair[1]["votes"]), int(pair[0]) if play_type == "tema_n" else XIAO.index(pair[0])),
        )
        result[play_type] = [
            {
                "value": value,
                "kind": "num" if play_type == "tema_n" else "xiao",
                "votes": int(data["votes"]),
                "percentage": round(int(data["votes"]) / len(voters) * 100, 1) if voters else 0.0,
                "sources": data["sources"],
            }
            for value, data in ordered
        ]

    atom_tallies = {
        key: [
            {
                **item,
                "sources": [
                    f"{source['name']}／第{source['group_key']}组" if source.get("group_key") else source["name"]
                    for source in item["sources"]
                ],
            }
            for item in items
        ]
        for key, items in result.items()
    }
    return {
        "policy": {
            "count_unit": "source_group",
            "denominator": "eligible_source_groups",
            "excluded_claimed_status": ["missing"],
        },
        "totals": {"tema_n": totals["tema_n"], "texiao": totals["texiao"]},
        "tema_n": result["tema_n"],
        "texiao": result["texiao"],
        "atom_tallies": atom_tallies,
    }


def freeze_frequency_snapshot(
    lottery: str,
    period: str,
    *,
    reason: str = "draw_sync",
    force: bool = False,
) -> dict[str, Any] | None:
    """Persist one immutable period ranking after an official draw exists.

    Normal calls are idempotent. ``force`` is reserved for the explicit staff
    backfill endpoint and is the only path allowed to replace a row. Concurrent
    automatic calls are also safe: the losing writer rereads the row instead of
    turning a successful ingest into a failure.
    """
    def _read_existing(s):
        existing = s.get(ConsensusSnapshot, (lottery, period))
        if existing is None:
            return None
        return {
            "frozen": True,
            "frozen_at": existing.frozen_at.isoformat() if existing.frozen_at else None,
            "cutoff_at": existing.cutoff_at.isoformat() if existing.cutoff_at else None,
            "algorithm_version": existing.algorithm_version,
            "payload_hash": existing.payload_hash,
            "quality": existing.quality,
            "freeze_reason": existing.freeze_reason,
        }

    try:
        with session_scope() as s:
            draw = s.scalar(select(Draw).where(Draw.lottery == lottery, Draw.period == period))
            if draw is None:
                return None
            existing = s.get(ConsensusSnapshot, (lottery, period))
            existing_result = _read_existing(s)
            if existing_result is not None and not force:
                return existing_result
            # Freeze the ranking at the first successful post-draw capture. The
            # opening time is useful quality metadata, but using it as the row
            # cutoff would incorrectly discard sources that were collected in the
            # short window after the draw and before this snapshot was created.
            cutoff = datetime.now()
            quality = _draw_quality(s, draw)
            rows = _prediction_versions(s, lottery, period, None)
            payload = _frequency_payload(rows)
            has_board_data = bool(payload["tema_n"] or payload["texiao"])
            if not has_board_data and not force:
                return None
            payload_hash = sha256_json(payload)
            now = datetime.now()
            values = {
                "cutoff_at": cutoff,
                "frozen_at": now,
                "algorithm_version": FREQUENCY_ALGORITHM_VERSION,
                "payload_hash": payload_hash,
                "payload": payload,
                "quality": quality,
                "freeze_reason": reason,
            }
            if existing is None:
                s.add(ConsensusSnapshot(lottery=lottery, period=period, **values))
            else:
                for key, value in values.items():
                    setattr(existing, key, value)
            return {
                "frozen": True,
                "frozen_at": now.isoformat(),
                "cutoff_at": cutoff.isoformat(),
                "algorithm_version": FREQUENCY_ALGORITHM_VERSION,
                "payload_hash": payload_hash,
                "quality": quality,
                "freeze_reason": reason,
            }
    except IntegrityError:
        if force:
            raise
        with session_scope() as s:
            return _read_existing(s)


def _norm_text(s: str) -> str:
    t = re.sub(r"\s+", "", s or "")
    t = re.sub(r"[【】\[\]:：]", "", t)
    return t


def compare(lottery: str, period: str, play_type: str | None) -> dict[str, Any]:
    with session_scope() as s:
        q = select(Prediction, Source).outerjoin(Source, Source.source_id == Prediction.source_id).where(
            Prediction.lottery == lottery,
            Prediction.period == period,
            Prediction.claimed_status != "missing",
        )
        all_rows = list(s.execute(q).all())
        rows = [
            (pred, src)
            for pred, src in all_rows
            if not play_type or pred.play_type == play_type
        ]
        groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for pred, src in rows:
            groups[pred.play_type].append(
                {
                    "source_id": pred.source_id,
                    "group_key": pred.group_key,
                    "site_family": src.site_family if src else pred.source_id,
                    "raw_text": pred.raw_text,
                    "preds": pred.preds_json,
                    "claimed_status": pred.claimed_status,
                }
            )
        out = []
        for pt, items in groups.items():
            # one vote per site_family or near-identical raw_text
            seen_fp: set[tuple[str, str]] = set()
            votes: dict[str, int] = defaultdict(int)
            voters: dict[str, list[str]] = defaultdict(list)
            for it in items:
                key = json.dumps(it["preds"], ensure_ascii=False, sort_keys=True)
                txt = sha256_text(_norm_text(it["raw_text"]))[:12]
                fam = it["site_family"]
                # 同家族 + 近文只算 1 票（跳板镜像）；不同栏目仍分开投
                fp = (fam, txt)
                if fp in seen_fp:
                    continue
                seen_fp.add(fp)
                votes[key] += 1
                voter = it["source_id"]
                if it["group_key"]:
                    voter += f"／第{it['group_key']}组"
                voters[key].append(voter)
            ranked = sorted(votes.items(), key=lambda kv: (-kv[1], kv[0]))
            out.append(
                {
                    "play_type": pt,
                    "n_sources": len(items),
                    "n_votes": sum(votes.values()),
                    "leader": json.loads(ranked[0][0]) if ranked else None,
                    "leader_votes": ranked[0][1] if ranked else 0,
                    "tally": [
                        {"preds": json.loads(k), "votes": v, "sources": voters[k]} for k, v in ranked
                    ],
                }
            )

        # Keep live atom tallies on the same source+group voter semantics as the
        # frozen frequency board. This prevents the latest period from changing
        # counting rules when it transitions into a snapshot.
        frequency = _frequency_payload(
            [
                {
                    "source_id": pred.source_id,
                    "source_name": src.source_name if src else pred.source_id,
                    "play_type": pred.play_type,
                    "group_key": pred.group_key,
                    "preds": pred.preds_json,
                }
                for pred, src in all_rows
            ]
        )
        return {
            "ok": True,
            "lottery": lottery,
            "period": period,
            "groups": out,
            "atom_tallies": frequency["atom_tallies"],
            "frequency": frequency,
        }


def rate_sources(lottery: str, play_type: str, windows: tuple[int, ...] = (30, 50, 100)) -> dict[str, Any]:
    from analytics import ratings
    return ratings(lottery, play_type, windows)


def main() -> None:
    p = argparse.ArgumentParser(description="对照 / 共识投票 / 源评级（读模型）")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("compare")
    c.add_argument("--lottery", required=True)
    c.add_argument("--period", required=True)
    c.add_argument("--play-type", default=None)
    r = sub.add_parser("rate")
    r.add_argument("--lottery", required=True)
    r.add_argument("--play-type", required=True)
    args = p.parse_args()
    if args.cmd == "compare":
        from common.period import normalize

        period = normalize(args.lottery, args.period)
        out = compare(args.lottery, period, args.play_type)
    else:
        out = rate_sources(args.lottery, args.play_type)
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
