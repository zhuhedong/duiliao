from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Any

from sqlalchemy import delete, select

from common import ROOT
from common.attr import pad_num
from common.draw_tags import POSITIONS, draw_tags
from audit import ensure_baseline, record, now_local
from common.config import load_yaml
from common.http import get_json, get_text
from common.period import normalize, period_raw_of
from db import session_scope
from schema import Draw, JudgeResult, Prediction, create_all

FORBIDDEN_SOURCES = {"料站", "claimed", "prediction", "haige", "dingjian"}


class DrawRow(dict):
    lottery: str
    period: str
    period_raw: str
    draw_date: date
    balls: list[str]
    tema: str
    source: str


def parse_balls(code: str | list) -> tuple[list[str], str]:
    """Keep source order. Never sort by number size. z1..z6 = 落球顺序, last = 特码."""
    if isinstance(code, list):
        parts = [pad_num(x) for x in code]
    else:
        raw = str(code).replace(" ", ",").replace("+", ",").replace("|", ",")
        parts = [pad_num(p) for p in raw.split(",") if p.strip()]
    if len(parts) != 7:
        raise ValueError(f"need 7 balls, got {parts}")
    return parts[:6], parts[6]


def parse_date(value: Any) -> date:
    if isinstance(value, datetime):
        from common.period import _naive
        return _naive(value).date()
    if isinstance(value, date):
        return value
    s = str(value).strip()
    if "T" in s:
        return parse_date(datetime.fromisoformat(s.replace("Z", "+00:00")))
    s2 = s.replace("/", "-")
    try:
        return datetime.strptime(s2[:10], "%Y-%m-%d").date()
    except ValueError as e:
        raise ValueError(f"bad date: {value!r}") from e


def from_generic(obj: dict[str, Any], lottery: str, source: str) -> dict[str, Any]:
    period_raw_candidate = str(obj.get("period") or obj.get("expect") or obj.get("issue") or obj.get("period_raw") or obj.get("periodStr") or "")
    dt = parse_date(obj.get("openTime") or obj.get("open_time") or obj.get("draw_date") or obj.get("date"))
    period = normalize(lottery, str(obj.get("periodStr") or obj.get("period") or period_raw_candidate), year=dt.year)
    period_raw = period_raw_of(period) if (not period_raw_candidate or len(period_raw_candidate) >= 7) else str(period_raw_candidate).replace("期", "")
    open_code = obj.get("openCode") or obj.get("opencode") or obj.get("open_code") or obj.get("balls")
    if open_code is None and isinstance(obj.get("code"), list):
        open_code = obj.get("code")
    if not open_code:
        zs = [obj.get(f"z{i}") for i in range(1, 7)]
        tema = obj.get("tema")
        if all(zs) and tema:
            open_code = zs + [tema]
    if not open_code:
        ns = [obj.get(f"n{i}") for i in range(1, 8)]
        if all(n is not None and str(n).strip() != "" for n in ns):
            open_code = ns
    z, tema = parse_balls(open_code)
    dt = parse_date(obj.get("openTime") or obj.get("open_time") or obj.get("draw_date") or obj.get("date"))
    return {
        "lottery": lottery,
        "period": period,
        "period_raw": period_raw,
        "draw_date": dt,
        "opened_at": parse_opened_at(obj.get("opened_at") or obj.get("openTime") or obj.get("open_time") or obj.get("draw_date") or obj.get("date")),
        "z1": z[0], "z2": z[1], "z3": z[2], "z4": z[3], "z5": z[4], "z6": z[5],
        "tema": tema,
        "source": source,
    }


def _parse_trend_items(items: list[dict[str, Any]], lottery: str, src: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for it in items:
        if not isinstance(it, dict):
            continue
        balls = it.get("code")
        if not isinstance(balls, list):
            balls = [it.get(f"n{i}") for i in range(1, 8)]
            if not all(b is not None and str(b).strip() != "" for b in balls):
                continue
        try:
            rows.append(
                from_generic(
                    {
                        "period": it.get("periodStr") or it.get("period"),
                        "period_raw": it.get("periodStr") or it.get("period"),
                        "openCode": balls,
                        "draw_date": it.get("date") or it.get("draw_date"),
                    },
                    lottery,
                    src,
                )
            )
        except Exception as e:
            raise ValueError(f"开奖条目解析失败：{e}") from e
    if not rows:
        raise ValueError("returned no draws")
    return rows


def fetch_get_last_lottery(url: str, headers: dict[str, str], lottery: str) -> list[dict[str, Any]]:
    """GET last lottery API (当期最新开奖接口).
    Endpoint e.g. https://kj2.kjkjkj-1.com/api/v1/index/getLastLottery
    Response format:
    {
      "code": 0,
      "message": "Success",
      "data": {
        "id": 20262632,
        "date": "2026-09-20",
        "period": 263,
        "periodStr": "2026263",
        "time": "21:30",
        "n1": "44", "n2": "28", "n3": "03", "n4": "02", "n5": "24", "n6": "13", "n7": "09",
        "status": true
      }
    }
    """
    from common.http import get

    hdrs = {str(k): str(v) for k, v in (headers or {}).items() if v not in (None, "")}
    r = get(url, headers=hdrs, timeout=20, retries=1)
    payload = r.json()
    if not isinstance(payload, dict):
        raise ValueError("getLastLottery response is not an object")
    biz = payload.get("code")
    if isinstance(biz, int) and biz not in (0, 200):
        raise ValueError(payload.get("message") or f"getLastLottery code={biz}")
    data = payload.get("data")
    if isinstance(data, list):
        return _parse_trend_items(data, lottery, f"getLastLottery:{url}")
    if not isinstance(data, dict):
        raise ValueError("getLastLottery returned empty data")

    if data.get("status") is False:
        raise ValueError("当期开奖尚未完成或尚未开奖 (status=false)")

    balls = [data.get(f"n{i}") for i in range(1, 8)]
    if not all(b is not None and str(b).strip() != "" for b in balls):
        if isinstance(data.get("code"), list):
            balls = data.get("code")
        else:
            raise ValueError(f"getLastLottery 开奖球号不完整: {balls}")

    period_val = data.get("periodStr") or data.get("period")
    if not period_val:
        raise ValueError("getLastLottery 缺少期号")
    draw_date = data.get("date") or data.get("draw_date")
    if not draw_date:
        raise ValueError("getLastLottery 缺少开奖日期")

    opened_at_cand = None
    if data.get("time") and draw_date:
        try:
            cand = datetime.fromisoformat(f"{draw_date}T{data['time']}:00")
            if cand <= now_local():
                opened_at_cand = cand
        except Exception:
            pass

    src = f"getLastLottery:{url}"
    row = from_generic(
        {
            "period": period_val,
            "periodStr": period_val,
            "period_raw": period_val,
            "openCode": balls,
            "draw_date": draw_date,
            "opened_at": opened_at_cand,
        },
        lottery,
        src,
    )
    return [row]


def fetch_get_trend(url: str, headers: dict[str, str], lottery: str) -> list[dict[str, Any]]:
    """GET trend API. `code` array is 落球顺序, last is 特码. Do not sort."""
    from common.http import get

    hdrs = {str(k): str(v) for k, v in (headers or {}).items() if v not in (None, "")}
    r = get(url, headers=hdrs, timeout=20, retries=1)
    payload = r.json()
    if not isinstance(payload, dict):
        raise ValueError("getTrend response is not an object")
    biz = payload.get("code")
    if isinstance(biz, int) and biz not in (0, 200):
        raise ValueError(payload.get("message") or f"getTrend code={biz}")
    items = payload.get("data") or []
    if isinstance(items, dict):
        if "n1" in items or items.get("status") is not None:
            return fetch_get_last_lottery(url, headers, lottery)
        items = [items]
    return _parse_trend_items(items, lottery, f"getTrend:{url}")


def fetch_macaumarksix(urls: list[str], lottery: str, period: str | None) -> list[dict[str, Any]]:
    year = period[:4] if period and len(period) >= 4 else str(date.today().year)
    rows: list[dict[str, Any]] = []
    last_err: Exception | None = None
    for url in urls:
        u = url.replace("{year}", year).replace("{period}", period or "")
        try:
            data = get_json(u)
        except Exception as e:
            last_err = e
            continue
        items = data
        if isinstance(data, dict):
            items = data.get("data") or data.get("list") or data.get("result") or []
            if isinstance(items, dict):
                items = [items]
        if not isinstance(items, list):
            continue
        src = f"macaumarksix:{u}"
        for it in items:
            if not isinstance(it, dict):
                continue
            try:
                rows.append(from_generic(it, lottery, src))
            except Exception as e:
                raise ValueError(f"开奖条目解析失败：{e}") from e
        if rows:
            break
    if not rows and last_err:
        raise last_err
    return rows


def fetch_hkjc(urls: list[str], period: str | None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    last_err: Exception | None = None
    for url in urls:
        try:
            data = get_json(url)
        except Exception as e:
            last_err = e
            try:
                text = get_text(url)
                data = json.loads(text)
            except Exception as e2:
                last_err = e2
                continue
        items = data if isinstance(data, list) else (data.get("data") or data.get("results") or data.get("list") or [data])
        if isinstance(items, dict):
            items = [items]
        for it in items:
            if not isinstance(it, dict):
                continue
            try:
                if "no1" in it or "n1" in it:
                    balls = [it.get(k) for k in ("no1", "no2", "no3", "no4", "no5", "no6", "sno")]
                    if not all(balls):
                        balls = [it.get(k) for k in ("n1", "n2", "n3", "n4", "n5", "n6", "sno")]
                    it = {
                        **it,
                        "openCode": balls,
                        "period": it.get("id") or it.get("drawNo") or it.get("period"),
                        "openTime": it.get("date") or it.get("drawDate"),
                    }
                rows.append(from_generic(it, "hk", f"hkjc:{url}"))
            except Exception as e:
                raise ValueError(f"HKJC 开奖条目解析失败：{e}") from e
        if rows:
            break
    if not rows and last_err:
        raise RuntimeError(f"hkjc fetch failed: {last_err}")
    return rows


def load_json_file(path: Path, lottery: str) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict) and "draws" in data:
        data = data["draws"]
    if isinstance(data, dict):
        data = [data]
    src = "file:" + path.name
    if any(s in src.lower() for s in FORBIDDEN_SOURCES):
        src = "file:manual"
    return [from_generic(it, lottery, it.get("source") or src) for it in data]


def parse_opened_at(value):
    if value is None or (not isinstance(value, datetime) and len(str(value).strip()) <= 10):
        return None
    from common.period import _naive
    parsed = value if isinstance(value, datetime) else datetime.fromisoformat(str(value).strip().replace("Z", "+00:00"))
    return _naive(parsed)


def validate_draw(row: dict[str, Any]) -> dict[str, Any]:
    import re
    row = dict(row)
    dt = parse_date(row["draw_date"])
    if not 2000 <= dt.year <= 2040 or dt > now_local().date():
        raise ValueError("开奖日期超出支持范围或尚未到来")
    period = str(row["period"])
    if not re.fullmatch(r"\d{7}", period) or int(period[4:]) == 0 or int(period[:4]) != dt.year:
        raise ValueError("开奖期号必须为年份加三位期数，且年份与开奖日期一致")
    if row["lottery"] not in {"hk", "macau", "taiwan", "new"}:
        raise ValueError("未知彩种")
    balls = []
    for p in POSITIONS:
        value = str(row[p]).strip()
        if not re.fullmatch(r"\d{1,2}", value) or not 1 <= int(value) <= 49:
            raise ValueError(f"{p} 号码必须为 01–49")
        row[p] = f"{int(value):02d}"
        balls.append(row[p])
    if len(set(balls)) != 7:
        raise ValueError("七个开奖号码不能重复（生肖可以重复）")
    if not str(row.get("source") or "").strip():
        raise ValueError("开奖来源不能为空")
    row["draw_date"] = dt
    opened_at = parse_opened_at(row.get("opened_at"))
    if opened_at and (opened_at.date() != dt or opened_at > now_local()):
        raise ValueError("开奖时刻与日期不一致或尚未到来")
    row["opened_at"] = opened_at
    return row


def upsert_draw(row: dict[str, Any]) -> str:
    row = validate_draw(row)
    src = str(row["source"])
    if any(bad in src.lower() for bad in ("haige", "dingjian", "claimed", "料")):
        raise ValueError("refusing 料站 as draw source")
    with session_scope() as s:
        existing = s.scalar(
            select(Draw).where(Draw.lottery == row["lottery"], Draw.period == row["period"])
        )
        fields = {k: row[k] for k in ("period_raw", "draw_date", "z1", "z2", "z3", "z4", "z5", "z6", "tema", "source")}
        fields["opened_at"] = row["opened_at"] or (existing.opened_at if existing and existing.draw_date == row["draw_date"] else None)
        fields["tag"] = draw_tags([row[p] for p in POSITIONS], row["draw_date"], existing.tag if existing else None)
        if existing is None:
            created = Draw(lottery=row["lottery"], period=row["period"], **fields)
            s.add(created)
            record(s, created, "created")
            return "inserted"
        ensure_baseline(s, existing)
        changed = any(getattr(existing, k) != v for k, v in fields.items())
        if any(getattr(existing, k) != fields[k] for k in ("draw_date", "z1", "z2", "z3", "z4", "z5", "z6", "tema")):
            from rules import archive_current
            for pid in s.scalars(select(JudgeResult.prediction_id).where(JudgeResult.lottery == row["lottery"], JudgeResult.period == row["period"])):
                archive_current(s, pid)
            s.execute(delete(JudgeResult).where(
                JudgeResult.lottery == row["lottery"], JudgeResult.period == row["period"],
                JudgeResult.prediction_id.in_(select(Prediction.id).where(Prediction.claimed_status != "missing"))
            ))
        for k, v in fields.items():
            setattr(existing, k, v)
        if changed:
            record(s, existing, "corrected")
        return "updated"


def sync_draws(rows: list[dict[str, Any]]) -> dict[str, Any]:
    """Persist this batch, then judge every source for its lottery/period keys."""
    from judge import run_judge

    # Reject malformed batches before any of their rows are persisted.
    rows = [validate_draw(row) for row in rows]

    stats: dict[str, Any] = {"ok": True, "inserted": 0, "updated": 0, "count": 0,
                             "judged_periods": 0, "judged": 0, "hits": 0,
                             "dirty_claimed": 0, "deadletter": []}
    keys = set()
    for row in rows:
        action = upsert_draw(row)
        stats[action] += 1
        stats["count"] += 1
        keys.add((row["lottery"], row["period"]))
    with session_scope() as s:
        from sqlalchemy import tuple_

        available = set(s.execute(
            select(Prediction.lottery, Prediction.period)
            .where(tuple_(Prediction.lottery, Prediction.period).in_(keys))
            .distinct()
        ).all()) if keys else set()
    # Rejudge unchanged draws too: new predictions may have arrived since last sync.
    for lottery, period in sorted(keys & available):
        result = run_judge(lottery, period)
        stats["judged_periods"] += 1
        for key in ("judged", "hits", "dirty_claimed"):
            stats[key] += result[key]
        stats["deadletter"].extend(result["deadletter"])
    return stats


def main() -> None:
    p = argparse.ArgumentParser(description="sync official draws and judge matching predictions")
    p.add_argument("--lottery", required=True, choices=["hk", "macau", "taiwan", "new"])
    p.add_argument("--period", default=None)
    p.add_argument("--from-json", dest="from_json", default=None)
    p.add_argument("--init-db", action="store_true")
    args = p.parse_args()
    create_all()
    lottery = args.lottery
    period = normalize(lottery, args.period) if args.period else None
    if args.from_json:
        path = Path(args.from_json)
        if not path.is_absolute():
            path = ROOT / path
        rows = load_json_file(path, lottery)
    else:
        cfg = (load_yaml().get("draw") or {}).get(lottery) or {}
        adapter = cfg.get("adapter") or "getLastLottery"
        url = (cfg.get("url") or "").strip()
        urls = list(cfg.get("urls") or [])
        headers = {str(k): str(v) for k, v in (cfg.get("headers") or {}).items() if v not in (None, "")}
        if adapter in ("getLastLottery", "getTrend"):
            if not url:
                raise SystemExit(f"no draw url for {lottery}; set it on the 开奖 page")
            if adapter == "getLastLottery" or "getLastLottery" in url:
                rows = fetch_get_last_lottery(url, headers, lottery)
            else:
                rows = fetch_get_trend(url, headers, lottery)
        elif adapter == "hkjc":
            if not urls:
                raise SystemExit(f"no draw urls for {lottery}")
            rows = fetch_hkjc(urls, period)
        else:
            if not urls:
                raise SystemExit(f"no draw urls for {lottery}; pass --from-json")
            rows = fetch_macaumarksix(urls, lottery, period)
    if period:
        rows = [r for r in rows if r["period"] == period]
        if not rows:
            raise SystemExit(f"no draw for {lottery} {period}")
    stats = sync_draws(rows)
    sys.stdout.write(json.dumps(stats, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
