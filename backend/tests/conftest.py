"""Shared pytest fixtures for the backend test suite.

Every test runs against throwaway SQLite databases in a temp directory and uses
the offline collection fixtures, so nothing here touches the real databases or
makes an outbound HTTP request.

Environment has to be set before ``app`` or the collector modules are imported,
because both resolve their database URL at import time.
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

BACKEND_ROOT = Path(__file__).resolve().parent.parent
COLLECTOR_ROOT = BACKEND_ROOT / "collector"

# --- Environment must be configured before importing the app --------------- #
_TMP = Path(tempfile.mkdtemp(prefix="duiliao-tests-"))
os.environ["DATABASE_URL"] = f"sqlite:///{_TMP / 'app.db'}"
os.environ["COLLECTOR_DATABASE_URL"] = f"sqlite:///{_TMP / 'collector.db'}"
# Lets source scripts read from collector/fixtures instead of the network.
os.environ["PRED_ALLOW_FIXTURE"] = "1"
os.environ["JWT_SECRET"] = "test-jwt-secret-not-production"
os.environ["APP_SIGNING_SECRET"] = "test-signing-secret-not-production"
os.environ["ENVIRONMENT"] = "development"
# The encryption middleware is exercised by its own test module; the endpoint
# tests drive the routes directly and would otherwise need a handshake per call.
os.environ["ENFORCE_REQUEST_SIGNATURE"] = "true"

for path in (str(BACKEND_ROOT), str(COLLECTOR_ROOT)):
    if path not in sys.path:
        sys.path.insert(0, path)


def pytest_sessionfinish(session, exitstatus):  # noqa: ARG001
    shutil.rmtree(_TMP, ignore_errors=True)


@pytest.fixture(scope="session")
def tmp_root() -> Path:
    return _TMP


@pytest.fixture(scope="session", autouse=True)
def _prepare_databases():
    """Create both schemas once for the whole session."""
    from app.db.session import init_db

    init_db()
    from app import collector_bridge as cb

    cb.bootstrap()
    yield


@pytest.fixture(scope="session")
def seeded_draws():
    """Load the checked-in macau draw fixture so judging has something to judge.

    ``collector/fixtures/draw_macau.json`` contains periods 2026247 and 2026248,
    which are the periods the prediction fixtures reference.
    """
    import json

    from app import collector_bridge as cb

    payload = json.loads((COLLECTOR_ROOT / "fixtures" / "draw_macau.json").read_text("utf-8"))
    result = cb.sync_draws("macau", draws=payload["draws"])
    assert result["count"] >= 2
    return payload["draws"]


@pytest.fixture
def db_session():
    from app.db.session import SessionLocal

    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


def _make_user(role: str):
    """Insert an active user with the given role and return it."""
    from app.core.security import hash_password
    from app.db.session import SessionLocal
    from app.models.user import RegistrationSource, User, UserRole, UserStatus

    suffix = uuid.uuid4().hex[:8]
    session = SessionLocal()
    try:
        user = User(
            id=uuid.uuid4().hex,
            username=f"{role}_{suffix}",
            email=f"{role}_{suffix}@duiliaoapp.com",
            password_hash=hash_password("TestPass123"),
            display_name=f"{role} {suffix}",
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


@pytest.fixture
def user_account():
    return _make_user("user")


@pytest.fixture
def staff_account():
    return _make_user("staff")


@pytest.fixture
def admin_account():
    return _make_user("admin")


def _client_for(user):
    """A ``CryptoClient`` authenticated as ``user`` with a real access token.

    Nothing is stubbed: the client performs a genuine encryption handshake, signs
    every request, and carries a real JWT, so role enforcement and the middleware
    both run exactly as in production. (Overriding ``get_current_user`` instead
    would break any test that needs two different users at once, because the
    override is global to the app.)
    """
    from fastapi.testclient import TestClient

    from app.core.config import settings
    from app.core.security import create_access_token
    from app.main import app

    from tests.crypto_client import CryptoClient

    app.dependency_overrides.clear()
    transport = TestClient(app)
    client = CryptoClient(transport, settings.APP_SIGNING_SECRET)
    client.handshake()
    client.access_token = create_access_token(user.id)
    client.user = user
    return client


@pytest.fixture
def user_client(user_account):
    return _client_for(user_account)


@pytest.fixture
def staff_client(staff_account):
    return _client_for(staff_account)


@pytest.fixture
def admin_client(admin_account):
    return _client_for(admin_account)


@pytest.fixture
def raw_client():
    """An unauthenticated ``TestClient`` with no dependency overrides."""
    from fastapi.testclient import TestClient

    from app.main import app

    app.dependency_overrides.clear()
    return TestClient(app)


@pytest.fixture
def crypto_client(raw_client):
    """A signed transport client with no credentials attached."""
    from app.core.config import settings

    from tests.crypto_client import CryptoClient

    client = CryptoClient(raw_client, settings.APP_SIGNING_SECRET)
    client.handshake()
    return client


@pytest.fixture
def fixture_sources() -> list[str]:
    """Source ids that have offline fixtures checked into the repo."""
    return ["haige_pingte", "heizhuang_pingte"]
