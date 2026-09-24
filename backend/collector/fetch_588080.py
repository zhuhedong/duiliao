"""Full-page data scraper and HTML assembler for 588080.com (Option B).

Bypasses heavy headless browser dependencies by reversing the three-layer
dispatch network (jump URLs -> am.js line pool -> backend app clusters) and
concurrently fetching all lazy-loaded content blocks defined in the page catalog.
"""
from __future__ import annotations

import argparse
import html
import json
import logging
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

# Ensure collector directory is on sys.path
ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from common.http import get, get_json, get_text
from common.sites.dingjian import STATIC_API_HOSTS, discover_api_hosts

log = logging.getLogger("pred.fetch_588080")

DEFAULT_ENTRY_URLS = ("https://588080.com/",)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
JUMP_URL_RE = re.compile(r"jumpURL\s*=\s*\[(.*?)\]", re.S)
URL_EXTRACT_RE = re.compile(r"[\x27\x22](https?://[^\x27\x22]+)[\x27\x22]")
SRC_URL_RE = re.compile(r"""(?:src|href)\s*=\s*['"](https?://[^'"]+)['"]""", re.I)


@dataclass
class FetchResult:
    ok: bool
    entry_url: str | None
    app_base: str | None
    site_title: str
    total_modules: int
    content_modules_count: int
    loaded_content_count: int
    elapsed_sec: float
    html_size_bytes: int
    html: str
    modules: list[dict[str, Any]]
    raw_html: str = ""
    raw_html_error: str | None = None
    error: str | None = None

    def to_summary(self) -> dict[str, Any]:
        d = asdict(self)
        d.pop("html", None)
        d.pop("raw_html", None)
        d.pop("modules", None)
        d["raw_html_bytes"] = len((self.raw_html or "").encode("utf-8"))
        return d


def extract_jump_urls(entry_html: str) -> list[str]:
    """Extract valid gateway URLs from entry HTML, safely skipping commented-out lines."""
    clean_html = HTML_COMMENT_RE.sub("", entry_html)
    match = JUMP_URL_RE.search(clean_html)
    if not match:
        return []
    return URL_EXTRACT_RE.findall(match.group(1))


def extract_app_hosts_from_am_js(am_js: str) -> list[str]:
    """Extract target app cluster origins from am.js."""
    urls = SRC_URL_RE.findall(am_js)
    hosts: list[str] = []
    for u in urls:
        m = re.match(r"(https?://[^/]+)", u.strip())
        if m and m.group(1) not in hosts:
            hosts.append(m.group(1))
    return hosts


def validate_host(host: str, timeout: float = 6.0) -> tuple[bool, dict[str, Any]]:
    """Check if the given host responds to /api/v1/index/website/config."""
    try:
        data = get_json(f"{host.rstrip('/')}/api/v1/index/website/config", timeout=timeout, retries=1)
        if isinstance(data, dict) and data.get("code") == 0 and isinstance(data.get("data"), dict):
            return True, data["data"]
    except Exception as e:
        log.debug("Host validation failed for %s: %s", host, e)
    return False, {}


def resolve_app_base(
    entries: tuple[str, ...] | list[str] = DEFAULT_ENTRY_URLS,
    *,
    timeout: float = 8.0,
    fallback_hosts: tuple[str, ...] | list[str] = STATIC_API_HOSTS,
) -> tuple[str, dict[str, Any], str]:
    """Resolve the active app host by traversing entry -> jump gateway -> am.js.

    Returns:
        (app_base, site_config, resolved_entry_url)
    """
    for entry in entries:
        try:
            entry_html = get_text(entry, timeout=timeout, retries=1)
            jump_urls = extract_jump_urls(entry_html)
            for jump_url in jump_urls:
                try:
                    am_js = get_text(jump_url.rstrip("/") + "/url/am.js", timeout=timeout, retries=1)
                    candidate_hosts = extract_app_hosts_from_am_js(am_js)
                    for host in candidate_hosts:
                        valid, config = validate_host(host, timeout=timeout)
                        if valid:
                            return host.rstrip("/"), config, entry
                except Exception as e:
                    log.warning("Jump URL %s resolution failed: %s", jump_url, e)
                    continue
        except Exception as e:
            log.warning("Entry %s failed: %s", entry, e)
            continue

    # Fallback to predefined/discovered static hosts
    log.info("Direct route traversal failed; trying fallback hosts...")
    for host in fallback_hosts:
        valid, config = validate_host(host, timeout=timeout)
        if valid:
            return host.rstrip("/"), config, entries[0] if entries else ""

    try:
        discovered, _ = discover_api_hosts(entries, fallback_hosts=fallback_hosts, deadline_sec=15.0)
        if discovered:
            valid, config = validate_host(discovered[0], timeout=timeout)
            if valid:
                return discovered[0].rstrip("/"), config, entries[0] if entries else ""
    except Exception as e:
        log.error("Host discovery failed: %s", e)

    raise RuntimeError("未能解析到可用的 588080 / 顶尖大师 业务接口集群")


def fetch_lazy_modules(app_base: str, timeout: float = 10.0) -> list[dict[str, Any]]:
    """Fetch the complete module list from /api/v1/index/config/lazy."""
    res = get_json(f"{app_base}/api/v1/index/config/lazy", timeout=timeout, retries=2)
    if not isinstance(res, dict) or res.get("code") != 0:
        raise ValueError(f"Failed to fetch lazy config: {res}")
    return res.get("data", [])


def fetch_lazy_contents(
    app_base: str,
    modules: list[dict[str, Any]],
    *,
    max_workers: int = 10,
    timeout: float = 10.0,
) -> dict[int, str]:
    """Concurrently fetch HTML content for modules that need lazy loading."""
    content_modules = [m for m in modules if m.get("type") == "content"]

    def _fetch_one(item: dict[str, Any]) -> tuple[int, str]:
        item_id = item.get("id")
        if item.get("content"):
            return item_id, item["content"]
        try:
            url = f"{app_base}/api/v1/index/config/byid/{item_id}"
            res = get_json(url, timeout=timeout, retries=2)
            if isinstance(res, dict) and isinstance(res.get("data"), dict):
                return item_id, res["data"].get("content", "")
        except Exception as e:
            log.warning("Failed to fetch content for module %s (%s): %s", item_id, item.get("name"), e)
        return item_id, ""

    results: dict[int, str] = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        for item_id, content in executor.map(_fetch_one, content_modules):
            results[item_id] = content
    return results


def assemble_page_html(
    site_config: dict[str, Any],
    modules: list[dict[str, Any]],
    loaded_contents: dict[int, str],
    title: str | None = None,
) -> str:
    """Stitch all modules, styles, and configurations into a complete standalone HTML document."""
    page_title = title or site_config.get("webSiteTitle") or "588080 完整抓取页面"
    keywords = site_config.get("webSiteKeywords") or ""
    desc = site_config.get("webSiteDesc") or ""
    bg_img = site_config.get("backgroundImage") or ""

    parts = [
        "<!DOCTYPE html>",
        "<html lang='zh-CN'>",
        "<head>",
        "  <meta charset='UTF-8'>",
        "  <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=2.0, user-scalable=yes'>",
        f"  <title>{html.escape(page_title)}</title>",
        f"  <meta name='keywords' content='{html.escape(keywords)}'>",
        f"  <meta name='description' content='{html.escape(desc)}'>",
        "  <style>",
        "    * { box-sizing: border-box; }",
        f"    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'PingFang SC', 'Microsoft YaHei', sans-serif; margin: 0; padding: 0; background: #f5f5f5{' url(' + bg_img + ')' if bg_img else ''}; }}",
        "    #app { max-width: 768px; margin: 0 auto; min-height: 100vh; background: #fff; box-shadow: 0 0 10px rgba(0,0,0,0.1); }",
        "    .module-wrapper { margin: 8px 0; }",
        "    .content-module { padding: 4px; }",
        "    .code-module, .public-code-module { overflow: hidden; }",
        "    .trend-table { width: 100%; border-collapse: collapse; text-align: center; }",
        "    .trend-table td, .trend-table th { border: 1px solid #ddd; padding: 4px; font-size: 14px; }",
        "  </style>",
    ]

    # Include custom styles from 'style' type modules
    for m in modules:
        if m.get("type") == "style" and m.get("content"):
            parts.append(f"  <style id='module-style-{m.get('id')}'>\n{m['content']}\n  </style>")

    parts.append("</head><body><div id='app'>")

    # Render each module in order
    for m in modules:
        m_id = m.get("id")
        m_name = m.get("name") or ""
        m_type = m.get("type") or ""
        escaped_name = html.escape(m_name)

        if m_type == "content":
            content_html = loaded_contents.get(m_id) or m.get("content") or ""
            parts.append(
                f"\n  <!-- Module: {escaped_name} (Type: {m_type}, ID: {m_id}) -->\n"
                f"  <section class='module-wrapper content-module' data-id='{m_id}' data-name='{escaped_name}'>\n"
                f"{content_html}\n"
                f"  </section>"
            )
        elif m_type in ("code", "publicCode"):
            code_html = m.get("content") or ""
            cls_name = "code-module" if m_type == "code" else "public-code-module"
            parts.append(
                f"\n  <!-- Code Module: {escaped_name} (Type: {m_type}, ID: {m_id}) -->\n"
                f"  <section class='module-wrapper {cls_name}' data-id='{m_id}' data-name='{escaped_name}'>\n"
                f"{code_html}\n"
                f"  </section>"
            )
        elif m_type == "system":
            parts.append(
                f"\n  <!-- System Module: {escaped_name} (ID: {m_id}) -->\n"
                f"  <section class='module-wrapper system-module' data-id='{m_id}' data-name='{escaped_name}'>\n"
                f"    <div class='system-placeholder' style='padding: 10px; background: #fafafa; color: #888; text-align: center;'>[系统模块: {escaped_name}]</div>\n"
                f"  </section>"
            )
        elif m_type not in ("style",):
            # Fallback for other modules
            raw_content = m.get("content") or ""
            parts.append(
                f"\n  <!-- Custom Module: {escaped_name} (Type: {m_type}, ID: {m_id}) -->\n"
                f"  <section class='module-wrapper' data-id='{m_id}' data-name='{escaped_name}'>\n"
                f"{raw_content}\n"
                f"  </section>"
            )

    parts.append("\n</div></body></html>")
    return "\n".join(parts)


def resolve_page_base(api_base: str, *, timeout: float = 8.0) -> str:
    """Pick a host that actually serves the SPA. Some API mirrors answer 403 for `/`."""
    from common.sites.dingjian import STATIC_API_HOSTS

    candidates = [api_base.rstrip("/"), *[host.rstrip("/") for host in STATIC_API_HOSTS]]
    for host in dict.fromkeys(candidates):
        try:
            response = get(host + "/", timeout=timeout, retries=0)
        except Exception:
            continue
        text = response.text or ""
        if response.status_code == 200 and "<script" in text.lower() and "403 Forbidden" not in text[:200]:
            return host
    return api_base.rstrip("/")


def fetch_rendered_html(
    url: str,
    *,
    timeout: float = 45.0,
    required_names: list[str] | None = None,
) -> str:
    """Open the live app and scroll until every catalog column is in the DOM.

    The public entry is a JavaScript shell. Columns mount only as they enter
    the viewport, so jumping straight to the bottom skips the ones in between.
    """
    from playwright.sync_api import sync_playwright

    def _compact(value: str) -> str:
        return re.sub(r"\s+", "", value)

    names: list[str] = []
    seen_names: set[str] = set()
    for name in required_names or []:
        text = str(name or "").strip()
        key = _compact(text)
        if len(key) < 2 or key in seen_names:
            continue
        seen_names.add(key)
        names.append(text)

    timeout_ms = int(max(timeout, 20) * 1000)
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        try:
            page = browser.new_page(viewport={"width": 420, "height": 900})
            page.goto(url, wait_until="domcontentloaded", timeout=timeout_ms)
            page.wait_for_function(
                "() => document.body && document.body.innerText.includes('期')",
                timeout=timeout_ms,
            )
            missing = set(names)
            last_height = -1
            last_text = -1
            stable_rounds = 0
            for _ in range(100):
                state = page.evaluate(
                    """() => {
                        const el = document.scrollingElement || document.documentElement;
                        const view = window.innerHeight || 900;
                        const next = Math.min((el.scrollTop || 0) + view * 0.75, el.scrollHeight || 0);
                        window.scrollTo(0, next);
                        return {
                            height: el.scrollHeight || 0,
                            text: (document.body && document.body.innerText || '').length,
                            atBottom: next + 8 >= (el.scrollHeight || 0),
                            body: document.body ? document.body.innerText : '',
                        };
                    }"""
                )
                page.wait_for_timeout(400)
                body = _compact(state.get("body") or "")
                if missing:
                    missing = {name for name in missing if _compact(name) not in body}
                at_bottom = bool(state.get("atBottom"))
                unchanged = state.get("height") == last_height and state.get("text") == last_text
                if not missing and at_bottom:
                    break
                if at_bottom and unchanged:
                    stable_rounds += 1
                    if stable_rounds >= 4:
                        break
                else:
                    stable_rounds = 0
                last_height = state.get("height") or 0
                last_text = state.get("text") or 0
            if names and missing:
                log.warning(
                    "rendered page missing %s/%s columns: %s",
                    len(missing),
                    len(names),
                    "、".join(list(missing)[:8]),
                )
            page.evaluate("window.scrollTo(0, 0)")
            return page.content()
        finally:
            browser.close()


def fetch_588080_full_page(
    *,
    host: str | None = None,
    output_html_path: str | Path | None = None,
    output_json_path: str | Path | None = None,
    timeout: float = 10.0,
    max_workers: int = 10,
) -> FetchResult:
    """High-level function: fetch full 588080.com page HTML and structured data."""
    t0 = time.perf_counter()
    entry_url = None
    try:
        if host:
            app_base = host.rstrip("/")
            valid, site_config = validate_host(app_base, timeout=timeout)
            if not valid:
                raise ValueError(f"指定的主机无法通过验证: {app_base}")
        else:
            app_base, site_config, entry_url = resolve_app_base(timeout=timeout)

        # 1. Catalog first, so the browser knows which column titles must appear.
        modules = fetch_lazy_modules(app_base, timeout=timeout)
        required_names = [
            str(item.get("name") or "").strip()
            for item in modules
            if item.get("type") == "content" and str(item.get("name") or "").strip()
        ]

        # 2. Scroll the live page while the module bodies download.
        raw_html = ""
        raw_html_error = None
        with ThreadPoolExecutor(max_workers=1) as raw_pool:
            page_base = resolve_page_base(app_base, timeout=timeout)
            raw_future = raw_pool.submit(
                fetch_rendered_html,
                page_base + "/",
                timeout=90,
                required_names=required_names,
            )
            loaded_contents = fetch_lazy_contents(app_base, modules, max_workers=max_workers, timeout=timeout)
            try:
                raw_html = raw_future.result(timeout=120)
            except Exception as raw_exc:
                raw_html_error = str(raw_exc)
                log.warning("Playwright raw HTML failed: %s", raw_exc)

        # 3. Populate content into modules dict for structured output
        content_count = 0
        loaded_count = 0
        enriched_modules = []
        for m in modules:
            m_copy = dict(m)
            if m_copy.get("type") == "content":
                content_count += 1
                cnt = loaded_contents.get(m_copy["id"]) or m_copy.get("content") or ""
                m_copy["content"] = cnt
                if cnt:
                    loaded_count += 1
            enriched_modules.append(m_copy)

        # 4. Assemble complete HTML
        full_html = assemble_page_html(site_config, modules, loaded_contents)
        elapsed = time.perf_counter() - t0

        result = FetchResult(
            ok=True,
            entry_url=entry_url or (DEFAULT_ENTRY_URLS[0] if not host else None),
            app_base=app_base,
            site_title=site_config.get("webSiteTitle") or "顶尖大师",
            total_modules=len(modules),
            content_modules_count=content_count,
            loaded_content_count=loaded_count,
            elapsed_sec=round(elapsed, 2),
            html_size_bytes=len(full_html.encode("utf-8")),
            html=full_html,
            raw_html=raw_html,
            raw_html_error=raw_html_error,
            modules=enriched_modules,
            error=None,
        )

        # Write output files if specified
        if output_html_path:
            p = Path(output_html_path)
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(full_html, encoding="utf-8")

        if output_json_path:
            p = Path(output_json_path)
            p.parent.mkdir(parents=True, exist_ok=True)
            json_data = {
                "summary": result.to_summary(),
                "site_config": site_config,
                "modules": enriched_modules,
            }
            p.write_text(json.dumps(json_data, ensure_ascii=False, indent=2), encoding="utf-8")

        return result

    except Exception as e:
        elapsed = time.perf_counter() - t0
        log.exception("fetch_588080_full_page failed: %s", e)
        return FetchResult(
            ok=False,
            entry_url=entry_url,
            app_base=host,
            site_title="",
            total_modules=0,
            content_modules_count=0,
            loaded_content_count=0,
            elapsed_sec=round(elapsed, 2),
            html_size_bytes=0,
            html="",
            raw_html="",
            modules=[],
            error=str(e),
        )


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    parser = argparse.ArgumentParser(description="588080.com 完整网页数据获取工具")
    parser.add_argument("-o", "--output", help="输出完整 HTML 文件路径")
    parser.add_argument("-j", "--json", help="输出结构化 JSON 文件路径")
    parser.add_argument("--host", help="指定业务端集群 Host（跳过跳板解析）")
    parser.add_argument("--timeout", type=float, default=10.0, help="网络请求超时时间 (秒)")
    args = parser.parse_args()

    print("开始获取 588080.com 完整数据...")
    res = fetch_588080_full_page(
        host=args.host,
        output_html_path=args.output,
        output_json_path=args.json,
        timeout=args.timeout,
    )

    if res.ok:
        print("\n=== 抓取成功 ===")
        print(f"站点标题: {res.site_title}")
        print(f"业务端集群: {res.app_base}")
        print(f"页面模块总数: {res.total_modules}")
        print(f"核心预测模块: {res.loaded_content_count}/{res.content_modules_count} 已完整填充")
        print(f"HTML 字节数: {res.html_size_bytes:,} 字节 ({res.html_size_bytes/1024:.1f} KB)")
        print(f"总耗时: {res.elapsed_sec} 秒")
        if args.output:
            print(f"HTML 已保存至: {args.output}")
        if args.json:
            print(f"JSON 已保存至: {args.json}")
    else:
        print(f"\n=== 抓取失败: {res.error} ===")
        sys.exit(1)


if __name__ == "__main__":
    main()
