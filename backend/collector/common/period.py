from __future__ import annotations

import re
from datetime import date, datetime, timedelta, timezone

LOTTERIES = ("hk", "macau", "taiwan", "new")

TZ8 = timezone(timedelta(hours=8))
_SLASH = re.compile(r"^(\d{2,4})[/_\-](\d{1,3})$")
_DATE_ISO = re.compile(r"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$")
_DIGITS = re.compile(r"^\d{1,7}$")


def beijing_now() -> datetime:
    """Current datetime in China Standard Time (UTC+8)."""
    return datetime.now(timezone.utc).astimezone(TZ8)


def current_year(d: date | datetime | None = None) -> int:
    if d is None:
        return beijing_now().year
    return d.year


def day_of_year(d: date | datetime | None = None) -> int:
    """1-based day of year (1..366) in Beijing Time."""
    if d is None:
        target_date = beijing_now().date()
    elif isinstance(d, datetime):
        if d.tzinfo is not None:
            target_date = d.astimezone(TZ8).date()
        else:
            target_date = d.date()
    elif isinstance(d, date):
        target_date = d
    else:
        raise TypeError(f"expected date or datetime, got {type(d)}")
    return target_date.timetuple().tm_yday


def period_for_date(d: date | datetime | None = None) -> str:
    """Canonical day-of-year period format: YYYYDDD (e.g. 2026-10-13 -> '2026286')."""
    if d is None:
        target_date = beijing_now().date()
    elif isinstance(d, datetime):
        if d.tzinfo is not None:
            target_date = d.astimezone(TZ8).date()
        else:
            target_date = d.date()
    elif isinstance(d, date):
        target_date = d
    else:
        raise TypeError(f"expected date or datetime, got {type(d)}")
    doy = target_date.timetuple().tm_yday
    return f"{target_date.year}{doy:03d}"


def date_for_period(period: str) -> date:
    """Parse canonical period YYYYDDD back to date."""
    p = str(period).strip()
    if len(p) >= 7 and p[:4].isdigit():
        year = int(p[:4])
        doy = int(p[4:])
        return datetime.strptime(f"{year}-{doy:03d}", "%Y-%j").date()
    raise ValueError(f"cannot parse period into date: {period!r}")


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

    if _DATE_ISO.match(raw):
        clean = raw.replace("/", "-")
        parts = clean.split("-")
        try:
            d = date(int(parts[0]), int(parts[1]), int(parts[2]))
            return period_for_date(d)
        except Exception:
            pass

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
