from __future__ import annotations

import json
import os
import re
from pathlib import Path
from string import Template
from typing import Any

import yaml

from common import ROOT
from common.contract import PLAY_TYPES
from db import session_scope
from schema import Source


def yaml_path() -> Path:
    raw = os.getenv("PRED_SOURCES_YAML")
    return Path(raw) if raw else ROOT / "sources.yaml"


def sources_dir() -> Path:
    raw = os.getenv("PRED_SOURCES_DIR")
    return Path(raw) if raw else ROOT / "sources"
SOURCE_ID_RE = re.compile(r"^[a-z][a-z0-9_]{1,62}$")
SCRIPT_NAME_RE = re.compile(r"^[a-zA-Z0-9_]+\.py$")
MAX_SCRIPT_BYTES = 200_000

DB_FIELDS = (
    "source_name",
    "site_family",
    "lottery",
    "play_type",
    "hit_mode",
    "script_path",
    "timeout_sec",
    "enabled",
    "remark",
)

SCRIPT_TEMPLATE = Template(
    '''from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from common.contract import Claimed, PredAtom, PredItem, PredV1  # noqa: E402
from common.hash import sha256_text  # noqa: E402
from common.parse_pred import parse_column_text  # noqa: E402
from common.period import normalize, year_of  # noqa: E402
from common.source_base import emit, fail, now_cn, parse_common_args  # noqa: E402
from common.source_fetch import load_page  # noqa: E402

SOURCE_ID = $source_id_literal
SOURCE_NAME = $source_name_literal
SITE_FAMILY = $site_family_literal
PLAY_TYPE = $play_type_literal
HIT_MODE = $hit_mode_literal
TITLE = $title_literal
PREFER = $prefer_literal

# 本脚本自己请求。服务只负责启动本文件，不会代发 HTTP。
URLS = [
    $urls_literal
]


def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    page = load_page(urls=URLS, fixture=fixture)
    year = year_of(period) if period else None
    parsed = parse_column_text(page.text, title_hint=TITLE, prefer=PREFER)
    items: list[PredItem] = []
    for row in parsed:
        try:
            per = normalize(lottery, row["period_raw"], year=year)
        except ValueError:
            continue
        atoms = [
            PredAtom(kind=a["kind"], value=a["value"], text=a.get("text"))
            for a in row["preds"]
            if a["kind"] == PREFER
        ]
        if not atoms:
            continue
        c = row["claimed"]
        items.append(
            PredItem(
                period_raw=row["period_raw"],
                period=per,
                published_at=None,
                preds=atoms,
                claimed=Claimed(
                    status=c["status"],
                    xiao=c.get("xiao"),
                    num=c.get("num"),
                    raw=c.get("raw"),
                ),
                raw_text=row["raw_text"][:1024],
            )
        )
    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        site_family=SITE_FAMILY,
        lottery=lottery,  # type: ignore[arg-type]
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,  # type: ignore[arg-type]
        fetched_at=now_cn(),
        final_url=page.url,
        content_hash=page.content_hash or sha256_text(page.text),
        items=items,
        error=None,
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        pred = build(args.lottery, args.period, args.fixture)
        emit(pred, ok=True)
    except Exception as e:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(e))


if __name__ == "__main__":
    main()
'''
)


def _render_dynamic_site_template(body: dict[str, Any]) -> str | None:
    """Render a thin typed wrapper for the two mirror-backed site families.

    Catalog onboarding supplies a stable path while the shared parser carries
    the site-specific HTTP and ``pred.v1`` details.  Keeping this wrapper in
    the source file means the collector's subprocess isolation is preserved.
    """
    family = str(body.get("site_family") or "")
    extra = dict(body.get("extra") or {})
    path = str(extra.get("path") or "").strip()
    if family not in {"tongtian_83191", "dingji_77452"} or not path:
        return None
    sid = validate_source_id(str(body.get("source_id") or ""))
    name = str(body.get("source_name") or sid)
    play_type = str(body.get("play_type") or "texiao")
    hit_mode = str(body.get("hit_mode") or "any")
    kind = str(extra.get("kind") or ("num" if "码" in name or "ma" in path else "xiao"))
    if kind not in {"xiao", "num", "twoface", "wei", "head", "bose", "all"}:
        raise RegistryError("bad_kind", "动态站点脚本 kind 不受支持")
    q = lambda value: json.dumps(value, ensure_ascii=False)
    if family == "tongtian_83191":
        imports = "from tt_util import build_tt_pred, urls_for"
        call = "build_tt_pred"
    else:
        imports = "from dingji_util import build_dj_pred, urls_for"
        call = "build_dj_pred"
    return f'''from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.source_base import emit, fail, parse_common_args
{imports}

SOURCE_ID = {q(sid)}
SOURCE_NAME = {q(name)}
SITE_FAMILY = {q(family)}
PLAY_TYPE = {q(play_type)}
HIT_MODE = {q(hit_mode)}
PATH = {q(path)}
KIND = {q(kind)}


def build(lottery: str, period: str | None, fixture: str | None):
    return {call}(
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        urls=urls_for(PATH),
        kind=KIND,
        lottery=lottery,
        period=period,
        fixture=fixture,
    )


def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as exc:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(exc))


if __name__ == "__main__":
    main()
'''


class RegistryError(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def load_config() -> dict[str, Any]:
    path = yaml_path()
    if not path.exists():
        return {"site_families": {}, "draw": {}, "sources": []}
    with path.open(encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise RegistryError("bad_yaml", "sources.yaml is not a mapping")
    data.setdefault("site_families", {})
    data.setdefault("draw", {})
    data.setdefault("sources", [])
    return data


def save_config(data: dict[str, Any]) -> None:
    path = yaml_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    text = yaml.safe_dump(data, allow_unicode=True, sort_keys=False, default_flow_style=False)
    path.write_text(text, encoding="utf-8")


def _yaml_row(sid: str, cfg: dict[str, Any] | None = None) -> dict[str, Any] | None:
    cfg = cfg or load_config()
    for row in cfg.get("sources") or []:
        if row.get("source_id") == sid:
            return row
    return None


def _upsert_db(row: dict[str, Any]) -> None:
    sid = row["source_id"]
    fields = dict(
        source_name=row["source_name"],
        site_family=row["site_family"],
        lottery=row["lottery"],
        play_type=row["play_type"],
        hit_mode=row.get("hit_mode") or "any",
        script_path=row.get("script_path") or f"sources/{sid}.py",
        timeout_sec=int(row.get("timeout_sec") or 30),
        enabled=1 if row.get("enabled", True) else 0,
        remark=row.get("remark"),
    )
    with session_scope() as s:
        existing = s.get(Source, sid)
        if existing is None:
            s.add(Source(source_id=sid, **fields))
        else:
            for k, v in fields.items():
                setattr(existing, k, v)


def _delete_db(sid: str) -> None:
    with session_scope() as s:
        existing = s.get(Source, sid)
        if existing is not None:
            s.delete(existing)


def validate_source_id(sid: str) -> str:
    sid = (sid or "").strip()
    if not SOURCE_ID_RE.match(sid):
        raise RegistryError("bad_id", "source_id 须为小写字母开头的字母数字下划线，2–63 位")
    return sid


def script_path_for(name: str) -> Path:
    raw = str(name or "").strip().replace("\\", "/")
    if raw.startswith("sources/"):
        raw = raw[len("sources/") :]
    if not SCRIPT_NAME_RE.match(raw):
        raise RegistryError("bad_script", "脚本名只能是 sources/ 下的 *.py")
    if raw == "__init__.py":
        raise RegistryError("forbidden", "不能改 __init__.py")
    root = sources_dir().resolve()
    path = (root / raw).resolve()
    if not path.is_relative_to(root):
        raise RegistryError("forbidden", "脚本必须在 sources/ 目录内")
    return path


def canonical_script_path(name: str) -> str:
    """Validate a configured path and persist one unambiguous relative form."""
    return f"sources/{script_path_for(name).name}"


def list_scripts() -> list[dict[str, Any]]:
    sources_dir().mkdir(parents=True, exist_ok=True)
    cfg = load_config()
    used: set[str] = set()
    for row in cfg.get("sources") or []:
        try:
            used.add(canonical_script_path(row.get("script_path") or f"sources/{row.get('source_id')}.py"))
        except RegistryError:
            continue
    out = []
    for p in sorted(sources_dir().glob("*.py")):
        if p.name == "__init__.py":
            continue
        rel = f"sources/{p.name}"
        out.append(
            {
                "name": p.name,
                "path": rel,
                "bytes": p.stat().st_size,
                "attached": rel in used,
            }
        )
    return out


def read_script(name: str) -> dict[str, Any]:
    path = script_path_for(name)
    if not path.exists():
        raise RegistryError("not_found", f"没有脚本 {path.name}")
    return {"ok": True, "name": path.name, "path": f"sources/{path.name}", "content": path.read_text(encoding="utf-8")}


def write_script(name: str, content: str) -> dict[str, Any]:
    path = script_path_for(name)
    data = content if content.endswith("\n") else content + "\n"
    encoded = data.encode("utf-8")
    if len(encoded) > MAX_SCRIPT_BYTES:
        raise RegistryError("too_large", "脚本超过 200KB")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")
    return {"ok": True, "name": path.name, "path": f"sources/{path.name}", "bytes": len(encoded)}


def delete_script(name: str) -> None:
    path = script_path_for(name)
    if path.exists():
        path.unlink()


def _urls_literal(extra: dict[str, Any]) -> str:
    url = str((extra or {}).get("url") or "").strip()
    if url:
        return f"{json.dumps(url, ensure_ascii=False)},"
    return '# "https://example.com/your-column",'


def render_template(body: dict[str, Any]) -> str:
    if (body.get("play_type") or "pingte_xiao") not in PLAY_TYPES:
        raise RegistryError("bad_play", "该玩法不存在或已移除")
    dynamic = _render_dynamic_site_template(body)
    if dynamic is not None:
        return dynamic
    sid = validate_source_id(body["source_id"])
    extra = body.get("extra") or {}
    return SCRIPT_TEMPLATE.substitute(
        source_id_literal=json.dumps(sid, ensure_ascii=False),
        source_name_literal=json.dumps(str(body.get("source_name") or sid), ensure_ascii=False),
        site_family_literal=json.dumps(str(body.get("site_family") or "default"), ensure_ascii=False),
        play_type_literal=json.dumps(str(body.get("play_type") or "pingte_xiao"), ensure_ascii=False),
        hit_mode_literal=json.dumps(str(body.get("hit_mode") or "any"), ensure_ascii=False),
        title_literal=json.dumps(str(extra.get("title") or body.get("source_name") or sid), ensure_ascii=False),
        prefer_literal=json.dumps(str(extra.get("prefer") or "xiao"), ensure_ascii=False),
        urls_literal=_urls_literal(extra),
    )


def list_sources() -> list[dict[str, Any]]:
    cfg = load_config()
    scripts = {s["path"]: s for s in list_scripts()}
    items = []
    for row in cfg.get("sources") or []:
        rel = row.get("script_path") or f"sources/{row.get('source_id')}.py"
        try:
            normalized_rel = canonical_script_path(rel)
        except RegistryError:
            normalized_rel = None
        items.append(
            {
                **row,
                "enabled": bool(row.get("enabled", True)),
                "timeout_sec": int(row.get("timeout_sec") or 30),
                "extra": row.get("extra") or {},
                "script_exists": normalized_rel in scripts if normalized_rel else False,
                "script_path_valid": normalized_rel is not None,
            }
        )
    return items


def get_source(sid: str) -> dict[str, Any]:
    row = _yaml_row(sid)
    if row is None:
        raise RegistryError("not_found", f"没有源 {sid}")
    rel = row.get("script_path") or f"sources/{sid}.py"
    script = None
    path = script_path_for(rel)
    if path.exists():
        script = path.read_text(encoding="utf-8")
    return {**row, "enabled": bool(row.get("enabled", True)), "extra": row.get("extra") or {}, "script": script}


def create_source(body: dict[str, Any]) -> dict[str, Any]:
    if (body.get("play_type") or "pingte_xiao") not in PLAY_TYPES:
        raise RegistryError("bad_play", "该玩法不存在或已移除")
    sid = validate_source_id(body.get("source_id") or "")
    cfg = load_config()
    if _yaml_row(sid, cfg):
        raise RegistryError("exists", f"源 {sid} 已存在")
    extra = dict(body.get("extra") or {})
    script_path = canonical_script_path(body.get("script_path") or f"sources/{sid}.py")
    row = {
        "source_id": sid,
        "source_name": (body.get("source_name") or sid).strip(),
        "site_family": (body.get("site_family") or "default").strip(),
        "lottery": body.get("lottery") or "macau",
        "play_type": body.get("play_type") or "pingte_xiao",
        "hit_mode": body.get("hit_mode") or "any",
        "script_path": script_path,
        "timeout_sec": int(body.get("timeout_sec") or 30),
        "enabled": True if body.get("enabled") is None else bool(body["enabled"]),
        "remark": body.get("remark") or None,
        "extra": extra,
    }
    cfg.setdefault("sources", []).append(row)
    save_config(cfg)
    _upsert_db(row)
    if body.get("create_script", True):
        content = body.get("script") or render_template(row)
        write_script(row["script_path"], content)
    return get_source(sid)


def update_source(sid: str, body: dict[str, Any]) -> dict[str, Any]:
    if body.get("play_type") is not None and body["play_type"] not in PLAY_TYPES:
        raise RegistryError("bad_play", "该玩法不存在或已移除")
    sid = validate_source_id(sid)
    cfg = load_config()
    rows = cfg.get("sources") or []
    idx = next((i for i, r in enumerate(rows) if r.get("source_id") == sid), None)
    if idx is None:
        raise RegistryError("not_found", f"没有源 {sid}")
    row = dict(rows[idx])
    for key in ("source_name", "site_family", "lottery", "play_type", "hit_mode", "remark"):
        if key in body and body[key] is not None:
            row[key] = body[key]
    candidate_path = body.get("script_path") if body.get("script_path") is not None else row.get("script_path")
    row["script_path"] = canonical_script_path(candidate_path or f"sources/{sid}.py")
    if "timeout_sec" in body and body["timeout_sec"] is not None:
        row["timeout_sec"] = int(body["timeout_sec"])
    if "enabled" in body and body["enabled"] is not None:
        row["enabled"] = bool(body["enabled"])
    if "extra" in body and body["extra"] is not None:
        extra = dict(row.get("extra") or {})
        extra.update(body["extra"])
        row["extra"] = extra
    rows[idx] = row
    cfg["sources"] = rows
    save_config(cfg)
    _upsert_db(row)
    if "script" in body and body["script"] is not None:
        write_script(row["script_path"], body["script"])
    return get_source(sid)


def delete_source(sid: str, *, delete_file: bool = False) -> dict[str, Any]:
    sid = validate_source_id(sid)
    cfg = load_config()
    row = _yaml_row(sid, cfg)
    if row is None:
        raise RegistryError("not_found", f"没有源 {sid}")
    cfg["sources"] = [r for r in (cfg.get("sources") or []) if r.get("source_id") != sid]
    save_config(cfg)
    _delete_db(sid)
    if delete_file:
        rel = row.get("script_path") or f"sources/{sid}.py"
        try:
            delete_script(rel)
        except RegistryError:
            pass
    return {"ok": True, "deleted": sid}


def list_families() -> dict[str, Any]:
    cfg = load_config()
    return {"ok": True, "items": cfg.get("site_families") or {}}


def update_family(name: str, body: dict[str, Any]) -> dict[str, Any]:
    name = name.strip()
    if not re.match(r"^[a-z][a-z0-9_]{1,62}$", name):
        raise RegistryError("bad_id", "站点族名不合法")
    cfg = load_config()
    fam = dict((cfg.get("site_families") or {}).get(name) or {})
    if "qps" in body and body["qps"] is not None:
        fam["qps"] = float(body["qps"])
    if "hosts" in body and body["hosts"] is not None:
        fam["hosts"] = [h.strip() for h in body["hosts"] if str(h).strip()]
    if "am_js" in body and body["am_js"] is not None:
        fam["am_js"] = body["am_js"]
    if "column_api" in body and body["column_api"] is not None:
        fam["column_api"] = body["column_api"]
    if "columns" in body and body["columns"] is not None:
        fam["columns"] = body["columns"]
    cfg.setdefault("site_families", {})[name] = fam
    save_config(cfg)
    return {"ok": True, "name": name, "family": fam}


def _norm_draw(row: dict[str, Any] | None) -> dict[str, Any]:
    row = dict(row or {})
    headers = {str(k): str(v) for k, v in (row.get("headers") or {}).items()}
    return {
        "adapter": row.get("adapter") or "getLastLottery",
        "url": row.get("url") or "",
        "headers": headers,
        "lotterytype": str(headers.get("lotterytype") or ""),
    }


def get_draw_config(lottery: str | None = None) -> dict[str, Any]:
    draw = load_config().get("draw") or {}
    if lottery:
        return {"ok": True, "lottery": lottery, **_norm_draw(draw.get(lottery) if isinstance(draw.get(lottery), dict) else {})}
    items = {k: _norm_draw(v if isinstance(v, dict) else {}) for k, v in draw.items()}
    return {"ok": True, "items": items}


def update_draw_config(lottery: str, body: dict[str, Any]) -> dict[str, Any]:
    if lottery not in ("hk", "macau", "taiwan", "new"):
        raise RegistryError("bad_id", f"unknown lottery {lottery}")
    cfg = load_config()
    draw = cfg.setdefault("draw", {})
    row = dict(draw.get(lottery) or {})
    row["adapter"] = body.get("adapter") or row.get("adapter") or "getLastLottery"
    if "url" in body and body["url"] is not None:
        row["url"] = str(body["url"]).strip()
    headers = dict(row.get("headers") or {})
    if "headers" in body and isinstance(body["headers"], dict):
        for k, v in body["headers"].items():
            if v in (None, ""):
                headers.pop(str(k), None)
            else:
                headers[str(k)] = str(v)
    if "lotterytype" in body and body["lotterytype"] is not None:
        val = str(body["lotterytype"]).strip()
        if val:
            headers["lotterytype"] = val
        else:
            headers.pop("lotterytype", None)
    row["headers"] = headers
    draw[lottery] = row
    save_config(cfg)
    return get_draw_config(lottery)


def get_script_templates() -> list[dict[str, Any]]:
    return [
        {
            "id": "dingjian_standard",
            "name": "标准栏目切词模版",
            "description": "适用于顶尖站群及常见栏目文本，支持按期切行、自动识别生肖与特码",
            "code": '''from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.parse_pred import parse_column_text
from common.period import normalize, year_of
from common.source_base import emit, fail, now_cn, parse_common_args
from common.source_fetch import load_page
from dj_util import urls_for, isolate_title, atoms_xiao, atoms_num, claimed_of

SOURCE_ID = "my_source"
SOURCE_NAME = "我的预测源"
SITE_FAMILY = "dingjian_dashi"
PLAY_TYPE = "pingte_xiao"
HIT_MODE = "any"
TITLE = "我的预测栏目"
KIND = "xiao"  # xiao 或 num
URLS = urls_for("/api/v1/index/config/byid/1690478792806")

def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    page = load_page(urls=URLS, fixture=fixture)
    column_text = isolate_title(page.text, TITLE)
    if not column_text:
        raise ValueError(f"找不到栏目 {TITLE}")
    year = year_of(period) if period else None
    parsed = parse_column_text(column_text, title_hint=TITLE, prefer=("num" if KIND == "num" else "xiao"))
    items: list[PredItem] = []
    seen = set()
    for row in parsed or []:
        raw = row.get("raw_text") or ""
        try:
            per = normalize(lottery, row["period_raw"], year=year)
        except ValueError:
            continue
        if period and per != period and not str(period).endswith(str(row["period_raw"])):
            continue
        if per in seen:
            continue
        seen.add(per)
        atoms = [PredAtom(kind=a["kind"], value=str(a["value"]), text=a.get("text")) for a in row.get("preds", [])]
        if not atoms:
            continue
        c = row.get("claimed") or {}
        items.append(
            PredItem(
                period_raw=str(row["period_raw"]),
                period=per,
                published_at=None,
                preds=atoms,
                claimed=Claimed(status=c.get("status", "unknown"), xiao=c.get("xiao"), num=c.get("num"), raw=c.get("raw")),
                raw_text=raw[:1024],
            )
        )
    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        site_family=SITE_FAMILY,
        lottery=lottery,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        fetched_at=now_cn(),
        final_url=page.url,
        content_hash=page.content_hash or sha256_text(page.text),
        items=items,
        error=None,
    )

def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as e:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(e))

if __name__ == "__main__":
    main()
''',
        },
        {
            "id": "direct_api",
            "name": "直接请求 JSON API 模版",
            "description": "适用于外部网站提供标准 JSON API 返回预测列表",
            "code": '''from __future__ import annotations
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.http import get_json
from common.period import normalize, year_of
from common.source_base import emit, fail, now_cn, parse_common_args

SOURCE_ID = "api_source"
SOURCE_NAME = "API数据源"
SITE_FAMILY = "custom_api"
PLAY_TYPE = "pingte_xiao"
HIT_MODE = "any"
API_URL = "https://example.com/api/predictions"

def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    if fixture:
        data = json.loads(Path(fixture).read_text(encoding="utf-8"))
    else:
        data = get_json(API_URL, timeout=15)
    
    # 根据实际接口响应格式抽取列表
    records = data.get("list") or data.get("data") or []
    items: list[PredItem] = []
    year = year_of(period) if period else None
    
    for row in records:
        raw_period = str(row.get("period") or "")
        try:
            per = normalize(lottery, raw_period, year=year)
        except ValueError:
            continue
        if period and per != period and not str(period).endswith(raw_period):
            continue
            
        values = row.get("predictions") or [] # 如 ["鼠", "牛"]
        atoms = [PredAtom(kind="xiao", value=str(v).strip()) for v in values]
        if not atoms:
            continue
            
        items.append(
            PredItem(
                period_raw=raw_period,
                period=per,
                published_at=None,
                preds=atoms,
                claimed=Claimed(status="unknown"),
                raw_text=json.dumps(row, ensure_ascii=False),
            )
        )
        
    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        site_family=SITE_FAMILY,
        lottery=lottery,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        fetched_at=now_cn(),
        final_url=API_URL,
        content_hash=sha256_text(json.dumps(records)),
        items=items,
        error=None,
    )

def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as e:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(e))

if __name__ == "__main__":
    main()
''',
        },
        {
            "id": "regex_html",
            "name": "自定义正则提取模版",
            "description": "适用于纯 HTML 页面，通过正则表达式精确提取期号与推荐号码",
            "code": r'''from __future__ import annotations
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from common.contract import Claimed, PredAtom, PredItem, PredV1
from common.hash import sha256_text
from common.http import get_text
from common.period import normalize, year_of
from common.source_base import emit, fail, now_cn, parse_common_args

SOURCE_ID = "regex_source"
SOURCE_NAME = "正则提取数据源"
SITE_FAMILY = "custom_web"
PLAY_TYPE = "tema_n"
HIT_MODE = "any"
PAGE_URL = "https://example.com/page.html"

# 示例：第(\d+)期：特码【(\d{2}[,\s\d{2}]*)】
PATTERN = re.compile(r"第?\s*(\d{1,7})\s*期[：:]\s*([0-9\s,，、]+)")

def build(lottery: str, period: str | None, fixture: str | None) -> PredV1:
    if fixture:
        text = Path(fixture).read_text(encoding="utf-8")
    else:
        text = get_text(PAGE_URL, timeout=15)
        
    items: list[PredItem] = []
    year = year_of(period) if period else None
    
    for match in PATTERN.finditer(text):
        raw_period, nums_text = match.group(1), match.group(2)
        try:
            per = normalize(lottery, raw_period, year=year)
        except ValueError:
            continue
        if period and per != period and not str(period).endswith(raw_period):
            continue
            
        # 提取 01-49 号码
        found_nums = re.findall(r"\b0?[1-9]\b|\b[1-4][0-9]\b", nums_text)
        atoms = [PredAtom(kind="num", value=f"{int(n):02d}") for n in found_nums]
        if not atoms:
            continue
            
        items.append(
            PredItem(
                period_raw=raw_period,
                period=per,
                published_at=None,
                preds=atoms,
                claimed=Claimed(status="unknown"),
                raw_text=match.group(0),
            )
        )
        
    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=SOURCE_ID,
        source_name=SOURCE_NAME,
        site_family=SITE_FAMILY,
        lottery=lottery,
        play_type=PLAY_TYPE,
        hit_mode=HIT_MODE,
        fetched_at=now_cn(),
        final_url=PAGE_URL,
        content_hash=sha256_text(text),
        items=items,
        error=None,
    )

def main() -> None:
    args = parse_common_args(SOURCE_NAME)
    try:
        emit(build(args.lottery, args.period, args.fixture), ok=True)
    except Exception as e:
        fail(SOURCE_ID, SOURCE_NAME, SITE_FAMILY, args.lottery, PLAY_TYPE, HIT_MODE, "fetch", str(e))

if __name__ == "__main__":
    main()
''',
        },
    ]
