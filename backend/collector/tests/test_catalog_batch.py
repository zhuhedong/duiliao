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
from common.dingjian_columns import extract as extract_dingjian_column
from dingji_catalog import _parse_amtz_records
from dingjian_shenwei import extract as extract_shenwei
from dingjian_vip import extract as extract_vip
from dingjian_wuma import extract as extract_wuma
import wu_buzhong
from source_catalog import classify_content
from tongtian_catalog import analyze_script, compare_inventory, discover_homepage_scripts, extract_iframe_paths, extract_script_paths, reconstruct_script_html
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
    def test_reviewed_588080_contracts_extract_only_declared_pick_region(self):
        raw = """
        第269期\n鸡 鼠\n10-22-19-31\n开奖:鸡22中
        第270期\n發88中
        """
        rows = extract_dingjian_column(raw, "four_number_line")
        self.assertEqual(rows[0].period_raw, "269")
        self.assertEqual([atom["value"] for atom in rows[0].preds], ["10", "22", "19", "31"])
        # Placeholder-only periods are not emitted as false predictions.
        self.assertEqual(len(rows), 1)

    def test_pending_588080_columns_have_reviewed_contracts(self):
        raw = """
        第267期\n40-24-30\n28-36-42\n开奖:兔40中
        第270期\n┣24.36.19.31┫\n
        第270期\n【09.21.19.31.12.24.48】\n
        271期 ①肖 發 88 开000中\n防：88 88 88 88
        """
        self.assertEqual(len(extract_dingjian_column(raw, "six_number_lines")), 1)
        self.assertEqual(len(extract_dingjian_column(raw, "four_bracket_numbers")), 1)
        self.assertEqual(len(extract_dingjian_column(raw, "seven_bracket_numbers")), 1)
        self.assertEqual(extract_dingjian_column(raw, "xiao_num_defense"), [])

        live = "267期 ①肖 兔 40 开兔40中\n防：14 26 15 27"
        rows = extract_dingjian_column(live, "xiao_num_defense")
        self.assertEqual([atom["value"] for atom in rows[0].preds], ["兔", "40", "14", "26", "15", "27"])

    def test_newest_three_columns_contracts(self):
        raw_wangshouyi = """
        第268期\n兔-40\n30-42-08-21\n开奖:兔40中\n第272期\n王守义，一肖一码\n开奖:發88中
        """
        rows1 = extract_dingjian_column(raw_wangshouyi, "wangshouyi_defense")
        self.assertEqual(len(rows1), 1)
        self.assertEqual([a["value"] for a in rows1[0].preds], ["兔", "40", "30", "42", "08", "21"])

        raw_aocai2x2m = """
        268期 澳彩二码 开：兔40准\n精 [鸡46][兔40] 准\n272期 澳彩二码 开：發88准\n精 [發88][财88] 准
        """
        rows2 = extract_dingjian_column(raw_aocai2x2m, "bracket_pairs_2x2m")
        self.assertEqual(len(rows2), 1)
        self.assertEqual([a["value"] for a in rows2[0].preds], ["鸡", "兔", "46", "40"])

        raw_ribao = """
        268期:搞钱②码(40.28)拖(29.41.33)\n协防猪跟着发财!\n开奖:兔40准\n272期:搞钱②码(88.88)拖(88.88.88)\n协防發跟着发财!
        """
        rows3 = extract_dingjian_column(raw_ribao, "ribao_drag_defense")
        self.assertEqual(len(rows3), 1)
        self.assertEqual([a["value"] for a in rows3[0].preds], ["猪", "40", "28", "29", "41", "33"])

        raw_baofu = """
        272期【猪】【羊】+小买【蛇】\n开:蛇02中\n273期【發】【發】+小买【發】
        """
        rows4 = extract_dingjian_column(raw_baofu, "baofu_3xiao")
        self.assertEqual(len(rows4), 1)
        self.assertEqual([a["value"] for a in rows4[0].preds], ["猪", "羊", "蛇"])

        raw_diamond = """
        2026年澳门第272期\n18\n06\n14\n02中\n2026年澳门第273期\n88\n88\n88\n88
        """
        rows5 = extract_dingjian_column(raw_diamond, "diamond_four_numbers")
        self.assertEqual(len(rows5), 1)
        self.assertEqual([a["value"] for a in rows5[0].preds], ["18", "06", "14", "02"])

        raw_datoumi = """
        第272期\n蛇-02-14\n防:12-24\n开奖:蛇02中\n第273期\n内部大佬大透密\n开奖:發88中
        """
        rows6 = extract_dingjian_column(raw_datoumi, "datoumi_defense")
        self.assertEqual(len(rows6), 1)
        self.assertEqual([a["value"] for a in rows6[0].preds], ["蛇", "02", "14", "12", "24"])

    def test_october_new_columns_contracts(self):
        # 1. wangzhe_defense
        raw_wz = "第280期 ①肖①码 开：龙15 ⚡\n精准【虎-17】分析\n防15.27.02.38\n第283期 ①肖①码 开：發88 ⚡\n精准【發-88】分析"
        rows1 = extract_dingjian_column(raw_wz, "wangzhe_defense")
        self.assertEqual(len(rows1), 1)
        self.assertEqual(rows1[0].preds[0]["value"], "虎")
        self.assertEqual([a["value"] for a in rows1[0].preds[1:]], ["17", "15", "27", "02", "38"])

        # 2. juemi_2x4m
        raw_jm = "第279期\n鸡 牛\n10 -22-18-30\n开奖: 鸡10 中\n第283期\n發 财\n加好友\n开奖: 發88 中"
        rows2 = extract_dingjian_column(raw_jm, "juemi_2x4m")
        self.assertEqual(len(rows2), 1)
        self.assertEqual([a["value"] for a in rows2[0].preds[:2]], ["鸡", "牛"])
        self.assertEqual([a["value"] for a in rows2[0].preds[2:]], ["10", "22", "18", "30"])

        # 3. xingyun_6ma
        raw_xy = "279期 ★ 幸运之星 ★\n開： 鸡10中\n精选「24.34」\n赠送「12.36.10.22」\n283期 ★ 幸运之星 ★\n開： 發88中\n精选「88.88」"
        rows3 = extract_dingjian_column(raw_xy, "xingyun_6ma")
        self.assertEqual(len(rows3), 1)
        self.assertEqual([a["value"] for a in rows3[0].preds], ["24", "34", "12", "36", "10", "22"])

        # 4. four_number_line (jinding_4ma)
        raw_jd = "第278期\n02-14-04-16\n开奖: 蛇02 中\n第283期\n88-88-88-88\n开奖: 發88 中"
        rows4 = extract_dingjian_column(raw_jd, "four_number_line")
        self.assertEqual(len(rows4), 1)
        self.assertEqual([a["value"] for a in rows4[0].preds], ["02", "14", "04", "16"])

        # 5. jipin_defense
        raw_jp = "第277期：极品内幕\n玄机①码: ✡猴11✡\n✡ 02.14.19.31 ✡\n第283期：极品内幕\n玄机①码: ✡發88✡\n✡ 88.88.88.88 ✡"
        rows5 = extract_dingjian_column(raw_jp, "jipin_defense")
        self.assertEqual(len(rows5), 1)
        self.assertEqual(rows5[0].preds[0]["value"], "猴")
        self.assertEqual([a["value"] for a in rows5[0].preds[1:]], ["11", "02", "14", "19", "31"])

        # 6. zhugong_3ma
        raw_zg = "第279期\n开奖：鸡10准\n主攻三码\n21 · 33 · 45\n次参考码\n10 · 46 · 12 · 48\n第283期\n主攻三码\n88 · 88 · 88"
        rows6 = extract_dingjian_column(raw_zg, "zhugong_3ma")
        self.assertEqual(len(rows6), 1)
        self.assertEqual([a["value"] for a in rows6[0].preds], ["21", "33", "45"])

        # 7. kaijiang_2xiao
        raw_kj = "第278期开奖二肖已公开\n密函直达\n鼠\n蛇\n第283期开奖二肖待公布\n發\n财"
        rows7 = extract_dingjian_column(raw_kj, "kaijiang_2xiao")
        self.assertEqual(len(rows7), 1)
        self.assertEqual([a["value"] for a in rows7[0].preds], ["鼠", "蛇"])

        # 8. boshi_jingxuan
        raw_bs = "277期：博士精选 开：猴11\n【马13】 【11.23.24.36】 今晚重点资料\n283期：博士精选 开：發88\n【發88】 【88.88.88.88】"
        rows8 = extract_dingjian_column(raw_bs, "boshi_jingxuan")
        self.assertEqual(len(rows8), 1)
        self.assertEqual(rows8[0].preds[0]["value"], "马")
        self.assertEqual([a["value"] for a in rows8[0].preds[1:]], ["13", "11", "23", "24", "36"])

        # 9. neibu_1x4m
        raw_nb = "第281期\n本期必开内部一肖+四码\n蛇.12.24.10.22\n第285期\n本期必开内部一肖+四码\n内部资料渠道不易"
        rows9 = extract_dingjian_column(raw_nb, "neibu_1x4m")
        self.assertEqual(len(rows9), 1)
        self.assertEqual(rows9[0].preds[0]["value"], "蛇")
        self.assertEqual([a["value"] for a in rows9[0].preds[1:]], ["12", "24", "10", "22"])

        # 10. zhanggong_2xiao
        raw_zg2 = "第281期\n鸡 龙\n开奖: 鸡10 中\n第282期\n兔-猴\n开奖: 猴23 中\n第285期\n张公神算\n开奖: 發88 中"
        rows10 = extract_dingjian_column(raw_zg2, "zhanggong_2xiao")
        self.assertEqual(len(rows10), 2)
        self.assertEqual([a["value"] for a in rows10[0].preds], ["鸡", "龙"])
        self.assertEqual([a["value"] for a in rows10[1].preds], ["兔", "猴"])

        # 11. hengcai_defense
        raw_hc = "第280期\n龙-15\n防:28-40\n开奖: 龙15 中\n第285期\n發-88\n防:88-88\n开奖: 發88 中"
        rows11 = extract_dingjian_column(raw_hc, "hengcai_defense")
        self.assertEqual(len(rows11), 1)
        self.assertEqual(rows11[0].preds[0]["value"], "龙")
        self.assertEqual([a["value"] for a in rows11[0].preds[1:]], ["15", "28", "40"])

        # 12. five_bracket_numbers
        raw_sj5 = "280期：数据五码\n【15.27.19.07.33】\n中奖\n285期：数据五码\n【88.88.88.88.88】"
        rows12 = extract_dingjian_column(raw_sj5, "five_bracket_numbers")
        self.assertEqual(len(rows12), 1)
        self.assertEqual([a["value"] for a in rows12[0].preds], ["15", "27", "19", "07", "33"])

        # 13. dashi_xinshui
        raw_ds = "280 期\n大师心水 开: 龙15 准\n本期主【 龙 】防【 虎 】\n285 期\n大师心水 开: 發88 准\n本期主【發】防【财】"
        rows13 = extract_dingjian_column(raw_ds, "dashi_xinshui")
        self.assertEqual(len(rows13), 1)
        self.assertEqual([a["value"] for a in rows13[0].preds], ["龙", "虎"])

        # 14. jinpai_1x3m
        raw_jp3 = "第282期\n猴-23\n防:05-17-29\n开奖: 猴23 中\n第285期\n金牌秘报\n开奖: 發88 中"
        rows14 = extract_dingjian_column(raw_jp3, "jinpai_1x3m")
        self.assertEqual(len(rows14), 1)
        self.assertEqual(rows14[0].preds[0]["value"], "猴")
        self.assertEqual([a["value"] for a in rows14[0].preds[1:]], ["23", "05", "17", "29"])

        # 15. wangzhe_duijue
        raw_wzdj = "第282期开奖：猴23准\n王者对决\n【鸡】\nVS\n【牛】\n第285期开奖：鼠19准\n王者对决\n【發】\nVS\n【财】"
        rows15 = extract_dingjian_column(raw_wzdj, "wangzhe_duijue")
        self.assertEqual(len(rows15), 1)
        self.assertEqual([a["value"] for a in rows15[0].preds], ["鸡", "牛"])

        # 16. zhongbang_2x4m
        raw_zb = "282期🔥重磅提炼🔥 开:猴23准\n👉猴‧虎（重中之重）\n👉01.49.21.33（精简绝杀）\n286期🔥重磅提炼🔥 开:發00准\n👉發‧财（重中之重）\n👉88.88.88.88（精简绝杀）"
        rows16 = extract_dingjian_column(raw_zb, "zhongbang_2x4m")
        self.assertEqual(len(rows16), 1)
        self.assertEqual([a["value"] for a in rows16[0].preds[:2]], ["猴", "虎"])
        self.assertEqual([a["value"] for a in rows16[0].preds[2:]], ["01", "49", "21", "33"])

        # 17. caishen_6ma
        raw_cs = "283期 精选猛料 开：牛18 中\n主打②码：17.29\n协防:20.32.18.30\n287期 精选猛料 开：發88 中\n主打②码：精准来料"
        rows17 = extract_dingjian_column(raw_cs, "caishen_6ma")
        self.assertEqual(len(rows17), 1)
        self.assertEqual([a["value"] for a in rows17[0].preds], ["17", "29", "20", "32", "18", "30"])

        # 18. seven_number_lines
        raw_qm = "第283期\n18-30-17-29\n11-23-35\n开奖: 牛18 中\n第287期\n七码连中\n开奖: 發88 中"
        rows18 = extract_dingjian_column(raw_qm, "seven_number_lines")
        self.assertEqual(len(rows18), 1)
        self.assertEqual([a["value"] for a in rows18[0].preds], ["18", "30", "17", "29", "11", "23", "35"])

        # 19. gaoguang_2x2m
        raw_gg = "第284期\n猪-32 兔-28\n开奖: 猪32 中\n第288期\n跟上资料一路中奖\n开奖: 發88 中"
        rows19 = extract_dingjian_column(raw_gg, "gaoguang_2x2m")
        self.assertEqual(len(rows19), 1)
        self.assertEqual([a["value"] for a in rows19[0].preds[:2]], ["猪", "兔"])
        self.assertEqual([a["value"] for a in rows19[0].preds[2:]], ["32", "28"])

        # 20. pyy_1x5m
        raw_py = "284期：【龙】【20.32.24.36.48】 澳门玄机\n288期：【發】【快跟彭于晏中大奖】 澳门玄机"
        rows20 = extract_dingjian_column(raw_py, "pyy_1x5m")
        self.assertEqual(len(rows20), 1)
        self.assertEqual(rows20[0].preds[0]["value"], "龙")
        self.assertEqual([a["value"] for a in rows20[0].preds[1:]], ["20", "32", "24", "36", "48"])

        # 21. fuge_4ma
        raw_fg = "284期\n32.44.29.41\n开:猪32\n288期\n速速跟上中中中\n开:發88"
        rows21 = extract_dingjian_column(raw_fg, "fuge_4ma")
        self.assertEqual(len(rows21), 1)
        self.assertEqual([a["value"] for a in rows21[0].preds], ["32", "44", "29", "41"])

        # 22. xiaokapian_1x2m
        raw_xkp = "第289期\n 蛇-26-38\n 开奖: 蛇38 中\n第290期\n 爆中一肖二码\n速跟发财！\n 开奖: 發88 中"
        rows22 = extract_dingjian_column(raw_xkp, "xiaokapian_1x2m")
        self.assertEqual(len(rows22), 1)
        self.assertEqual(rows22[0].preds[0]["value"], "蛇")
        self.assertEqual([a["value"] for a in rows22[0].preds[1:]], ["26", "38"])

        # 23. jingxuan_7ma
        raw_jx7 = "289期 🔥精选参考🔥 开:蛇38准\n 【17.29.41.09.21.26.38】\n290期 🔥精选参考🔥 开:發88准\n 【继续参与，继续中奖】"
        rows23 = extract_dingjian_column(raw_jx7, "jingxuan_7ma")
        self.assertEqual(len(rows23), 1)
        self.assertEqual([a["value"] for a in rows23[0].preds], ["17", "29", "41", "09", "21", "26", "38"])

        # 24. yihao_6ma
        raw_yh6 = "290\n 期\n 兔40\n \n 🔥 爆料 [内幕爆料]\n 08 20 28 40 09 21\n291\n 期\n 發88\n \n 🔥 爆料 [内幕爆料]\n 88 88 88 88 88 88\n 顶尖大师 058585.com"
        rows24 = extract_dingjian_column(raw_yh6, "yihao_6ma")
        self.assertEqual(len(rows24), 1)
        self.assertEqual([a["value"] for a in rows24[0].preds], ["08", "20", "28", "40", "09", "21"])
        self.assertEqual(rows24[0].claimed["status"], "hit")
        self.assertEqual(rows24[0].claimed["num"], "40")

        # 25. caifu_2x4m
        raw_cf = "第290期\n 兔 狗\n28-40-21-33\n 开奖: 兔40中\n 顶尖大师058585.com\n第291期\n 财富机密\n 跟上发财，准准准\n 开奖: 發88 中\n 顶尖大师058585.com"
        rows25 = extract_dingjian_column(raw_cf, "caifu_2x4m")
        self.assertEqual(len(rows25), 1)
        self.assertEqual([a["value"] for a in rows25[0].preds[:2]], ["兔", "狗"])
        self.assertEqual([a["value"] for a in rows25[0].preds[2:]], ["28", "40", "21", "33"])
        self.assertEqual(rows25[0].claimed["status"], "hit")

        # 26. maizhong_4ma
        raw_mz4 = "291期 📆买这四码📊\n《20.44.17.41》开:虎17\n292期 📆买这四码📊\n《跟买必发！准准准》开:發88\n顶尖大师 058585.com"
        rows26 = extract_dingjian_column(raw_mz4, "maizhong_4ma")
        self.assertEqual(len(rows26), 1)
        self.assertEqual([a["value"] for a in rows26[0].preds], ["20", "44", "17", "41"])
        self.assertEqual(rows26[0].claimed["status"], "hit")
        self.assertEqual(rows26[0].claimed["num"], "17")

        # 27. liaoshen_7ma
        raw_ls7 = "294期 ✦ 料神⑦码\n ﹝04.16.28.26.38.12.24﹞\n 🏆 赚\n295期 ✦ 料神⑦码\n ﹝18.30.42.08.32.14.26﹞\n 🏆 赚"
        rows27 = extract_dingjian_column(raw_ls7, "liaoshen_7ma")
        self.assertEqual(len(rows27), 2)
        self.assertEqual([a["value"] for a in rows27[0].preds], ["04", "16", "28", "26", "38", "12", "24"])
        self.assertEqual([a["value"] for a in rows27[1].preds], ["18", "30", "42", "08", "32", "14", "26"])

        # 28. ganhuo_4ma
        raw_gh4 = "294期（重磅干货）开：兔28准 澳门玄机\n 04◈28◈20◈44\n295期（重磅干货）开：發00准 澳门玄机\n 21◈33◈20◈44\n296期（重磅干货）开：發88准 澳门玄机\n 88◈88◈88◈88"
        rows28 = extract_dingjian_column(raw_gh4, "ganhuo_4ma")
        self.assertEqual(len(rows28), 2)
        self.assertEqual([a["value"] for a in rows28[0].preds], ["04", "28", "20", "44"])
        self.assertEqual(rows28[0].claimed["status"], "hit")
        self.assertEqual([a["value"] for a in rows28[1].preds], ["21", "33", "20", "44"])
        self.assertEqual(rows28[1].claimed["status"], "pending")

        # 29. temawang_2x4m
        raw_tw = "第294期\n 兔-16-28\n鸡-22-34\n 开奖: 兔28 中\n第295期\n 猴-11-23\n兔-16-40\n 开奖: 發88 中\n第296期\n 稳赚二肖\n 开奖: 發88 中"
        rows29 = extract_dingjian_column(raw_tw, "temawang_2x4m")
        self.assertEqual(len(rows29), 2)
        self.assertEqual([a["value"] for a in rows29[0].preds[:2]], ["兔", "鸡"])
        self.assertEqual([a["value"] for a in rows29[0].preds[2:]], ["16", "28", "22", "34"])
        self.assertEqual([a["value"] for a in rows29[1].preds[:2]], ["猴", "兔"])
        self.assertEqual([a["value"] for a in rows29[1].preds[2:]], ["11", "23", "16", "40"])
        self.assertEqual(rows29[1].claimed["status"], "pending")

        # 30. dageda_1x3m
        raw_dgd = "第293期\n 一肖牛\n防:05-17-29\n 开奖: 虎05 中\n第295期\n 一肖马\n防:02-14-26\n 开奖: 發88 中\n第296期\n 一肖内幕\n 开奖: 發88 中"
        rows30 = extract_dingjian_column(raw_dgd, "dageda_1x3m")
        self.assertEqual(len(rows30), 2)
        self.assertEqual(rows30[0].preds[0]["value"], "牛")
        self.assertEqual([a["value"] for a in rows30[0].preds[1:]], ["05", "17", "29"])
        self.assertEqual(rows30[1].preds[0]["value"], "马")
        self.assertEqual([a["value"] for a in rows30[1].preds[1:]], ["02", "14", "26"])
        self.assertEqual(rows30[1].claimed["status"], "pending")

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

    def test_wu_buzhong_extract_filters_placeholders(self):
        raw = """
        <p>
        286期:五不中【44-05-18-26-34】准<br>
        288期:五不中【21-05-43-16-28】准<br>
        289期:五不中【00-00-00-00-00】准<br>
        290期:五不中【00-00-00-00-00】准<br>
        291期:五不中【88-88-88-88-88】准<br>
        292期:五不中【等待公布】准<br>
        293期:五不中【01-02-03】准
        </p>
        """
        rows = wu_buzhong.extract(raw)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0].period_raw, "286")
        self.assertEqual([atom["value"] for atom in rows[0].preds], ["44", "05", "18", "26", "34"])
        self.assertEqual(rows[1].period_raw, "288")
        self.assertEqual([atom["value"] for atom in rows[1].preds], ["21", "05", "43", "16", "28"])


class TestTongtianCatalog(unittest.TestCase):
    def test_reconstruct_script_and_deep_profile(self):
        raw = r'''document.writeln("<table><tr><td>270期</td><td>鼠牛</td><td>？00</td></tr></table>");'''
        self.assertIn("270期", reconstruct_script_html(raw))

        class Response:
            status_code = 200
            url = "https://mirror/chajie/demo.js"
            text = raw

        old_get = tongtian_catalog.get
        tongtian_catalog.get = lambda url, **_: Response()
        try:
            result = analyze_script("https://mirror", "/chajie/demo.js")
        finally:
            tongtian_catalog.get = old_get
        self.assertTrue(result["ok"])
        self.assertEqual(result["record_count"], 1)
        self.assertEqual(result["latest_period"], 270)

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
    def test_dingjian_deep_profile_reads_periods_and_assets(self):
        profile = classify_content(
            '<div><h1>测试</h1><p>第270期:【鼠牛】开:鼠01准</p><img src="/a.png"></div>',
            source="detail_api",
            name="测试",
        )
        self.assertEqual(profile["analysis"]["parser_hint"], "period_prediction_claim")
        self.assertEqual(profile["analysis"]["latest_period"], 270)
        self.assertEqual(profile["analysis"]["record_count"], 1)

    def test_dingji_page_parser_reads_live_table_rows(self):
        title, rows = _parse_amtz_records(
            '<h1>顶级论坛【九肖】</h1><table><tr><td>270期:【鼠牛】开:鼠01准</td></tr></table>'
        )
        self.assertIn("九肖", title)
        self.assertEqual(rows[0]["period"], 270)
        self.assertEqual(rows[0]["status"], "hit")

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

    def test_batch_template_uses_588080_upstream_id(self):
        script = render_template(
            {
                "source_id": "dj_new_column",
                "source_name": "顶尖新栏目",
                "site_family": "dingjian_dashi",
                "play_type": "tema_n",
                "hit_mode": "any",
                "extra": {"upstream_id": "1788003193307", "kind": "num", "parser": "rescue_six"},
            }
        )
        self.assertIn("build_column_pred", script)
        self.assertIn('PATH = "/api/v1/index/config/byid/1788003193307"', script)
        self.assertIn('KIND = "num"', script)

    def test_batch_template_allows_mixed_588080_contract(self):
        script = render_template(
            {
                "source_id": "dj_mixed_column",
                "source_name": "顶尖一肖八码",
                "site_family": "dingjian_dashi",
                "play_type": "texiao",
                "hit_mode": "any",
                "extra": {"upstream_id": "1784459913197", "kind": "mixed", "parser": "xiao_num_defense"},
            }
        )
        self.assertIn("build_column_pred", script)
        self.assertIn('KIND = "mixed"', script)

    def test_reconcile_missing_defaults_to_preview(self):
        old_status = site_catalog.status
        site_catalog.status = lambda _: {
            "site_family": "fake",
            "missing": [{"path": "/chajie/old.js", "sources": [{"source_id": "tt_old", "source_name": "旧栏目"}]}],
        }
        try:
            result = site_catalog.reconcile_missing(site_family="fake")
        finally:
            site_catalog.status = old_status
        self.assertTrue(result["dry_run"])
        self.assertEqual(result["items"][0]["source_id"], "tt_old")

    def test_expand_five_period_bundle(self):
        rows = expand_period_ranges(
            [{"period_raw": "265", "pred_raw": "02.09", "claim_raw": "", "full_text": "261-265期特码 02.09"}]
        )
        self.assertEqual([row["period_raw"] for row in rows], ["261", "262", "263", "264", "265"])


if __name__ == "__main__":
    unittest.main()
