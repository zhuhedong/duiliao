"""In-memory cache and scheduled recomputation for statistical & aggregated endpoints.

This service provides:
1. Thread-safe in-memory caching with TTL for heavy statistical & aggregated endpoints:
   - Trend analysis (`/api/v1/collector/trend`, `/api/v1/trend/getTrend`)
   - Pingte appearance rankings (`/api/v1/collector/pingte-ranking`)
   - Ratings leaderboard (`/api/v1/collector/ratings`)
   - Overview metrics (`/api/v1/collector/overview`)
   - Mobile home workbench aggregate (`/api/v1/app/home`)
2. Startup pre-warming: asynchronously precomputes and caches common views on server boot.
3. Draw-triggered invalidation & recomputation: automatically purges stale data and
   pre-warms the cache when new lottery results are synced/updated (e.g. nightly draw window).
"""
from __future__ import annotations

import asyncio
import copy
import logging
import threading
import time
from datetime import datetime, timezone, timedelta
from typing import Any, Callable, TypeVar

logger = logging.getLogger("app.services.stats_cache")
TZ8 = timezone(timedelta(hours=8))

T = TypeVar("T")

DEFAULT_LOTTERIES = ("macau", "hk", "taiwan", "new")


class StatsCacheService:
    """Thread-safe in-memory cache store with TTL and background warmup."""

    def __init__(self) -> None:
        self._cache: dict[str, tuple[float, Any]] = {}
        self._lock = threading.RLock()
        self._hits = 0
        self._misses = 0
        self._last_warmup_at: str | None = None
        self._last_invalidation_at: str | None = None
        self._is_warming_up = False

    def get(self, key: str) -> Any | None:
        """Retrieve a cached item if present and not expired."""
        now = time.time()
        with self._lock:
            entry = self._cache.get(key)
            if entry is None:
                self._misses += 1
                return None
            expire_at, data = entry
            if now > expire_at:
                # Expired
                del self._cache[key]
                self._misses += 1
                return None
            self._hits += 1
            # Return deepcopy to ensure mutations outside cannot pollute the cache
            return copy.deepcopy(data)

    def set(self, key: str, value: Any, ttl: int = 1800) -> None:
        """Store an item in the cache with a specified TTL in seconds (default 30 mins)."""
        now = time.time()
        expire_at = now + ttl
        with self._lock:
            self._cache[key] = (expire_at, copy.deepcopy(value))

    def delete(self, key: str) -> bool:
        """Delete a single key from cache."""
        with self._lock:
            return self._cache.pop(key, None) is not None

    def invalidate_prefix(self, prefix: str) -> int:
        """Invalidate all keys matching the prefix."""
        with self._lock:
            keys_to_del = [k for k in self._cache if k.startswith(prefix)]
            for k in keys_to_del:
                del self._cache[k]
            if keys_to_del:
                self._last_invalidation_at = datetime.now(TZ8).strftime("%Y-%m-%d %H:%M:%S")
            return len(keys_to_del)

    def invalidate_lottery(self, lottery: str) -> int:
        """Invalidate all cached items for a specific lottery."""
        lottery_str = str(lottery).lower()
        with self._lock:
            keys_to_del = [
                k
                for k in self._cache
                if f":{lottery_str}:" in k
                or k.startswith(f"trend:{lottery_str}")
                or k.startswith(f"pingte_ranking:{lottery_str}")
                or k.startswith(f"ratings:{lottery_str}")
                or k.startswith(f"mobile_home:{lottery_str}")
                or k.startswith(f"draws:{lottery_str}")
            ]
            for k in keys_to_del:
                del self._cache[k]
            # Also invalidate global overview when any lottery updates
            self._cache.pop("overview", None)
            if keys_to_del:
                self._last_invalidation_at = datetime.now(TZ8).strftime("%Y-%m-%d %H:%M:%S")
            logger.info("Invalidated %d cache keys for lottery '%s'", len(keys_to_del), lottery_str)
            return len(keys_to_del)

    def clear(self) -> None:
        """Purge all entries from the cache."""
        with self._lock:
            self._cache.clear()
            self._last_invalidation_at = datetime.now(TZ8).strftime("%Y-%m-%d %H:%M:%S")
            logger.info("Stats cache cleared completely")

    def on_draw_updated(self, lottery: str) -> None:
        """Callback triggered when a lottery draw is inserted or updated."""
        self.invalidate_lottery(lottery)

    def stats(self) -> dict[str, Any]:
        """Return cache health & performance statistics."""
        with self._lock:
            total_reqs = self._hits + self._misses
            hit_rate = round(self._hits / total_reqs, 4) if total_reqs > 0 else 0.0
            return {
                "ok": True,
                "cached_keys_count": len(self._cache),
                "hits": self._hits,
                "misses": self._misses,
                "hit_rate": hit_rate,
                "is_warming_up": self._is_warming_up,
                "last_warmup_at": self._last_warmup_at,
                "last_invalidation_at": self._last_invalidation_at,
                "keys": list(self._cache.keys())[:50],  # preview top 50
            }

    # ------------------------------------------------------------------ #
    # Warmup routines
    # ------------------------------------------------------------------ #
    def warmup_lottery(self, lottery: str) -> None:
        """Precompute and cache common views for a specific lottery (sync worker)."""
        from app import collector_bridge as cb

        lottery = lottery.lower()
        t0 = time.time()
        logger.info("Starting stats cache warmup for lottery '%s'...", lottery)

        # 1. Trend analysis (50 & 100 limit)
        for lim in (50, 100):
            try:
                res = cb.get_trend(lottery=lottery, limit=lim, force_refresh=True)
                self.set(f"trend:{lottery}:{lim}", res, ttl=3600)
            except Exception as e:
                logger.warning("Failed warming trend for %s (limit=%d): %s", lottery, lim, e)

        # 2. Pingte rankings (100, 50, 30 limit, count_desc default)
        for lim in (100, 50, 30):
            try:
                res = cb.get_pingte_ranking(
                    lottery=lottery,
                    limit=lim,
                    dimension="all",
                    order_by="count_desc",
                    force_refresh=True,
                )
                self.set(f"pingte_ranking:{lottery}:{lim}:all:count_desc", res, ttl=3600)
            except Exception as e:
                logger.warning("Failed warming pingte-ranking for %s (limit=%d): %s", lottery, lim, e)

        # 3. Ratings (standard windows 30, 50, 100 for top play types)
        for pt in ("pingte_xiao", "texiao", "tema_n"):
            try:
                res = cb.ratings(
                    lottery=lottery,
                    play_type=pt,
                    windows=(30, 50, 100),
                    force_refresh=True,
                )
                self.set(f"ratings:{lottery}:{pt}:30,50,100", res, ttl=3600)
            except Exception as e:
                logger.warning("Failed warming ratings for %s (%s): %s", lottery, pt, e)

        # 4. Mobile home workbench snapshot (default play_type=pingte_xiao)
        try:
            self._warmup_home_snapshot(lottery, "pingte_xiao")
        except Exception as e:
            logger.warning("Failed warming home snapshot for %s: %s", lottery, e)

        elapsed = time.time() - t0
        logger.info("Stats cache warmup completed for lottery '%s' in %.2fs", lottery, elapsed)

    def _warmup_home_snapshot(self, lottery: str, play_type: str = "pingte_xiao") -> None:
        """Precompute mobile home payload synchronously."""
        from app import collector_bridge as cb

        draws = cb.list_draws(lottery=lottery, limit=1, offset=0)
        latest_period_info = cb.consensus_latest_period(lottery)
        overview = self.get("overview") or cb.overview()

        latest = None
        if isinstance(draws, dict) and draws.get("items"):
            latest = draws["items"][0]
        today_period = cb.period_for_date()
        consensus_period = (
            (latest_period_info or {}).get("current_period")
            if isinstance(latest_period_info, dict)
            else None
        ) or today_period

        consensus = (
            cb.consensus_compare(lottery, consensus_period, play_type)
            if consensus_period
            else None
        )
        comparison = (
            cb.get_period_comparison(lottery, consensus_period)
            if consensus_period
            else None
        )
        ratings = cb.ratings(
            lottery=lottery,
            play_type=play_type,
            windows=(30, 50, 100),
        )
        jobs = cb.list_collect_jobs(limit=3, lottery=lottery)

        consensus_summary = None
        if isinstance(consensus, dict):
            groups = consensus.get("groups") or []
            tallies = consensus.get("atom_tallies") or {}
            consensus_summary = {
                "lottery": consensus.get("lottery"),
                "period": consensus.get("period") or consensus_period,
                "group_count": len(groups),
                "atom_tallies": {
                    "tema_n": (tallies.get("tema_n") or [])[:5],
                    "texiao": (tallies.get("texiao") or [])[:5],
                },
                "groups": [
                    {
                        "play_type": g.get("play_type"),
                        "n_sources": g.get("n_sources"),
                        "leader": g.get("leader"),
                        "leader_votes": g.get("leader_votes"),
                        "consensus_strength": g.get("consensus_strength"),
                        "dispersion": g.get("dispersion"),
                    }
                    for g in groups[:5]
                ],
            }

        comparison_summary = None
        if isinstance(comparison, dict):
            comparison_summary = {
                "lottery": comparison.get("lottery"),
                "period": comparison.get("period") or consensus_period,
                "total": comparison.get("total", 0),
                "valid": comparison.get("valid", 0),
                "empty": comparison.get("empty", 0),
                "agreement_rate": comparison.get("agreement_rate"),
            }

        trend7d: list[dict[str, Any]] = []
        if isinstance(overview, dict) and isinstance(overview.get("daily"), list):
            for day in overview["daily"][:7]:
                trend7d.append({
                    "date": day.get("date"),
                    "total": day.get("total", 0),
                    "hit": day.get("hit", 0),
                    "miss": day.get("miss", 0),
                    "judged": day.get("judged", 0),
                    "hit_rate": day.get("hit_rate"),
                })

        lead_group = (
            (consensus or {}).get("groups", [None])[0]
            if isinstance(consensus, dict)
            else None
        )
        tallies = (consensus or {}).get("atom_tallies") or {}

        home_payload = {
            "lottery": lottery,
            "play_type": play_type,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "latest_draw": latest,
            "consensus_period": consensus_period,
            "lead_group": lead_group,
            "consensus_groups": (consensus or {}).get("groups", [])[:5] if isinstance(consensus, dict) else [],
            "tema_tallies": (tallies.get("tema_n") or [])[:10],
            "texiao_tallies": (tallies.get("texiao") or [])[:10],
            "trend7d": trend7d,
            "comparison_summary": comparison_summary,
            "consensus_summary": consensus_summary,
            "recent_ratings": (ratings or {}).get("ratings", [])[:10] if isinstance(ratings, dict) else [],
            "recent_jobs": jobs or [],
        }
        self.set(f"mobile_home:{lottery}:{play_type}", home_payload, ttl=1800)

    def warmup_global(self) -> None:
        """Precompute global statistical views like overview."""
        from app import collector_bridge as cb

        try:
            t0 = time.time()
            ov = cb.overview(force_refresh=True)
            self.set("overview", ov, ttl=1800)
            logger.info("Global overview cache warmed in %.2fs", time.time() - t0)
        except Exception as e:
            logger.warning("Failed warming global overview: %s", e)

    def warmup_all(self, lotteries: list[str] | None = None) -> None:
        """Run a full warmup across all configured lotteries."""
        targets = lotteries or list(DEFAULT_LOTTERIES)
        self._is_warming_up = True
        t0 = time.time()
        logger.info("Starting full stats cache warmup for lotteries: %s", targets)
        try:
            self.warmup_global()
            for lot in targets:
                self.warmup_lottery(lot)
            self._last_warmup_at = datetime.now(TZ8).strftime("%Y-%m-%d %H:%M:%S")
            logger.info("Full stats cache warmup finished in %.2fs", time.time() - t0)
        finally:
            self._is_warming_up = False

    async def warmup_background(self, lotteries: list[str] | None = None, delay_seconds: float = 1.0) -> None:
        """Asynchronously warm up cache off the main thread."""
        if delay_seconds > 0:
            await asyncio.sleep(delay_seconds)
        await asyncio.to_thread(self.warmup_all, lotteries)

    async def warmup_lottery_async(self, lottery: str) -> None:
        """Asynchronously warm up a single lottery off the main thread."""
        await asyncio.to_thread(self.warmup_lottery, lottery)


# Global singleton instance
stats_cache = StatsCacheService()
