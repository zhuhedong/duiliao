from __future__ import annotations

from datetime import date

from common.xiao import num_to_xiao

POSITIONS = ("z1", "z2", "z3", "z4", "z5", "z6", "tema")


def draw_tags(balls: list[str], draw_date: date, previous: dict | None = None) -> dict:
    """Derived tags use all seven balls and the zodiac at the draw date."""
    if len(balls) != 7:
        raise ValueError("draw tags require seven balls")
    tags = dict(previous or {})
    groups: dict[str, list[dict]] = {}
    for position, num in zip(POSITIONS, balls):
        xiao = num_to_xiao(num, draw_date)
        groups.setdefault(xiao, []).append({"num": f"{int(num):02d}", "position": position})
    repeated = [{"xiao": xiao, "count": len(matches), "balls": matches}
                for xiao, matches in groups.items() if len(matches) > 1]
    tags.pop("repeat_xiao", None)
    if repeated:
        tags["repeat_xiao"] = repeated
    return tags
