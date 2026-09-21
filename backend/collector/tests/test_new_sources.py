"""Unit tests for newly added prediction source scripts (588080 and 83191)."""

import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
COLLECTOR_DIR = BACKEND_DIR / "collector"
SOURCES_DIR = COLLECTOR_DIR / "sources"

for p in (str(BACKEND_DIR), str(COLLECTOR_DIR), str(SOURCES_DIR)):
    if p not in sys.path:
        sys.path.insert(0, p)

import dingjian_baoliao
import sima_shuju
import touzi_neimu
import tt_4wbm
import tt_4x8m
import zengshi_xinshui


class TestNewSources(unittest.TestCase):
    def test_dingjian_baoliao_extract_structure(self):
        sample = """
        顶尖爆料·一肖二码
        058585.com｜实力战绩公开栏
        261期 已经命中
        本期开：羊24 验证：成功
        羊 中
        27
        39
        264期   等待公布
        本期开：發88 验证：成功
        """
        rows = dingjian_baoliao.extract(sample)
        self.assertEqual(len(rows), 2)
        # Period 261
        self.assertEqual(rows[0].period_raw, "261")
        pred_vals = [p["value"] for p in rows[0].preds]
        self.assertIn("羊", pred_vals)
        self.assertIn("27", pred_vals)
        self.assertIn("39", pred_vals)
        # Period 264 pending
        self.assertEqual(rows[1].period_raw, "264")
        self.assertEqual(rows[1].claimed["status"], "pending")

    def test_sima_shuju_extract_structure(self):
        sample = """
        260 期数
        09 21 08 20中
        📊 官方开奖结果：猪20
        264 期数
        88 88 88 88
        📊 官方开奖结果：？00
        """
        rows = sima_shuju.extract(sample)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0].period_raw, "260")
        self.assertEqual([p["value"] for p in rows[0].preds], ["09", "21", "08", "20"])
        self.assertEqual(rows[1].period_raw, "264")
        self.assertEqual(rows[1].claimed["status"], "pending")

    def test_zengshi_xinshui_extract_structure(self):
        sample = """
        第260期
        猪 狗
        20-32-21-33
        开奖:猪20中
        第264期
        曾氏心水你值得信赖！
        """
        rows = zengshi_xinshui.extract(sample)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0].period_raw, "260")
        pred_vals = [p["value"] for p in rows[0].preds]
        self.assertIn("猪", pred_vals)
        self.assertIn("狗", pred_vals)
        self.assertIn("20", pred_vals)
        self.assertEqual(rows[1].period_raw, "264")
        self.assertEqual(rows[1].claimed["status"], "pending")

    def test_touzi_neimu_extract_structure(self):
        sample = """
        263期   投资内幕开奖
        狗 09 中 ✅
        站长二肖   【狗 + 猴】
        264期   投资内幕开奖
        肖 00 中 ✅
        站长二肖   【發 + 财】
        """
        rows = touzi_neimu.extract(sample)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0].period_raw, "263")
        pred_vals = [p["value"] for p in rows[0].preds]
        self.assertEqual(pred_vals, ["狗", "猴"])
        self.assertEqual(rows[1].period_raw, "264")
        self.assertEqual(rows[1].claimed["status"], "pending")

    def test_live_source_builds(self):
        # Test that all 6 scripts can build successfully with macau lottery
        for mod, sid in [
            (dingjian_baoliao, "dingjian_baoliao"),
            (sima_shuju, "sima_shuju"),
            (zengshi_xinshui, "zengshi_xinshui"),
            (touzi_neimu, "touzi_neimu"),
            (tt_4x8m, "tt_4x8m"),
            (tt_4wbm, "tt_4wbm"),
        ]:
            pred = mod.build("macau", None, None)
            self.assertTrue(pred.ok, f"{sid} build not ok")
            self.assertEqual(pred.source_id, sid)
            self.assertGreater(len(pred.items), 0, f"{sid} produced 0 items")
            self.assertEqual(pred.lottery, "macau")


if __name__ == "__main__":
    unittest.main()
