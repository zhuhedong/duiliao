"""Bridge between the FastAPI app and the ported ``collector`` package.

The collector (``backend/collector``) is a faithful port of pred-collector's
core: source collection (``runner`` + ``sources/*``), ingest, draw sync, the
judge engine, consensus / analytics, and source management (``registry`` /
``source_catalog``). It keeps its original flat-import layout, so we add its
directory to ``sys.path`` and import its top-level modules directly.

The collector uses its **own** database (SQLite at ``collector/data/pred.db``
by default) so its ~15 domain tables never mix with the app's user/auth tables.
Override with the ``COLLECTOR_DATABASE_URL`` environment variable (e.g. a
PostgreSQL DSN in production).

Only the collector subprocess makes outbound HTTP requests; this API process
never talks to external prediction sites directly.
"""
from __future__ import annotations

import os
import sys
import threading
from datetime import datetime
from pathlib import Path
from typing import Any

COLLECTOR_ROOT = Path(__file__).resolve().parent.parent / "collector"

_init_lock = threading.Lock()
_initialized = False


def _ensure_env() -> None:
    """Point the collector at its own database and make sure the dir exists."""
    data_dir = COLLECTOR_ROOT / "data"
    data_dir.mkdir(parents=True, exist_ok=True)
    override = os.getenv("COLLECTOR_DATABASE_URL", "").strip()
    if not override:
        app_db = os.getenv("DATABASE_URL", "").strip()
        if app_db.startswith("postgres"):
            override = app_db
    # Isolate the collector DB from the app DB when on SQLite, or share when on Postgres.
    os.environ["COLLECTOR_DATABASE_URL"] = override or ("sqlite:///" + (data_dir / "pred.db").as_posix())


def bootstrap() -> None:
    """Idempotently prepare sys.path and create/seed the collector schema."""
    global _initialized
    if _initialized:
        return
    with _init_lock:
        if _initialized:
            return
        _ensure_env()
        root = str(COLLECTOR_ROOT)
        if root not in sys.path:
            sys.path.insert(0, root)
        import schema  # noqa: F401  (collector top-level module)

        schema.create_all()
        schema.seed_numbers()
        schema.seed_number_attrs()
        schema.seed_number_code_meta()
        schema.seed_xiao_year_meta()
        schema.seed_sources()
        _initialized = True


def _resolve_fixture_dir(fixture_dir: str | None) -> Path | None:
    if not fixture_dir:
        return None
    path = Path(fixture_dir)
    if not path.is_absolute():
        path = COLLECTOR_ROOT / path
    return path


# --------------------------------------------------------------------------- #
# Pipeline orchestration
# --------------------------------------------------------------------------- #
def collect(
    lottery: str,
    period: str | None = None,
    source_ids: list[str] | None = None,
    fixture_dir: str | None = None,
    do_ingest: bool = True,
    concurrency: int = 8,
) -> dict[str, Any]:
    """Run the enabled source scripts in a ThreadPool (as subprocesses) and optionally ingest.

    Uses concurrent.futures.ThreadPoolExecutor to parallelize outbound crawling
    across data sources, drastically reducing overall collection time.
    """
    bootstrap()
    import concurrent.futures
    import ingest
    import runner
    from common.config import load_yaml
    from common.period import normalize

    cfg = load_yaml()
    canonical_period = normalize(lottery, period) if period and period.strip() else None
    only = set(source_ids) if source_ids else None
    sources = runner.load_sources(cfg, lottery, only)
    now = datetime.now(runner.TZ8)
    run_id = runner.new_run_id(now)

    fixtures = _resolve_fixture_dir(fixture_dir)

    def _execute_source(row: dict[str, Any]) -> dict[str, Any]:
        extra: list[str] = []
        if fixtures is not None:
            fp = fixtures / f"{row['source_id']}.json"
            if fp.exists():
                extra += ["--fixture", str(fp)]
        return runner.run_one(row, lottery, canonical_period, extra)

    max_workers = max(1, min(int(concurrency or 8), len(sources) or 1))
    if max_workers == 1 or len(sources) <= 1:
        results: list[dict[str, Any]] = [_execute_source(row) for row in sources]
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            results = list(executor.map(_execute_source, sources))

    for r in results:
        r["raw_path"] = runner.write_raw(run_id, r)

    # If period wasn't provided, detect latest period from extracted items
    detected_periods = [
        it.get("period")
        for r in results if r.get("data")
        for it in r["data"].get("items", [])
        if it.get("period")
    ]
    latest_period = max(detected_periods) if detected_periods else None
    period_summary = canonical_period or latest_period or "auto"

    payload = {
        "ok": True,
        "schema": "run.v1",
        "run_id": run_id,
        "run_at": now.isoformat(),
        "lottery": lottery,
        "period": period_summary,
        "results": [
            {
                k: r.get(k)
                for k in (
                    "source_id",
                    "ok",
                    "exit_code",
                    "elapsed_ms",
                    "item_count",
                    "data",
                    "error_code",
                    "error_msg",
                    "raw_path",
                    "raw_output",
                )
            }
            for r in results
        ],
    }

    out: dict[str, Any] = {
        "ok": True,
        "run_id": run_id,
        "lottery": lottery,
        "period": period_summary,
        "source_total": len(results),
        "source_ok": sum(1 for r in results if r["ok"]),
    }
    if do_ingest:
        out["ingest"] = ingest.ingest_run(payload)
    else:
        out["payload"] = payload
    return out


def ingest_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Ingest a run.v1 payload (dedupe + upsert + auto-judge on existing draws)."""
    bootstrap()
    import ingest

    return ingest.ingest_run(payload)


def sync_draws(
    lottery: str,
    period: str | None = None,
    draws: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Import/normalize official draws and re-judge affected predictions.

    If ``draws`` is provided, each generic object is normalized (accepts common
    shapes like ``openCode``/``openTime``); otherwise the configured adapter for
    the lottery (``getTrend`` / ``hkjc`` / ``macaumarksix``) is used.
    """
    bootstrap()
    import draw_sync
    from common.config import load_yaml
    from common.period import normalize

    canonical_period = normalize(lottery, period) if period else None

    if draws:
        rows = [draw_sync.from_generic(obj, lottery, str(obj.get("source") or "api")) for obj in draws]
    else:
        cfg = (load_yaml().get("draw") or {}).get(lottery) or {}
        adapter = cfg.get("adapter") or "getTrend"
        url = (cfg.get("url") or "").strip()
        urls = list(cfg.get("urls") or [])
        headers = {str(k): str(v) for k, v in (cfg.get("headers") or {}).items() if v not in (None, "")}
        if adapter == "getTrend":
            if not url:
                raise ValueError(f"no draw url configured for {lottery}")
            rows = draw_sync.fetch_get_trend(url, headers, lottery)
        elif adapter == "hkjc":
            if not urls:
                raise ValueError(f"no draw urls configured for {lottery}")
            rows = draw_sync.fetch_hkjc(urls, canonical_period)
        else:
            if not urls:
                raise ValueError(f"no draw urls configured for {lottery}")
            rows = draw_sync.fetch_macaumarksix(urls, lottery, canonical_period)

    if canonical_period:
        rows = [r for r in rows if r["period"] == canonical_period]
        if not rows:
            raise ValueError(f"no draw for {lottery} {canonical_period}")
    return draw_sync.sync_draws(rows)


def judge(lottery: str, period: str) -> dict[str, Any]:
    """Re-run the judge engine for one lottery+period."""
    bootstrap()
    import judge as judge_mod
    from common.period import normalize

    return judge_mod.run_judge(lottery, normalize(lottery, period))


def consensus_compare(lottery: str, period: str, play_type: str | None = None) -> dict[str, Any]:
    bootstrap()
    import consensus
    from common.period import normalize
    from db import session_scope
    from schema import Draw
    from sqlalchemy import select

    canonical_period = normalize(lottery, period)
    res = consensus.compare(lottery, canonical_period, play_type)

    with session_scope(guard=False) as s:
        draw_row = s.scalar(select(Draw).where(Draw.lottery == lottery, Draw.period == canonical_period))
        if draw_row:
            res["draw"] = enrich_draw_row(draw_row)
            try:
                import judge

                ctx = judge.draw_view(draw_row)
                for g in res.get("groups", []):
                    pt = g.get("play_type")
                    judge_fn = judge.JUDGES.get(pt)
                    if judge_fn:
                        if g.get("leader"):
                            try:
                                l_hit, l_detail = judge_fn(g["leader"], "regular", ctx)
                                g["leader_hit"] = l_hit
                                g["leader_hit_detail"] = l_detail
                            except Exception:
                                pass
                        for t in g.get("tally", []):
                            try:
                                t_hit, t_detail = judge_fn(t["preds"], "regular", ctx)
                                t["hit"] = t_hit
                                t["hit_detail"] = t_detail
                            except Exception:
                                pass
                tema_val = str(draw_row.tema or "").zfill(2)
                tema_xiao = res.get("draw", {}).get("tema_detail", {}).get("xiao")
                for item in res.get("atom_tallies", {}).get("tema_n", []):
                    item["hit"] = (item["value"] == tema_val)
                for item in res.get("atom_tallies", {}).get("texiao", []):
                    item["hit"] = (item["value"] == tema_xiao) if tema_xiao else False
            except Exception:
                pass
        else:
            res["draw"] = None

    return res


def ratings(
    lottery: str,
    play_type: str,
    windows: tuple[int, ...] = (30, 50, 100),
    period_from: str | None = None,
    period_to: str | None = None,
) -> dict[str, Any]:
    bootstrap()
    import analytics

    return analytics.ratings(lottery, play_type, windows, period_from, period_to)


def monitor(lottery: str | None = None) -> dict[str, Any]:
    bootstrap()
    import analytics

    return analytics.monitor(lottery)


def enrich_draw_row(d: Any) -> dict[str, Any]:
    """Calculate full number attributes (生肖, 波色, 五行, 家野, 大小, 单双, 合数, 总分) for a draw."""
    from datetime import date
    from common.attr import pad_num, bose, size, odd, heshu_odd, wei, head, jia_ye, halfwave
    from common.xiao import num_to_xiao
    from common.wuxing import num_to_wuxing

    dd: date | None = d.draw_date if isinstance(getattr(d, "draw_date", None), date) else None
    if not dd and getattr(d, "opened_at", None):
        dd = d.opened_at.date()
    if not dd:
        try:
            yr = int(d.period[:4]) if len(d.period) >= 4 else 2026
            dd = date(yr, 6, 1)
        except Exception:
            dd = date.today()

    def get_attr(num_val: str) -> dict[str, Any]:
        p = pad_num(num_val)
        x = num_to_xiao(p, dd)
        wx = num_to_wuxing(p, dd)
        b = bose(p)
        s = size(p)
        o = odd(p)
        ho = heshu_odd(p)
        w = wei(p)
        h = head(p)
        jy = jia_ye(x)
        hw = halfwave(p)
        return {
            "num": p,
            "bose": b,
            "xiao": x,
            "wuxing": wx,
            "size": s,
            "odd": o,
            "sum": ho,
            "wei": w,
            "head": h,
            "jiaye": jy,
            "halfwave": hw,
        }

    balls = [d.z1, d.z2, d.z3, d.z4, d.z5, d.z6]
    balls_detail = [get_attr(b) for b in balls]
    tema_detail = get_attr(d.tema)
    all_7 = balls_detail + [tema_detail]

    # Calculate 连肖 (repeated zodiacs and adjacent order matches)
    positions = ["正1", "正2", "正3", "正4", "正5", "正6", "特码"]
    xiao_counts: dict[str, int] = {}
    for b in all_7:
        x = b["xiao"]
        xiao_counts[x] = xiao_counts.get(x, 0) + 1

    lianxiao_xiaos = {x: cnt for x, cnt in xiao_counts.items() if cnt >= 2}
    has_lianxiao = len(lianxiao_xiaos) > 0

    adjacent_lianxiao = []
    for i in range(6):
        if all_7[i]["xiao"] == all_7[i + 1]["xiao"]:
            all_7[i]["is_adjacent_lianxiao"] = True
            all_7[i + 1]["is_adjacent_lianxiao"] = True
            adjacent_lianxiao.append({
                "xiao": all_7[i]["xiao"],
                "pos1": positions[i],
                "pos2": positions[i + 1],
                "num1": all_7[i]["num"],
                "num2": all_7[i + 1]["num"],
            })

    for b in all_7:
        b["is_lianxiao"] = b["xiao"] in lianxiao_xiaos
        b["lianxiao_count"] = lianxiao_xiaos.get(b["xiao"], 1)
        if "is_adjacent_lianxiao" not in b:
            b["is_adjacent_lianxiao"] = False

    lianxiao_groups = []
    for x, cnt in sorted(lianxiao_xiaos.items(), key=lambda item: (-item[1], item[0])):
        nums = [all_7[i]["num"] for i in range(7) if all_7[i]["xiao"] == x]
        pos_list = [positions[i] for i in range(7) if all_7[i]["xiao"] == x]
        lianxiao_groups.append({
            "xiao": x,
            "count": cnt,
            "nums": nums,
            "positions": pos_list,
        })

    lianxiao_text = " · ".join(f"{g['xiao']}({g['count']}码)" for g in lianxiao_groups) if lianxiao_groups else "7肖各异"

    sum7 = sum(int(b["num"]) for b in all_7)
    sum7_size = "大" if sum7 >= 175 else "小"
    sum7_odd = "单" if sum7 % 2 != 0 else "双"

    summary = {
        "sum7": sum7,
        "sum7_size": sum7_size,
        "sum7_odd": sum7_odd,
        "tema_xiao": tema_detail["xiao"],
        "tema_bose": tema_detail["bose"],
        "tema_wuxing": tema_detail["wuxing"],
        "tema_size": tema_detail["size"],
        "tema_odd": tema_detail["odd"],
        "tema_sum_odd": tema_detail["sum"],
        "tema_jiaye": tema_detail["jiaye"],
        "tema_halfwave": tema_detail["halfwave"],
        "has_lianxiao": has_lianxiao,
        "has_adjacent_lianxiao": len(adjacent_lianxiao) > 0,
        "lianxiao_groups": lianxiao_groups,
        "adjacent_lianxiao": adjacent_lianxiao,
        "lianxiao_text": lianxiao_text,
    }

    return {
        "lottery": d.lottery,
        "period": d.period,
        "period_raw": d.period_raw,
        "draw_date": d.draw_date.isoformat() if d.draw_date else None,
        "opened_at": d.opened_at.isoformat() if d.opened_at else None,
        "balls": balls,
        "tema": d.tema,
        "source": d.source,
        "tag": d.tag if isinstance(d.tag, dict) else {},
        "balls_detail": balls_detail,
        "tema_detail": tema_detail,
        "summary": summary,
    }


def list_draws(
    lottery: str | None = None,
    limit: int = 50,
    offset: int = 0,
    period_from: str | None = None,
    period_to: str | None = None,
) -> dict[str, Any]:
    """List stored official draws (most recent period first)."""
    bootstrap()
    from sqlalchemy import func, select

    from db import session_scope
    from schema import Draw

    limit = max(1, min(limit, 500))
    offset = max(0, offset)
    with session_scope(guard=False) as s:
        base = select(Draw)
        if lottery:
            base = base.where(Draw.lottery == lottery)
        if period_from:
            base = base.where(Draw.period >= period_from)
        if period_to:
            base = base.where(Draw.period <= period_to)
        total = s.scalar(select(func.count()).select_from(base.subquery())) or 0
        rows = list(s.scalars(base.order_by(Draw.period.desc()).offset(offset).limit(limit)))
        items = [enrich_draw_row(d) for d in rows]
    return {"ok": True, "total": int(total), "count": len(items), "items": items}


def list_predictions(
    lottery: str | None = None,
    period: str | None = None,
    source_id: str | None = None,
    limit: int = 100,
) -> dict[str, Any]:
    """List stored predictions (most recent period first)."""
    bootstrap()
    from sqlalchemy import func, select

    from db import session_scope
    from schema import Prediction

    limit = max(1, min(limit, 500))
    with session_scope(guard=False) as s:
        base = select(Prediction)
        if lottery:
            base = base.where(Prediction.lottery == lottery)
        if period:
            base = base.where(Prediction.period == period)
        if source_id:
            base = base.where(Prediction.source_id == source_id)
        total = s.scalar(select(func.count()).select_from(base.subquery())) or 0
        rows = list(
            s.scalars(base.order_by(Prediction.period.desc(), Prediction.source_id).limit(limit))
        )
        items = [
            {
                "id": p.id,
                "source_id": p.source_id,
                "lottery": p.lottery,
                "play_type": p.play_type,
                "period": p.period,
                "preds": p.preds_json,
                "claimed_status": p.claimed_status,
                "raw_text": p.raw_text,
                "final_url": p.final_url,
                "fetched_at": p.fetched_at.isoformat() if p.fetched_at else None,
            }
            for p in rows
        ]
    return {"ok": True, "total": int(total), "count": len(items), "items": items}


def confirm_missing(source_id: str, periods: list[str]) -> dict[str, Any]:
    bootstrap()
    import analytics

    return analytics.confirm_missing(source_id, periods)


def list_numbers(date_str: str | None = None) -> dict[str, Any]:
    """Return 01–49 with their attributes for a given date.

    Zodiac (生肖) and 家野 rotate by lunar year (春节 boundary), so they are
    computed for the selected date; 波色 / 大小 / 单双 / 头 / 尾 / 合数 are fixed.
    Supported date range is 2000–2040 (the lunar-new-year table).
    """
    bootstrap()
    from datetime import date

    from sqlalchemy import select

    from common.attr import pad_num
    from common.wuxing import wuxing_years
    from common.xiao import lunar_year
    from db import session_scope
    from schema import NumberInfo, NumberYearAttr, NumberCodeMeta, XiaoYearMeta

    d = date.fromisoformat(date_str) if date_str else date.today()
    if not 2000 <= d.year <= 2040:
        raise ValueError("日期需在 2000–2040 之间")
    ly = lunar_year(d)

    with session_scope(guard=False) as s:
        fixed = {r.num: r for r in s.scalars(select(NumberInfo))}
        year_rows = {
            r.num: r for r in s.scalars(select(NumberYearAttr).where(NumberYearAttr.lunar_year == ly))
        }
        meta_rows = {r.num: r for r in s.scalars(select(NumberCodeMeta).where(NumberCodeMeta.lunar_year == ly))}
        xiao_meta_rows = {r.xiao: r for r in s.scalars(select(XiaoYearMeta).where(XiaoYearMeta.lunar_year == ly))}
        items = []
        for n in range(1, 50):
            num = pad_num(n)
            fi = fixed.get(num)
            ya = year_rows.get(num)
            meta = meta_rows.get(num)
            items.append(
                {
                    "num": num,
                    "xiao": ya.xiao if ya else None,
                    "jiaye": ya.jiaye if ya else None,
                    "wuxing": ya.wuxing if ya else None,
                    "bose": fi.bose if fi else None,
                    "size": fi.size if fi else None,
                    "odd": fi.odd if fi else None,
                    "head": fi.head if fi else None,
                    "wei": fi.wei if fi else None,
                    "sum": fi.sum if fi else None,
                    "role": meta.role if meta else None,
                    "flower": meta.flower if meta else None,
                    "hour": meta.hour if meta else None,
                    "dizhi": meta.dizhi if meta else None,
                    "xiao_color": meta.xiao_color if meta else None,
                    "stroke": meta.stroke if meta else None,
                    "tian_di": xiao_meta_rows.get(ya.xiao).tian_di if ya and xiao_meta_rows.get(ya.xiao) else None,
                    "yin_yang": xiao_meta_rows.get(ya.xiao).yin_yang if ya and xiao_meta_rows.get(ya.xiao) else None,
                    "gender": xiao_meta_rows.get(ya.xiao).gender if ya and xiao_meta_rows.get(ya.xiao) else None,
                    "luck": xiao_meta_rows.get(ya.xiao).luck if ya and xiao_meta_rows.get(ya.xiao) else None,
                    "season": xiao_meta_rows.get(ya.xiao).season if ya and xiao_meta_rows.get(ya.xiao) else None,
                    "direction": xiao_meta_rows.get(ya.xiao).direction if ya and xiao_meta_rows.get(ya.xiao) else None,
                }
            )
    has_wuxing = any(it["wuxing"] for it in items)
    return {
        "ok": True,
        "date": d.isoformat(),
        "lunar_year": ly,
        "items": items,
        "wuxing_available": has_wuxing,
        "wuxing_years": wuxing_years(),
    }


def rules_catalog() -> list[dict[str, Any]]:
    bootstrap()
    import rules

    return rules.catalog()


# --------------------------------------------------------------------------- #
# Source management (registry) + catalog
# --------------------------------------------------------------------------- #
def registry_module():
    bootstrap()
    import registry

    return registry


def catalog_status() -> dict[str, Any]:
    bootstrap()
    import source_catalog

    return source_catalog.status()


def catalog_scan(record: bool = True) -> dict[str, Any]:
    bootstrap()
    import source_catalog

    return source_catalog.scan(record=record)


def test_source_script(
    source_id: str,
    lottery: str = "macau",
    period: str | None = None,
    fixture_dir: str | None = None,
    do_ingest: bool = False,
) -> dict[str, Any]:
    """Execute a single source script directly and capture detailed output."""
    bootstrap()
    import ingest
    import runner
    from common.period import normalize

    reg = registry_module()
    src = reg.get_source(source_id)
    canonical_period = normalize(lottery, period) if period else None

    fixtures = _resolve_fixture_dir(fixture_dir)
    extra: list[str] = []
    if fixtures is not None:
        fp = fixtures / f"{source_id}.json"
        if fp.exists():
            extra += ["--fixture", str(fp)]

    res = runner.run_one(src, lottery, canonical_period, extra)
    out: dict[str, Any] = {
        "ok": res["ok"],
        "source_id": source_id,
        "lottery": lottery,
        "period": canonical_period,
        "exit_code": res.get("exit_code"),
        "elapsed_ms": res.get("elapsed_ms", 0),
        "item_count": res.get("item_count", 0),
        "stdout": res.get("stdout") or "",
        "stderr": res.get("stderr") or "",
        "error_code": res.get("error_code"),
        "error_msg": res.get("error_msg"),
        "data": res.get("data"),
    }
    if do_ingest and res.get("ok") and res.get("data"):
        now = datetime.now(runner.TZ8)
        run_id = runner.new_run_id(now)
        payload = {
            "ok": True,
            "schema": "run.v1",
            "run_id": run_id,
            "run_at": now.isoformat(),
            "lottery": lottery,
            "period": canonical_period or res["data"].get("items", [{}])[0].get("period", ""),
            "results": [res],
        }
        out["ingest"] = ingest.ingest_run(payload)
    return out


def run_script_by_name(
    name: str,
    lottery: str = "macau",
    period: str | None = None,
    fixture: str | None = None,
) -> dict[str, Any]:
    """Execute any script in sources/ directly by filename."""
    bootstrap()
    import runner
    from common.period import normalize

    reg = registry_module()
    script_info = reg.read_script(name)
    canonical_period = normalize(lottery, period) if period else None
    mock_row = {
        "source_id": name.replace(".py", ""),
        "script_path": f"sources/{name}",
        "timeout_sec": 30,
        "enabled": True,
    }
    extra: list[str] = []
    if fixture:
        extra += ["--fixture", fixture]
    res = runner.run_one(mock_row, lottery, canonical_period, extra)
    return {
        "ok": res["ok"],
        "name": name,
        "lottery": lottery,
        "period": canonical_period,
        "exit_code": res.get("exit_code"),
        "elapsed_ms": res.get("elapsed_ms", 0),
        "item_count": res.get("item_count", 0),
        "stdout": res.get("stdout") or "",
        "stderr": res.get("stderr") or "",
        "error_code": res.get("error_code"),
        "error_msg": res.get("error_msg"),
        "data": res.get("data"),
    }


def get_period_comparison(lottery: str, period: str) -> dict[str, Any]:
    """Aggregate official draw numbers, all predictions, and JudgeResults for a period."""
    bootstrap()
    from common.period import normalize
    from db import session_scope
    from schema import Draw, Prediction, JudgeResult, Source
    from sqlalchemy import select

    canonical_period = normalize(lottery, period)
    with session_scope(guard=False) as s:
        # 1. Official draw
        draw_row = s.scalar(select(Draw).where(Draw.lottery == lottery, Draw.period == canonical_period))
        draw_info = None
        if draw_row:
            draw_info = enrich_draw_row(draw_row)

        # 2. Predictions for this period
        preds_stmt = (
            select(Prediction)
            .where(Prediction.lottery == lottery, Prediction.period == canonical_period)
            .order_by(Prediction.source_id, Prediction.play_type)
        )
        preds = list(s.scalars(preds_stmt))

        # 3. Source names map
        sources_map = {src.source_id: src.source_name for src in s.scalars(select(Source))}

        # 4. Judge results
        pred_ids = [p.id for p in preds]
        judge_map: dict[int, JudgeResult] = {}
        if pred_ids:
            jr_stmt = select(JudgeResult).where(JudgeResult.prediction_id.in_(pred_ids))
            for jr in s.scalars(jr_stmt):
                judge_map[jr.prediction_id] = jr

        items = []
        hit_count = 0
        miss_count = 0
        pending_count = 0
        conflict_count = 0

        for p in preds:
            jr = judge_map.get(p.id)
            status = "pending"
            official_hit = None
            claimed_hit = None
            hit_detail = None
            judged_at = None

            if jr is not None:
                official_hit = jr.official_hit
                claimed_hit = jr.claimed_hit
                hit_detail = jr.hit_detail
                judged_at = jr.judged_at.isoformat() if jr.judged_at else None
                if official_hit == 1:
                    status = "hit"
                    hit_count += 1
                else:
                    status = "miss"
                    miss_count += 1
                if p.claimed_status == "hit" and official_hit == 0:
                    status = "conflict"
                    conflict_count += 1
            else:
                pending_count += 1

            items.append({
                "id": p.id,
                "source_id": p.source_id,
                "source_name": sources_map.get(p.source_id) or p.source_id,
                "lottery": p.lottery,
                "play_type": p.play_type,
                "hit_mode": p.hit_mode,
                "period": p.period,
                "period_raw": p.period_raw,
                "group_key": p.group_key,
                "preds": p.preds_json,
                "claimed_status": p.claimed_status,
                "raw_text": p.raw_text,
                "fetched_at": p.fetched_at.isoformat() if p.fetched_at else None,
                "official_hit": official_hit,
                "claimed_hit": claimed_hit,
                "hit_detail": hit_detail,
                "judged_at": judged_at,
                "status": status,
            })

        total = len(items)
        judged_total = hit_count + miss_count
        hit_rate = round(hit_count / judged_total * 100, 1) if judged_total > 0 else 0.0

        return {
            "ok": True,
            "lottery": lottery,
            "period": canonical_period,
            "draw": draw_info,
            "summary": {
                "total": total,
                "judged": judged_total,
                "hits": hit_count,
                "misses": miss_count,
                "pending": pending_count,
                "conflicts": conflict_count,
                "hit_rate": hit_rate,
            },
            "items": items,
        }


# --------------------------------------------------------------------------- #
# Source Collection Scheduled Tasks (数据源采集定时任务)
# --------------------------------------------------------------------------- #
def _schedule_to_dict(s: Any) -> dict[str, Any]:
    return {
        "id": s.id,
        "name": s.name,
        "lottery": s.lottery,
        "period": s.period,
        "source_ids": s.source_ids,
        "cron": s.cron,
        "start_at": s.start_at.strftime("%Y-%m-%d %H:%M:%S") if s.start_at else None,
        "end_at": s.end_at.strftime("%Y-%m-%d %H:%M:%S") if s.end_at else None,
        "interval_minutes": s.interval_minutes,
        "enabled": bool(s.enabled),
        "do_ingest": bool(s.do_ingest),
        "auto_judge": bool(s.auto_judge),
        "next_run_at": s.next_run_at.strftime("%Y-%m-%d %H:%M:%S") if s.next_run_at else None,
        "last_run_at": s.last_run_at.strftime("%Y-%m-%d %H:%M:%S") if s.last_run_at else None,
        "last_status": s.last_status,
        "last_result": s.last_result,
        "spec": s.spec or {},
        "created_at": s.created_at.strftime("%Y-%m-%d %H:%M:%S") if s.created_at else None,
        "updated_at": s.updated_at.strftime("%Y-%m-%d %H:%M:%S") if s.updated_at else None,
    }


def list_schedules(lottery: str | None = None) -> list[dict[str, Any]]:
    bootstrap()
    from db import session_scope
    from schema import Schedule
    from sqlalchemy import select

    with session_scope() as s:
        stmt = select(Schedule)
        if lottery:
            stmt = stmt.where(Schedule.lottery == lottery)
        stmt = stmt.order_by(Schedule.id.asc())
        rows = list(s.scalars(stmt))
        return [_schedule_to_dict(r) for r in rows]


def get_schedule(schedule_id: int) -> dict[str, Any] | None:
    bootstrap()
    from db import session_scope
    from schema import Schedule

    with session_scope() as s:
        row = s.get(Schedule, schedule_id)
        return _schedule_to_dict(row) if row else None


def create_schedule(
    name: str,
    lottery: str = "macau",
    period: str | None = None,
    source_ids: list[str] | None = None,
    cron: str | None = None,
    start_at: str | datetime | None = None,
    end_at: str | datetime | None = None,
    enabled: bool = True,
    do_ingest: bool = True,
    auto_judge: bool = True,
    spec: dict | None = None,
) -> dict[str, Any]:
    bootstrap()
    import cron_util
    from db import session_scope
    from schema import Schedule

    dt_start = cron_util.parse_datetime(start_at)
    dt_end = cron_util.parse_datetime(end_at)
    cleaned_cron = cron.strip() if cron and cron.strip() else None
    if cleaned_cron:
        cron_util.CronSchedule(cleaned_cron)

    next_run = cron_util.compute_next_run(
        cron_expr=cleaned_cron,
        start_at=dt_start,
        end_at=dt_end,
    )

    with session_scope() as s:
        sched = Schedule(
            name=name.strip(),
            lottery=lottery.strip(),
            period=period.strip() if period and period.strip() else None,
            source_ids=source_ids if source_ids else None,
            cron=cleaned_cron,
            start_at=cron_util.to_naive_cn(dt_start),
            end_at=cron_util.to_naive_cn(dt_end),
            enabled=1 if enabled else 0,
            do_ingest=1 if do_ingest else 0,
            auto_judge=1 if auto_judge else 0,
            spec=spec or {},
            next_run_at=cron_util.to_naive_cn(next_run),
        )
        s.add(sched)
        s.flush()
        return _schedule_to_dict(sched)


def update_schedule(schedule_id: int, **fields: Any) -> dict[str, Any] | None:
    bootstrap()
    import cron_util
    from db import session_scope
    from schema import Schedule

    with session_scope() as s:
        sched = s.get(Schedule, schedule_id)
        if not sched:
            return None

        if "name" in fields and fields["name"] is not None:
            sched.name = str(fields["name"]).strip()
        if "lottery" in fields and fields["lottery"] is not None:
            sched.lottery = str(fields["lottery"]).strip()
        if "period" in fields:
            p = fields["period"]
            sched.period = str(p).strip() if p and str(p).strip() else None
        if "source_ids" in fields:
            sched.source_ids = fields["source_ids"]
        if "enabled" in fields and fields["enabled"] is not None:
            sched.enabled = 1 if fields["enabled"] else 0
        if "do_ingest" in fields and fields["do_ingest"] is not None:
            sched.do_ingest = 1 if fields["do_ingest"] else 0
        if "auto_judge" in fields and fields["auto_judge"] is not None:
            sched.auto_judge = 1 if fields["auto_judge"] else 0
        if "spec" in fields and fields["spec"] is not None:
            sched.spec = fields["spec"]

        cron_changed = "cron" in fields
        start_changed = "start_at" in fields
        end_changed = "end_at" in fields

        if cron_changed:
            c = fields["cron"]
            sched.cron = str(c).strip() if c and str(c).strip() else None
            if sched.cron:
                cron_util.CronSchedule(sched.cron)
        if start_changed:
            dt_s = cron_util.parse_datetime(fields["start_at"])
            sched.start_at = cron_util.to_naive_cn(dt_s)
        if end_changed:
            dt_e = cron_util.parse_datetime(fields["end_at"])
            sched.end_at = cron_util.to_naive_cn(dt_e)

        if cron_changed or start_changed or end_changed or "enabled" in fields:
            if sched.enabled:
                next_run = cron_util.compute_next_run(
                    cron_expr=sched.cron,
                    start_at=sched.start_at,
                    end_at=sched.end_at,
                )
                sched.next_run_at = cron_util.to_naive_cn(next_run)
            else:
                sched.next_run_at = None

        s.flush()
        return _schedule_to_dict(sched)


def delete_schedule(schedule_id: int) -> bool:
    bootstrap()
    from db import session_scope
    from schema import Schedule

    with session_scope() as s:
        sched = s.get(Schedule, schedule_id)
        if not sched:
            return False
        s.delete(sched)
        return True


def get_due_schedules(now_dt: datetime) -> list[dict[str, Any]]:
    bootstrap()
    import cron_util
    from db import session_scope
    from schema import Schedule
    from sqlalchemy import select

    naive_now = cron_util.to_naive_cn(now_dt)

    with session_scope() as s:
        stmt = (
            select(Schedule)
            .where(Schedule.enabled == 1)
            .where(Schedule.next_run_at.is_not(None))
            .where(Schedule.next_run_at <= naive_now)
            .order_by(Schedule.next_run_at.asc())
        )
        rows = list(s.scalars(stmt))
        return [_schedule_to_dict(r) for r in rows]


def update_schedule_run_result(
    schedule_id: int,
    last_run_at: datetime,
    next_run_at: datetime | None,
    last_status: str,
    last_result: dict[str, Any] | None,
    enabled: int | None = None,
) -> None:
    bootstrap()
    import cron_util
    from db import session_scope
    from schema import Schedule

    with session_scope() as s:
        sched = s.get(Schedule, schedule_id)
        if not sched:
            return
        sched.last_run_at = cron_util.to_naive_cn(last_run_at)
        sched.next_run_at = cron_util.to_naive_cn(next_run_at)
        sched.last_status = last_status
        sched.last_result = last_result
        if enabled is not None:
            sched.enabled = enabled

