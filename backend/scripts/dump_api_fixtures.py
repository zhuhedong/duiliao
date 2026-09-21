#!/usr/bin/env python3
"""Capture real API responses as fixtures for the Flutter model tests.

The Dart model layer is a hand-written port of `frontend/src/lib/collector.ts`.
Asserting it against *actual* backend payloads — rather than payloads hand-written
to match the port — is what catches a field this port got wrong.

Spins up the app against throwaway SQLite databases, seeds the offline draw and
prediction fixtures, runs a real collection, then writes each endpoint's response
to `duiliao_app/assets/fixtures/api/`.

Usage:
    cd backend && .venv/bin/python scripts/dump_api_fixtures.py \
        ../duiliao_app/assets/fixtures/api
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
import uuid
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent.parent
COLLECTOR_ROOT = BACKEND_ROOT / "collector"

# Must be configured before importing the app; both resolve their DB URL on import.
_TMP = Path(tempfile.mkdtemp(prefix="duiliao-fixtures-"))
os.environ["DATABASE_URL"] = f"sqlite:///{_TMP / 'app.db'}"
os.environ["COLLECTOR_DATABASE_URL"] = f"sqlite:///{_TMP / 'collector.db'}"
os.environ["PRED_ALLOW_FIXTURE"] = "1"
os.environ["JWT_SECRET"] = "fixture-jwt-secret"
os.environ["APP_SIGNING_SECRET"] = "fixture-app-signing-secret"
os.environ["ENVIRONMENT"] = "development"

for path in (str(BACKEND_ROOT), str(COLLECTOR_ROOT)):
    if path not in sys.path:
        sys.path.insert(0, path)

FIXTURE_SOURCES = ["haige_pingte", "heizhuang_pingte"]


def _make_user(role: str):
    from app.core.security import hash_password
    from app.db.session import SessionLocal
    from app.models.user import RegistrationSource, User, UserRole, UserStatus

    session = SessionLocal()
    try:
        user = User(
            id=uuid.uuid4().hex,
            username=f"fixture_{role}",
            email=f"fixture_{role}@duiliaoapp.com",
            password_hash=hash_password("FixturePass123"),
            display_name=f"夹具{role}",
            status=UserStatus.ACTIVE,
            role=UserRole(role),
            registration_source=RegistrationSource.ANDROID,
            locale="zh",
            timezone="Asia/Shanghai",
        )
        session.add(user)
        session.commit()
        session.refresh(user)
        session.expunge(user)
        return user
    finally:
        session.close()


def main() -> int:
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("api_fixtures")
    target.mkdir(parents=True, exist_ok=True)

    from fastapi.testclient import TestClient

    from app import collector_bridge as cb
    from app.core.config import settings
    from app.core.security import create_access_token
    from app.db.session import init_db
    from app.main import app
    from app.services.collect_jobs import collect_job_worker
    from tests.crypto_client import CryptoClient

    init_db()
    cb.bootstrap()

    # --- seed real data ---------------------------------------------------- #
    draws = json.loads((COLLECTOR_ROOT / "fixtures" / "draw_macau.json").read_text("utf-8"))
    sync = cb.sync_draws("macau", draws=draws["draws"])
    print(f"seeded draws: {sync['count']}")

    staff = _make_user("staff")
    transport = TestClient(app)
    client = CryptoClient(transport, settings.APP_SIGNING_SECRET)
    client.handshake()
    client.access_token = create_access_token(staff.id)

    # Run a real collection so predictions, judgements and a finished job exist.
    import asyncio

    job = cb.create_collect_job(
        lottery="macau", period="248", source_ids=FIXTURE_SOURCES, concurrency=2
    )
    real_collect = cb.collect

    def collect_with_fixtures(*args, **kwargs):
        kwargs["fixture_dir"] = "fixtures/dingjian"
        return real_collect(*args, **kwargs)

    cb.collect = collect_with_fixtures
    asyncio.run(collect_job_worker._run_job(job["id"]))
    cb.collect = real_collect
    print(f"ran collect job {job['id']}: {cb.get_collect_job(job['id'])['status']}")

    # --- capture ----------------------------------------------------------- #
    captures: list[tuple[str, str, dict]] = [
        ("rules", "/collector/rules", {}),
        ("draws", "/collector/draws", {"lottery": "macau", "limit": 5}),
        ("numbers", "/collector/numbers", {"date": "2026-09-05"}),
        ("sources", "/collector/sources", {}),
        ("consensus", "/collector/consensus", {"lottery": "macau", "period": "2026248"}),
        ("comparison", "/collector/comparison", {"lottery": "macau", "period": "2026248"}),
        (
            "ratings",
            "/collector/ratings",
            {"lottery": "macau", "play_type": "pingte_xiao", "windows": "30,50,100"},
        ),
        ("monitor", "/collector/monitor", {"lottery": "macau"}),
        ("predictions", "/collector/predictions", {"lottery": "macau", "period": "2026248"}),
        ("schedules", "/collector/schedules", {}),
        ("home", "/app/home", {"lottery": "macau"}),
        ("collect_job", f"/app/collect-jobs/{job['id']}", {}),
        ("collect_jobs", "/app/collect-jobs", {"limit": 5}),
        ("events", "/app/events", {"lottery": "macau", "limit": 20}),
        ("version", "/app/version", {"platform": "android", "current": "1.0.0"}),
        ("subscriptions", "/users/me/subscriptions", {}),
        ("me", "/users/me", {}),
        ("sessions", "/users/me/sessions", {}),
        ("ai_prompts", "/ai/prompts", {}),
    ]

    written = 0
    for name, path, params in captures:
        try:
            payload = client.get(path, params=params or None)
        except Exception as exc:
            print(f"  [skip] {name}: {exc}")
            continue
        out = target / f"{name}.json"
        out.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        size = out.stat().st_size
        print(f"  [ok] {name:14s} -> {out.name} ({size} bytes)")
        written += 1

    # A single-source test run, which is the only payload carrying stdout/stderr.
    try:
        payload = client.post(
            f"/collector/sources/{FIXTURE_SOURCES[0]}/test",
            {"lottery": "macau", "period": "248", "fixture_dir": "fixtures/dingjian"},
        )
        (target / "source_test.json").write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"  [ok] {'source_test':14s} -> source_test.json")
        written += 1
    except Exception as exc:
        print(f"  [skip] source_test: {exc}")

    print(f"\nwrote {written} fixtures to {target}")
    shutil.rmtree(_TMP, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
