"""Host pool, fetch observation, dump cache, backfill preview, SSRF guards."""
from __future__ import annotations

import json
import time
from pathlib import Path
from unittest.mock import patch

import pytest

from app.services.settings_service import validate_external_url
from tests.crypto_client import ApiError


def test_host_pool_persists_and_loads(tmp_root):
    from app import collector_bridge as cb

    cb.prepare_modules()
    import host_pool

    fake = {
        "schema": host_pool.SCHEMA,
        "updated_at": host_pool._now_iso(),
        "entry_urls": ["https://588080.com/"],
        "hosts": ["https://example-pool.test"],
        "primary": "https://example-pool.test",
        "errors": [],
        "health": {
            "https://example-pool.test": {
                "ok": True,
                "elapsed_ms": 12,
                "error": None,
            }
        },
    }
    with patch.object(host_pool, "save_api_hosts", return_value=Path("/tmp/hosts.json")):
        saved = host_pool.save_pool(fake)
    assert saved["primary"] == "https://example-pool.test"
    loaded = host_pool.load_pool()
    assert loaded["hosts"] == ["https://example-pool.test"]
    status = host_pool.status()
    assert status["ok"] is True
    assert status["host_count"] == 1


def test_host_pool_health_check_rejects_private(monkeypatch):
    from app import collector_bridge as cb

    cb.prepare_modules()
    import host_pool

    result = host_pool.health_check("http://127.0.0.1")
    assert result["ok"] is False
    assert result["error"]


def test_host_pool_refresh_rejects_private_entry_via_api(staff_client):
    with pytest.raises(ApiError) as exc:
        staff_client.post(
            "/collector/host-pool/refresh",
            body={"entries": ["http://127.0.0.1/"]},
        )
    assert exc.value.status_code in {400, 422}


def test_host_pool_status_endpoint(user_client):
    body = user_client.get("/collector/host-pool")
    assert body.get("ok") is True
    assert "hosts" in body


def test_fetch_observation_roundtrip():
    from app import collector_bridge as cb

    cb.prepare_modules()
    import fetch_observation as fo

    row = fo.record_observation(
        source_id="demo_source",
        lottery="macau",
        period="2026248",
        url="https://example.test/api",
        http_status=200,
        elapsed_ms=42,
        content_hash="abc123",
        ok=True,
        job_id=99,
    )
    assert row["id"]
    listed = fo.list_observations(source_id="demo_source", limit=10)
    assert listed["total"] >= 1
    assert listed["items"][0]["content_hash"] == "abc123"

    from_result = fo.record_from_collect_result(
        {
            "source_id": "demo_source",
            "ok": False,
            "elapsed_ms": 10,
            "error_code": "timeout",
            "error_msg": "timed out",
        },
        lottery="macau",
        period="2026248",
        job_id=100,
    )
    assert from_result is not None
    assert from_result["ok"] is False


def test_fetch_observations_api(user_client):
    from app import collector_bridge as cb

    cb.record_fetch_observation_from_result(
        {"source_id": "api_obs", "ok": True, "elapsed_ms": 5, "content_hash": "h1"},
        lottery="macau",
        period="1",
        job_id=1,
    )
    body = user_client.get("/collector/fetch-observations", params={"source_id": "api_obs"})
    assert body["ok"] is True
    assert body["total"] >= 1


def test_dump_cache_ttl(tmp_path, monkeypatch):
    from app.services.ai import scraped_data as sd

    monkeypatch.setattr(sd, "SCRAPED_DATA_DIR", tmp_path)
    monkeypatch.setattr(sd, "BACKEND_DIR", tmp_path)

    class FakeResult:
        ok = True
        html = "<html>ok</html>"
        raw_html = "<html>raw</html>"
        site_title = "顶尖大师"
        modules = [{"id": 1, "name": "m", "type": "content", "content": "x"}]

        def to_summary(self):
            return {"ok": True, "content_modules_count": 1, "loaded_content_count": 1}

    # save_scraped_data uses BACKEND_DIR-relative paths; point both roots at tmp.
    # Rewrite relative path logic by also patching SCRAPED under tmp as backend/collector/html
    backend = tmp_path
    html_dir = backend / "collector" / "html"
    html_dir.mkdir(parents=True)
    monkeypatch.setattr(sd, "BACKEND_DIR", backend)
    monkeypatch.setattr(sd, "SCRAPED_DATA_DIR", html_dir)
    monkeypatch.setattr(sd, "STORAGE_DIR", backend / "storage")

    paths = sd.save_scraped_data(FakeResult())
    assert paths["file_path"].endswith(".json")
    status = sd.latest_cache_status(max_age_sec=60)
    assert status["fresh"] is True
    loaded = sd.load_latest_scraped_data(max_age_sec=60)
    assert loaded is not None
    assert loaded["site_title"] == "顶尖大师"

    # Expire by rewriting meta timestamp
    meta_path = html_dir / sd.LATEST_META_NAME
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta["saved_at"] = time.time() - 9999
    meta_path.write_text(json.dumps(meta), encoding="utf-8")
    assert sd.latest_cache_status(max_age_sec=60)["fresh"] is False
    assert sd.load_latest_scraped_data(max_age_sec=60) is None


def test_backfill_preview_empty_when_no_sources(user_client):
    body = user_client.get(
        "/collector/backfill-jobs/preview",
        params={"lottery": "macau", "period": "2099999"},
    )
    assert body["ok"] is True
    assert body["period"] == "2099999"
    assert "missing_sources" in body


def test_backfill_submit_dry_run(staff_client):
    body = staff_client.post(
        "/collector/backfill-jobs",
        body={"lottery": "macau", "period": "2099999", "dry_run": True},
    )
    assert body["ok"] is True
    assert body["dry_run"] is True
    assert body["submitted"] is False


def test_catalog_suggestions_endpoint(user_client):
    body = user_client.get("/collector/catalog/suggestions")
    assert body.get("ok") is True
    assert "suggest_new" in body
    assert "suggest_disable" in body
    assert "counts" in body


def test_template_fetch_urls():
    from app import collector_bridge as cb

    cb.prepare_modules()
    from common.template_fetch import byid_path, source_extra_template, urls_for_upstream

    assert byid_path("123") == "/api/v1/index/config/byid/123"
    with pytest.raises(ValueError):
        byid_path("abc")
    extra = source_extra_template(upstream_id=123, parser="pingte_1xiao", kind="xiao")
    assert extra["upstream_id"] == "123"
    urls = urls_for_upstream(123)
    assert urls
    assert urls[0].endswith("/api/v1/index/config/byid/123")


def test_site_dump_latest_404_without_cache(user_client):
    with pytest.raises(ApiError) as exc:
        user_client.get("/collector/site-dump/588080/latest")
    assert exc.value.status_code == 404


def test_validate_external_url_still_blocks_metadata():
    with pytest.raises(ValueError):
        validate_external_url("http://169.254.169.254/latest", resolve_dns=False)
