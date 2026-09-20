from __future__ import annotations

from datetime import date

from common.xiao import jia_ye, num_to_xiao

# HKJC 波色
RED = frozenset({1, 2, 7, 8, 12, 13, 18, 19, 23, 24, 29, 30, 34, 35, 40, 45, 46})
BLUE = frozenset({3, 4, 9, 10, 14, 15, 20, 25, 26, 31, 36, 37, 41, 42, 47, 48})
GREEN = frozenset({5, 6, 11, 16, 17, 21, 22, 27, 28, 32, 33, 38, 39, 43, 44, 49})

BOSE_ZH = {"红": "红", "紅": "红", "蓝": "蓝", "藍": "蓝", "绿": "绿", "綠": "绿"}


def pad_num(num: int | str) -> str:
    n = int(str(num).strip())
    if n < 1 or n > 49:
        raise ValueError(f"num out of range: {num}")
    return f"{n:02d}"


def wei(num: int | str) -> str:
    return str(int(pad_num(num)) % 10)


def head(num: int | str) -> str:
    return str(int(pad_num(num)) // 10)


def bose(num: int | str) -> str:
    n = int(pad_num(num))
    if n in RED:
        return "红"
    if n in BLUE:
        return "蓝"
    if n in GREEN:
        return "绿"
    raise ValueError(f"no bose for {n}")


def normalize_bose(value: str) -> str:
    v = (value or "").strip().replace("波", "")
    if v not in BOSE_ZH:
        raise ValueError(f"unknown bose: {value!r}")
    return BOSE_ZH[v]


def size(num: int | str) -> str:
    return "小" if int(pad_num(num)) <= 24 else "大"


def odd(num: int | str) -> str:
    return "单" if int(pad_num(num)) % 2 else "双"


def heshu_odd(num: int | str) -> str:
    n = int(pad_num(num))
    s = n // 10 + n % 10
    return "单" if s % 2 else "双"


def halfwave(num: int | str) -> str:
    return f"{bose(num)}{size(num)}"


def halfhalf(num: int | str) -> str:
    return f"{bose(num)}{size(num)}{odd(num)}"


def ball_attrs(num: int | str, draw_date: date) -> dict[str, str]:
    n = pad_num(num)
    x = num_to_xiao(n, draw_date)
    return {
        "num": n,
        "xiao": x,
        "wei": wei(n),
        "head": head(n),
        "bose": bose(n),
        "size": size(n),
        "odd": odd(n),
        "sum": heshu_odd(n),
        "jiaye": jia_ye(x),
        "halfwave": halfwave(n),
        "halfhalf": halfhalf(n),
    }
