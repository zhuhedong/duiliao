"""Reviewed 588080 column contracts. Picks never fall back to whole-row tokens."""
from __future__ import annotations

import re
from common.catalog_text import claimed_from_block, period_blocks
from common.parse_pred import strip_html
from common.source_rows import ParsedRow, build_prediction

# Each selector is deliberately tied to observed markup, not the column name.
# A changed contract produces no predictions instead of using the draw as a pick.
EXTRACTORS = {
    "rescue_six": ("num", 6, r"精选\s*[:：]\s*([^\n]+)|必备\s*[:：]\s*【([^】]+)】"),
    "six_number_lines": ("num", 6, r"(?m)^\s*(\d{2}(?:\s*[-－]\s*\d{2}){2})\s*$"),
    "four_number_line": ("num", 4, r"(?m)^\s*(\d{2}(?:\s*[-－]\s*\d{2}){3})\s*$"),
    "four_bracket_numbers": ("num", 4, r"┣\s*([\d.\s]+)\s*┫"),
    "recommended_xiao": ("xiao", 1, r"今日推荐\s*[（(]([^）)]+)[）)]"),
    "eight_bracket_numbers": ("num", 8, r"【([\d.\s]+)】"),
    "seven_bracket_numbers": ("num", 7, r"【([\d.\s]+)】"),
    "five_bracket_numbers": ("num", 5, r"【([\d.\s]+)】"),
    "primary_two_numbers": ("num", 2, r"(?m)^\s*[鼠牛虎兔龙蛇马羊猴鸡狗猪]\s*[-－]\s*(\d{2}\s*[-－]\s*\d{2})\s*$"),
    "main_bracket_xiao": ("xiao", 1, r"【([鼠牛虎兔龙蛇马羊猴鸡狗猪])】"),
    "archive_two_numbers": ("num", 2, r"内幕【[鼠牛虎兔龙蛇马羊猴鸡狗猪](\d{2})】\s*VS\s*【[鼠牛虎兔龙蛇马羊猴鸡狗猪](\d{2})】"),
    "xiao_num_defense": ("all", 6, r""),
    "wangshouyi_defense": ("all", 6, r""),
    "bracket_pairs_2x2m": ("all", 4, r""),
    "ribao_drag_defense": ("all", 6, r""),
    "baofu_3xiao": ("xiao", 3, r""),
    "diamond_four_numbers": ("num", 4, r""),
    "datoumi_defense": ("all", 5, r""),
    "wangzhe_defense": ("all", 0, r""),
    "juemi_2x4m": ("all", 6, r""),
    "xingyun_6ma": ("num", 6, r""),
    "jipin_defense": ("all", 5, r""),
    "zhugong_3ma": ("num", 3, r""),
    "kaijiang_2xiao": ("xiao", 2, r""),
    "boshi_jingxuan": ("all", 6, r""),
    "neibu_1x4m": ("all", 5, r""),
    "zhanggong_2xiao": ("xiao", 2, r""),
    "hengcai_defense": ("all", 4, r""),
    "dashi_xinshui": ("xiao", 2, r""),
    "jinpai_1x3m": ("all", 5, r""),
    "wangzhe_duijue": ("xiao", 2, r""),
    "zhongbang_2x4m": ("all", 6, r""),
    "caishen_6ma": ("num", 6, r""),
    "seven_number_lines": ("num", 7, r""),
    "gaoguang_2x2m": ("all", 4, r""),
    "pyy_1x5m": ("all", 6, r""),
    "fuge_4ma": ("num", 4, r""),
    "xiaokapian_1x2m": ("all", 3, r""),
    "jingxuan_7ma": ("num", 7, r""),
    "yihao_6ma": ("num", 6, r""),
    "caifu_2x4m": ("all", 6, r""),
}


def extract(raw: str, parser: str) -> list[ParsedRow]:
    kind, count, pattern = EXTRACTORS[parser]
    rows = []
    for period, block in period_blocks(strip_html(raw)):
        if parser == "xiao_num_defense":
            xiao_match = re.search(r"①肖\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*(\d{2})", block)
            defense_match = re.search(r"防\s*[:：]\s*([^\n]+)", block)
            if not xiao_match or not defense_match:
                continue
            numbers = re.findall(r"(?<!\d)\d{2}(?!\d)", defense_match.group(1))
            main_number = xiao_match.group(2)
            if not 1 <= int(main_number) <= 49:
                continue
            if len(numbers) != 4 or len(set(numbers)) != 4 or any(not 1 <= int(value) <= 49 for value in numbers):
                continue
            selected = f"{xiao_match.group(1)} {main_number} 防：{' '.join(numbers)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao_match.group(1), "text": selected},
                    {"kind": "num", "value": main_number, "text": selected},
                    *({"kind": "num", "value": value, "text": selected} for value in numbers),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "wangshouyi_defense":
            m_xiao = re.search(r"([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[-－]\s*(\d{2})", block)
            m_def = re.search(r"(?m)^\s*(\d{2}(?:\s*[-－]\s*\d{2}){3})\s*$", block)
            if not m_xiao or not m_def:
                continue
            xiao, main_num = m_xiao.group(1), m_xiao.group(2)
            def_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m_def.group(1))
            if not (1 <= int(main_num) <= 49) or len(def_nums) != 4 or any(not 1 <= int(n) <= 49 for n in def_nums):
                continue
            nums = [main_num, *def_nums]
            if len(set(nums)) != 5:
                continue
            selected = f"{xiao}-{main_num} 防:{m_def.group(1)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    *({"kind": "num", "value": n, "text": selected} for n in nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "bracket_pairs_2x2m":
            pairs = re.findall(r"\[([鼠牛虎兔龙蛇马羊猴鸡狗猪])(\d{2})\]", block)
            if len(pairs) != 2:
                continue
            xiaos = [p[0] for p in pairs]
            nums = [p[1] for p in pairs]
            if any(not 1 <= int(n) <= 49 for n in nums) or len(set(nums)) != 2 or len(set(xiaos)) != 2:
                continue
            selected = " ".join(f"[{x}{n}]" for x, n in pairs)
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    *({"kind": "xiao", "value": x, "text": selected} for x in xiaos),
                    *({"kind": "num", "value": n, "text": selected} for n in nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "ribao_drag_defense":
            m_main = re.search(r"搞钱[②2]码\s*\(([\d.]+)\)\s*拖\s*\(([\d.]+)\)", block)
            m_xiao = re.search(r"协防\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])", block)
            if not m_main or not m_xiao:
                continue
            main_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m_main.group(1))
            tuo_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m_main.group(2))
            xiao = m_xiao.group(1)
            if len(main_nums) != 2 or len(tuo_nums) != 3:
                continue
            all_nums = [*main_nums, *tuo_nums]
            if any(not 1 <= int(n) <= 49 for n in all_nums) or len(set(all_nums)) != 5:
                continue
            selected = f"搞钱2码({m_main.group(1)})拖({m_main.group(2)}) 协防{xiao}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    *({"kind": "num", "value": n, "text": selected} for n in all_nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "baofu_3xiao":
            m = re.search(r"【([鼠牛虎兔龙蛇马羊猴鸡狗猪])】\s*【([鼠牛虎兔龙蛇马羊猴鸡狗猪])】\s*\+\s*小买\s*【([鼠牛虎兔龙蛇马羊猴鸡狗猪])】", block)
            if not m:
                continue
            xiaos = list(dict.fromkeys(m.groups()))
            if len(xiaos) != 3:
                continue
            selected = f"【{m.group(1)}】【{m.group(2)}】+小买【{m.group(3)}】"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "xiao", "value": x, "text": selected} for x in xiaos],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "diamond_four_numbers":
            nums = re.findall(r"(?<!\d)(\d{2})(?:中)?(?!\d)", block)
            nums = [n for n in nums if 1 <= int(n) <= 49 and n != period]
            if len(nums) < 4:
                continue
            target = nums[:4]
            if len(set(target)) != 4:
                continue
            selected = " ".join(target)
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "num", "value": n, "text": selected} for n in target],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "datoumi_defense":
            m_xiao = re.search(r"([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[-－]\s*(\d{2})\s*[-－]\s*(\d{2})", block)
            m_def = re.search(r"防\s*[:：]\s*(\d{2})\s*[-－]\s*(\d{2})", block)
            if not m_xiao:
                continue
            xiao = m_xiao.group(1)
            m1, m2 = m_xiao.group(2), m_xiao.group(3)
            all_nums = [m1, m2]
            if m_def:
                all_nums.extend([m_def.group(1), m_def.group(2)])
            if len(all_nums) != 4 or len(set(all_nums)) != 4 or any(not 1 <= int(n) <= 49 for n in all_nums):
                continue
            selected = f"{xiao}-{m1}-{m2} 防:{m_def.group(1)}-{m_def.group(2)}" if m_def else f"{xiao}-{m1}-{m2}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    *({"kind": "num", "value": n, "text": selected} for n in all_nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "wangzhe_defense":
            m_main = re.search(r"精准\s*【([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[-－]\s*(\d{2})】", block)
            if not m_main:
                continue
            xiao = m_main.group(1)
            main_num = m_main.group(2)
            m_def = re.search(r"防[:：]?\s*([\d.]+)", block)
            def_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m_def.group(1)) if m_def else []
            all_nums = list(dict.fromkeys([main_num, *def_nums]))
            if any(not 1 <= int(n) <= 49 for n in all_nums):
                continue
            selected = f"【{xiao}-{main_num}】" + (f" 防:{m_def.group(1)}" if m_def else "")
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    *({"kind": "num", "value": n, "text": selected} for n in all_nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "juemi_2x4m":
            lines = [l.strip() for l in block.splitlines() if l.strip() and "期" not in l and "开奖" not in l and "顶尖" not in l and "独家" not in l]
            if len(lines) < 2:
                continue
            xiaos = list(dict.fromkeys(re.findall(r"[鼠牛虎兔龙蛇马羊猴鸡狗猪]", lines[0])))
            nums = list(dict.fromkeys(re.findall(r"(?<!\d)\d{2}(?!\d)", lines[1])))
            if len(xiaos) != 2 or len(nums) != 4 or any(not 1 <= int(n) <= 49 for n in nums):
                continue
            selected = f"{' '.join(xiaos)} {' '.join(nums)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    *({"kind": "xiao", "value": x, "text": selected} for x in xiaos),
                    *({"kind": "num", "value": n, "text": selected} for n in nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "xingyun_6ma":
            m_jx = re.search(r"精选\s*[「【\[]([\d.]+)[」】\]]", block)
            m_zs = re.search(r"赠送\s*[「【\[]([\d.]+)[」】\]]", block)
            if not m_jx or not m_zs:
                continue
            jx_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m_jx.group(1))
            zs_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m_zs.group(1))
            all_nums = list(dict.fromkeys([*jx_nums, *zs_nums]))
            if len(all_nums) != 6 or any(not 1 <= int(n) <= 49 for n in all_nums):
                continue
            selected = f"精选「{m_jx.group(1)}」赠送「{m_zs.group(1)}」"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "num", "value": n, "text": selected} for n in all_nums],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "jipin_defense":
            m_main = re.search(r"玄机①码\s*[:：]?\s*[✡*]?\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])?\s*(\d{2})\s*[✡*]?", block)
            m_defense = re.search(r"(?m)^\s*[✡*]\s*([\d.\s]+)\s*[✡*]\s*$", block)
            if not m_main or not m_defense:
                continue
            xiao = m_main.group(1)
            main_num = m_main.group(2)
            other_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m_defense.group(1))
            all_nums = list(dict.fromkeys([main_num, *other_nums]))
            if len(all_nums) != 5 or any(not 1 <= int(n) <= 49 for n in all_nums):
                continue
            selected = f"玄机①码:{xiao or ''}{main_num} 防:{' '.join(other_nums)}"
            preds = []
            if xiao:
                preds.append({"kind": "xiao", "value": xiao, "text": selected})
            preds.extend({"kind": "num", "value": n, "text": selected} for n in all_nums)
            rows.append(ParsedRow(
                period_raw=period,
                preds=preds,
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "zhugong_3ma":
            m_zg = re.search(r"主攻三码\s*([\d\s·.]+)\s*次参考码", block)
            if not m_zg:
                continue
            nums = list(dict.fromkeys(re.findall(r"(?<!\d)\d{2}(?!\d)", m_zg.group(1))))
            if len(nums) != 3 or any(not 1 <= int(n) <= 49 for n in nums):
                continue
            selected = f"主攻三码 {' '.join(nums)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "num", "value": n, "text": selected} for n in nums],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "kaijiang_2xiao":
            lines = [l.strip() for l in block.splitlines() if l.strip() and "期" not in l and "密函" not in l and "顶尖" not in l and "内部" not in l and "澳门" not in l and "拆封" not in l]
            xiaos = [line for line in lines if re.fullmatch(r"[鼠牛虎兔龙蛇马羊猴鸡狗猪]", line)]
            if len(xiaos) != 2:
                continue
            selected = " ".join(xiaos)
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "xiao", "value": x, "text": selected} for x in xiaos],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "boshi_jingxuan":
            m = re.search(r"【([鼠牛虎兔龙蛇马羊猴鸡狗猪])(\d{2})】\s*【([\d.\s]+)】", block)
            if not m:
                continue
            xiao = m.group(1)
            main_num = m.group(2)
            other_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m.group(3))
            all_nums = list(dict.fromkeys([main_num, *other_nums]))
            if len(all_nums) != 5 or any(not 1 <= int(n) <= 49 for n in all_nums):
                continue
            selected = f"【{xiao}{main_num}】 【{m.group(3)}】"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    *({"kind": "num", "value": n, "text": selected} for n in all_nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "neibu_1x4m":
            m = re.search(r"(?m)^\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])[.\s·\-－:：]+((?:\d{2}[.\s·\-－]*){4})\s*$", block)
            if not m:
                continue
            xiao = m.group(1)
            nums = list(dict.fromkeys(re.findall(r"(?<!\d)\d{2}(?!\d)", m.group(2))))
            if len(nums) != 4 or any(not 1 <= int(n) <= 49 for n in nums):
                continue
            selected = f"{xiao}.{'.'.join(nums)}"
            clean_claim_block = re.sub(r"本期必开[^\n]*", "", block)
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    *({"kind": "num", "value": n, "text": selected} for n in nums),
                ],
                claimed=claimed_from_block(clean_claim_block),
                raw_text=block,
            ))
            continue
        if parser == "zhanggong_2xiao":
            m = re.search(r"(?m)^\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[-－\s·.,，、]?\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*$", block)
            if not m:
                continue
            xiaos = list(dict.fromkeys([m.group(1), m.group(2)]))
            if len(xiaos) != 2:
                continue
            selected = f"{xiaos[0]} {xiaos[1]}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "xiao", "value": x, "text": selected} for x in xiaos],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "hengcai_defense":
            m_xiao = re.search(r"(?m)^\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[-－]\s*(\d{2})\s*$", block)
            m_def = re.search(r"防\s*[:：]\s*(\d{2})\s*[-－.\s]+\s*(\d{2})", block)
            if not m_xiao or not m_def:
                continue
            xiao = m_xiao.group(1)
            all_nums = list(dict.fromkeys([m_xiao.group(2), m_def.group(1), m_def.group(2)]))
            if len(all_nums) != 3 or any(not 1 <= int(n) <= 49 for n in all_nums):
                continue
            selected = f"{xiao}-{m_xiao.group(2)} 防:{m_def.group(1)}-{m_def.group(2)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    *({"kind": "num", "value": n, "text": selected} for n in all_nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "dashi_xinshui":
            m = re.search(r"主\s*【\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*】\s*防\s*【\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*】", block)
            if not m:
                continue
            xiaos = list(dict.fromkeys([m.group(1), m.group(2)]))
            if len(xiaos) != 2:
                continue
            selected = f"主【{xiaos[0]}】防【{xiaos[1]}】"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "xiao", "value": x, "text": selected} for x in xiaos],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "jinpai_1x3m":
            m_xiao = re.search(r"(?m)^\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[-－]\s*(\d{2})\s*$", block)
            m_def = re.search(r"防\s*[:：]\s*(\d{2})\s*[-－.\s]+\s*(\d{2})\s*[-－.\s]+\s*(\d{2})", block)
            if not m_xiao or not m_def:
                continue
            xiao = m_xiao.group(1)
            all_nums = list(dict.fromkeys([m_xiao.group(2), m_def.group(1), m_def.group(2), m_def.group(3)]))
            if len(all_nums) != 4 or any(not 1 <= int(n) <= 49 for n in all_nums):
                continue
            selected = f"{xiao}-{m_xiao.group(2)} 防:{m_def.group(1)}-{m_def.group(2)}-{m_def.group(3)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    *({"kind": "num", "value": n, "text": selected} for n in all_nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "wangzhe_duijue":
            m = re.search(r"【\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*】\s*VS\s*【\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*】", block, re.IGNORECASE)
            if not m:
                continue
            xiaos = list(dict.fromkeys([m.group(1), m.group(2)]))
            if len(xiaos) != 2:
                continue
            selected = f"【{xiaos[0]}】VS【{xiaos[1]}】"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "xiao", "value": x, "text": selected} for x in xiaos],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "zhongbang_2x4m":
            m_xiao = re.search(r"([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[‧·.\-－\s]+\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[（(]", block)
            m_num = re.search(r"((?:\d{2}[.\s·\-－]*){4})\s*[（(]", block)
            if not m_xiao or not m_num:
                continue
            xiaos = list(dict.fromkeys([m_xiao.group(1), m_xiao.group(2)]))
            nums = list(dict.fromkeys(re.findall(r"(?<!\d)\d{2}(?!\d)", m_num.group(1))))
            if len(xiaos) != 2 or len(nums) != 4 or any(not 1 <= int(n) <= 49 for n in nums):
                continue
            selected = f"{xiaos[0]}‧{xiaos[1]} {'.'.join(nums)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    *({"kind": "xiao", "value": x, "text": selected} for x in xiaos),
                    *({"kind": "num", "value": n, "text": selected} for n in nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "caishen_6ma":
            m_main = re.search(r"主打[②2]码\s*[:：]\s*(\d{2}[.\s·\-－]+\d{2})", block)
            m_def = re.search(r"协防\s*[:：]\s*((?:\d{2}[.\s·\-－]*){4})", block)
            if not m_main or not m_def:
                continue
            main_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m_main.group(1))
            def_nums = re.findall(r"(?<!\d)\d{2}(?!\d)", m_def.group(1))
            all_nums = list(dict.fromkeys([*main_nums, *def_nums]))
            if len(all_nums) != 6 or any(not 1 <= int(n) <= 49 for n in all_nums):
                continue
            selected = f"主打2码:{'.'.join(main_nums)} 协防:{'.'.join(def_nums)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "num", "value": n, "text": selected} for n in all_nums],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "seven_number_lines":
            m1 = re.search(r"(?m)^\s*(\d{2}(?:\s*[-－]\s*\d{2}){3})\s*$", block)
            m2 = re.search(r"(?m)^\s*(\d{2}(?:\s*[-－]\s*\d{2}){2})\s*$", block)
            if not m1 or not m2:
                continue
            nums1 = re.findall(r"(?<!\d)\d{2}(?!\d)", m1.group(1))
            nums2 = re.findall(r"(?<!\d)\d{2}(?!\d)", m2.group(1))
            all_nums = list(dict.fromkeys([*nums1, *nums2]))
            if len(all_nums) != 7 or any(not 1 <= int(n) <= 49 for n in all_nums):
                continue
            selected = f"{'-'.join(nums1)} {'-'.join(nums2)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "num", "value": n, "text": selected} for n in all_nums],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "gaoguang_2x2m":
            m = re.search(r"(?m)^\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[-－]\s*(\d{2})\s+([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[-－]\s*(\d{2})\s*$", block)
            if not m:
                continue
            x1, n1, x2, n2 = m.group(1), m.group(2), m.group(3), m.group(4)
            if x1 == x2 or n1 == n2 or not (1 <= int(n1) <= 49) or not (1 <= int(n2) <= 49):
                continue
            selected = f"{x1}-{n1} {x2}-{n2}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": x1, "text": selected},
                    {"kind": "xiao", "value": x2, "text": selected},
                    {"kind": "num", "value": n1, "text": selected},
                    {"kind": "num", "value": n2, "text": selected},
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "pyy_1x5m":
            m = re.search(r"【\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*】\s*【\s*((?:\d{2}[.\s·\-－]*){5})\s*】", block)
            if not m:
                continue
            xiao = m.group(1)
            nums = list(dict.fromkeys(re.findall(r"(?<!\d)\d{2}(?!\d)", m.group(2))))
            if len(nums) != 5 or any(not 1 <= int(n) <= 49 for n in nums):
                continue
            selected = f"【{xiao}】【{'.'.join(nums)}】"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    *({"kind": "num", "value": n, "text": selected} for n in nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "fuge_4ma":
            m = re.search(r"(?m)^\s*((?:\d{2}[.\s·\-－]*){4})\s*$", block)
            if not m:
                continue
            nums = list(dict.fromkeys(re.findall(r"(?<!\d)\d{2}(?!\d)", m.group(1))))
            if len(nums) != 4 or any(not 1 <= int(n) <= 49 for n in nums):
                continue
            selected = ".".join(nums)
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "num", "value": n, "text": selected} for n in nums],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "xiaokapian_1x2m":
            m = re.search(r"([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*[-－]\s*(\d{2})\s*[-－]\s*(\d{2})", block)
            if not m:
                continue
            xiao, n1, n2 = m.group(1), m.group(2), m.group(3)
            nums = [n1, n2]
            if any(not 1 <= int(n) <= 49 for n in nums) or len(set(nums)) != 2:
                continue
            selected = f"{xiao}-{n1}-{n2}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    {"kind": "xiao", "value": xiao, "text": selected},
                    {"kind": "num", "value": n1, "text": selected},
                    {"kind": "num", "value": n2, "text": selected},
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "jingxuan_7ma":
            m = re.search(r"【\s*((?:\d{2}[.\s·\-－]*){7})\s*】", block)
            if not m:
                continue
            nums = list(dict.fromkeys(re.findall(r"(?<!\d)\d{2}(?!\d)", m.group(1))))
            if len(nums) != 7 or any(not 1 <= int(n) <= 49 for n in nums):
                continue
            selected = ".".join(nums)
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "num", "value": n, "text": selected} for n in nums],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        if parser == "yihao_6ma":
            m = re.search(r"\[内幕爆料\]\s*([\s\S]+?)(?:\n\s*顶尖大师|\Z)", block)
            if not m:
                continue
            nums = list(dict.fromkeys(re.findall(r"\d{2}", m.group(1))))
            if len(nums) != 6 or any(not 1 <= int(n) <= 49 for n in nums):
                continue
            m_claim = re.search(r"期\s*([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s*(\d{2})", block)
            if m_claim:
                claim_xiao, claim_num = m_claim.group(1), m_claim.group(2)
                claimed = {"status": "hit" if claim_num in nums else "miss", "xiao": claim_xiao, "num": claim_num, "raw": f"{claim_xiao}{claim_num}"}
            else:
                claimed = claimed_from_block(block)
            selected = ".".join(nums)
            rows.append(ParsedRow(
                period_raw=period,
                preds=[{"kind": "num", "value": n, "text": selected} for n in nums],
                claimed=claimed,
                raw_text=block,
            ))
            continue
        if parser == "caifu_2x4m":
            m_xiao = re.search(r"([鼠牛虎兔龙蛇马羊猴鸡狗猪])\s+([鼠牛虎兔龙蛇马羊猴鸡狗猪])", block)
            m_num = re.search(r"(\d{2}(?:\s*[-－]\s*\d{2}){3})", block)
            if not m_xiao or not m_num:
                continue
            xiaos = [m_xiao.group(1), m_xiao.group(2)]
            nums = list(dict.fromkeys(re.findall(r"(?<!\d)\d{2}(?!\d)", m_num.group(1))))
            if len(set(xiaos)) != 2 or len(nums) != 4 or any(not 1 <= int(n) <= 49 for n in nums):
                continue
            selected = f"{xiaos[0]} {xiaos[1]} {'.'.join(nums)}"
            rows.append(ParsedRow(
                period_raw=period,
                preds=[
                    *({"kind": "xiao", "value": x, "text": selected} for x in xiaos),
                    *({"kind": "num", "value": n, "text": selected} for n in nums),
                ],
                claimed=claimed_from_block(block),
                raw_text=block,
            ))
            continue
        matches = re.findall(pattern, block)
        selected = " ".join(part for match in matches for part in (match if isinstance(match, tuple) else (match,)) if part)
        tokens = re.findall(r"(?<!\d)\d{2}(?!\d)" if kind == "num" else r"[鼠牛虎兔龙蛇马羊猴鸡狗猪]", selected)
        values = list(dict.fromkeys(tokens))
        if len(values) != count or (kind == "num" and any(not 1 <= int(value) <= 49 for value in values)):
            continue
        rows.append(ParsedRow(
            period_raw=period,
            preds=[{"kind": kind, "value": value, "text": selected} for value in values],
            claimed=claimed_from_block(block),
            raw_text=block,
        ))
    return rows


def build_column_pred(*, source_id: str, source_name: str, play_type: str, hit_mode: str,
                      urls: list[str], parser: str, lottery: str, period: str | None, fixture: str | None):
    from common.source_fetch import load_page
    page = load_page(urls=urls, fixture=fixture)
    return build_prediction(
        page=page, lottery=lottery, period=period, source_id=source_id,
        source_name=source_name, site_family="dingjian_dashi", play_type=play_type,
        hit_mode=hit_mode, rows=extract(page.text, parser),
        empty_error=f"{source_name} 未提取到符合已审核契约的预测数据",
    )
