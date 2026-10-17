"""Tests for the statistics and aggregation cache service (stats_cache_service)."""
import time
from fastapi.testclient import TestClient

from app.main import app
from app.services.stats_cache_service import stats_cache, StatsCacheService


def test_stats_cache_store_basic_operations():
    cache = StatsCacheService()
    cache.set("test:1", {"a": 100}, ttl=60)
    assert cache.get("test:1") == {"a": 100}

    # Verify deepcopy safety: mutating returned data does not pollute cache
    val = cache.get("test:1")
    val["a"] = 999
    assert cache.get("test:1") == {"a": 100}

    # Deletion
    assert cache.delete("test:1") is True
    assert cache.get("test:1") is None

    # Expiry
    cache.set("test:short", "hello", ttl=0.01)
    time.sleep(0.02)
    assert cache.get("test:short") is None


def test_stats_cache_invalidation_by_lottery():
    cache = StatsCacheService()
    cache.set("trend:macau:100", {"data": 1}, ttl=300)
    cache.set("pingte_ranking:macau:100:all:count_desc", {"data": 2}, ttl=300)
    cache.set("trend:hk:100", {"data": 3}, ttl=300)
    cache.set("overview", {"totals": 4}, ttl=300)

    # Invalidate macau
    removed = cache.invalidate_lottery("macau")
    assert removed == 2
    assert cache.get("trend:macau:100") is None
    assert cache.get("pingte_ranking:macau:100:all:count_desc") is None
    # HK is kept
    assert cache.get("trend:hk:100") == {"data": 3}
    # Global overview is purged on draw update
    assert cache.get("overview") is None


def test_cached_endpoints_and_stats_api(user_client, seeded_draws):
    stats_cache.clear()

    # Initial call (cache miss)
    res1 = user_client.get("/collector/pingte-ranking?lottery=macau&limit=50")
    assert res1["ok"] is True

    # Second call (cache hit)
    res2 = user_client.get("/collector/pingte-ranking?lottery=macau&limit=50")
    assert res2["ok"] is True
    assert res1["latest_period"] == res2["latest_period"]

    # Check cache stats endpoint
    stats = user_client.get("/collector/cache/stats")
    assert stats["ok"] is True
    assert stats["cached_keys_count"] >= 1
    assert stats["hits"] >= 1

    # Force refresh bypasses cache
    res_fresh = user_client.get("/collector/pingte-ranking?lottery=macau&limit=50&force_refresh=true")
    assert res_fresh["ok"] is True


def test_warmup_and_clear_endpoints(user_client, admin_client, seeded_draws):
    # Clear cache via admin
    clr = admin_client.post("/collector/cache/clear?lottery=macau")
    assert clr["ok"] is True

    # Warmup via admin
    wm = admin_client.post("/collector/cache/warmup?lottery=macau")
    assert wm["ok"] is True
    assert wm["stats"]["cached_keys_count"] >= 1
    assert "trend:macau:50" in wm["stats"]["keys"] or "pingte_ranking:macau:50:all:count_desc" in wm["stats"]["keys"]
