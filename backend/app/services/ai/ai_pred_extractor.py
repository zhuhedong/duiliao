"""AI Prediction Extractor & Automated Ingestion Service.

Extracts top 5 zodiacs and 10 numbers from AI analysis reports (or structured JSON),
constructs a pred.v1 envelope under source 'ai_expert_10m5x' (AI智能研判十码五肖),
persists latest snapshots, and ingests into the prediction database for hit judging
and consensus analysis.
"""
from __future__ import annotations

import json
import logging
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

# Valid Twelve Chinese Zodiacs
VALID_ZODIACS: tuple[str, ...] = (
    "鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"
)
ZODIAC_SET: set[str] = set(VALID_ZODIACS)

SOURCE_ID: str = "ai_expert_10m5x"
SOURCE_NAME: str = "AI智能研判十码五肖"
SITE_FAMILY: str = "ai_forecast"
PLAY_TYPE: str = "texiao"
HIT_MODE: str = "any"


def get_ai_snapshot_dir() -> Path:
    """Return the directory used to persist AI prediction snapshots."""
    # backend/collector/data/ai_predictions
    backend_root = Path(__file__).resolve().parent.parent.parent.parent
    snapshot_dir = backend_root / "collector" / "data" / "ai_predictions"
    snapshot_dir.mkdir(parents=True, exist_ok=True)
    return snapshot_dir


def extract_ai_predictions(text: str) -> dict[str, list[str]]:
    """Extract top 5 zodiacs and 10 numbers from AI analysis report or JSON.

    Returns:
        dict with keys "xiao" (list of up to 5 valid zodiacs) and
        "numbers" (list of up to 10 unique 01-49 formatted strings).
    """
    if not text or not str(text).strip():
        return {"xiao": [], "numbers": []}

    cleaned_text = str(text).strip()

    # 1. Try structured JSON parsing if output starts and ends with braces
    if cleaned_text.startswith("{") and cleaned_text.endswith("}"):
        try:
            data = json.loads(cleaned_text)
            xiao_raw = (
                data.get("top_5_xiao")
                or data.get("top_xiao")
                or data.get("xiao")
                or data.get("zodiacs")
                or []
            )
            num_raw = (
                data.get("top_10_numbers")
                or data.get("top_numbers")
                or data.get("numbers")
                or data.get("nums")
                or []
            )
            x_res = [x for x in xiao_raw if str(x).strip() in ZODIAC_SET][:5]
            n_res: list[str] = []
            for n in num_raw:
                try:
                    val = int(str(n).strip())
                    if 1 <= val <= 49:
                        formatted = f"{val:02d}"
                        if formatted not in n_res:
                            n_res.append(formatted)
                except (ValueError, TypeError):
                    continue
            if x_res or n_res:
                return {"xiao": x_res, "numbers": n_res[:10]}
        except Exception:
            pass

    # 2. Extract Zodiacs (up to 5 unique)
    xiao_list: list[str] = []

    # Priority 1: Match Section 二 (热度最高生肖 / Top 5 / 五肖)
    m_sec2 = re.search(
        r"(?:####\s*二|热度最高.*?生肖|Top\s*5|五肖|推荐生肖)(.*?)(?=####\s*[三四]|###|\Z)",
        cleaned_text,
        re.DOTALL | re.IGNORECASE,
    )
    sec2_text = m_sec2.group(1) if m_sec2 else cleaned_text

    # Strip labels that might contain misleading text
    cleaned_sec2 = re.sub(r"第\s*\d+\s*期", "", sec2_text)

    for ch in cleaned_sec2:
        if ch in ZODIAC_SET and ch not in xiao_list:
            xiao_list.append(ch)
            if len(xiao_list) == 5:
                break

    # If section 2 yielded fewer than 5, scan entire text
    if len(xiao_list) < 5 and m_sec2:
        for ch in cleaned_text:
            if ch in ZODIAC_SET and ch not in xiao_list:
                xiao_list.append(ch)
                if len(xiao_list) == 5:
                    break

    # 3. Extract Numbers (up to 10 unique 01-49)
    num_list: list[str] = []

    # Priority 1: Look for explicit 10-numbers line (e.g. 重点 10 个号码 / 大底防守 / 10个号码 / 十码)
    m_10 = re.search(
        r"(?:重点\s*10\s*个号码|大底防守|10\s*个号码|十码|10\s*码)[^:\n：]*[:：]([^\n]+)",
        cleaned_text,
        re.IGNORECASE,
    )
    if m_10:
        raw_line = m_10.group(1)
        # Extract 1-49 numbers
        found_nums = re.findall(r"\b0?[1-9]\b|\b[1-4][0-9]\b", raw_line)
        for n in found_nums:
            formatted = f"{int(n):02d}"
            if formatted not in num_list:
                num_list.append(formatted)

    # Priority 2: Look into Section 三 (重点号码精选) if we don't have 10 numbers yet
    if len(num_list) < 10:
        m_sec3 = re.search(
            r"(?:####\s*三|重点号码精选)(.*?)(?=####\s*[四五]|###|\Z)",
            cleaned_text,
            re.DOTALL | re.IGNORECASE,
        )
        search_target = m_sec3.group(1) if m_sec3 else cleaned_text

        # Strip list markers like "1. ", "2. ", "10. ", "(1) ", "1、" to avoid index confusion
        cleaned_sec3 = re.sub(r"(?m)^\s*(?:\d{1,2}|[(（]\d{1,2}[)）])[.、\s)）]\s*", "", search_target)
        # Strip period and count labels (e.g. "第 263 期", "10 个号码", "6 个号码", "6 码", "10 码")
        cleaned_sec3 = re.sub(r"第\s*\d+\s*期", "", cleaned_sec3)
        cleaned_sec3 = re.sub(r"\b\d{1,2}\s*个号码", "", cleaned_sec3)
        cleaned_sec3 = re.sub(r"\b\d{1,2}\s*码", "", cleaned_sec3)

        found_nums = re.findall(r"\b0?[1-9]\b|\b[1-4][0-9]\b", cleaned_sec3)
        for n in found_nums:
            formatted = f"{int(n):02d}"
            if formatted not in num_list:
                num_list.append(formatted)
                if len(num_list) == 10:
                    break

    # Priority 3: Fallback across cleaned text if still less than 10
    if len(num_list) < 10:
        cleaned_all = re.sub(r"(?m)^\s*(?:\d{1,2}|[(（]\d{1,2}[)）])[.、\s)）]\s*", "", cleaned_text)
        cleaned_all = re.sub(r"第\s*\d+\s*期", "", cleaned_all)
        cleaned_all = re.sub(r"\b\d{1,2}\s*个号码", "", cleaned_all)
        cleaned_all = re.sub(r"\b\d{1,2}\s*码", "", cleaned_all)
        found_nums = re.findall(r"\b0?[1-9]\b|\b[1-4][0-9]\b", cleaned_all)
        for n in found_nums:
            formatted = f"{int(n):02d}"
            if formatted not in num_list:
                num_list.append(formatted)
                if len(num_list) == 10:
                    break

    return {
        "xiao": xiao_list[:5],
        "numbers": num_list[:10],
    }


def _iso_now() -> str:
    """Return ISO format string of current time in China timezone."""
    from common.source_base import now_cn
    dt = now_cn()
    return dt.isoformat() if hasattr(dt, "isoformat") else str(dt)


def build_ai_prediction_envelope(
    lottery: str,
    period: str,
    xiao: list[str],
    numbers: list[str],
    source_id: str = SOURCE_ID,
    source_name: str = SOURCE_NAME,
    site_family: str = SITE_FAMILY,
    play_type: str = PLAY_TYPE,
    hit_mode: str = HIT_MODE,
    raw_text: str = "",
    fetched_at: str | None = None,
) -> Any:
    """Build a PredV1 schema envelope containing mixed xiao and num atoms."""
    from common.contract import Claimed, PredAtom, PredItem, PredV1
    from common.hash import sha256_text
    from common.period import normalize

    canonical_period = normalize(lottery, period)

    atoms: list[PredAtom] = []
    for x in xiao:
        if x in ZODIAC_SET:
            atoms.append(PredAtom(kind="xiao", value=x))
    for n in numbers:
        try:
            val = int(str(n).strip())
            if 1 <= val <= 49:
                atoms.append(PredAtom(kind="num", value=f"{val:02d}"))
        except (ValueError, TypeError):
            continue

    if not atoms:
        raise ValueError("AI预测提取为空：未提取到有效生肖或号码")

    item = PredItem(
        period_raw=str(period),
        period=canonical_period,
        published_at=None,
        preds=atoms,
        claimed=Claimed(status="unknown"),
        raw_text=raw_text[:1024] if raw_text else f"AI智能研判: {','.join(xiao)} | {','.join(numbers)}",
    )

    fetch_time = fetched_at or _iso_now()
    content_sig = sha256_text(raw_text or f"{canonical_period}:{','.join(xiao)}:{','.join(numbers)}")

    return PredV1(
        ok=True,
        schema_name="pred.v1",
        source_id=source_id,
        source_name=source_name,
        site_family=site_family,
        lottery=lottery,
        play_type=play_type,
        hit_mode=hit_mode,
        fetched_at=fetch_time,
        final_url="ai://macau_analyst_expert",
        content_hash=content_sig,
        items=[item],
        error=None,
    )


def save_ai_prediction_snapshot(
    lottery: str,
    period: str,
    xiao: list[str],
    numbers: list[str],
    raw_text: str = "",
    fetched_at: str | None = None,
) -> Path:
    """Persist prediction snapshot JSON to disk for offline CLI/runner fallback."""
    from common.period import normalize

    canonical_period = normalize(lottery, period)
    snapshot_dir = get_ai_snapshot_dir()
    snapshot_data = {
        "source_id": SOURCE_ID,
        "source_name": SOURCE_NAME,
        "site_family": SITE_FAMILY,
        "lottery": lottery,
        "play_type": PLAY_TYPE,
        "hit_mode": HIT_MODE,
        "period": canonical_period,
        "period_raw": str(period),
        "fetched_at": fetched_at or _iso_now(),
        "xiao": xiao,
        "numbers": numbers,
        "raw_text": raw_text[:2048] if raw_text else "",
    }

    # 1. Save latest file
    latest_file = snapshot_dir / f"latest_{SOURCE_ID}.json"
    latest_file.write_text(json.dumps(snapshot_data, ensure_ascii=False, indent=2), encoding="utf-8")

    # 2. Save period-specific file
    period_file = snapshot_dir / f"{lottery}_{canonical_period}.json"
    period_file.write_text(json.dumps(snapshot_data, ensure_ascii=False, indent=2), encoding="utf-8")

    logger.info("Saved AI prediction snapshot: %s and %s", latest_file.name, period_file.name)
    return latest_file


def ingest_ai_predictions(
    lottery: str,
    period: str,
    xiao: list[str],
    numbers: list[str],
    raw_text: str = "",
    source_id: str = SOURCE_ID,
    source_name: str = SOURCE_NAME,
) -> dict[str, Any]:
    """Build pred.v1 envelope, persist snapshot, and ingest into database."""
    from common.period import normalize
    import app.collector_bridge as cb

    canonical_period = normalize(lottery, period)
    fetch_time = _iso_now()

    envelope = build_ai_prediction_envelope(
        lottery=lottery,
        period=period,
        xiao=xiao,
        numbers=numbers,
        source_id=source_id,
        source_name=source_name,
        raw_text=raw_text,
        fetched_at=fetch_time,
    )

    # Save snapshots on disk
    save_ai_prediction_snapshot(
        lottery=lottery,
        period=period,
        xiao=xiao,
        numbers=numbers,
        raw_text=raw_text,
        fetched_at=fetch_time,
    )

    clean_ts = fetch_time.replace(":", "").replace("-", "").replace("T", "_")[:15]
    run_id = f"ai_run_{clean_ts}_{canonical_period}"
    run_payload = {
        "ok": True,
        "schema": "run.v1",
        "run_id": run_id,
        "run_at": fetch_time,
        "lottery": lottery,
        "period": canonical_period,
        "results": [
            {
                "source_id": source_id,
                "ok": True,
                "exit_code": 0,
                "elapsed_ms": 1,
                "item_count": len(envelope.items),
                "data": envelope.model_dump(mode="json"),
                "error_code": None,
                "error_msg": None,
            }
        ],
    }

    ingest_res = cb.ingest_payload(run_payload)
    logger.info(
        "Ingested AI prediction for source=%s lottery=%s period=%s: items=%s inserted=%s updated=%s unchanged=%s",
        source_id,
        lottery,
        canonical_period,
        ingest_res.get("items"),
        ingest_res.get("inserted"),
        ingest_res.get("updated"),
        ingest_res.get("unchanged"),
    )
    return {
        "ok": True,
        "source_id": source_id,
        "source_name": source_name,
        "lottery": lottery,
        "period": canonical_period,
        "period_raw": str(period),
        "xiao": xiao,
        "numbers": numbers,
        "ingest_stats": ingest_res,
    }
