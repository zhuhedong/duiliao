"""Unit tests for the 70246.com (神算集团 / ss49) source integration and catalog."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
COLLECTOR_DIR = BACKEND_DIR / "collector"
SOURCES_DIR = COLLECTOR_DIR / "sources"
for item in (str(BACKEND_DIR), str(COLLECTOR_DIR), str(SOURCES_DIR)):
    if item not in sys.path:
        sys.path.insert(0, item)

from common.sites.shensuan import base_domain_of, origin, xor_decrypt
from shensuan_util import build_shensuan_pred, parse_shensuan_article_periods
import shensuan_catalog
import site_catalog

SAMPLE_ARTICLE_HTML = """
<div class="tab-panel active" data-period="272">
  <div class="result-top"><span>开奖结果: ?</span> <span class="result-number">00</span></div>
  <div class="result-content">
    <div class="result-row"><span class="row-label">推荐九肖:</span> <span class="row-value">牛鸡狗马虎蛇猴兔鼠</span> <span class="row-hint">这里稳</span></div>
    <div class="result-row"><span class="row-label">推荐七肖:</span> <span class="row-value">牛鸡狗马虎蛇猴</span> <span class="row-hint">平均压</span></div>
    <div class="result-row"><span class="row-label">推荐五肖:</span> <span class="row-value">牛鸡狗马虎</span> <span class="row-hint">稳准狠</span></div>
    <div class="result-row"><span class="row-label">推荐三肖:</span> <span class="row-value">牛鸡狗</span> <span class="row-hint">重点多压</span></div>
    <div class="result-row"><span class="row-label">推荐一肖:</span> <span class="row-value">牛</span> <span class="row-hint">重点多压</span></div>
    <div class="result-row"><span class="row-label">推荐⑨碼:</span> <span class="row-value">06.22.21.25.41.38.11.04.07</span> <span class="row-hint">已确定</span></div>
    <div class="result-row"><span class="row-label">推荐⑦碼:</span> <span class="row-value">06.22.21.25.41.38.11</span> <span class="row-hint">稳准狠!</span></div>
    <div class="result-row"><span class="row-label">推荐⑤碼:</span> <span class="row-value">06.22.21.25.41</span> <span class="row-hint">平均压!</span></div>
    <div class="result-row"><span class="row-label">推荐③碼:</span> <span class="row-value">06.22.21</span> <span class="row-hint">这里稳!</span></div>
    <div class="result-row"><span class="row-label">推荐①碼:</span> <span class="row-value">06</span> <span class="row-hint">多少买点</span></div>
    <div class="result-row"><span class="row-label">推荐单双:</span> <span class="row-value">双数</span> <span class="row-hint">这里稳!</span></div>
    <div class="result-row"><span class="row-label">推荐双波:</span> <span class="row-value">红波 蓝波</span> <span class="row-hint">已确定!</span></div>
    <div class="result-row"><span class="row-label">推荐平特:</span> <span class="row-value">鼠</span> <span class="row-hint">重点多压!</span></div>
    <div class="result-row"><span class="row-label">推荐八尾:</span> <span class="row-value">0-1-3-4-5-6-7-8</span> <span class="row-hint">稳准狠!</span></div>
  </div>
</div>
<div class="tab-panel" data-period="271">
  <div class="result-top"><span>开奖结果: 猴35</span></div>
  <div class="result-content">
    <div class="result-row"><span class="row-label">推荐九肖:</span> <span class="row-value">龙<span style="background-color:#ffe500">猴</span>虎鼠鸡狗蛇猪牛</span> <span class="row-hint">这里稳</span></div>
    <div class="result-row"><span class="row-label">推荐三肖:</span> <span class="row-value">龙<span style="background-color:#ffe500">猴</span>虎</span> <span class="row-hint">重点多压</span></div>
    <div class="result-row"><span class="row-label">推荐一肖:</span> <span class="row-value">龙</span> <span class="row-hint">重点多压</span></div>
    <div class="result-row"><span class="row-label">推荐③碼:</span> <span class="row-value">11.35.22</span> <span class="row-hint">这里稳!</span></div>
    <div class="result-row"><span class="row-label">推荐单双:</span> <span class="row-value">单数</span> <span class="row-hint">这里稳!</span></div>
  </div>
</div>
"""

SAMPLE_FIXTURE_PAYLOAD = [
    {
        "id": 24464,
        "title": "内幕来料-一肖一码",
        "content": SAMPLE_ARTICLE_HTML,
    },
    {
        "id": 23761,
        "title": "全网最快开奖网pro专业版",
        "content": "<div>导航外链内容</div>",
    }
]


class TestShensuanCipherAndNetwork(unittest.TestCase):
    def test_xor_decrypt(self):
        key = "yyrxzj.com"
        original = '{"code":200,"msg":"success","data":"test"}'
        # encrypt
        encrypted = "".join(chr(ord(c) ^ ord(key[i % len(key)])) for i, c in enumerate(original))
        decrypted = xor_decrypt(encrypted, key)
        self.assertEqual(decrypted, original)

    def test_base_domain_extraction(self):
        self.assertEqual(base_domain_of("https://abc12345.yyrxzj.com:8443/api"), "yyrxzj.com")
        self.assertEqual(base_domain_of("70246.com"), "70246.com")
        self.assertEqual(origin("https://abc12345.yyrxzj.com:8443/api"), "https://abc12345.yyrxzj.com:8443")


class TestShensuanParser(unittest.TestCase):
    def test_parse_periods_handles_nested_spans(self):
        periods = parse_shensuan_article_periods(SAMPLE_ARTICLE_HTML)
        self.assertEqual(len(periods), 2)
        
        # Period 272 (active, pending)
        p272 = periods[0]
        self.assertEqual(p272["period_raw"], "272")
        self.assertEqual(p272["status"], "pending")
        self.assertEqual(p272["rows"]["推荐一肖"], "牛")
        self.assertEqual(p272["rows"]["推荐⑨碼"], "06.22.21.25.41.38.11.04.07")
        self.assertEqual(p272["rows"]["推荐单双"], "双数")
        self.assertEqual(p272["rows"]["推荐双波"], "红波 蓝波")
        self.assertEqual(p272["rows"]["推荐八尾"], "0-1-3-4-5-6-7-8")

        # Period 271 (historical with hit span)
        p271 = periods[1]
        self.assertEqual(p271["period_raw"], "271")
        self.assertEqual(p271["xiao"], "猴")
        self.assertEqual(p271["num"], "35")
        # Ensure nested <span style="...">猴</span> was cleaned to plain text
        self.assertEqual(p271["rows"]["推荐九肖"], "龙猴虎鼠鸡狗蛇猪牛")
        self.assertEqual(p271["rows"]["推荐三肖"], "龙猴虎")

    def test_build_shensuan_pred_with_fixture(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".json", delete=False) as f:
            json.dump(SAMPLE_FIXTURE_PAYLOAD, f, ensure_ascii=False)
            fixture_path = f.name

        try:
            # 1. Xiao builder (ss_3xiao)
            pred_3xiao = build_shensuan_pred(
                source_id="ss_3xiao",
                source_name="神算三肖",
                play_type="texiao",
                hit_mode="any",
                sub_label="推荐三肖",
                kind="xiao",
                fixture=fixture_path,
            )
            self.assertEqual(len(pred_3xiao.items), 2)
            self.assertEqual(pred_3xiao.items[0].claimed.status, "pending")
            self.assertEqual([a.value for a in pred_3xiao.items[0].preds], ["牛", "鸡", "狗"])
            self.assertEqual(pred_3xiao.items[1].claimed.status, "hit")
            self.assertEqual([a.value for a in pred_3xiao.items[1].preds], ["龙", "猴", "虎"])

            # 2. Number builder (ss_1ma)
            pred_1ma = build_shensuan_pred(
                source_id="ss_1ma",
                source_name="神算一码",
                play_type="tema_n",
                hit_mode="any",
                sub_label="推荐①碼",
                kind="num",
                fixture=fixture_path,
            )
            self.assertEqual(len(pred_1ma.items), 1)  # Only 272 has 推荐①碼
            self.assertEqual([a.value for a in pred_1ma.items[0].preds], ["06"])

            # 3. Twoface builder (ss_danshuang)
            pred_ds = build_shensuan_pred(
                source_id="ss_danshuang",
                source_name="神算特码单双",
                play_type="tema_twoface",
                hit_mode="any",
                sub_label="推荐单双",
                kind="twoface",
                fixture=fixture_path,
            )
            self.assertEqual(len(pred_ds.items), 2)
            self.assertEqual([a.value for a in pred_ds.items[0].preds], ["双"])
            self.assertEqual([a.value for a in pred_ds.items[1].preds], ["单"])
            # In 271, num is 35 (odd), so it is a hit!
            self.assertEqual(pred_ds.items[1].claimed.status, "hit")

            # 4. Tail builder (ss_8wei)
            pred_8wei = build_shensuan_pred(
                source_id="ss_8wei",
                source_name="神算八尾",
                play_type="tema_wei_n",
                hit_mode="any",
                sub_label="推荐八尾",
                kind="wei",
                fixture=fixture_path,
            )
            self.assertEqual(len(pred_8wei.items), 1)
            self.assertEqual([a.value for a in pred_8wei.items[0].preds], ["0", "1", "3", "4", "5", "6", "7", "8"])

        finally:
            Path(fixture_path).unlink(missing_ok=True)


class TestShensuanCatalogAndGovernance(unittest.TestCase):
    def test_local_inventory_indexes_by_upstream_id(self):
        cfg = {
            "sources": [
                {
                    "source_id": "ss_9xiao",
                    "source_name": "神算九肖",
                    "site_family": "shensuan_70246",
                    "enabled": True,
                    "extra": {
                        "path": "/api/index/content_list/2",
                        "upstream_id": "24464",
                        "sub_label": "推荐九肖",
                        "kind": "xiao",
                    },
                }
            ]
        }
        inv = shensuan_catalog.local_inventory(cfg)
        self.assertIn("24464", inv)
        self.assertEqual(inv["24464"][0]["source_id"], "ss_9xiao")

    def test_site_catalog_status_includes_shensuan(self):
        st = site_catalog.status("shensuan_70246")
        self.assertEqual(st["site_family"], "shensuan_70246")
        self.assertIn("70246.com", st["site_label"])

        all_st = site_catalog.status("all")
        self.assertEqual(all_st["site_label"], "全站点 / 汇总")
        self.assertIn("shensuan_70246", all_st["sites"])
        self.assertEqual(len(all_st["sites"]), 4)


if __name__ == "__main__":
    unittest.main()
