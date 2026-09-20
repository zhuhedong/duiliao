from __future__ import annotations

import re
from datetime import date

LOTTERIES = ("hk", "macau", "taiwan", "new")

_SLASH = re.compile(r"^(\d{2,4})[/_\-](\d{1,3})$")
_DIGITS = re.compile(r"^\d{1,7}$")


def current_year(d: date | None = None) -> int:
    return (d or date.today()).year


def normalize(lottery: str, period_raw: str, year: int | None = None) -> str:
    """Canonical period: hk `2026096`, others `2026248`."""
    if lottery not in LOTTERIES:
        raise ValueError(f"unknown lottery: {lottery}")
    raw = str(period_raw).strip().lstrip("第")
    raw = raw.replace("期", "").strip()
    y = year or current_year()
    seq_width = 3

    m = _SLASH.match(raw)
    if m:
        ypart, seq = m.group(1), m.group(2)
        yy = int(ypart)
        if yy < 100:
            yy += 2000
        return f"{yy}{int(seq):0{seq_width}d}"

    if not _DIGITS.match(raw):
        raise ValueError(f"bad period_raw: {period_raw!r}")

    n = int(raw)
    s = str(n)
    if lottery == "hk":
        if len(s) >= 7:
            return s[-7:]
        if len(s) == 6 and s.startswith(("20", "19")):
            # 260096 style is rare; 202096 would be ambiguous. treat 6-digit
            # starting with 20 as year-2 + seq-3 only when seq looks right.
            return s
        if n > 10000:
            return str(n)
        return f"{y}{n:03d}"

    # macau / taiwan / new: year4 + seq3 (daily, seq can exceed 366)
    if len(s) >= 7:
        return s[-7:]
    if len(s) == 6:
        # e.g. '202248' → already a valid YYYY+NN (year=2022, seq=48)
        # vs '260248' → ambiguous short year (year=26, seq=0248) — prepend '20'
        prefix = int(s[:4])
        if 1990 <= prefix <= 2099:
            # Already a 4-digit year + 2-digit seq — pad seq to 3 digits
            return f"{prefix}{int(s[4:]):03d}"
        # Otherwise treat first 2 digits as short year
        return f"20{s}"
    return f"{y}{n:03d}"


def period_raw_of(period: str) -> str:
    p = str(period).strip()
    if len(p) >= 7 and p[:4].isdigit():
        return str(int(p[4:]))
    return p


def year_of(period: str) -> int:
    p = str(period).strip()
    if len(p) >= 7 and p[:4].isdigit():
        return int(p[:4])
    return current_year()


def _naive(dt):
    from datetime import datetime
    if isinstance(dt, datetime) and dt.tzinfo is not None:
        from datetime import timedelta, timezone
        return dt.astimezone(timezone(timedelta(hours=8))).replace(tzinfo=None)
    return dt
