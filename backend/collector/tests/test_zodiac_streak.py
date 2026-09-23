"""连肖归类：三连 / 四连 / 五连 / N连 / 复式，不连数据库。"""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.services.ai.prompts import get_prompt_template
from app.services.ai.zodiac_streak import (
    compute_streaks,
    format_zodiac_streak_for_ai,
)


def _period(period: str, *xiaos: str) -> dict:
    balls = list(xiaos) + ["鼠"] * (7 - len(xiaos))
    return {
        "period": period,
        "date": "2026-01-01",
        "balls": ["01"] * 7,
        "xiaos": balls[:7],
        "tema_xiao": balls[6],
        "unique_xiaos": list(xiaos),
    }


class TestZodiacStreakBuckets(unittest.TestCase):
    def test_classifies_exact_lengths_and_compound_sets(self):
        # 马虎龙 连续 3 期，马虎再延 2 期变成五连；中间断开后兔羊四连直到最新期。
        # 蛇单独 6 期，落在样本前半，用来覆盖 N连。
        data = [
            _period("01", "蛇", "马", "虎", "龙"),
            _period("02", "蛇", "马", "虎", "龙"),
            _period("03", "蛇", "马", "虎", "龙"),
            _period("04", "蛇", "马", "虎"),
            _period("05", "蛇", "马", "虎"),
            _period("06", "蛇"),
            _period("07", "兔", "羊"),
            _period("08", "兔", "羊"),
            _period("09", "兔", "羊"),
            _period("10", "兔", "羊"),
        ]
        stats = compute_streaks(data, min_streak=3)
        buckets = stats["buckets"]

        self.assertEqual([row["xiao"] for row in buckets["三连"]], ["龙"])
        self.assertEqual(sorted(row["xiao"] for row in buckets["四连"]), ["兔", "羊"])
        self.assertTrue(all(row["is_active"] for row in buckets["四连"]))
        self.assertEqual(sorted(row["xiao"] for row in buckets["五连"]), ["虎", "马"])
        self.assertEqual([(row["xiao"], row["length"]) for row in buckets["N连"]], [("蛇", 6)])
        self.assertFalse(buckets["N连"][0]["is_active"])

        fushi = buckets["复式"]
        # 前三期四个生肖一起开出；蛇继续跟着马虎到第五期，所以五连复式含蛇。
        self.assertEqual(fushi["三连"][0]["xiaos"], ["虎", "龙", "蛇", "马"])
        self.assertEqual(fushi["三连"][0]["start_period"], "01")
        self.assertEqual(fushi["三连"][0]["end_period"], "03")
        self.assertEqual(fushi["五连"][0]["xiaos"], ["虎", "蛇", "马"])
        self.assertEqual(fushi["五连"][0]["end_period"], "05")
        self.assertEqual(fushi["四连"][0]["xiaos"], ["兔", "羊"])
        self.assertTrue(fushi["四连"][0]["is_active"])
        self.assertEqual(fushi["N连"], [])
        # 马虎这两肖的五连窗口已经被「虎蛇马」整段覆盖，不再单列。
        self.assertFalse(
            any(row["xiaos"] == ["虎", "马"] and row["length"] == 5 for row in stats["compound_streaks"])
        )

    def test_pair_that_outlasts_a_triple_is_kept(self):
        data = [
            _period("01", "马", "虎", "龙"),
            _period("02", "马", "虎", "龙"),
            _period("03", "马", "虎", "龙"),
            _period("04", "马", "虎"),
            _period("05", "马", "虎"),
        ]
        fushi = compute_streaks(data, min_streak=3)["buckets"]["复式"]
        self.assertEqual(fushi["三连"][0]["xiaos"], ["虎", "龙", "马"])
        self.assertEqual(fushi["三连"][0]["end_period"], "03")
        self.assertEqual(fushi["五连"][0]["xiaos"], ["虎", "马"])
        self.assertEqual(fushi["五连"][0]["end_period"], "05")

    def test_min_streak_hides_shorter_runs(self):
        data = [
            _period("01", "龙"),
            _period("02", "龙"),
            _period("03", "龙"),
            _period("04", "马", "虎"),
            _period("05", "马", "虎"),
            _period("06", "马", "虎"),
            _period("07", "马", "虎"),
        ]
        stats = compute_streaks(data, min_streak=4)
        self.assertEqual(stats["buckets"]["三连"], [])
        self.assertEqual(sorted(row["xiao"] for row in stats["buckets"]["四连"]), ["虎", "马"])
        self.assertEqual(stats["buckets"]["复式"]["三连"], [])
        self.assertEqual(stats["buckets"]["复式"]["四连"][0]["xiaos"], ["虎", "马"])

    def test_empty_history(self):
        stats = compute_streaks([], min_streak=3)
        self.assertEqual(stats["total_periods"], 0)
        self.assertEqual(stats["buckets"]["三连"], [])
        self.assertEqual(stats["buckets"]["复式"]["五连"], [])

    def test_prompt_context_is_grouped_by_period(self):
        data = [
            _period("2026261", "马", "虎", "龙"),
            _period("2026262", "马", "虎", "龙"),
            _period("2026263", "马", "虎", "龙"),
        ]
        stats = compute_streaks(data, min_streak=3)
        text = format_zodiac_streak_for_ai(data, stats)
        self.assertIn("2026261", text)
        self.assertIn("2026263", text)
        self.assertIn("【三连】", text)
        self.assertIn("【复式】", text)
        self.assertIn("龙", text)
        self.assertLess(text.index("2026261"), text.index("2026263"))

        template = get_prompt_template("zodiac_streak_analysis")
        messages = template.render(context_data=text, period="2026264")
        user = messages[1]["content"]
        for title in ("### 三连", "### 四连", "### 五连", "### N连", "### 复式"):
            self.assertIn(title, user)
        self.assertIn("2026261", user)
        self.assertIn("2026264", user)


if __name__ == "__main__":
    unittest.main()
