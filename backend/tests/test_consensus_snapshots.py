"""Immutable 特码/特肖 frequency-board snapshot coverage."""
from __future__ import annotations

from datetime import datetime


def _insert_board_predictions(period: str = "2026248") -> None:
    from db import session_scope
    from schema import Prediction, Source
    from sqlalchemy import select

    now = datetime.now()
    with session_scope() as s:
        for source_id, play_type, preds in (
            (
                "snapshot_tema_source",
                "tema_n",
                [{"kind": "num", "value": "01"}, {"kind": "num", "value": "02"}],
            ),
            (
                "snapshot_texiao_source",
                "texiao",
                [{"kind": "xiao", "value": "鼠"}, {"kind": "xiao", "value": "猪"}],
            ),
        ):
            source = s.get(Source, source_id)
            if source is None:
                s.add(
                    Source(
                        source_id=source_id,
                        source_name=source_id,
                        site_family=source_id,
                        lottery="macau",
                        play_type=play_type,
                        hit_mode="any",
                        script_path=f"sources/{source_id}.py",
                        timeout_sec=30,
                        enabled=1,
                    )
                )
            pred = s.scalar(
                select(Prediction).where(
                    Prediction.source_id == source_id,
                    Prediction.lottery == "macau",
                    Prediction.play_type == play_type,
                    Prediction.period == period,
                    Prediction.group_key == "",
                )
            )
            if pred is None:
                s.add(
                    Prediction(
                        source_id=source_id,
                        lottery="macau",
                        play_type=play_type,
                        hit_mode="any",
                        period=period,
                        group_key="",
                        period_raw=period[-3:],
                        preds_json=preds,
                        claimed_status="unknown",
                        claimed_xiao=None,
                        claimed_num=None,
                        claimed_raw=None,
                        raw_text="snapshot test",
                        content_hash=f"{source_id}-{period}-hash",
                        final_url=None,
                        fetched_at=now,
                        first_seen_at=now,
                        last_seen_at=now,
                        last_run_id=f"{source_id}-{period}-run",
                    )
                )


def test_draw_sync_without_predictions_does_not_create_empty_snapshot(seeded_draws):
    from db import session_scope
    from schema import ConsensusSnapshot
    from sqlalchemy import select

    with session_scope() as s:
        row = s.scalar(
            select(ConsensusSnapshot).where(
                ConsensusSnapshot.lottery == "macau",
                ConsensusSnapshot.period == "2026248",
            )
        )
        assert row is None


def test_snapshot_freezes_rankings_and_late_rows_do_not_change_it(seeded_draws):
    from app import collector_bridge as cb
    from db import session_scope
    from schema import Prediction
    from sqlalchemy import select

    _insert_board_predictions()
    frozen = cb.freeze_consensus_snapshot("macau", "248")
    assert frozen is not None

    first = cb.consensus_compare("macau", "248")
    assert first["snapshot"]["frozen"] is True
    assert first["frequency"]["policy"]["count_unit"] == "source_group"
    before_hash = first["snapshot"]["payload_hash"]
    before_tema = first["frequency"]["tema_n"]
    before_texiao = first["frequency"]["texiao"]

    # Simulate a late correction/new response to an already frozen prediction.
    with session_scope() as s:
        pred = s.scalar(
            select(Prediction).where(
                Prediction.lottery == "macau",
                Prediction.period == "2026248",
                Prediction.source_id == "snapshot_tema_source",
            )
        )
        assert pred is not None
        pred.preds_json = [{"kind": "num", "value": "49"}]

    second = cb.consensus_compare("macau", "248")
    assert second["snapshot"]["payload_hash"] == before_hash
    assert second["frequency"]["tema_n"] == before_tema
    assert second["frequency"]["texiao"] == before_texiao


def test_latest_period_without_draw_stays_live(seeded_draws):
    from app import collector_bridge as cb
    from db import session_scope
    from schema import Prediction
    from sqlalchemy import select

    _insert_board_predictions("2026249")
    first = cb.consensus_compare("macau", "249")
    assert first["snapshot"]["frozen"] is False
    assert first["frequency"]["tema_n"][0]["value"] == "01"

    with session_scope() as s:
        pred = s.scalar(
            select(Prediction).where(
                Prediction.lottery == "macau",
                Prediction.period == "2026249",
                Prediction.source_id == "snapshot_tema_source",
            )
        )
        assert pred is not None
        pred.preds_json = [{"kind": "num", "value": "49"}]

    second = cb.consensus_compare("macau", "249")
    assert second["snapshot"]["frozen"] is False
    values = {item["value"] for item in second["frequency"]["tema_n"]}
    assert "49" in values
    assert "01" not in values


def test_snapshot_freeze_is_idempotent_and_force_rebuild_is_explicit(seeded_draws):
    from app import collector_bridge as cb

    _insert_board_predictions()
    first = cb.freeze_consensus_snapshot("macau", "248")
    second = cb.freeze_consensus_snapshot("macau", "248")
    assert first["payload_hash"] == second["payload_hash"]
    assert first["frozen_at"] == second["frozen_at"]

    rebuilt = cb.freeze_consensus_snapshot("macau", "248", force=True)
    assert rebuilt["frozen"] is True
    assert rebuilt["payload_hash"]


def test_consensus_latest_exposes_prediction_and_official_cursors(user_client, seeded_draws):
    _insert_board_predictions()
    body = user_client.get("/collector/consensus/latest", params={"lottery": "macau"})
    assert body["ok"] is True
    assert body["official_draw_period"] == "2026248"
    assert body["latest_prediction_period"] >= body["official_draw_period"]
    assert body["current_period"] == max(body["official_draw_period"], body["latest_prediction_period"])


def test_consensus_read_includes_snapshot_metadata(user_client, seeded_draws):
    from app import collector_bridge as cb

    _insert_board_predictions()
    cb.freeze_consensus_snapshot("macau", "248")
    body = user_client.get("/collector/consensus", params={"lottery": "macau", "period": "248"})
    assert body["snapshot"]["frozen"] is True
    assert body["frequency"]["totals"]["tema_n"] == 1
    assert body["frequency"]["totals"]["texiao"] == 1
