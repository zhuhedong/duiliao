"""Data preprocessor and context formatter for preparing scraped 588080.com data for LLMs."""
from __future__ import annotations

import html
import re
from collections import Counter
from typing import Any


VALID_ZODIACS = ("鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪")
_ZODIAC_NORMALIZE = {"龍": "龙", "馬": "马", "雞": "鸡", "豬": "猪"}
_ZODIAC_RE = re.compile(r"[" + "".join(VALID_ZODIACS) + "龍馬雞豬]")
_PERIOD_RE = re.compile(r"第?\s*(\d{1,7})\s*期")
_NUMBER_RE = re.compile(r"(?<!\d)(?:0?[1-9]|[1-4]\d)(?!\d)")
_RESULT_LINE_RE = re.compile(r"(?:开奖|開獎|开出|開出|命中|已中|准中|中[码碼])")
_AD_LINE_RE = re.compile(r"(?:https?://|www\.|\.com\b|加[微威]信|联系|上车|跟上|中奖|中獎|发财|發財)", re.I)
_NEGATIVE_LINE_RE = re.compile(r"(?:杀肖|殺肖|杀码|殺碼|不看|不要|排除|避开|避開|剔除|淘汰)")


def clean_html_to_text(raw_html: str) -> str:
    """Convert raw HTML into clean, readable text preserving linebreaks."""
    if not raw_html:
        return ""
    text = raw_html
    # Remove scripts, styles, comments
    text = re.sub(r"(?is)<script.*?>.*?</script>", "", text)
    text = re.sub(r"(?is)<style.*?>.*?</style>", "", text)
    text = re.sub(r"(?s)<!--.*?-->", "", text)
    # Linebreak replacements
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"(?i)</(?:p|div|tr|h[1-6]|li)>", "\n", text)
    text = re.sub(r"(?i)<td[^>]*>", "  ", text)
    text = re.sub(r"(?i)</td>", "", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    # Normalize whitespaces while preserving intentional newlines
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def _target_period_block(text: str, period: str) -> str:
    """Return all blocks headed by the requested period."""
    wanted = str(period).strip()
    matches = list(_PERIOD_RE.finditer(text))
    blocks: list[str] = []
    for index, match in enumerate(matches):
        if match.group(1) != wanted:
            continue
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        blocks.append(text[match.start():end].strip())
    return "\n".join(blocks)


def _extract_prediction_tokens(block: str) -> tuple[list[str], list[str]]:
    """Extract valid zodiac and 01-49 tokens from a period block.

    Result lines are excluded so historical ``开奖:兔40中`` annotations do not
    become predictions for the next report.  Invalid placeholders such as
    ``發`` and ``88`` never enter the valid token sets.
    """
    xiaos: list[str] = []
    numbers: list[str] = []
    seen_xiaos: set[str] = set()
    seen_numbers: set[str] = set()
    for raw_line in block.splitlines():
        line = raw_line.strip()
        if (
            not line
            or _RESULT_LINE_RE.search(line)
            or _AD_LINE_RE.search(line)
            or _NEGATIVE_LINE_RE.search(line)
        ):
            continue
        for token in _ZODIAC_RE.findall(line):
            zodiac = _ZODIAC_NORMALIZE.get(token, token)
            if zodiac not in seen_xiaos:
                seen_xiaos.add(zodiac)
                xiaos.append(zodiac)
        for token in _NUMBER_RE.findall(line):
            number = f"{int(token):02d}"
            if number not in seen_numbers:
                seen_numbers.add(number)
                numbers.append(number)
    return xiaos, numbers


def _format_period_extraction(
    data: dict[str, Any] | Any,
    *,
    period: str,
) -> str:
    """Build a compact, complete context for one target period."""
    if isinstance(data, dict):
        modules = data.get("modules", [])
        site_title = data.get("site_title") or "顶尖大师"
    elif hasattr(data, "modules"):
        modules = getattr(data, "modules", [])
        site_title = getattr(data, "site_title", "顶尖大师")
    else:
        modules = []
        site_title = "顶尖大师"

    records: list[tuple[str, list[str], list[str]]] = []
    for index, module in enumerate(modules, start=1):
        if not isinstance(module, dict) or module.get("type") in ("publicCode", "style"):
            continue
        name = str(module.get("name") or f"栏目{index}")
        text = clean_html_to_text(str(module.get("content") or ""))
        block = _target_period_block(text, period)
        if not block:
            continue
        xiaos, numbers = _extract_prediction_tokens(block)
        if xiaos or numbers:
            records.append((name, xiaos, numbers))

    xiao_counts = Counter(xiao for _, xiaos, _ in records for xiao in xiaos)
    number_counts = Counter(number for _, _, numbers in records for number in numbers)
    lines = [
        f"【站点标题: {site_title}】",
        f"【结构化抽取: 第 {period} 期】",
        "【过滤规则: 仅保留正统十二生肖与 01-49 实码；剔除發、猫、？、0O、88、广告及开奖结果行】",
        f"【有效专家栏目: {len(records)}】",
        "",
        "一、生肖热度（按有效栏目出现次数）",
        "、".join(f"{zodiac}:{count}" for zodiac, count in xiao_counts.most_common()) or "无",
        "二、实码热度（按有效栏目出现次数）",
        "、".join(f"{number}:{count}" for number, count in number_counts.most_common()) or "无",
        "三、逐栏目抽取结果",
    ]
    for name, xiaos, numbers in records:
        lines.append(f"- {name} | 生肖: {','.join(xiaos) or '无'} | 实码: {','.join(numbers) or '无'}")
    return "\n".join(lines)


def format_scraped_data_for_ai(
    data: dict[str, Any] | Any,
    *,
    mode: str = "modules_summary",
    period: str | None = None,
) -> str:
    """Format scraped 588080.com data without a local character limit.

    Args:
        data: FetchResult object or dict containing 'modules', 'site_title', 'html'.
        mode: 'modules_summary' (denoised text, recommended) or 'raw_html'.
        period: target period for modules_summary extraction; raw_html stays intact.
    """
    if mode == "raw_html":
        if isinstance(data, dict):
            return data.get("html") or ""
        return getattr(data, "html", None) or str(data)

    if period:
        extracted = _format_period_extraction(data, period=str(period).strip())
        # Structured extraction is intentionally compact and complete for the
        # requested period; do not cut records in the middle of a source row.
        return extracted

    # Mode: modules_summary
    modules: list[dict[str, Any]] = []
    site_title = "顶尖大师"

    if isinstance(data, dict):
        modules = data.get("modules", [])
        site_title = data.get("site_title") or site_title
    elif hasattr(data, "modules"):
        modules = getattr(data, "modules", [])
        site_title = getattr(data, "site_title", site_title)

    blocks: list[str] = [f"【站点标题: {site_title}】\n【说明: 以下已过滤纯广告与样式代码，仅保留核心预测栏目】\n"]

    content_count = 0
    for idx, m in enumerate(modules, start=1):
        m_type = m.get("type")
        m_name = m.get("name") or f"栏目{idx}"
        m_id = m.get("id")
        content = m.get("content") or ""

        # Skip pure ads, styles, and empty placeholders
        if m_type in ("publicCode", "style") or not content.strip():
            continue

        clean_text = clean_html_to_text(content)
        if not clean_text:
            continue

        content_count += 1
        blocks.append(
            f"=== 预测栏目 {content_count}：【{m_name}】 (类型: {m_type}, 模块ID: {m_id}) ===\n"
            f"{clean_text}\n"
        )

    return "\n".join(blocks)
