from __future__ import annotations

from datetime import date

XIAO = ("鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪")

XIAO_NORM = {
    "鼠": "鼠",
    "牛": "牛",
    "虎": "虎",
    "兔": "兔",
    "龙": "龙",
    "龍": "龙",
    "蛇": "蛇",
    "马": "马",
    "馬": "马",
    "羊": "羊",
    "猴": "猴",
    "鸡": "鸡",
    "雞": "鸡",
    "狗": "狗",
    "猪": "猪",
    "豬": "猪",
}

# Gregorian date of 春节 (month, day) keyed by lunar new year number.
CNY_MD = {
    2000: (2, 5),
    2001: (1, 24),
    2002: (2, 12),
    2003: (2, 1),
    2004: (1, 22),
    2005: (2, 9),
    2006: (1, 29),
    2007: (2, 18),
    2008: (2, 7),
    2009: (1, 26),
    2010: (2, 14),
    2011: (2, 3),
    2012: (1, 23),
    2013: (2, 10),
    2014: (1, 31),
    2015: (2, 19),
    2016: (2, 8),
    2017: (1, 28),
    2018: (2, 16),
    2019: (2, 5),
    2020: (1, 25),
    2021: (2, 12),
    2022: (2, 1),
    2023: (1, 22),
    2024: (2, 10),
    2025: (1, 29),
    2026: (2, 17),
    2027: (2, 6),
    2028: (1, 26),
    2029: (2, 13),
    2030: (2, 3),
    2031: (1, 23),
    2032: (2, 11),
    2033: (1, 31),
    2034: (2, 19),
    2035: (2, 8),
    2036: (1, 28),
    2037: (2, 15),
    2038: (2, 4),
    2039: (1, 24),
    2040: (2, 12),
}

JIA_XIAO = frozenset({"牛", "马", "羊", "鸡", "狗", "猪"})
YE_XIAO = frozenset({"鼠", "虎", "兔", "龙", "蛇", "猴"})

NAN_XIAO = frozenset({"鼠", "牛", "虎", "龙", "马", "猴", "狗"})
NV_XIAO = frozenset({"兔", "蛇", "羊", "鸡", "猪"})

TIAN_XIAO = frozenset({"牛", "兔", "龙", "马", "猴", "猪"})
DI_XIAO = frozenset({"鼠", "虎", "蛇", "羊", "鸡", "狗"})

YANG_XIAO = frozenset({"牛", "虎", "兔", "羊", "猴", "鸡"})
YIN_XIAO = frozenset({"鼠", "龙", "蛇", "马", "狗", "猪"})

JI_XIAO = frozenset({"兔", "龙", "蛇", "马", "羊", "鸡"})
XIONG_XIAO = frozenset({"鼠", "牛", "虎", "猴", "狗", "猪"})

SEASON_XIAO = {
    "春": frozenset({"虎", "兔", "龙"}),
    "夏": frozenset({"蛇", "马", "羊"}),
    "秋": frozenset({"猴", "鸡", "狗"}),
    "冬": frozenset({"鼠", "牛", "猪"}),
}

DIRECTION_XIAO = {
    "东": frozenset({"虎", "兔", "龙"}),
    "南": frozenset({"蛇", "马", "羊"}),
    "西": frozenset({"猴", "鸡", "狗"}),
    "北": frozenset({"鼠", "牛", "猪"}),
}


def normalize_xiao(value: str) -> str:
    v = (value or "").strip()
    if v not in XIAO_NORM:
        raise ValueError(f"unknown xiao: {value!r}")
    return XIAO_NORM[v]


def lunar_year(d: date) -> int:
    """Lunar year number that is in effect on Gregorian date `d`."""
    y = d.year
    md = CNY_MD.get(y)
    if md is None:
        # rough fallback: treat Feb 20 as 春节
        return y if (d.month, d.day) >= (2, 20) else y - 1
    cny = date(y, md[0], md[1])
    return y if d >= cny else y - 1


def year_xiao(d: date) -> str:
    # 1984 = 鼠. (year - 4) % 12
    ly = lunar_year(d)
    return XIAO[(ly - 4) % 12]


def num_to_xiao(num: int | str, draw_date: date) -> str:
    n = int(num)
    if n < 1 or n > 49:
        raise ValueError(f"num out of range: {num}")
    yx = year_xiao(draw_date)
    idx = XIAO.index(yx)
    return XIAO[(idx - (n - 1)) % 12]


def nums_to_xiao(nums: list[int | str], draw_date: date) -> list[str]:
    return [num_to_xiao(n, draw_date) for n in nums]


def is_jia(xiao: str) -> bool:
    return normalize_xiao(xiao) in JIA_XIAO


def jia_ye(xiao: str) -> str:
    return "家" if is_jia(xiao) else "野"


def gender_xiao(xiao: str) -> str:
    return "男肖" if normalize_xiao(xiao) in NAN_XIAO else "女肖"


def tiandi_xiao(xiao: str) -> str:
    return "天肖" if normalize_xiao(xiao) in TIAN_XIAO else "地肖"


def yinyang_xiao(xiao: str) -> str:
    return "阳肖" if normalize_xiao(xiao) in YANG_XIAO else "阴肖"


def luck_xiao(xiao: str) -> str:
    return "吉肖" if normalize_xiao(xiao) in JI_XIAO else "凶肖"


def season_xiao(xiao: str) -> str:
    nx = normalize_xiao(xiao)
    for s, members in SEASON_XIAO.items():
        if nx in members:
            return s
    return "春"


def direction_xiao(xiao: str) -> str:
    nx = normalize_xiao(xiao)
    for d, members in DIRECTION_XIAO.items():
        if nx in members:
            return d
    return "东"


def extract_xiao(text: str) -> list[str]:
    """Unique xiao in appearance order."""
    seen: list[str] = []
    for ch in text:
        if ch in XIAO_NORM:
            n = XIAO_NORM[ch]
            if n not in seen:
                seen.append(n)
    return seen
