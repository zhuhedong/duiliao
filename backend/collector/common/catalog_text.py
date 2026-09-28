"""Text evidence shared by catalog inspection and reviewed column parsers."""
from __future__ import annotations

import re
from common.parse_pred import parse_claimed

PERIOD_RE = re.compile(r"(?<![\d第])(?:第\s*)?(\d{1,7})\s*期")
CLAIM_RE = re.compile(r"(?:开奖|開獎|开|開)\s*[:：]?\s*([^\n]{1,60})")


def period_blocks(text: str) -> list[tuple[str, str]]:
    matches = list(PERIOD_RE.finditer(text))
    return [
        (match.group(1), text[match.start():matches[index + 1].start() if index + 1 < len(matches) else len(text)].strip())
        for index, match in enumerate(matches)
    ]


def claimed_from_block(text: str) -> dict:
    match = CLAIM_RE.search(text)
    raw = match.group(1).strip() if match else ""
    # A placeholder remains pending even if the author appends 准/中.
    compact = re.sub(r"\s+", "", raw)
    if re.match(r"(?:[發发猫貓？?]\s*)?(?:0{1,4}|88)(?!\d)", compact):
        return {"status": "pending", "xiao": None, "num": None, "raw": raw}
    return parse_claimed(raw)
