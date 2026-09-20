"""Cron expression parsing and execution time calculation for scheduled tasks.

Supports standard 5-part cron syntax:
    minute (0-59)
    hour (0-23)
    day of month (1-31)
    month (1-12)
    day of week (0-6 or 1-7, where 0 and 7 are Sunday)

Features:
- Standard tokens: *, */step, range (e.g. 1-5), comma lists (e.g. 1,3,5)
- Support for specific start time (start_at) and end time (end_at)
- Timezone-aware (defaults to Beijing Time UTC+8)
"""

from __future__ import annotations

import calendar
import re
from datetime import datetime, timedelta, timezone
from typing import Any

TZ8 = timezone(timedelta(hours=8))


def now_cn() -> datetime:
    """Return current datetime in China Standard Time (UTC+8)."""
    return datetime.now(TZ8)


def parse_datetime(val: Any) -> datetime | None:
    """Parse various datetime string formats into timezone-aware datetime."""
    if val is None:
        return None
    if isinstance(val, datetime):
        return val.astimezone(TZ8) if val.tzinfo else val.replace(tzinfo=TZ8)
    s = str(val).strip()
    if not s:
        return None
    # Handle ISO formats
    s = s.replace("Z", "+00:00")
    if "T" in s or " " in s:
        try:
            dt = datetime.fromisoformat(s)
            return dt.astimezone(TZ8) if dt.tzinfo else dt.replace(tzinfo=TZ8)
        except ValueError:
            pass
    # Common format: YYYY-MM-DD HH:MM:SS
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y/%m/%d %H:%M:%S", "%Y-%m-%d"):
        try:
            dt = datetime.strptime(s, fmt)
            return dt.replace(tzinfo=TZ8)
        except ValueError:
            pass
    raise ValueError(f"无法解析的时间格式: {val!r}")


def _parse_field(field_str: str, min_val: int, max_val: int, is_dow: bool = False) -> set[int]:
    """Parse a single cron field into a set of matching integers."""
    result: set[int] = set()
    parts = field_str.strip().split(",")
    for part in parts:
        part = part.strip()
        if not part:
            continue
        if "/" in part:
            subparts = part.split("/", 1)
            range_part, step_str = subparts[0].strip(), subparts[1].strip()
            if not step_str.isdigit() or int(step_str) <= 0:
                raise ValueError(f"非法的 Cron 步长: {part!r}")
            step = int(step_str)
            if range_part == "*" or range_part == "":
                start, end = min_val, max_val
            elif "-" in range_part:
                r_start, r_end = range_part.split("-", 1)
                start, end = int(r_start.strip()), int(r_end.strip())
            else:
                start, end = int(range_part), max_val
            for val in range(start, end + 1, step):
                if is_dow and val == 7:
                    val = 0
                if min_val <= val <= max_val or (is_dow and val == 0):
                    result.add(val)
        elif "-" in part:
            r_start, r_end = part.split("-", 1)
            start, end = int(r_start.strip()), int(r_end.strip())
            if start > end:
                raise ValueError(f"非法的 Cron 范围: {part!r}")
            for val in range(start, end + 1):
                if is_dow and val == 7:
                    val = 0
                if min_val <= val <= max_val or (is_dow and val == 0):
                    result.add(val)
        elif part == "*":
            for val in range(min_val, max_val + 1):
                result.add(0 if (is_dow and val == 7) else val)
        else:
            if not part.isdigit():
                raise ValueError(f"非法的 Cron 字段值: {part!r}")
            val = int(part)
            if is_dow and val == 7:
                val = 0
            if not (min_val <= val <= max_val or (is_dow and val == 0)):
                raise ValueError(f"Cron 值超出范围 [{min_val}, {max_val}]: {part!r}")
            result.add(val)
    return result


def time_window_to_cron(start_time: str, end_time: str, interval_minutes: int) -> str:
    """Convert a time window like ('21:00', '21:30', 5) into standard Cron syntax.

    Examples:
      time_window_to_cron('21:00', '21:30', 5) -> '0-30/5 21 * * *'
      time_window_to_cron('20:45', '21:30', 5) -> '45-59/5 20 * * *; 0-30/5 21 * * *'
    """
    sh, sm = [int(x) for x in start_time.strip().split(":")[:2]]
    eh, em = [int(x) for x in end_time.strip().split(":")[:2]]
    interval = max(1, int(interval_minutes))

    if sh == eh:
        if sm == 0 and em >= 59:
            return f"*/{interval} {sh} * * *" if interval > 1 else f"* {sh} * * *"
        return f"{sm}-{em}/{interval} {sh} * * *"

    parts: list[str] = []
    # Start hour
    parts.append(f"{sm}-59/{interval} {sh} * * *")
    # Intermediate hours
    for h in range(sh + 1, eh):
        parts.append(f"*/{interval} {h} * * *")
    # End hour
    if em > 0:
        parts.append(f"0-{em}/{interval} {eh} * * *")
    elif em == 0:
        parts.append(f"0 {eh} * * *")
    return "; ".join(parts)


class CronSchedule:
    """Evaluates 5-part cron expressions (supports composite ';' separated expressions)."""

    def __init__(self, expr: str) -> None:
        expr = expr.strip()
        self.expr = expr
        if ";" in expr:
            sub_exprs = [e.strip() for e in expr.split(";") if e.strip()]
            if not sub_exprs:
                raise ValueError(f"空的 Cron 表达式: {expr!r}")
            self._subs = [CronSchedule(sub) for sub in sub_exprs]
            self.is_composite = True
            # Merge field sets for quick introspection
            self.minutes = set().union(*(s.minutes for s in self._subs))
            self.hours = set().union(*(s.hours for s in self._subs))
            self.days = set().union(*(s.days for s in self._subs))
            self.months = set().union(*(s.months for s in self._subs))
            self.weekdays = set().union(*(s.weekdays for s in self._subs))
            self.is_wildcard_day = all(s.is_wildcard_day for s in self._subs)
            self.is_wildcard_dow = all(s.is_wildcard_dow for s in self._subs)
        else:
            self.is_composite = False
            self._subs = []
            tokens = expr.split()
            if len(tokens) != 5:
                raise ValueError(f"Cron 表达式必须包含 5 个字段 (分 时 日 月 周)，当前为: {expr!r}")
            self.minutes = _parse_field(tokens[0], 0, 59)
            self.hours = _parse_field(tokens[1], 0, 23)
            self.days = _parse_field(tokens[2], 1, 31)
            self.months = _parse_field(tokens[3], 1, 12)
            raw_dow = _parse_field(tokens[4], 0, 7, is_dow=True)
            self.weekdays = {(d + 6) % 7 for d in raw_dow}
            self.is_wildcard_day = tokens[2] == "*"
            self.is_wildcard_dow = tokens[4] == "*"

    def matches(self, dt: datetime) -> bool:
        if self.is_composite:
            return any(s.matches(dt) for s in self._subs)
        if dt.minute not in self.minutes or dt.hour not in self.hours:
            return False
        if dt.month not in self.months:
            return False

        # If both day of month and day of week are restricted, standard cron matches either (OR)
        # If either is wildcard, it matches the restricted one
        day_match = dt.day in self.days
        dow_match = dt.weekday() in self.weekdays

        if self.is_wildcard_day and self.is_wildcard_dow:
            return True
        elif not self.is_wildcard_day and not self.is_wildcard_dow:
            return day_match or dow_match
        elif not self.is_wildcard_day:
            return day_match
        else:
            return dow_match

    def next_occurrence(self, base_dt: datetime) -> datetime:
        """Find the next matching occurrence strictly after base_dt (checked minute by minute)."""
        if self.is_composite:
            return min(s.next_occurrence(base_dt) for s in self._subs)
        # Start searching from the next full minute
        curr = base_dt.replace(second=0, microsecond=0) + timedelta(minutes=1)
        # Look ahead up to 5 years (avoid infinite loop)
        max_lookahead = 5 * 366 * 24 * 60
        steps = 0
        while steps < max_lookahead:
            if curr.month not in self.months:
                # Fast forward to next month
                if curr.month == 12:
                    curr = datetime(curr.year + 1, 1, 1, 0, 0, tzinfo=curr.tzinfo)
                else:
                    curr = datetime(curr.year, curr.month + 1, 1, 0, 0, tzinfo=curr.tzinfo)
                steps += 1
                continue

            day_match = curr.day in self.days
            dow_match = curr.weekday() in self.weekdays
            day_ok = (
                True
                if (self.is_wildcard_day and self.is_wildcard_dow)
                else (day_match or dow_match)
                if (not self.is_wildcard_day and not self.is_wildcard_dow)
                else day_match
                if not self.is_wildcard_day
                else dow_match
            )

            if not day_ok:
                # Fast forward to next day
                curr = datetime(curr.year, curr.month, curr.day, 0, 0, tzinfo=curr.tzinfo) + timedelta(days=1)
                steps += 1
                continue

            if curr.hour not in self.hours:
                # Fast forward to next hour
                curr = datetime(curr.year, curr.month, curr.day, curr.hour, 0, tzinfo=curr.tzinfo) + timedelta(hours=1)
                steps += 1
                continue

            if curr.minute in self.minutes:
                return curr

            curr += timedelta(minutes=1)
            steps += 1

        raise RuntimeError(f"在未来5年内未找到匹配 Cron {self.expr!r} 的执行时间点")


def compute_next_run(
    cron_expr: str | None,
    start_at: datetime | str | None = None,
    end_at: datetime | str | None = None,
    base_time: datetime | str | None = None,
) -> datetime | None:
    """Compute the next scheduled execution time given cron and specific start/end times.

    Logic:
    1. If end_at is reached, returns None.
    2. If start_at is in the future, the earliest execution can only be start_at (or the first
       cron time at or after start_at).
    3. If cron_expr is provided:
       - Base is max(now, start_at).
       - Finds the next matching occurrence at or after start_at.
    4. If no cron_expr (one-shot task at specific start_at):
       - If base_time < start_at, returns start_at.
       - If already reached/passed, returns None (task completed).
    """
    now = parse_datetime(base_time) if base_time else now_cn()
    s_at = parse_datetime(start_at)
    e_at = parse_datetime(end_at)

    if e_at and now >= e_at:
        return None

    cron_str = (cron_expr or "").strip()

    # Case 1: Pure one-shot specific time (no cron)
    if not cron_str:
        if s_at is None:
            return None
        if now < s_at:
            if e_at and s_at > e_at:
                return None
            return s_at
        # Already reached and executed
        return None

    # Case 2: Cron schedule exists
    cron = CronSchedule(cron_str)

    # Determine reference starting point
    if s_at and s_at > now:
        # Before start_at arrives: check if start_at itself exactly matches cron
        if cron.matches(s_at):
            candidate = s_at.replace(second=0, microsecond=0)
        else:
            candidate = cron.next_occurrence(s_at)
    else:
        candidate = cron.next_occurrence(now)

    if e_at and candidate > e_at:
        return None

    return candidate


def to_naive_cn(dt: datetime | None) -> datetime | None:
    """Convert a datetime to naive Beijing Time (stripping tzinfo for DB storage)."""
    if dt is None:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(TZ8).replace(tzinfo=None)
    return dt

