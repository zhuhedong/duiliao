from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

from common import ROOT
from common.config import load_yaml
from common.contract import pred_loads
from common.period import normalize

TZ8 = timezone(timedelta(hours=8))


def new_run_id(now: datetime) -> str:
    utc = now.astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"{utc}-{secrets.token_hex(2)}"


def load_sources(cfg: dict, lottery: str | None, only: set[str] | None) -> list[dict]:
    rows = []
    for row in cfg.get("sources") or []:
        if not row.get("enabled", True):
            continue
        if lottery and row.get("lottery") != lottery:
            continue
        if only and row["source_id"] not in only:
            continue
        rows.append(row)
    return rows


def run_one(row: dict, lottery: str, period: str | None, extra_args: list[str]) -> dict:
    from registry import RegistryError, script_path_for

    try:
        script = script_path_for(row.get("script_path") or "")
    except RegistryError as exc:
        return {
            "source_id": row.get("source_id") or "unknown",
            "ok": False,
            "exit_code": None,
            "elapsed_ms": 0,
            "item_count": 0,
            "data": None,
            "error_code": "bad_script_path",
            "error_msg": exc.message,
        }
    if not script.exists():
        return {
            "source_id": row["source_id"],
            "ok": False,
            "exit_code": None,
            "elapsed_ms": 0,
            "item_count": 0,
            "data": None,
            "error_code": "no_script",
            "error_msg": f"missing sources/{script.name}",
        }
    cmd = [sys.executable, str(script), "--lottery", lottery]
    if period:
        cmd += ["--period", period]
    cmd += extra_args
    timeout = int(row.get("timeout_sec") or 30)
    t0 = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            env={**os.environ, "PYTHONPATH": str(ROOT), "PYTHONIOENCODING": "utf-8"},
        )
    except subprocess.TimeoutExpired as e:
        err = e.stderr
        if isinstance(err, bytes):
            err = err.decode("utf-8", "replace")
        hint = (err or "").strip()
        msg = f"timeout {timeout}s（脚本进程未退出）"
        if hint:
            msg = f"{msg}: {hint[:400]}"
        return {
            "source_id": row["source_id"],
            "ok": False,
            "exit_code": None,
            "elapsed_ms": int((time.perf_counter() - t0) * 1000),
            "item_count": 0,
            "data": None,
            "stdout": "",
            "stderr": hint or msg,
            "error_code": "timeout",
            "error_msg": msg,
        }
    elapsed = int((time.perf_counter() - t0) * 1000)
    stderr_text = proc.stderr or ""
    if proc.stderr:
        sys.stderr.write(proc.stderr)
        if not proc.stderr.endswith("\n"):
            sys.stderr.write("\n")
    stdout = (proc.stdout or "").strip()
    if not stdout:
        return {
            "source_id": row["source_id"],
            "ok": False,
            "exit_code": proc.returncode,
            "elapsed_ms": elapsed,
            "item_count": 0,
            "data": None,
            "stdout": "",
            "stderr": stderr_text,
            "error_code": "empty_stdout",
            "error_msg": "source printed no JSON",
        }
    try:
        pred = pred_loads(stdout)
        data = json.loads(stdout)
    except Exception as e:
        return {
            "source_id": row["source_id"],
            "ok": False,
            "exit_code": proc.returncode,
            "elapsed_ms": elapsed,
            "item_count": 0,
            "data": None,
            "raw_output": stdout,
            "stdout": stdout,
            "stderr": stderr_text,
            "error_code": "bad_json",
            "error_msg": str(e)[:500],
        }
    ok = bool(pred.ok) and proc.returncode == 0
    err = pred.error
    return {
        "source_id": row["source_id"],
        "ok": ok,
        "exit_code": proc.returncode,
        "elapsed_ms": elapsed,
        "item_count": len(pred.items) if pred.ok else 0,
        "data": data,
        "stdout": stdout,
        "stderr": stderr_text,
        "error_code": None if ok else (err.code if err else "source_fail"),
        "error_msg": None if ok else (err.message if err else "ok=false"),
    }


def write_raw(run_id: str, result: dict) -> str | None:
    data = result.get("data")
    if not data:
        return None
    d = ROOT / "out" / "raw" / run_id
    d.mkdir(parents=True, exist_ok=True)
    path = d / f"{result['source_id']}.json"
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return str(path.relative_to(ROOT)).replace("\\", "/")


def main() -> None:
    p = argparse.ArgumentParser(description="schedule source scripts, emit run.v1")
    p.add_argument("--lottery", required=True, choices=["hk", "macau", "taiwan", "new"])
    p.add_argument("--period", required=True, help="canonical or raw, e.g. 248 or 2026248")
    p.add_argument("--out", default="out/latest.json")
    p.add_argument("--source", action="append", default=[], help="only these source_id, repeatable")
    p.add_argument("--fixture-dir", default=None, help="pass --fixture <dir>/<id>.json to each source")
    p.add_argument("--concurrency", type=int, default=8, help="concurrent thread pool size (default 8)")
    p.add_argument("--config", default=None)
    args = p.parse_args()

    cfg = load_yaml(Path(args.config) if args.config else None)
    period = normalize(args.lottery, args.period)
    only = set(args.source) if args.source else None
    sources = load_sources(cfg, args.lottery, only)
    now = datetime.now(TZ8)
    run_id = new_run_id(now)

    import concurrent.futures

    def _execute_source(row: dict) -> dict:
        extra: list[str] = []
        if args.fixture_dir:
            fp = Path(args.fixture_dir) / f"{row['source_id']}.json"
            if fp.exists():
                extra += ["--fixture", str(fp)]
        return run_one(row, args.lottery, period, extra)

    concurrency = max(1, min(args.concurrency, len(sources) or 1))
    if concurrency == 1 or len(sources) <= 1:
        results: list[dict] = [_execute_source(row) for row in sources]
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as executor:
            results = list(executor.map(_execute_source, sources))

    for r in results:
        r["raw_path"] = write_raw(run_id, r)

    payload = {
        "ok": True,
        "schema": "run.v1",
        "run_id": run_id,
        "run_at": now.isoformat(),
        "lottery": args.lottery,
        "period": period,
        "results": [
            {
                "source_id": r["source_id"],
                "ok": r["ok"],
                "exit_code": r["exit_code"],
                "elapsed_ms": r["elapsed_ms"],
                "item_count": r["item_count"],
                "data": r["data"],
                "error_code": r.get("error_code"),
                "error_msg": r.get("error_msg"),
                "raw_path": r.get("raw_path"),
                "raw_output": r.get("raw_output"),
            }
            for r in results
        ],
    }
    out = Path(args.out)
    if not out.is_absolute():
        out = ROOT / out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    sys.stdout.write(json.dumps({
        "ok": True,
        "run_id": run_id,
        "out": str(out),
        "source_total": len(results),
        "source_ok": sum(1 for r in results if r["ok"]),
    }, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
