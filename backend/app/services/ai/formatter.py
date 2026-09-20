"""Data preprocessor and context formatter for preparing scraped 588080.com data for LLMs."""
from __future__ import annotations

import html
import re
from typing import Any


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


def format_scraped_data_for_ai(
    data: dict[str, Any] | Any,
    *,
    mode: str = "modules_summary",
    max_chars: int = 80000,
) -> str:
    """Format scraped 588080.com data for AI consumption.

    Args:
        data: FetchResult object or dict containing 'modules', 'site_title', 'html'.
        mode: 'modules_summary' (denoised text, recommended) or 'raw_html'.
        max_chars: character cutoff safeguard.
    """
    if mode == "raw_html":
        raw = getattr(data, "html", None) or (data.get("html") if isinstance(data, dict) else str(data))
        if len(raw) > max_chars:
            return raw[:max_chars] + f"\n\n[... 截断：超出 {max_chars} 字符限制 ...]"
        return raw

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

    formatted = "\n".join(blocks)
    if len(formatted) > max_chars:
        return formatted[:max_chars] + f"\n\n[... 截断：超出 {max_chars} 字符限制 ...]"
    return formatted
