from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.period import normalize, year_of
from common.source_base import emit, fail, now_cn, parse_common_args

SOURCE_ID = "ai_expert_10m5x"
SOURCE_NAME = "AI智能研判十码五肖"
SITE_FAMILY = "ai_forecast"
PLAY_TYPE = "texiao"
HIT_MODE = "any"

VALID_ZODIACS = {"鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"}


def _load_from_snapshot(lottery: str, period: str | None) -> dict | None:
    snapshot_dir = ROOT / "data" / "ai_predictions"
    if not snapshot_dir.exists():
        return None

    # 1. Try exact period file if period specified
    if period:
        p_norm = normalize(lottery, period)
        p_file = snapshot_dir / f"{lottery}_{p_norm}.json"
        if p_file.exists():
            try:
                return json.loads(p_file.read_text(encoding="utf-8"))
            except Exception:
                pass

    # 2. Try latest snapshot file
    latest_file = snapshot_dir / f"latest_{SOURCE_ID}.json"
    if latest_file.exists():
        try:
            data = json.loads(latest_file.read_text(encoding="utf-8"))
            if period:
                p_norm = normalize(lottery, period)
                if data.get("period") == p_norm or str(data.get("period", "")).endswith(str(period)):
                    return data
            else:
                return data
        except Exception:
            pass

    return None


def _load_from_db(lottery: str, period: str | None) -> dict | None:
    try:
        from db import session_scope
        from schema import Prediction
        from sqlalchemy import select

        p_norm = normalize(lottery, period) if period else None
        with session_scope() as s:
            query = select(Prediction).where(
                Prediction.source_id == SOURCE_ID,
                Prediction.lottery == lottery,
            )
            if p_norm:
                query = query.where(Prediction.period == p_norm)
            query = query.order_by(Prediction.period.desc()).limit(10)
            rows = s.scalars(query).all()
            if not rows:
                return None

            # Group rows by period
            latest_per = rows[0].period
            matching_rows = [r for r in rows if r.period == latest_per]
            xiao_list: list[str] = []
            num_list: list[str] = []
            raw_text = matching_rows[0].raw_text or ""

            for r in matching_rows:
                preds = r.preds_json or []
                for p in preds:
                    kind = p.get("kind")
                    val = str(p.get("value", "")).strip()
                    if kind == "xiao" and val in VALID_ZODIACS and val not in xiao_list:
                        xiao_list.append(val)
                    elif kind == "num" and val and val not in num_list:
                        num_list.append(val.zfill(2)[-2:])

            if not xiao_list and not num_list:
                return None

            return {
                "period": latest_per,
                "period_raw": matching_rows[0].period_raw or latest_per[-3:],
                "xiao": xiao_list,
                "numbers": num_list,
                "raw_text": raw_text,
                "fetched_at": matching_rows[0].fetched_at.isoformat() if matching_rows[0].fetched_at else None,
            }
    except Exception:
        return None


def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    data: dict | None = None

    if fixture:
        f_path = Path(fixture)
        if not f_path.is_absolute():
            f_path = ROOT / f_path
        data = json.loads(f_path.read_text(encoding="utf-8"))
    else:
        # Try local snapshot first, then database
        data = _load_from_snapshot(lottery, period)
        if not data:
            data = _load_from_db(lottery, period)

    if not data:
        raise ValueError(f"暂无 AI 研判预测数据 (lottery={lottery}, period={period or '最新'})，请先执行每日 AI 智能研判流水线")

    raw_period = str(data.get("period_raw") or data.get("period") or "最新")
    year = year_of(period) if period else None
    try:
        canonical_period = normalize(lottery, raw_period, year=year)
    except ValueError:
        canonical_period = normalize(lottery, period or raw_period)

    xiao_vals = [str(x).strip() for x in data.get("xiao") or [] if str(x).strip() in VALID_ZODIACS][:5]
    num_vals: list[str] = []
    for n in data.get("numbers") or []:
        try:
            val = int(str(n).strip())
            if 1 <= val <= 49:
                formatted = f"{val:02d}"
                if formatted not in num_vals:
                    num_vals.append(formatted)
        except (ValueError, TypeError):
            continue
    num_vals = num_vals[:10]

    atoms: list[PredAtom] = [PredAtom(kind="xiao", value=x) for x in xiao_vals] + [
        PredAtom(kind="num", value=n) for n in num_vals
    ]

    if not atoms:
        raise ValueError("AI预测记录为空：未包含有效生肖或号码")

    raw_text = str(data.get("raw_text") or f"AI智能研判十码五肖: {','.join(xiao_vals)} | {','.join(num_vals)}")

    item = PredItem(
        period_raw=raw_period,
        period=canonical_period,
        published_at=None,
        preds=atoms,
        claimed=Claimed(status="unknown"),
        raw_text=raw_text[:1024],
    )

    fetch_time = str(data.get("fetched_at") or now_cn())

    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        site_family=SITE_FAMILY,
        lottery=lottery,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        fetched_at=fetch_time,
        final_url="ai://macau_analyst_expert",
        content_hash=sha256_text(f"{canonical_period}:{','.join(xiao_vals)}:{','.join(num_vals)}"),
        items=[item],
        error=None,
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        pred = build(args.lottery, args.period, args.fixture)
        emit(pred, ok=True)
    except Exception as e:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(e))


if __name__ == "__main__":
    main()
