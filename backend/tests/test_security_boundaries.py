from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.api.v1.ai import AIAnalyzeRequest
from app.services.db_service import test_pg_connection as probe_pg_connection
from app.services.settings_service import validate_external_url


def test_provider_url_rejects_private_and_non_http_targets() -> None:
    with pytest.raises(ValueError, match="内网"):
        validate_external_url("http://127.0.0.1:8080/v1", resolve_dns=False)

    with pytest.raises(ValueError, match="http 或 https"):
        validate_external_url("file:///etc/passwd", resolve_dns=False)


def test_provider_url_preserves_public_custom_gateway_path() -> None:
    assert (
        validate_external_url("HTTPS://api.example.test/v1/", resolve_dns=False)
        == "https://api.example.test/v1"
    )


def test_ai_request_rejects_oversized_custom_data() -> None:
    with pytest.raises(ValidationError, match="不能超过 1 MB"):
        AIAnalyzeRequest(custom_data={"payload": "x" * 1_100_000}, fetch_fresh=False)


def test_pg_probe_rejects_private_target_before_connecting() -> None:
    result = probe_pg_connection("postgresql://user:pass@127.0.0.1:5432/app")
    assert result["ok"] is False
    assert "内网" in result["error"]


def test_site_dump_host_rejects_private_targets() -> None:
    from app.api.v1.collector import _normalize_site_dump_host

    assert _normalize_site_dump_host(None) is None
    assert _normalize_site_dump_host("   ") is None
    with pytest.raises(ValueError, match="内网|本机|本地"):
        _normalize_site_dump_host("http://127.0.0.1")
    with pytest.raises(ValueError, match="内网|本机|本地"):
        _normalize_site_dump_host("169.254.169.254")


def test_fixture_dir_must_stay_under_collector() -> None:
    from app.collector_bridge import COLLECTOR_ROOT, _resolve_fixture_dir

    ok = _resolve_fixture_dir("fixtures/dingjian")
    assert ok is not None
    assert ok.is_relative_to(COLLECTOR_ROOT.resolve())
    with pytest.raises(ValueError, match="collector"):
        _resolve_fixture_dir("/etc")
    with pytest.raises(ValueError, match="collector"):
        _resolve_fixture_dir("../../../../etc")


def test_public_register_defaults_closed_in_production() -> None:
    from app.core.config import Settings

    prod = Settings(
        APP_ENV="production",
        JWT_SECRET="x" * 32,
        APP_SIGNING_SECRET="y" * 16,
        RSA_PRIVATE_KEY_PEM="-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----",
        ALLOW_PUBLIC_REGISTER=None,
        WRITE_SCRIPT_ENABLED=None,
        RUN_SCRIPT_ENABLED=None,
    )
    assert prod.allow_public_register is False
    assert prod.write_script_enabled is False
    assert prod.run_script_enabled is False

    opened = Settings(
        APP_ENV="production",
        JWT_SECRET="x" * 32,
        APP_SIGNING_SECRET="y" * 16,
        RSA_PRIVATE_KEY_PEM="-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----",
        ALLOW_PUBLIC_REGISTER=True,
        WRITE_SCRIPT_ENABLED=True,
    )
    assert opened.allow_public_register is True
    assert opened.write_script_enabled is True




def test_write_script_rejects_dangerous_content(tmp_path, monkeypatch) -> None:
    import registry as reg

    monkeypatch.setattr(reg, "sources_dir", lambda: tmp_path)
    (tmp_path / "__init__.py").write_text("", encoding="utf-8")
    with pytest.raises(reg.RegistryError, match="dangerous|禁止"):
        reg.write_script("safe_name.py", "import os\nos.system('id')\n")
    ok = reg.write_script("safe_name.py", "print('hello')\n")
    assert ok["ok"] is True
    assert (tmp_path / "safe_name.py").is_file()


def test_http_assert_safe_url_blocks_private() -> None:
    from common.http import assert_safe_url

    with pytest.raises(ValueError, match="内网|本机"):
        assert_safe_url("http://127.0.0.1/x")
    with pytest.raises(ValueError, match="内网|本机"):
        assert_safe_url("http://169.254.169.254/latest/meta-data/")
    with pytest.raises(ValueError, match="http"):
        assert_safe_url("file:///etc/passwd")
    assert assert_safe_url("https://example.com/path", resolve_dns=False) == "https://example.com/path"
    assert assert_safe_url("http://198.18.3.171/path", resolve_dns=False) == "http://198.18.3.171/path"


def test_http_get_revalidates_redirect_hops(monkeypatch) -> None:
    """A public URL that redirects to loopback must be rejected mid-chain."""
    import common.http as http_mod

    class _FakeResponse:
        def __init__(self, status_code: int, location: str | None = None):
            self.status_code = status_code
            self.headers = {"location": location} if location else {}

        def raise_for_status(self) -> None:
            if self.status_code >= 400:
                raise RuntimeError(f"status {self.status_code}")

    class _FakeClient:
        def __init__(self, *args, **kwargs):
            self.calls: list[str] = []

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def get(self, url: str, headers=None):
            self.calls.append(url)
            if url.startswith("https://public.example"):
                return _FakeResponse(302, "http://127.0.0.1/secret")
            return _FakeResponse(200)

    monkeypatch.setattr(http_mod, "client", lambda timeout=None: _FakeClient())
    with pytest.raises(ValueError, match="内网|本机"):
        http_mod.get("https://public.example/start", retries=0)


def test_nonce_cache_persists_across_instances() -> None:
    from app.core.security import NonceCache
    from app.db.session import init_db

    init_db()
    a = NonceCache(60)
    b = NonceCache(60)
    assert a.check_and_store("shared-nonce-audit-1") is True
    assert b.check_and_store("shared-nonce-audit-1") is False
