"""Tests for AI prediction extraction, snapshot persistence, and automated source ingestion."""
from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from app.services.ai.ai_pred_extractor import (
    SOURCE_ID,
    SOURCE_NAME,
    SITE_FAMILY,
    PLAY_TYPE,
    build_ai_prediction_envelope,
    extract_ai_predictions,
    get_ai_snapshot_dir,
    ingest_ai_predictions,
    save_ai_prediction_snapshot,
)
from app.services.ai.pipeline import run_ai_judgment_pipeline
from app.services.ai.analyzer import AnalysisResult


SAMPLE_AI_MARKDOWN = """### 🎯 【澳门六合彩 第 263 期】实码与生肖研判精选

#### 一、 过滤与数据清洗说明
* 已严格过滤剔除所有包含“發”、“猫”、“？”、“0O”等无效假肖与乱码干扰；
* 统计到包含第 263 期实码预测的专家栏目列表。

#### 二、 第 263 期热度最高的 5 个生肖 (Top 5)
1. **[马]** - 出现频次 28 次（推荐专家：海哥平特、云顶心水）
2. **[虎]** - 出现频次 24 次（推荐专家：黑庄平特）
3. **[龙]** - 出现频次 22 次（推荐专家：冠军心水）
4. **[蛇]** - 出现频次 19 次（推荐专家：神算一肖）
5. **[狗]** - 出现频次 16 次（推荐专家：顶尖高手）

#### 三、 重点号码精选
* 🏆 **重点 6 个号码（核心精选）**：[ 05, 17, 29, 08, 20, 32 ]
* 🛡️ **重点 10 个号码（大底防守）**：[ 05, 17, 29, 08, 20, 32, 14, 26, 38, 41 ]

#### 四、 核心对料研判依据
* 简要说明上述 5 肖与 6 码、10 码在各大核心专家栏目中的重合交集理由。
"""


def test_extract_ai_predictions_standard_markdown():
    res = extract_ai_predictions(SAMPLE_AI_MARKDOWN)
    assert res["xiao"] == ["马", "虎", "龙", "蛇", "狗"]
    assert res["numbers"] == ["05", "17", "29", "08", "20", "32", "14", "26", "38", "41"]
    assert len(res["xiao"]) == 5
    assert len(res["numbers"]) == 10


def test_extract_ai_predictions_chinese_punctuation_and_list_markers():
    md = """
### 【澳门六合彩 第 264 期】研判
#### 二、推荐五肖
* 热肖推荐：兔、鸡、牛、猴、羊（已排除猫、發）

#### 三、重点号码精选
1. 01
2. 09
3. 12
4. 18
5. 22
6. 33
7. 35
8. 40
9. 44
10. 49
"""
    res = extract_ai_predictions(md)
    assert res["xiao"] == ["兔", "鸡", "牛", "猴", "羊"]
    assert res["numbers"] == ["01", "09", "12", "18", "22", "33", "35", "40", "44", "49"]


def test_extract_ai_predictions_json_structure():
    json_text = json.dumps({
        "top_5_xiao": ["虎", "猪", "牛", "鼠", "兔"],
        "top_10_numbers": [3, 7, 15, 21, 28, 30, 36, 42, 45, 49],
    })
    res = extract_ai_predictions(json_text)
    assert res["xiao"] == ["虎", "猪", "牛", "鼠", "兔"]
    assert res["numbers"] == ["03", "07", "15", "21", "28", "30", "36", "42", "45", "49"]


def test_extract_ai_predictions_empty_or_invalid():
    res_empty = extract_ai_predictions("")
    assert res_empty["xiao"] == []
    assert res_empty["numbers"] == []

    res_fake = extract_ai_predictions("这里只有假肖發和猫，以及乱码 0O ？？ 没有正统生肖和01-49实码")
    assert res_fake["xiao"] == []
    assert res_fake["numbers"] == []


def test_build_ai_prediction_envelope():
    envelope = build_ai_prediction_envelope(
        lottery="macau",
        period="263",
        xiao=["马", "虎", "龙", "蛇", "狗"],
        numbers=["05", "17", "29", "08", "20", "32", "14", "26", "38", "41"],
        raw_text=SAMPLE_AI_MARKDOWN,
    )
    assert envelope.ok is True
    assert envelope.source_id == SOURCE_ID
    assert envelope.source_name == SOURCE_NAME
    assert envelope.site_family == SITE_FAMILY
    assert envelope.play_type == PLAY_TYPE
    assert len(envelope.items) == 1

    item = envelope.items[0]
    assert item.period == "2026263"
    assert item.period_raw == "263"
    assert len(item.preds) == 15
    kinds = [p.kind for p in item.preds]
    assert kinds.count("xiao") == 5
    assert kinds.count("num") == 10


def test_save_and_load_ai_prediction_snapshot(tmp_path):
    snap_path = save_ai_prediction_snapshot(
        lottery="macau",
        period="263",
        xiao=["马", "虎", "龙", "蛇", "狗"],
        numbers=["05", "17", "29", "08", "20", "32", "14", "26", "38", "41"],
        raw_text="snapshot test",
    )
    assert snap_path.exists()
    content = json.loads(snap_path.read_text(encoding="utf-8"))
    assert content["source_id"] == SOURCE_ID
    assert content["xiao"] == ["马", "虎", "龙", "蛇", "狗"]
    assert content["numbers"] == ["05", "17", "29", "08", "20", "32", "14", "26", "38", "41"]


def test_ingest_ai_predictions_and_db_persistence():
    res = ingest_ai_predictions(
        lottery="macau",
        period="263",
        xiao=["马", "虎", "龙", "蛇", "狗"],
        numbers=["05", "17", "29", "08", "20", "32", "14", "26", "38", "41"],
        raw_text=SAMPLE_AI_MARKDOWN,
    )
    assert res["ok"] is True
    assert res["source_id"] == SOURCE_ID
    assert res["period"] == "2026263"
    assert res["ingest_stats"]["ok"] is True
    assert res["ingest_stats"]["items"] == 2  # texiao (5肖) + tema_n (10码)

    # Check collector database directly
    import app.collector_bridge as cb
    cb.bootstrap()
    from db import session_scope
    from schema import Prediction, Source
    from sqlalchemy import select

    with session_scope() as s:
        # Verify source table has ai_expert_10m5x
        src = s.get(Source, SOURCE_ID)
        assert src is not None
        assert src.source_name == SOURCE_NAME
        assert src.site_family == SITE_FAMILY

        # Verify predictions
        rows = s.scalars(
            select(Prediction)
            .where(Prediction.source_id == SOURCE_ID, Prediction.period == "2026263")
            .order_by(Prediction.play_type)
        ).all()
        assert len(rows) == 2
        play_types = {r.play_type for r in rows}
        assert "tema_n" in play_types
        assert "texiao" in play_types

        # Verify atoms
        tema_row = next(r for r in rows if r.play_type == "tema_n")
        assert len(tema_row.preds_json) == 10
        assert tema_row.preds_json[0]["value"] == "05"

        texiao_row = next(r for r in rows if r.play_type == "texiao")
        assert len(texiao_row.preds_json) == 5
        assert texiao_row.preds_json[0]["value"] == "马"


def test_ai_expert_10m5x_source_script_build():
    from sources.ai_expert_10m5x import build

    # Test reading from local snapshot or DB
    pred = build(lottery="macau", period="263", fixture=None)
    assert pred.ok is True
    assert pred.source_id == SOURCE_ID
    assert len(pred.items) == 1
    assert pred.items[0].period == "2026263"
    assert len(pred.items[0].preds) == 15


def test_run_ai_judgment_pipeline_auto_ingests_predictions():
    mock_scraped = MagicMock()
    mock_scraped.ok = True
    mock_scraped.period = "263"
    mock_scraped.site_title = "测试抓取数据"
    mock_scraped.html = "<html><body>263期 马 05</body></html>"
    mock_scraped.raw_html = "<html><body>263期 马 05</body></html>"
    mock_scraped.modules = [{"title": "海哥平特", "content": "263期 马"}]
    mock_scraped.to_summary.return_value = {"site_title": "测试抓取数据", "period": "263", "modules_count": 1}

    mock_analysis = AnalysisResult(
        ok=True,
        analysis=SAMPLE_AI_MARKDOWN,
        period="263",
        provider="mock_ai",
        model="mock_model",
        prompt_id="macau_analyst_expert",
        elapsed_sec=1.5,
        usage={"prompt_tokens": 100, "completion_tokens": 50},
        scraped_summary={"title": "mock"},
    )

    with patch("app.services.ai.pipeline.fetch_588080_full_page", return_value=mock_scraped), \
         patch("app.services.ai.pipeline.analyze_scraped_data", return_value=mock_analysis), \
         patch("app.services.ai.pipeline.send_smtp_email", return_value={"ok": True, "recipients": ["test@example.com"], "elapsed_ms": 100}):

        res = run_ai_judgment_pipeline(
            period="263",
            send_email=False,
            fetch_fresh=False,
        )

        assert res["ok"] is True
        assert res["period"] == "263"
        assert "ai_ingest" in res
        ai_ingest = res["ai_ingest"]
        assert ai_ingest["ok"] is True
        assert ai_ingest["source_id"] == "ai_expert_10m5x"
        assert ai_ingest["xiao"] == ["马", "虎", "龙", "蛇", "狗"]
        assert ai_ingest["numbers"] == ["05", "17", "29", "08", "20", "32", "14", "26", "38", "41"]
