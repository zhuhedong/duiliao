"""Unit and real-DB tests for per-zodiac Pingte draw history and streak/omission intervals."""
from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
COLLECTOR_DIR = Path(__file__).resolve().parent.parent
for p in (str(BACKEND_DIR), str(COLLECTOR_DIR)):
    if p not in sys.path:
        sys.path.insert(0, p)

from common.xiao import XIAO
from collector.pingte_history import (
    build_periods_data,
    compute_all_zodiacs_pingte_history,
    compute_single_zodiac_history,
    format_segment_text,
)


def _make_draw(period: str, numbers: list[int], draw_date: str = "2026-06-01") -> dict:
    return {
        "period": period,
        "draw_date": draw_date,
        "numbers": numbers,
        "z1": numbers[0],
        "z2": numbers[1],
        "z3": numbers[2],
        "z4": numbers[3],
        "z5": numbers[4],
        "z6": numbers[5],
        "tema": numbers[6],
    }


class TestPingteHistoryUnit(unittest.TestCase):
    def test_format_segment_text(self):
        self.assertEqual(format_segment_text("hit", "2026005", "2026005", 1), "2026005~2026005 连开1期")
        self.assertEqual(format_segment_text("hit", "2026001", "2026004", 4), "2026001~2026004 连开4期")
        self.assertEqual(format_segment_text("miss", "2026005", "2026005", 1), "2026005~2026005 没出1期")
        self.assertEqual(format_segment_text("miss", "2026005", "2026008", 4), "2026005~2026008 没出4期")

    def test_empty_draws(self):
        res = compute_all_zodiacs_pingte_history([], target_xiao="马")
        self.assertEqual(res["sample_periods"], 0)
        self.assertIsNone(res["latest_period"])
        self.assertIsNone(res["earliest_period"])
        self.assertEqual(len(res["zodiacs"]), 12)
        zh = res["zodiacs_map"]["马"]
        self.assertIsNotNone(zh)
        self.assertEqual(zh["name"], "马")
        self.assertEqual(zh["count"], 0)
        self.assertEqual(zh["periods_count"], 0)
        self.assertEqual(zh["miss_periods_count"], 0)
        self.assertEqual(zh["current_consecutive"], 0)
        self.assertEqual(zh["current_omission"], 0)
        self.assertIsNone(zh["current_range"])
        self.assertIsNone(zh["max_consecutive_range"])
        self.assertIsNone(zh["max_omission_range"])
        self.assertEqual(zh["segments"], [])
        self.assertEqual(zh["period_history"], [])

    def test_single_period_hit_and_miss(self):
        # In 2026-06-01 (lunar year 2026 = 马):
        # 01 is 马, 02 is 蛇, 03 is 龙, 04 is 兔, 05 is 虎, 06 is 牛, 07 is 鼠
        draws = [_make_draw("2026001", [2, 3, 4, 5, 6, 7, 1], "2026-06-01")]
        res = compute_all_zodiacs_pingte_history(draws)
        zh_ma = res["zodiacs_map"]["马"]
        self.assertEqual(zh_ma["count"], 1)
        self.assertEqual(zh_ma["ping_count"], 0)
        self.assertEqual(zh_ma["tema_count"], 1)
        self.assertEqual(zh_ma["periods_count"], 1)
        self.assertEqual(zh_ma["miss_periods_count"], 0)
        self.assertEqual(zh_ma["current_consecutive"], 1)
        self.assertEqual(zh_ma["current_omission"], 0)
        self.assertEqual(zh_ma["current_range"]["text"], "2026001~2026001 连开1期")
        self.assertEqual(zh_ma["max_consecutive_range"]["text"], "2026001~2026001 连开1期")
        self.assertIsNone(zh_ma["max_omission_range"])

        # 羊 (11) did not appear in 2026001
        zh_yang = res["zodiacs_map"]["羊"]
        self.assertEqual(zh_yang["count"], 0)
        self.assertEqual(zh_yang["periods_count"], 0)
        self.assertEqual(zh_yang["miss_periods_count"], 1)
        self.assertEqual(zh_yang["current_consecutive"], 0)
        self.assertEqual(zh_yang["current_omission"], 1)
        self.assertEqual(zh_yang["current_range"]["text"], "2026001~2026001 没出1期")
        self.assertIsNone(zh_yang["max_consecutive_range"])
        self.assertEqual(zh_yang["max_omission_range"]["text"], "2026001~2026001 没出1期")

    def test_alternating_streak_and_omission_segments(self):
        # Track 马 (numbers in 2026 after CNY: 01, 13, 25, 37, 49)
        # Non-马 balls: 2, 3, 4, 5, 6, 7, 8
        # Chronological sequence of 10 periods (2026001 .. 2026010):
        # 2026001~2026003: HIT 3 periods (2026001 has 2 马 balls: 01 ping + 13 tema)
        # 2026004~2026007: MISS 4 periods
        # 2026008: HIT 1 period
        # 2026009~2026010: MISS 2 periods (current)
        chronological = [
            _make_draw("2026001", [1, 2, 3, 4, 5, 6, 13], "2026-06-01"),  # hit (2 balls: 1 ping, 1 tema)
            _make_draw("2026002", [25, 2, 3, 4, 5, 6, 7], "2026-06-02"),  # hit (1 ball: 1 ping)
            _make_draw("2026003", [2, 3, 4, 5, 6, 7, 49], "2026-06-03"),  # hit (1 ball: 1 tema)
            _make_draw("2026004", [2, 3, 4, 5, 6, 7, 8], "2026-06-04"),   # miss
            _make_draw("2026005", [2, 3, 4, 5, 6, 7, 8], "2026-06-05"),   # miss
            _make_draw("2026006", [2, 3, 4, 5, 6, 7, 8], "2026-06-06"),   # miss
            _make_draw("2026007", [2, 3, 4, 5, 6, 7, 8], "2026-06-07"),   # miss
            _make_draw("2026008", [37, 2, 3, 4, 5, 6, 7], "2026-06-08"),  # hit (1 ball: 1 ping)
            _make_draw("2026009", [2, 3, 4, 5, 6, 7, 8], "2026-06-09"),   # miss
            _make_draw("2026010", [2, 3, 4, 5, 6, 7, 8], "2026-06-10"),   # miss (latest)
        ]
        res = compute_all_zodiacs_pingte_history(chronological, target_xiao="马肖")
        self.assertEqual(res["target_xiao"], "马")
        zh = res["zodiacs_map"]["马"]

        self.assertEqual(zh["name"], "马")
        self.assertEqual(zh["count"], 5)
        self.assertEqual(zh["ping_count"], 3)
        self.assertEqual(zh["tema_count"], 2)
        self.assertEqual(zh["periods_count"], 4)
        self.assertEqual(zh["miss_periods_count"], 6)
        self.assertEqual(zh["multi_ball_periods_count"], 1)
        self.assertEqual(zh["frequency"], 40.0)

        # Current status: 2026009~2026010 没出2期
        self.assertEqual(zh["current_consecutive"], 0)
        self.assertEqual(zh["current_omission"], 2)
        self.assertEqual(zh["current_range"]["type"], "miss")
        self.assertEqual(zh["current_range"]["start_period"], "2026009")
        self.assertEqual(zh["current_range"]["end_period"], "2026010")
        self.assertEqual(zh["current_range"]["length"], 2)
        self.assertEqual(zh["current_range"]["text"], "2026009~2026010 没出2期")

        # Max consecutive: 2026001~2026003 连开3期
        self.assertEqual(zh["max_consecutive"], 3)
        self.assertEqual(zh["max_consecutive_range"]["start_period"], "2026001")
        self.assertEqual(zh["max_consecutive_range"]["end_period"], "2026003")
        self.assertEqual(zh["max_consecutive_range"]["text"], "2026001~2026003 连开3期")

        # Max omission: 2026004~2026007 没出4期
        self.assertEqual(zh["max_omission"], 4)
        self.assertEqual(zh["max_omission_range"]["start_period"], "2026004")
        self.assertEqual(zh["max_omission_range"]["end_period"], "2026007")
        self.assertEqual(zh["max_omission_range"]["text"], "2026004~2026007 没出4期")

        # 4 segments total (newest first in zh["segments"])
        self.assertEqual(zh["segments_count"], 4)
        self.assertEqual(zh["hit_segments_count"], 2)
        self.assertEqual(zh["miss_segments_count"], 2)
        seg_texts = [s["text"] for s in zh["segments"]]
        self.assertEqual(
            seg_texts,
            [
                "2026009~2026010 没出2期",
                "2026008~2026008 连开1期",
                "2026004~2026007 没出4期",
                "2026001~2026003 连开3期",
            ],
        )
        self.assertTrue(zh["segments"][0]["is_current"])
        self.assertFalse(zh["segments"][1]["is_current"])

        # Distributions (including top-level latest_* fields for mobile & ranges list for web)
        self.assertEqual(
            [(d["length"], d["count"]) for d in zh["streak_distribution"]],
            [(3, 1), (1, 1)],
        )
        self.assertEqual(zh["streak_distribution"][0]["latest_start_period"], "2026001")
        self.assertEqual(zh["streak_distribution"][0]["latest_end_period"], "2026003")
        self.assertEqual(zh["streak_distribution"][0]["latest_text"], "2026001~2026003 连开3期")
        self.assertFalse(zh["streak_distribution"][0]["is_current"])
        self.assertEqual(len(zh["streak_distribution"][0]["ranges"]), 1)

        self.assertEqual(
            [(d["length"], d["count"]) for d in zh["omission_distribution"]],
            [(4, 1), (2, 1)],
        )
        self.assertEqual(zh["omission_distribution"][0]["latest_start_period"], "2026004")
        self.assertEqual(zh["omission_distribution"][0]["latest_end_period"], "2026007")
        self.assertTrue(zh["omission_distribution"][1]["is_current"])

        # Period history (newest first: 2026010 down to 2026001)
        ph = zh["period_history"]
        self.assertEqual(len(ph), 10)
        self.assertEqual(ph[0]["period"], "2026010")
        self.assertEqual(ph[0]["running_text"], "没出第2期")
        self.assertEqual(ph[0]["segment_text"], "2026009~2026010 没出2期")
        self.assertEqual(ph[-1]["period"], "2026001")
        self.assertEqual(ph[-1]["running_text"], "连开第1期")
        self.assertEqual(ph[-1]["ball_count"], 2)
        self.assertTrue(ph[-1]["has_tema"])

        # Other zodiacs should have period_history omitted when target_xiao is specified
        self.assertEqual(res["zodiacs_map"]["鼠"]["period_history"], [])

    def test_lunar_new_year_boundary_zodiac_rotation(self):
        # 2026 CNY is 2026-02-17.
        # On 2026-02-16 (lunar year 2025 = 蛇): number 01 is 蛇, number 12 is 马.
        # On 2026-02-17 (lunar year 2026 = 马): number 01 is 马, number 02 is 蛇.
        chronological = [
            _make_draw("2026047", [12, 3, 4, 5, 6, 7, 8], "2026-02-16"),  # 12 is 马
            _make_draw("2026048", [1, 3, 4, 5, 6, 7, 8], "2026-02-17"),   # 01 is 马
        ]
        res = compute_all_zodiacs_pingte_history(chronological, target_xiao="马")
        zh = res["zodiacs_map"]["马"]
        self.assertEqual(zh["periods_count"], 2)
        self.assertEqual(zh["current_consecutive"], 2)
        self.assertEqual(zh["current_range"]["text"], "2026047~2026048 连开2期")

    def test_missing_draw_date_derives_from_period(self):
        # 2025300 (Oct 2025, lunar year 2025 = 蛇, number 01 is 蛇) vs 2026200 (July 2026, lunar year 2026 = 马, number 01 is 马)
        d1 = _make_draw("2025300", [1, 3, 4, 5, 6, 7, 8], "")
        d1.pop("draw_date", None)
        d2 = _make_draw("2026200", [1, 3, 4, 5, 6, 7, 8], "2026-07-19")
        res = compute_all_zodiacs_pingte_history([d1, d2])
        # In 2025300, 01 is 蛇 (not 马); in 2026200, 01 is 马
        self.assertEqual(res["zodiacs_map"]["马"]["periods_count"], 1)
        self.assertEqual(res["zodiacs_map"]["马"]["current_range"]["text"], "2026200~2026200 连开1期")
        self.assertEqual(res["zodiacs_map"]["马"]["max_omission_range"]["text"], "2025300~2025300 没出1期")

    def test_real_pred_db_invariants(self):
        db_path = COLLECTOR_DIR / "data" / "pred.db"
        if not db_path.exists():
            self.skipTest("pred.db not found")

        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "SELECT period, draw_date, z1, z2, z3, z4, z5, z6, tema FROM draw WHERE lottery = 'macau' ORDER BY period ASC"
        ).fetchall()
        conn.close()

        draws = [dict(r) for r in rows]
        self.assertGreater(len(draws), 0)

        res = compute_all_zodiacs_pingte_history(draws, include_period_history=True)
        self.assertEqual(res["sample_periods"], len(draws))
        self.assertEqual(len(res["zodiacs"]), 12)

        for z in res["zodiacs"]:
            self.assertIn(z["name"], XIAO)
            self.assertEqual(z["periods_count"] + z["miss_periods_count"], len(draws))
            self.assertEqual(z["ping_count"] + z["tema_count"], z["count"])
            self.assertGreaterEqual(z["count"], z["periods_count"])
            self.assertEqual(sum(s["length"] for s in z["segments"]), len(draws))
            self.assertEqual(
                sum(d["count"] for d in z["streak_distribution"]),
                z["hit_segments_count"],
            )
            self.assertEqual(
                sum(d["count"] for d in z["omission_distribution"]),
                z["miss_segments_count"],
            )
            self.assertEqual(len(z["period_history"]), len(draws))

    def test_collector_bridge_zodiac_history_and_ranking(self):
        """Verify collector_bridge.get_pingte_zodiac_history and get_pingte_ranking against real pred.db."""
        from contextlib import contextmanager
        from datetime import date as dt_date
        import types
        from unittest.mock import patch

        db_path = COLLECTOR_DIR / "data" / "pred.db"
        if not db_path.exists():
            self.skipTest("pred.db not found")

        class _Col:
            def __init__(self, name: str):
                self.name = name

            def __eq__(self, other):
                return ("=", self.name, other)

            def __ge__(self, other):
                return (">=", self.name, other)

            def __le__(self, other):
                return ("<=", self.name, other)

            def desc(self):
                return ("DESC", self.name)

        class _DrawModel:
            lottery = _Col("lottery")
            period = _Col("period")

        class _FakeSelect:
            def __init__(self):
                self.conds = []
                self.lim = None

            def where(self, *conds):
                s = _FakeSelect()
                s.conds = list(self.conds) + list(conds)
                s.lim = self.lim
                return s

            def order_by(self, *_args):
                return self

            def limit(self, n: int):
                s = _FakeSelect()
                s.conds = list(self.conds)
                s.lim = n
                return s

        class _DrawObj:
            def __init__(self, row):
                self.lottery = row["lottery"]
                self.period = str(row["period"])
                dd = row["draw_date"]
                self.draw_date = dt_date.fromisoformat(dd[:10]) if dd else None
                self.z1 = row["z1"]
                self.z2 = row["z2"]
                self.z3 = row["z3"]
                self.z4 = row["z4"]
                self.z5 = row["z5"]
                self.z6 = row["z6"]
                self.tema = row["tema"]

        class _FakeSession:
            def scalars(self, stmt: _FakeSelect):
                conn = sqlite3.connect(str(db_path))
                conn.row_factory = sqlite3.Row
                sql = "SELECT lottery, period, draw_date, z1, z2, z3, z4, z5, z6, tema FROM draw"
                params = []
                if stmt.conds:
                    clauses = []
                    for op, col, val in stmt.conds:
                        clauses.append(f"{col} {op} ?")
                        params.append(val)
                    sql += " WHERE " + " AND ".join(clauses)
                sql += " ORDER BY period DESC"
                if stmt.lim is not None:
                    sql += f" LIMIT {int(stmt.lim)}"
                rows = conn.execute(sql, params).fetchall()
                conn.close()
                return [_DrawObj(r) for r in rows]

        @contextmanager
        def _fake_session_scope(guard: bool = False):  # noqa: ARG001
            yield _FakeSession()

        fake_sa = types.ModuleType("sqlalchemy")
        fake_sa.select = lambda _model: _FakeSelect()
        fake_db = types.ModuleType("db")
        fake_db.session_scope = _fake_session_scope
        fake_schema = types.ModuleType("schema")
        fake_schema.Draw = _DrawModel

        import app.collector_bridge as cb
        from app.services.stats_cache_service import stats_cache

        stats_cache.clear()
        with patch.object(cb, "bootstrap", lambda: None), patch.dict(
            sys.modules,
            {"sqlalchemy": fake_sa, "db": fake_db, "schema": fake_schema},
        ):
            # 1. Custom period range [2026001, 2026200] with limit=30 must NOT be truncated to 30
            r_range = cb.get_pingte_zodiac_history(
                lottery="macau",
                xiao="马",
                limit=30,
                period_from="2026001",
                period_to="2026200",
            )
            self.assertTrue(r_range["ok"])
            self.assertEqual(r_range["sample_scope"], "range")
            self.assertEqual(r_range["sample_periods"], 200)
            self.assertEqual(r_range["earliest_period"], "2026001")
            self.assertEqual(r_range["latest_period"], "2026200")
            self.assertEqual(r_range["selected_xiao"], "马")
            self.assertEqual(len(r_range["zodiac_history"]["period_history"]), 200)

            # 2. Short period numbers ("1" ~ "50") normalize to "2026001" ~ "2026050"
            r_short = cb.get_pingte_zodiac_history(
                lottery="macau",
                xiao="鼠",
                limit=0,
                period_from="1",
                period_to="50",
            )
            self.assertEqual(r_short["sample_periods"], 50)
            self.assertEqual(r_short["earliest_period"], "2026001")
            self.assertEqual(r_short["latest_period"], "2026050")

            # 3. Reversed period bounds ("2026050" ~ "2026001") auto-order cleanly
            r_rev = cb.get_pingte_zodiac_history(
                lottery="macau",
                xiao="鼠",
                limit=0,
                period_from="2026050",
                period_to="2026001",
            )
            self.assertEqual(r_rev["sample_periods"], 50)
            self.assertEqual(r_rev["earliest_period"], "2026001")
            self.assertEqual(r_rev["latest_period"], "2026050")

            # 4. Empty future range returns 0 periods cleanly
            r_empty = cb.get_pingte_zodiac_history(
                lottery="macau",
                xiao="龙",
                limit=0,
                period_from="2099001",
                period_to="2099010",
            )
            self.assertEqual(r_empty["sample_periods"], 0)
            self.assertIsNone(r_empty["earliest_period"])
            self.assertEqual(r_empty["zodiac_history"]["segments"], [])

            # 5. Ranking endpoint enrichment & cache invalidation
            r_rank = cb.get_pingte_ranking(lottery="macau", limit=50)
            self.assertEqual(r_rank["sample_periods"], 50)
            self.assertEqual(len(r_rank["zodiac_ranking"]), 12)
            self.assertIsNotNone(r_rank["zodiac_ranking"][0]["current_range"])
            stats_cache.on_draw_updated("macau")


if __name__ == "__main__":
    unittest.main()
