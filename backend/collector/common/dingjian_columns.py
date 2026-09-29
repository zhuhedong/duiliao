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
    "primary_two_numbers": ("num", 2, r"(?m)^\s*[鼠牛虎兔龙蛇马羊猴鸡狗猪]\s*[-－]\s*(\d{2}\s*[-－]\s*\d{2})\s*$"),
    "main_bracket_xiao": ("xiao", 1, r"【([鼠牛虎兔龙蛇马羊猴鸡狗猪])】"),
    "archive_two_numbers": ("num", 2, r"内幕【[鼠牛虎兔龙蛇马羊猴鸡狗猪](\d{2})】\s*VS\s*【[鼠牛虎兔龙蛇马羊猴鸡狗猪](\d{2})】"),
    "xiao_num_defense": ("all", 6, r""),
    "wangshouyi_defense": ("all", 6, r""),
    "bracket_pairs_2x2m": ("all", 4, r""),
    "ribao_drag_defense": ("all", 6, r""),
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
