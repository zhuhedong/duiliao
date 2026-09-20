"""号码五行（金木水火土）。

五行按农历年（春节切换）轮换，且不同年份分组不同，无法由号码本身或生肖推导，
只能依据当年官方「生肖灵码 / 五行」对照表录入。这里按农历年登记权威分组，
未登记的年份返回 None（不臆造）。新增一年只需在 WUXING_BY_YEAR 加一条。
"""
from __future__ import annotations

from datetime import date

from common.xiao import lunar_year

ELEMENTS = ("金", "木", "水", "火", "土")

# 号码分组，键为农历年。来源：当年澳门正版《六合大全经典全年资料》生肖灵码表。
WUXING_BY_YEAR: dict[int, dict[str, tuple[int, ...]]] = {
    # 2026 丙午（马）年，2 月 17 日启用。
    2026: {
        "金": (4, 5, 12, 13, 26, 27, 34, 35, 42, 43),
        "木": (8, 9, 16, 17, 24, 25, 38, 39, 46, 47),
        "水": (1, 14, 15, 22, 23, 30, 31, 44, 45),
        "火": (2, 3, 10, 11, 18, 19, 32, 33, 40, 41, 48, 49),
        "土": (6, 7, 20, 21, 28, 29, 36, 37),
    },
}


def _index_for_year(ly: int) -> dict[int, str] | None:
    groups = WUXING_BY_YEAR.get(ly)
    if not groups:
        return None
    index: dict[int, str] = {}
    for element, nums in groups.items():
        for n in nums:
            index[n] = element
    return index


def _validate() -> None:
    """Fail fast if a registered year's table is not a clean 1–49 partition."""
    for year, groups in WUXING_BY_YEAR.items():
        seen: dict[int, str] = {}
        for element, nums in groups.items():
            if element not in ELEMENTS:
                raise ValueError(f"{year} 五行未知类别: {element}")
            for n in nums:
                if not 1 <= n <= 49:
                    raise ValueError(f"{year} 五行号码越界: {n}")
                if n in seen:
                    raise ValueError(f"{year} 五行号码重复: {n}（{seen[n]} / {element}）")
                seen[n] = element
        missing = set(range(1, 50)) - set(seen)
        if missing:
            raise ValueError(f"{year} 五行缺少号码: {sorted(missing)}")


_validate()


def wuxing_years() -> list[int]:
    """Lunar years with an authoritative table."""
    return sorted(WUXING_BY_YEAR)


def num_to_wuxing(num: int | str, draw_date: date) -> str | None:
    """五行 of a number for the lunar year in effect on ``draw_date``.

    Returns None when that lunar year has no registered table.
    """
    n = int(num)
    if n < 1 or n > 49:
        raise ValueError(f"num out of range: {num}")
    index = _index_for_year(lunar_year(draw_date))
    return index.get(n) if index else None
