"""Tests for 588080.com scraper and HTML assembler (supports both unittest and pytest)."""
import sys
import unittest
from pathlib import Path

# Add backend and collector to sys.path
BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
COLLECTOR_DIR = BACKEND_DIR / "collector"

if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))
if str(COLLECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(COLLECTOR_DIR))

from collector.fetch_588080 import (
    assemble_page_html,
    extract_app_hosts_from_am_js,
    extract_jump_urls,
    fetch_588080_full_page,
)


class TestFetch588080(unittest.TestCase):
    def test_extract_jump_urls_filters_comments(self):
        sample_html = """
        <!doctype html>
        <html>
        <head>
        <!--<script>
        var jumpURL = [
            'https://invalid-commented.com/',
            'https://old-domain.com/'
        ];
        </script>-->
        <script>
        var jumpURL = [
            'https://valid-target-1.com/',
            'https://valid-target-2.com/'
        ];
        window.location.href = jumpURL[0];
        </script>
        </head>
        </html>
        """
        urls = extract_jump_urls(sample_html)
        self.assertEqual(len(urls), 2)
        self.assertIn("https://valid-target-1.com/", urls)
        self.assertIn("https://valid-target-2.com/", urls)
        self.assertNotIn("https://invalid-commented.com/", urls)

    def test_extract_app_hosts_from_am_js(self):
        sample_am_js = """
        switch(n) {
          case 1:
            document.write('<iframe src="https://node1.example.com/" width="100%"></iframe>');
            break;
          case 2:
            document.write('<iframe src="https://node2.example.com/some/path" width="100%"></iframe>');
            break;
          case 3:
            document.write('<iframe src="https://node1.example.com/" width="100%"></iframe>');
            break;
        }
        """
        hosts = extract_app_hosts_from_am_js(sample_am_js)
        self.assertEqual(len(hosts), 2)
        self.assertIn("https://node1.example.com", hosts)
        self.assertIn("https://node2.example.com", hosts)

    def test_assemble_page_html(self):
        site_config = {
            "webSiteTitle": "测试大师",
            "webSiteKeywords": "六合,心水",
            "webSiteDesc": "专业预测平台",
            "backgroundImage": "https://img.example.com/bg.png",
        }
        modules = [
            {"id": 1, "name": "顶部样式", "type": "style", "content": "body { color: red; }"},
            {"id": 2, "name": "特码推荐", "type": "content", "content": None},
            {"id": 3, "name": "广告模块", "type": "publicCode", "content": "<div>广告内容</div>"},
            {"id": 4, "name": "导航按钮", "type": "system", "content": None},
        ]
        loaded_contents = {
            2: "<div class='pred-table'><table><tr><td>特码</td><td>18</td></tr></table></div>"
        }

        full_html = assemble_page_html(site_config, modules, loaded_contents)

        self.assertIn("<!DOCTYPE html>", full_html)
        self.assertIn("<title>测试大师</title>", full_html)
        self.assertIn("body { color: red; }", full_html)
        self.assertIn("特码推荐", full_html)
        self.assertIn("特码", full_html)
        self.assertIn("18", full_html)
        self.assertIn("<div>广告内容</div>", full_html)
        self.assertIn("data-id='2'", full_html)
        self.assertIn("data-name='特码推荐'", full_html)

    def test_fetch_588080_full_page_live(self):
        """Live integration test against 588080.com."""
        result = fetch_588080_full_page(timeout=12.0)
        self.assertTrue(result.ok, f"Fetch failed with error: {result.error}")
        self.assertGreaterEqual(result.total_modules, 50)
        self.assertGreaterEqual(result.loaded_content_count, 18)
        self.assertGreater(len(result.html), 50000)
        self.assertIn("<!DOCTYPE html>", result.html)
        self.assertIn("module-wrapper", result.html)


if __name__ == "__main__":
    unittest.main()
