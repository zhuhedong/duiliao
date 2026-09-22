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

import chanzhuang_miliao
import dingjian_baoliao
import fanshen_erxiao
import jingsuan_sanma
import jingpin_7ma
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

    def test_jingsuan_sanma_extract_structure(self):
        sample = """
        📿 精算三码 · 数据说话
        264期 精算三码 开：狗21 准
        【07】【21】【11】
        ⛰️ 真金不怕火炼，数据说话最靠谱！
        265期 精算三码 开： 發88 准
        【88】【88】【88】
        """
        rows = jingsuan_sanma.extract(sample)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0].period_raw, "264")
        self.assertEqual([p["value"] for p in rows[0].preds], ["07", "21", "11"])
        self.assertEqual(rows[0].claimed["status"], "hit")
        self.assertEqual(rows[1].period_raw, "265")
        self.assertEqual(rows[1].claimed["status"], "pending")

    def test_chanzhuang_miliao_extract_structure(self):
        sample = """
        铲庄秘料 一肖二码
        ✧顶尖大师058585.com✧
        第264期
        狗-21-33
        防二码:12-24
        开奖:狗21中
        顶尖大师058585.com
        第25期
        铲庄秘料一肖二码连连爆特
        现在上车，下一个暴富的就是你！
        开奖:發88中
        """
        rows = chanzhuang_miliao.extract(sample)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0].period_raw, "264")
        pred_vals = [p["value"] for p in rows[0].preds]
        self.assertIn("狗", pred_vals)
        self.assertIn("21", pred_vals)
        self.assertIn("33", pred_vals)
        self.assertIn("12", pred_vals)
        self.assertIn("24", pred_vals)
        # Period 25 typo recovered as 265 and status pending
        self.assertEqual(rows[1].period_raw, "265")
        self.assertEqual(rows[1].claimed["status"], "pending")

    def test_jingpin_7ma_extract_structure(self):
        sample = """
        264期 澳 轻松拿下 澳 开： 狗21准
        ⑦码：21.33.36.48.25.37.49
        匠心打造精品内容 058585.com ← 精准资讯 →
        265期 澳 轻松拿下 澳 开： 000准
        ⑦码：添加迅聊好友，领料中中中
        """
        rows = jingpin_7ma.extract(sample)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0].period_raw, "264")
        self.assertEqual([p["value"] for p in rows[0].preds], ["21", "33", "36", "48", "25", "37", "49"])
        self.assertEqual(rows[0].claimed["status"], "hit")
        self.assertEqual(rows[1].period_raw, "265")
        self.assertEqual(rows[1].claimed["status"], "pending")

    def test_fanshen_erxiao_extract_structure(self):
        sample = """
        翻身二肖
        2026年第264期
        精准一肖
        狗
        稳中一肖
        猪
        实力记录·精准公开
        2026年第265期
        精准一肖
        發
        稳中一肖
        财
        """
        rows = fanshen_erxiao.extract(sample)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0].period_raw, "264")
        self.assertEqual([p["value"] for p in rows[0].preds], ["狗", "猪"])
        self.assertEqual(rows[1].period_raw, "265")
        self.assertEqual(rows[1].claimed["status"], "pending")

    def test_live_source_builds(self):
        for mod, sid in [
            (dingjian_baoliao, "dingjian_baoliao"),
            (sima_shuju, "sima_shuju"),
            (zengshi_xinshui, "zengshi_xinshui"),
            (touzi_neimu, "touzi_neimu"),
            (jingsuan_sanma, "jingsuan_sanma"),
            (chanzhuang_miliao, "chanzhuang_miliao"),
            (jingpin_7ma, "jingpin_7ma"),
            (fanshen_erxiao, "fanshen_erxiao"),
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
