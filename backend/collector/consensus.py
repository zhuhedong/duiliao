from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from typing import Any

from sqlalchemy import select

from common.hash import sha256_text
from db import session_scope
from schema import JudgeResult, Prediction, Source


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
        if play_type:
            q = q.where(Prediction.play_type == play_type)
        rows = list(s.execute(q).all())
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

        # Atom-level frequency rankings for individual numbers (tema_n) and zodiacs (texiao)
        atom_tallies: dict[str, list[dict[str, Any]]] = {"tema_n": [], "texiao": []}
        for pt in ("tema_n", "texiao"):
            pt_items = groups.get(pt, [])
            a_votes: dict[str, int] = defaultdict(int)
            a_voters: dict[str, list[str]] = defaultdict(list)
            for it in pt_items:
                voter = it["source_id"]
                if it["group_key"]:
                    voter += f"／第{it['group_key']}组"
                seen_vals: set[str] = set()
                for atom in (it.get("preds") or []):
                    val = str(atom.get("value", "")).strip()
                    if pt == "tema_n" and val.isdigit():
                        val = val.zfill(2)
                    if not val or val in seen_vals:
                        continue
                    seen_vals.add(val)
                    a_votes[val] += 1
                    a_voters[val].append(voter)
            sorted_atoms = sorted(a_votes.items(), key=lambda kv: (-kv[1], kv[0]))
            total_sources = len(pt_items)
            atom_tallies[pt] = [
                {
                    "value": val,
                    "kind": "num" if pt == "tema_n" else "xiao",
                    "votes": cnt,
                    "percentage": round(cnt / total_sources * 100, 1) if total_sources > 0 else 0.0,
                    "sources": a_voters[val],
                }
                for val, cnt in sorted_atoms
            ]

        return {"ok": True, "lottery": lottery, "period": period, "groups": out, "atom_tallies": atom_tallies}


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
