"""Parsers and catalog diffs for the three-site column onboarding."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
COLLECTOR_DIR = BACKEND_DIR / "collector"
SOURCES_DIR = COLLECTOR_DIR / "sources"
for item in (str(BACKEND_DIR), str(COLLECTOR_DIR), str(SOURCES_DIR)):
    if item not in sys.path:
        sys.path.insert(0, item)

from dingji_util import atoms_twoface, atoms_wei
from dingjian_shenwei import extract as extract_shenwei
from dingjian_vip import extract as extract_vip
from dingjian_wuma import extract as extract_wuma
from tongtian_catalog import compare_inventory, discover_homepage_scripts, extract_iframe_paths, extract_script_paths
import tongtian_catalog
import site_catalog
from registry import render_template
from tt_util import expand_period_ranges


class TestDingjiAtoms(unittest.TestCase):
    def test_repeated_tail_digits(self):
        self.assertEqual(atoms_wei("555")[0]["value"], "5")
        self.assertEqual(atoms_wei("99999")[0]["value"], "9")

    def test_grouped_zodiac_labels(self):
        values = {atom["value"] for atom in atoms_twoface("阳肖+鼠龙")}
        self.assertEqual(values, {"阳"})
        self.assertEqual(atoms_twoface("女肖")[0]["value"], "女")


class TestDingjianNewColumns(unittest.TestCase):
    def test_wuma_splits_numbers_and_holds_placeholder(self):
        raw = "第263期\n顶尖大师058585.com\n09-21\n11-23-35\n开奖:狗09中\n第267期\n跟上\n开奖:發88中\n"
        rows = extract_wuma(raw)
        self.assertEqual(rows[0].period_raw, "263")
        self.assertEqual([item["value"] for item in rows[0].preds], ["09", "21", "11", "23", "35"])
        self.assertEqual(rows[0].claimed["num"], "09")
        self.assertEqual(rows[1].claimed["status"], "pending")
        self.assertEqual(rows[1].preds, [])

    def test_vip_keeps_zodiac_and_drops_placeholder(self):
        raw = "263 期: VIP专属100%\n真实内幕 【 狗 +22.34.46】\n267 期: VIP专属100%\n真实内幕 【 88.88.88.88】\n"
        rows = extract_vip(raw)
        self.assertEqual([item["value"] for item in rows[0].preds], ["狗"])
        self.assertEqual(rows[1].claimed["status"], "pending")

    def test_shenwei_reads_two_zodiacs_around_hit_mark(self):
        raw = "2026年 第263期\n蛇\n中\n狗\n2026年 第265期\n中\n马\n虎\n2026年 第267期\n發\n财\n"
        rows = extract_shenwei(raw)
        self.assertEqual([item["value"] for item in rows[0].preds], ["蛇", "狗"])
        self.assertEqual(rows[0].claimed["xiao"], "狗")
        self.assertEqual([item["value"] for item in rows[1].preds], ["马", "虎"])
        self.assertEqual(rows[1].claimed["xiao"], "马")
        self.assertEqual(rows[2].claimed["status"], "pending")


class TestTongtianCatalog(unittest.TestCase):
    def test_extract_script_order(self):
        html = '<script src="/chajie/6xiao.js"></script><script src="/chajie/5qi.js"></script><script src="/chajie/6xiao.js"></script>'
        self.assertEqual(extract_script_paths(html), ["/chajie/6xiao.js", "/chajie/5qi.js"])

    def test_extract_nested_iframe_paths(self):
        html = "<iframe src='/83191.html'></iframe><script src='/chajie/x.js?v=1'></script>"
        self.assertEqual(extract_iframe_paths(html), ["/83191.html"])
        self.assertEqual(extract_script_paths(html), ["/chajie/x.js"])

    def test_discover_nested_homepage(self):
        class Response:
            def __init__(self, url, text):
                self.url, self.text = url, text

        pages = {
            "https://mirror/": "<iframe src='/83191.html'></iframe>",
            "https://mirror/83191.html": "<script>document.write('<script src=\"/chajie/6xiao.js?v=1\"></script>')</script>",
        }
        old_get = tongtian_catalog.get
        tongtian_catalog.get = lambda url, **_: Response(url, pages[url])
        try:
            paths, scanned, errors = discover_homepage_scripts("https://mirror")
        finally:
            tongtian_catalog.get = old_get
        self.assertEqual(paths, ["/chajie/6xiao.js"])
        self.assertEqual(len(scanned), 2)
        self.assertEqual(errors, [])

    def test_compare_enabled_ignored_pending_and_missing(self):
        cfg = {
            "sources": [
                {
                    "source_id": "tt_5qi",
                    "source_name": "通天八码五期必中",
                    "site_family": "tongtian_83191",
                    "script_path": "sources/tt_5qi.py",
                    "enabled": True,
                    "extra": {},
                }
            ]
        }
        covered = compare_inventory(
            ["/chajie/5qi.js", "/chajie/gsb.js", "/chajie/fresh.js"],
            cfg,
            ignored={"gsb.js": "导航"},
        )
        by_path = {item["path"]: item["coverage"] for item in covered["items"]}
        self.assertEqual(by_path["/chajie/5qi.js"], "enabled")
        self.assertEqual(by_path["/chajie/gsb.js"], "ignored")
        self.assertEqual(by_path["/chajie/fresh.js"], "untracked")
        self.assertEqual(covered["missing"], [])

        removed = compare_inventory(["/chajie/gsb.js"], cfg, ignored={"gsb.js": "导航"})
        self.assertEqual(removed["missing"][0]["path"], "/chajie/5qi.js")


class TestSiteCatalog(unittest.TestCase):
    def test_aggregate_keeps_family_identity(self):
        old = site_catalog.FAMILY_MODULES.copy()

        class Module:
            @staticmethod
            def status():
                return {"ok": True, "content_total": 2, "enabled_components": 1, "known_components": 2, "items": [], "pending": [], "missing": []}

            @staticmethod
            def scan(record=True):
                return Module.status()

        site_catalog.FAMILY_MODULES.clear()
        site_catalog.FAMILY_MODULES.update({"fake": "fake_module"})
        site_catalog.FAMILY_LABELS["fake"] = "测试站"
        old_load = site_catalog._load
        site_catalog._load = lambda _: Module
        try:
            result = site_catalog.status()
        finally:
            site_catalog._load = old_load
            site_catalog.FAMILY_MODULES.clear()
            site_catalog.FAMILY_MODULES.update(old)
            site_catalog.FAMILY_LABELS.pop("fake", None)
        self.assertEqual(result["site_family"], "all")
        self.assertEqual(result["content_total"], 2)
        self.assertEqual(result["sites"]["fake"]["site_family"], "fake")

    def test_batch_template_uses_dynamic_site_builder(self):
        script = render_template(
            {
                "source_id": "tt_new_column",
                "source_name": "通天新栏目",
                "site_family": "tongtian_83191",
                "play_type": "tema_n",
                "hit_mode": "any",
                "extra": {"path": "/chajie/new.js", "kind": "num"},
            }
        )
        self.assertIn("build_tt_pred", script)
        self.assertIn('PATH = "/chajie/new.js"', script)
        self.assertIn('KIND = "num"', script)

    def test_expand_five_period_bundle(self):
        rows = expand_period_ranges(
            [{"period_raw": "265", "pred_raw": "02.09", "claim_raw": "", "full_text": "261-265期特码 02.09"}]
        )
        self.assertEqual([row["period_raw"] for row in rows], ["261", "262", "263", "264", "265"])


if __name__ == "__main__":
    unittest.main()
