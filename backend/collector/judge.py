from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable

from sqlalchemy import delete, select

from common import ROOT
from common.attr import ball_attrs, bose, pad_num, wei
from common.xiao import num_to_xiao
from db import session_scope
from schema import Draw, JudgeResult, Prediction, create_all

TZ8 = timezone(timedelta(hours=8))
JudgeFn = Callable[[list[dict], str, dict[str, Any]], tuple[bool, dict]]


def _vals(preds: list[dict], kind: str) -> list[str]:
    values = [str(p["value"]).strip() for p in preds if p.get("kind") == kind]
    if kind == "xiao":
        from common.xiao import XIAO_NORM
        values = [XIAO_NORM.get(v, v) for v in values]
    return values


def _nums(preds: list[dict]) -> set[str]:
    return set(_num_list(preds))


def _num_list(preds: list[dict]) -> list[str]:
    out: list[str] = []
    for v in _vals(preds, "num"):
        n = pad_num(v)
        if n not in out:
            out.append(n)
    return out


def _uniq(seq: list[str]) -> list[str]:
    out: list[str] = []
    for x in seq:
        if x not in out:
            out.append(x)
    return out


def draw_view(d: Draw) -> dict[str, Any]:
    z = [pad_num(x) for x in (d.z1, d.z2, d.z3, d.z4, d.z5, d.z6)]
    tema = pad_num(d.tema)
    dd: date = d.draw_date if isinstance(d.draw_date, date) else date.fromisoformat(str(d.draw_date))
    nums_ord = z + [tema]
    zheng = set(z)
    nums = set(nums_ord)
    xiao_ord = _uniq([num_to_xiao(n, dd) for n in nums_ord])
    xiao_zheng_ord = _uniq([num_to_xiao(n, dd) for n in z])
    wei_ord = _uniq([wei(n) for n in nums_ord])
    tema_a = ball_attrs(tema, dd)
    return {
        "z": z,
        "tema": tema,
        "zheng": zheng,
        "nums": nums,
        "xiao_all": set(xiao_ord),
        "xiao_ord": xiao_ord,
        "xiao_zheng": set(xiao_zheng_ord),
        "xiao_zheng_ord": xiao_zheng_ord,
        "wei_all": set(wei_ord),
        "wei_ord": wei_ord,
        "draw_date": dd,
        "tema_attrs": tema_a,
        "sum7": sum(int(n) for n in nums_ord),
        "bose7": [bose(n) for n in nums_ord],
    }


def j_pingte_xiao(preds, mode, ctx):
    pred = _vals(preds, "xiao")
    s = set(pred)
    hit = bool(s & ctx["xiao_all"])
    matched_balls = []
    for index, num in enumerate(ctx["z"] + [ctx["tema"]]):
        xiao = num_to_xiao(num, ctx["draw_date"])
        if xiao in s:
            matched_balls.append({"num": num, "xiao": xiao,
                                  "position": f"z{index + 1}" if index < 6 else "tema"})
    return hit, {"pred": pred, "open": ctx["xiao_ord"],
                 "inter": [x for x in pred if x in ctx["xiao_all"]],
                 "scope": "zheng_and_tema", "tema_xiao": ctx["tema_attrs"]["xiao"],
                 "matched_balls": matched_balls}


def j_pingte_wei(preds, mode, ctx):
    pred = _vals(preds, "wei")
    s = set(pred)
    hit = bool(s & ctx["wei_all"])
    return hit, {"pred": pred, "open": ctx["wei_ord"], "inter": [x for x in pred if x in ctx["wei_all"]]}


def j_lianxiao(preds, mode, ctx):
    pred = _vals(preds, "xiao")
    s = set(pred)
    hit = bool(s) and s <= ctx["xiao_all"]
    return hit, {"pred": pred, "open": ctx["xiao_ord"]}


def j_lianwei(preds, mode, ctx):
    pred = _vals(preds, "wei")
    s = set(pred)
    hit = bool(s) and s <= ctx["wei_all"]
    return hit, {"pred": pred, "open": ctx["wei_ord"]}


def j_tema_n(preds, mode, ctx):
    pred = _num_list(preds)
    hit = ctx["tema"] in set(pred)
    return hit, {"pred": pred, "tema": ctx["tema"]}


def j_texiao(preds, mode, ctx):
    pred = _vals(preds, "xiao")
    hit = ctx["tema_attrs"]["xiao"] in set(pred)
    return hit, {"pred": pred, "tema_xiao": ctx["tema_attrs"]["xiao"]}


def j_tema_wei(preds, mode, ctx):
    pred = _vals(preds, "wei")
    hit = ctx["tema_attrs"]["wei"] in set(pred)
    return hit, {"pred": pred, "tema_wei": ctx["tema_attrs"]["wei"]}


def j_tema_head(preds, mode, ctx):
    pred = _vals(preds, "head")
    hit = ctx["tema_attrs"]["head"] in set(pred)
    return hit, {"pred": pred, "tema_head": ctx["tema_attrs"]["head"]}


def j_tema_bose(preds, mode, ctx):
    raw = _vals(preds, "bose")
    s = {v.replace("波", "") for v in raw}
    hit = ctx["tema_attrs"]["bose"] in s
    return hit, {"pred": raw, "tema_bose": ctx["tema_attrs"]["bose"]}


def j_tema_twoface(preds, mode, ctx):
    a = ctx["tema_attrs"]
    details = []
    hit_any = False
    hit_all = True
    for p in preds:
        k, v = p.get("kind"), str(p.get("value"))
        if v in {"合单", "合双", "合單", "合雙"}:
            raise ValueError("合单双玩法已移除")
        ok = False
        if k == "size":
            ok = v == a["size"]
        elif k == "odd":
            ok = v == a["odd"]
        elif k in {"gender"} or v in {"男", "女", "男肖", "女肖"}:
            ok = (v[0] == a.get("gender", "")[:1])
        elif k in {"tian_di"} or v in {"天", "地", "天肖", "地肖"}:
            ok = (v[0] == a.get("tian_di", "")[:1])
        elif k in {"yin_yang"} or v in {"阳", "阴", "阳肖", "阴肖"}:
            ok = (v[0] == a.get("yin_yang", "")[:1])
        elif k in {"luck"} or v in {"吉", "凶", "吉肖", "凶肖"}:
            ok = (v[0] == a.get("luck", "")[:1])
        elif k in {"xiao"} and v in {"家", "野", "家禽", "野兽", "家肖", "野肖"}:
            ok = (v[0] == a["jiaye"])
        elif k == "xiao":
            ok = v == a["jiaye"] or v == a["xiao"]
        else:
            # Only supported two-face attributes are size, odd/even, xiao classifications.
            raise ValueError(f"unsupported twoface atom: {k}={v}")
        details.append({"kind": k, "value": v, "hit": ok})
        hit_any = hit_any or ok
        hit_all = hit_all and ok
    if mode == "all":
        return hit_all, {"checks": details}
    return hit_any, {"checks": details}


def j_tema_halfwave(preds, mode, ctx):
    a = ctx["tema_attrs"]
    targets = {a["halfwave"], a["halfhalf"], a["bose"] + a["odd"]}
    vals = [str(p.get("value")) for p in preds]
    hit = any(v in targets or v == a["halfwave"] or v == a["halfhalf"] for v in vals)
    return hit, {"pred": vals, "tema": {"halfwave": a["halfwave"], "halfhalf": a["halfhalf"]}}


def j_hexiao(preds, mode, ctx):
    return j_texiao(preds, mode, ctx)


def j_zhengma(preds, mode, ctx):
    pred = _num_list(preds)
    s = set(pred)
    inter = [n for n in ctx["z"] if n in s]
    if mode == "all":
        hit = bool(s) and s <= ctx["zheng"]
    else:
        hit = bool(inter)
    return hit, {"pred": pred, "inter": inter}


def j_zhengxiao(preds, mode, ctx):
    pred = _vals(preds, "xiao")
    s = set(pred)
    hit = bool(s & ctx["xiao_zheng"])
    return hit, {"pred": pred, "open": ctx["xiao_zheng_ord"]}


def j_lianma_all(preds, mode, ctx, count):
    from common.contract import validate_regular_combo
    validate_regular_combo(preds, count, mode)
    pred = _num_list(preds)
    inter = [n for n in pred if n in ctx["zheng"]]
    return len(inter) == count, {"pred": pred, "zheng": ctx["z"], "inter": inter,
                                "required": count, "scope": "zheng_only"}


def j_lianma_2all(preds, mode, ctx):
    return j_lianma_all(preds, mode, ctx, 2)


def j_lianma_3all(preds, mode, ctx):
    return j_lianma_all(preds, mode, ctx, 3)


def j_lianma_3z2(preds, mode, ctx):
    pred = _num_list(preds)
    s = set(pred)
    zhit = [n for n in ctx["z"] if n in s]
    t = ctx["tema"] in s
    hit = len(zhit) >= 2
    return hit, {"pred": pred, "zheng_hit": zhit, "tema_hit": t}


def j_lianma_2zt(preds, mode, ctx):
    pred = _num_list(preds)
    s = set(pred)
    zhit = [n for n in ctx["z"] if n in s]
    t = ctx["tema"] in s
    hit = len(zhit) == 1 and t
    return hit, {"pred": pred, "zheng_hit": zhit, "tema_hit": t}


def j_buzhong_num(preds, mode, ctx):
    pred = _num_list(preds)
    s = set(pred)
    hit = not bool(s & ctx["nums"])
    return hit, {"pred": pred, "inter": [n for n in ctx["z"] + [ctx["tema"]] if n in s]}


def j_buzhong_xiao(preds, mode, ctx):
    pred = _vals(preds, "xiao")
    s = set(pred)
    hit = not bool(s & ctx["xiao_all"])
    return hit, {"pred": pred, "inter": [x for x in pred if x in ctx["xiao_all"]]}


def j_buzhong_wei(preds, mode, ctx):
    pred = _vals(preds, "wei")
    s = set(pred)
    hit = not bool(s & ctx["wei_all"])
    return hit, {"pred": pred, "inter": [x for x in pred if x in ctx["wei_all"]]}


JUDGES: dict[str, JudgeFn] = {
    "pingte_xiao": j_pingte_xiao,
    "pingte_wei": j_pingte_wei,
    "lianxiao_n": j_lianxiao,
    "lianwei_n": j_lianwei,
    "tema_n": j_tema_n,
    "texiao": j_texiao,
    "tema_wei_n": j_tema_wei,
    "tema_head_n": j_tema_head,
    "tema_bose": j_tema_bose,
    "tema_twoface": j_tema_twoface,
    "tema_halfwave": j_tema_halfwave,
    "hexiao": j_hexiao,
    "zhengma_n": j_zhengma,
    "zhengxiao": j_zhengxiao,
    "lianma_2all": j_lianma_2all,
    "lianma_3all": j_lianma_3all,
    "lianma_3z2": j_lianma_3z2,
    "lianma_2zt": j_lianma_2zt,
    "buzhong_num": j_buzhong_num,
    "buzhong_xiao": j_buzhong_xiao,
    "buzhong_wei": j_buzhong_wei,
}


def claimed_to_hit(status: str) -> int | None:
    if status == "hit":
        return 1
    if status == "miss":
        return 0
    return None


def apply_hit_mode(play_type: str, hit: bool, mode: str) -> bool:
    """Apply hit_mode logic on the raw judge result.

    - 'any'  → any-match (default; judge functions already produce any-match)
    - 'all'  → all-match (judge functions that support it branch internally)
    - 'none' → raw judge result stands unchanged (no mode adjustment)
    - buzhong play types handle inversion in their j_* functions already.
    """
    # All modes are handled inside the individual j_* functions that need
    # them (e.g. j_tema_twoface and j_zhengma branch on mode=='all').
    # This function is the single authoritative post-processing hook.
    return hit


def judge_one(pred: Prediction, ctx: dict[str, Any]) -> dict[str, Any] | None:
    if pred.claimed_status == "missing":
        from missing_periods import missing_result
        return missing_result(pred)
    fn = JUDGES.get(pred.play_type)
    if fn is None:
        return None
    preds = pred.preds_json if isinstance(pred.preds_json, list) else json.loads(pred.preds_json)
    from rules import validate, evidence
    validate(pred.play_type, preds, pred.hit_mode)
    hit, detail = fn(preds, pred.hit_mode, ctx)
    detail = evidence(pred, ctx, detail, hit)
    hit = apply_hit_mode(pred.play_type, hit, pred.hit_mode)
    ch = claimed_to_hit(pred.claimed_status)
    dirty = ch is not None and int(ch) != int(hit)
    return {
        "prediction_id": pred.id,
        "source_id": pred.source_id,
        "lottery": pred.lottery,
        "play_type": pred.play_type,
        "period": pred.period,
        "official_hit": 1 if hit else 0,
        "claimed_hit": ch,
        "hit_detail": {**detail, "dirty_source": dirty, "hit_mode": pred.hit_mode, "n": len(preds)},
    }


def write_deadletter(lottery: str, period: str, pred: Prediction, reason: str) -> str:
    d = ROOT / "out" / "deadletter"
    d.mkdir(parents=True, exist_ok=True)
    path = d / f"{lottery}_{period}_{pred.source_id}_{pred.id or 0}.json"
    path.write_text(
        json.dumps(
            {
                "reason": reason,
                "play_type": pred.play_type,
                "source_id": pred.source_id,
                "period": pred.period,
                "preds_json": pred.preds_json,
                "raw_text": pred.raw_text,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return str(path.relative_to(ROOT)).replace("\\", "/")


def run_judge(lottery: str, period: str) -> dict[str, Any]:
    now = datetime.now(TZ8).replace(tzinfo=None)
    dead: list[str] = []
    judged = 0
    hits = 0
    dirty = 0
    with session_scope() as s:
        draw = s.scalar(select(Draw).where(Draw.lottery == lottery, Draw.period == period))
        if draw is None:
            raise ValueError(f"no draw for {lottery} {period}")
        ctx = draw_view(draw)
        preds = list(
            s.scalars(select(Prediction).where(Prediction.lottery == lottery, Prediction.period == period))
        )
        for pred in preds:
            from rules import archive_current
            archive_current(s, pred.id)
            try:
                row = judge_one(pred, ctx)
            except (ValueError, TypeError, KeyError) as e:
                s.execute(delete(JudgeResult).where(JudgeResult.prediction_id == pred.id))
                from issues import report
                report(s, "judge", str(pred.id), str(e), {"preds": pred.preds_json, "raw_text": pred.raw_text}, prediction_id=pred.id, source_id=pred.source_id, lottery=lottery, period=period)
                dead.append(write_deadletter(lottery, period, pred, f"invalid_prediction: {e}"))
                continue
            if row is None:
                from issues import report
                s.execute(delete(JudgeResult).where(JudgeResult.prediction_id == pred.id))
                report(s, "judge", str(pred.id), "未支持的玩法", {"preds": pred.preds_json}, prediction_id=pred.id, source_id=pred.source_id, lottery=lottery, period=period)
                dead.append(write_deadletter(lottery, period, pred, "unimplemented_play_type"))
                continue
            from rules import save_result
            save_result(s, pred, row, now)
            judged += 1
            hits += row["official_hit"]
            if row["hit_detail"].get("dirty_source"):
                dirty += 1
    return {
        "ok": True,
        "lottery": lottery,
        "period": period,
        "judged": judged,
        "hits": hits,
        "dirty_claimed": dirty,
        "deadletter": dead,
    }


def main() -> None:
    p = argparse.ArgumentParser(description="official judge for a lottery+period")
    p.add_argument("--lottery", required=True, choices=["hk", "macau", "taiwan", "new"])
    p.add_argument("--period", required=True)
    p.add_argument("--init-db", action="store_true")
    args = p.parse_args()
    if args.init_db:
        create_all()
    from common.period import normalize

    period = normalize(args.lottery, args.period)
    stats = run_judge(args.lottery, period)
    sys.stdout.write(json.dumps(stats, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
