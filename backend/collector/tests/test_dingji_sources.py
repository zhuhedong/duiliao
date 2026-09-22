"""Unit tests for 77452.com (澳门顶级 / 顶级论坛) site discovery, parsing, and source scripts."""

import sys
import unittest
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
COLLECTOR_DIR = BACKEND_DIR / "collector"
SOURCES_DIR = COLLECTOR_DIR / "sources"

for p in (str(BACKEND_DIR), str(COLLECTOR_DIR), str(SOURCES_DIR)):
    if p not in sys.path:
        sys.path.insert(0, p)

from common.sites.dingji import decode_char_codes, origin
from dingji_util import (
    atoms_bose,
    atoms_head,
    atoms_num,
    atoms_twoface,
    atoms_wei,
    atoms_xiao,
    build_dj_pred,
    claimed_of,
    parse_dj_amtz_rows,
    parse_dj_baota_rows,
    parse_dj_htm_section_rows,
)


class TestDingjiDiscovery(unittest.TestCase):
    def test_decode_char_codes(self):
        # "https://" -> 'h'=104 -> 1104, 't'=116 -> 1116, 't'=116 -> 1116, 'p'=112 -> 1112, 's'=115 -> 1115, ':'=58 -> 1058, '/'=47 -> 1047, '/'=47 -> 1047
        encoded = "11041116111611121115105810471047"
        self.assertEqual(decode_char_codes(encoded), "https://")

    def test_decode_char_codes_invalid(self):
        self.assertEqual(decode_char_codes(""), "")
        self.assertEqual(decode_char_codes("123"), "")
        self.assertEqual(decode_char_codes("abcd"), "")

    def test_origin_parsing(self):
        self.assertEqual(
            origin("https://goncf1-1fsfhb.trueheartlight.com:2096/htm/#top"),
            "https://goncf1-1fsfhb.trueheartlight.com:2096",
        )
        self.assertEqual(origin("https://77452.com/"), "https://77452.com")
        self.assertIsNone(origin("not_a_url"))


class TestDingjiAtomExtractors(unittest.TestCase):
    def test_atoms_xiao(self):
        text = "猪猴虎羊龙马鸡狗鼠"
        atoms = atoms_xiao(text)
        self.assertEqual(len(atoms), 9)
        self.assertEqual([a["value"] for a in atoms], list("猪猴虎羊龙马鸡狗鼠"))

    def test_atoms_num(self):
        text = "03.09.19.21.23.28.30.31.32.33"
        atoms = atoms_num(text)
        self.assertEqual(len(atoms), 10)
        self.assertEqual(atoms[0]["value"], "03")
        self.assertEqual(atoms[1]["value"], "09")

    def test_atoms_twoface(self):
        d_dan = atoms_twoface("大单")
        self.assertEqual(len(d_dan), 2)
        kinds = {a["kind"]: a["value"] for a in d_dan}
        self.assertEqual(kinds["size"], "大")
        self.assertEqual(kinds["odd"], "单")

        x_shuang = atoms_twoface("小双")
        kinds_x = {a["kind"]: a["value"] for a in x_shuang}
        self.assertEqual(kinds_x["size"], "小")
        self.assertEqual(kinds_x["odd"], "双")

        jiaye = atoms_twoface("家禽")
        self.assertEqual(len(jiaye), 1)
        self.assertEqual(jiaye[0]["value"], "家")

        yeshou = atoms_twoface("野兽")
        self.assertEqual(len(yeshou), 1)
        self.assertEqual(yeshou[0]["value"], "野")

    def test_atoms_wei(self):
        text = "9-3-6-0-尾"
        atoms = atoms_wei(text)
        self.assertEqual([a["value"] for a in atoms], ["9", "3", "6", "0"])

    def test_atoms_head(self):
        text = "3-0-4"
        atoms = atoms_head(text)
        self.assertEqual([a["value"] for a in atoms], ["3", "0", "4"])

    def test_atoms_bose(self):
        text = "绿波红波"
        atoms = atoms_bose(text)
        vals = [a["value"] for a in atoms]
        self.assertIn("红波", vals)
        self.assertIn("绿波", vals)


class TestDingjiParsers(unittest.TestCase):
    def test_parse_dj_amtz_rows(self):
        sample_html = """
        <table border="1" class="neirong-table" width="100%"><tbody>
        <tr><td>264期:<font color="#FF00FF">九肖</font><font color="#0000FF">【猪猴虎羊龙马鸡狗鼠】</font>开:<font color="#FF0000">狗21</font>准</td></tr>
        <tr><td>265期:<font color="#FF00FF">九肖</font><font color="#0000FF">【蛇猴猪狗鼠龙虎马牛】</font>开:<font color="#FF0000">0000</font>准</td></tr>
        </tbody></table>
        """
        rows = parse_dj_amtz_rows(sample_html)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["period_raw"], "264")
        self.assertEqual(rows[0]["pred_raw"], "猪猴虎羊龙马鸡狗鼠")
        self.assertEqual(rows[1]["period_raw"], "265")
        self.assertEqual(rows[1]["pred_raw"], "蛇猴猪狗鼠龙虎马牛")

    def test_parse_dj_baota_rows(self):
        sample_html = """
        <div class="list-title">宝塔镇河妖【澳门顶级】好料随你挑</div>
        <table cellpadding="0" cellspacing="0" class="stairs">
        <tr>
        <td><i>七肖:</i>蛇牛兔龙猪马虎</td>
        <td><i>⑦码:</i>02.06.04.15.20.13.17</td>
        </tr>
        <tr>
        <td><i>五肖:</i><em>蛇牛兔龙猪</em></td>
        <td><i>⑤码:</i><em>02.06.04.15.20</em></td>
        </tr>
        <tr>
        <td><i>三肖:</i><b>蛇牛兔</b></td>
        <td><i>③码:</i><b>02.06.04</b></td>
        </tr>
        <tr>
        <td><i>一肖:</i><u>蛇</u></td>
        <td><i>①码:</i><u>02</u></td>
        </tr>
        <tr>
        <td class="firstt" colspan="2"><i>265期:今晚敢赌</i><u>【蛇-02】</u><i>明天开路虎</i></td>
        </tr>
        </table>
        """
        rows_7x = parse_dj_baota_rows(sample_html, "7xiao")
        self.assertEqual(len(rows_7x), 1)
        self.assertEqual(rows_7x[0]["period_raw"], "265")
        self.assertEqual(rows_7x[0]["pred_raw"], "蛇牛兔龙猪马虎")

        rows_7m = parse_dj_baota_rows(sample_html, "7ma")
        self.assertEqual(len(rows_7m), 1)
        self.assertEqual(rows_7m[0]["pred_raw"], "02.06.04.15.20.13.17")

    def test_parse_dj_htm_section_rows(self):
        sample_html = """
        <div class="list-title">贺州怀中猫【最准五不中】</div>
        <ul class="ziliao moyu"><li>264期：五不中<i>【<span class="style3">18.19.42.44.47</span>】</i>准</li><li>265期：五不中<i>【02.16.36.38.47】</i>准</li><li id="bottom">266期：五不中<i>【00.00.00.00.00】</i>准</li>
        <!-- 注释模版
        <li>031期：五不中<i>【00.00.00.00.00】</i>准</li>
        -->
        </ul>
        </div>
        <div class="list-title">北海奶茶鉴定师【独家成语】</div>
        """
        rows = parse_dj_htm_section_rows(sample_html, "贺州怀中猫")
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]["period_raw"], "264")
        self.assertIn("18.19.42.44.47", rows[0]["pred_raw"])
        self.assertEqual(rows[1]["period_raw"], "265")
        self.assertIn("02.16.36.38.47", rows[1]["pred_raw"])

    def test_claimed_of(self):
        self.assertEqual(claimed_of("开: 0000 准", "265期 开: 0000 准")["status"], "pending")
        self.assertEqual(claimed_of("开: ？00 准", "265期 开: ？00 准")["status"], "pending")
        self.assertEqual(claimed_of("开: 狗21 准", "264期 开: 狗21 准")["status"], "hit")
        self.assertEqual(claimed_of("开: 鸡46 错", "258期 开: 鸡46 错")["status"], "miss")


class TestDingjiBuilderWithFixture(unittest.TestCase):
    def test_build_dj_pred_from_parsed(self):
        rows = [
            {"period_raw": "264", "pred_raw": "猪猴虎羊龙马鸡狗鼠", "claim_raw": "开: 狗21 准", "full_text": "264期 开: 狗21 准"},
            {"period_raw": "265", "pred_raw": "蛇猴猪狗鼠龙虎马牛", "claim_raw": "开: 0000 准", "full_text": "265期 开: 0000 准"},
        ]
        pred = build_dj_pred(
            source_id="dj_9xiao",
            source_name="顶级论坛九肖中特",
            play_type="texiao",
            hit_mode="any",
            urls=["https://test.local/001.html"],
            kind="xiao",
            lottery="macau",
            parsed_rows=rows,
        )
        self.assertTrue(pred.ok)
        self.assertEqual(pred.schema_name, "pred.v1")
        self.assertEqual(pred.site_family, "dingji_77452")
        self.assertEqual(len(pred.items), 2)
        self.assertEqual(pred.items[0].period, "2026264")
        self.assertEqual(pred.items[0].claimed.status, "hit")
        self.assertEqual(pred.items[1].period, "2026265")
        self.assertEqual(pred.items[1].claimed.status, "pending")
        self.assertEqual(len(pred.items[1].preds), 9)


if __name__ == "__main__":
    unittest.main()
