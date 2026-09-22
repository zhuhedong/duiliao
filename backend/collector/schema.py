from __future__ import annotations

import argparse
from datetime import date, datetime

from sqlalchemy import (
    JSON,
    BigInteger,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
    inspect,
    select,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from common.config import load_yaml
from db import Base, get_engine, session_scope

JSON_TYPE = JSON().with_variant(JSONB, "postgresql")
# SQLite only autoincrements INTEGER PRIMARY KEY; BIGINT is a no-op there.
PK_INT = Integer().with_variant(BigInteger, "postgresql")


class NumberInfo(Base):
    """Static 01–49 reference data; zodiac is calculated for the selected date."""
    __tablename__ = "number_info"

    num: Mapped[str] = mapped_column(String(2), primary_key=True)
    bose: Mapped[str] = mapped_column(String(1), nullable=False)
    size: Mapped[str] = mapped_column(String(1), nullable=False)
    odd: Mapped[str] = mapped_column(String(1), nullable=False)
    head: Mapped[str] = mapped_column(String(1), nullable=False)
    wei: Mapped[str] = mapped_column(String(1), nullable=False)
    sum: Mapped[str] = mapped_column(String(1), nullable=False)


class NumberYearAttr(Base):
    """Per-lunar-year number attributes that rotate yearly: 生肖 / 家野 / 五行.

    Fixed attributes (波色/大小/单双/头/尾/合数) live in ``number_info``; these
    change with the lunar year (春节 boundary), so they are keyed by year.
    ``wuxing`` is null for years without an authoritative table.
    """
    __tablename__ = "number_year_attr"

    lunar_year: Mapped[int] = mapped_column(Integer, primary_key=True)
    num: Mapped[str] = mapped_column(String(2), primary_key=True)
    xiao: Mapped[str] = mapped_column(String(2), nullable=False)
    jiaye: Mapped[str] = mapped_column(String(1), nullable=False)
    wuxing: Mapped[str | None] = mapped_column(String(2), nullable=True)


class NumberCodeMeta(Base):
    """2026 生肖灵码 reference metadata supplied by the user."""
    __tablename__ = "number_code_meta"

    lunar_year: Mapped[int] = mapped_column(Integer, primary_key=True)
    num: Mapped[str] = mapped_column(String(2), primary_key=True)
    role: Mapped[str] = mapped_column(String(32), nullable=False)
    flower: Mapped[str] = mapped_column(String(8), nullable=False)
    hour: Mapped[str] = mapped_column(String(8), nullable=False)
    dizhi: Mapped[str] = mapped_column(String(8), nullable=False)
    xiao_color: Mapped[str] = mapped_column(String(2), nullable=False)
    stroke: Mapped[str] = mapped_column(String(2), nullable=False)


class XiaoYearMeta(Base):
    """2026 zodiac classification metadata supplied with the灵码表."""
    __tablename__ = "xiao_year_meta"
    lunar_year: Mapped[int] = mapped_column(Integer, primary_key=True)
    xiao: Mapped[str] = mapped_column(String(2), primary_key=True)
    tian_di: Mapped[str] = mapped_column(String(2), nullable=False)
    yin_yang: Mapped[str] = mapped_column(String(2), nullable=False)
    gender: Mapped[str] = mapped_column(String(2), nullable=False)
    luck: Mapped[str] = mapped_column(String(2), nullable=False)
    season: Mapped[str] = mapped_column(String(2), nullable=False)
    direction: Mapped[str] = mapped_column(String(2), nullable=False)


class Source(Base):
    __tablename__ = "source"

    source_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    source_name: Mapped[str] = mapped_column(String(64), nullable=False)
    site_family: Mapped[str] = mapped_column(String(64), nullable=False)
    lottery: Mapped[str] = mapped_column(String(16), nullable=False)
    play_type: Mapped[str] = mapped_column(String(32), nullable=False)
    hit_mode: Mapped[str] = mapped_column(String(8), nullable=False, default="any")
    script_path: Mapped[str] = mapped_column(String(255), nullable=False)
    timeout_sec: Mapped[int] = mapped_column(Integer, nullable=False, default=30)
    enabled: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    remark: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, server_default=func.now(), onupdate=func.now()
    )

    predictions = relationship('Prediction', back_populates='source')

    __table_args__ = (
        Index("idx_family", "site_family"),
        Index("idx_lottery_play", "lottery", "play_type"),
    )


class CrawlRun(Base):
    __tablename__ = "crawl_run"

    run_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    lottery: Mapped[str | None] = mapped_column(String(16), nullable=True)
    period: Mapped[str | None] = mapped_column(String(16), nullable=True)
    run_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    ok: Mapped[int] = mapped_column(Integer, nullable=False)
    source_total: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    source_ok: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    raw_path: Mapped[str | None] = mapped_column(String(512), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())

    sources = relationship('CrawlRunSource', back_populates='run')

    __table_args__ = (Index("idx_run_at", "run_at"),)


class CrawlRunSource(Base):
    __tablename__ = "crawl_run_source"

    id: Mapped[int] = mapped_column(PK_INT, primary_key=True, autoincrement=True)
    run_id: Mapped[str] = mapped_column(String(64), ForeignKey('crawl_run.run_id'), nullable=False)
    source_id: Mapped[str] = mapped_column(String(64), nullable=False)
    ok: Mapped[int] = mapped_column(Integer, nullable=False)
    exit_code: Mapped[int | None] = mapped_column(Integer, nullable=True)
    elapsed_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    item_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    error_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    error_msg: Mapped[str | None] = mapped_column(String(512), nullable=True)
    final_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    content_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    raw_path: Mapped[str | None] = mapped_column(String(512), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())

    run = relationship('CrawlRun', back_populates='sources')

    __table_args__ = (
        UniqueConstraint("run_id", "source_id", name="uk_run_source"),
        Index("idx_source_time", "source_id", "created_at"),
    )


class Prediction(Base):
    __tablename__ = "prediction"

    id: Mapped[int] = mapped_column(PK_INT, primary_key=True, autoincrement=True)
    source_id: Mapped[str] = mapped_column(String(64), ForeignKey('source.source_id'), nullable=False)
    lottery: Mapped[str] = mapped_column(String(16), nullable=False)
    play_type: Mapped[str] = mapped_column(String(32), nullable=False)
    hit_mode: Mapped[str] = mapped_column(String(8), nullable=False)
    period: Mapped[str] = mapped_column(String(16), nullable=False)
    group_key: Mapped[str] = mapped_column(String(32), nullable=False, default="", server_default=text("''"))
    period_raw: Mapped[str] = mapped_column(String(16), nullable=False)
    preds_json: Mapped[object] = mapped_column(JSON_TYPE, nullable=False)
    claimed_status: Mapped[str] = mapped_column(String(16), nullable=False, default="unknown")
    claimed_xiao: Mapped[str | None] = mapped_column(String(8), nullable=True)
    claimed_num: Mapped[str | None] = mapped_column(String(2), nullable=True)
    claimed_raw: Mapped[str | None] = mapped_column(String(64), nullable=True)
    raw_text: Mapped[str] = mapped_column(String(1024), nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    final_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    fetched_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    first_seen_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    last_run_id: Mapped[str] = mapped_column(String(64), nullable=False)

    source = relationship('Source', back_populates='predictions')
    judge_result = relationship('JudgeResult', back_populates='prediction', uselist=False)

    __table_args__ = (
        UniqueConstraint("source_id", "lottery", "play_type", "period", "group_key", name="uk_pred"),
        Index("idx_period_play", "lottery", "period", "play_type"),
        Index("idx_source_period", "source_id", "period"),
    )


class Draw(Base):
    __tablename__ = "draw"

    id: Mapped[int] = mapped_column(PK_INT, primary_key=True, autoincrement=True)
    lottery: Mapped[str] = mapped_column(String(16), nullable=False)
    period: Mapped[str] = mapped_column(String(16), nullable=False)
    period_raw: Mapped[str] = mapped_column(String(16), nullable=False)
    draw_date: Mapped[date] = mapped_column(Date, nullable=False)
    opened_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    z1: Mapped[str] = mapped_column(String(2), nullable=False)
    z2: Mapped[str] = mapped_column(String(2), nullable=False)
    z3: Mapped[str] = mapped_column(String(2), nullable=False)
    z4: Mapped[str] = mapped_column(String(2), nullable=False)
    z5: Mapped[str] = mapped_column(String(2), nullable=False)
    z6: Mapped[str] = mapped_column(String(2), nullable=False)
    tema: Mapped[str] = mapped_column(String(2), nullable=False)
    tag: Mapped[dict] = mapped_column(JSON_TYPE, nullable=False, default=dict, server_default=text("'{}'"))
    source: Mapped[str] = mapped_column(String(256), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())

    __table_args__ = (UniqueConstraint("lottery", "period", name="uk_draw"),)


class AuditEvent(Base):
    __tablename__ = "audit_event"
    id: Mapped[int] = mapped_column(PK_INT, primary_key=True, autoincrement=True)
    entity: Mapped[str] = mapped_column(String(16), nullable=False)
    entity_id: Mapped[int] = mapped_column(PK_INT, nullable=False, index=True)
    recorded_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    phase: Mapped[str] = mapped_column(String(32), nullable=False)
    snapshot: Mapped[dict] = mapped_column(JSON_TYPE, nullable=False)





class Issue(Base):
    __tablename__ = "issue"
    id: Mapped[int] = mapped_column(PK_INT, primary_key=True, autoincrement=True)
    key: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    stage: Mapped[str] = mapped_column(String(24), nullable=False)
    source_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    lottery: Mapped[str | None] = mapped_column(String(16), nullable=True)
    period: Mapped[str | None] = mapped_column(String(16), nullable=True)
    prediction_id: Mapped[int | None] = mapped_column(PK_INT, nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="open")
    reason: Mapped[str] = mapped_column(String(2000), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON_TYPE, nullable=False, default=dict)
    occurrences: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    note: Mapped[str | None] = mapped_column(String(2000), nullable=True)


class Setting(Base):
    __tablename__ = "setting"
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[dict] = mapped_column(JSON_TYPE, nullable=False, default=dict)





class JudgeResult(Base):
    __tablename__ = "judge_result"

    id: Mapped[int] = mapped_column(PK_INT, primary_key=True, autoincrement=True)
    prediction_id: Mapped[int] = mapped_column(PK_INT, ForeignKey('prediction.id'), nullable=False)
    source_id: Mapped[str] = mapped_column(String(64), nullable=False)
    lottery: Mapped[str] = mapped_column(String(16), nullable=False)
    play_type: Mapped[str] = mapped_column(String(32), nullable=False)
    period: Mapped[str] = mapped_column(String(16), nullable=False)
    official_hit: Mapped[int] = mapped_column(Integer, nullable=False)
    claimed_hit: Mapped[int | None] = mapped_column(Integer, nullable=True)
    hit_detail: Mapped[object | None] = mapped_column(JSON_TYPE, nullable=True)
    judged_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)

    prediction = relationship('Prediction', back_populates='judge_result')

    __table_args__ = (
        UniqueConstraint("prediction_id", name="uk_judge"),
        Index("idx_rank", "lottery", "play_type", "period"),
        Index("idx_source", "source_id", "lottery", "play_type"),
    )


class Schedule(Base):
    __tablename__ = "schedule"

    id: Mapped[int] = mapped_column(PK_INT, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(64), nullable=False)
    lottery: Mapped[str] = mapped_column(String(16), nullable=False, default="macau")
    period: Mapped[str | None] = mapped_column(String(16), nullable=True)
    source_ids: Mapped[list[str] | None] = mapped_column(JSON_TYPE, nullable=True)
    cron: Mapped[str | None] = mapped_column(String(64), nullable=True)
    start_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    end_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    interval_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default=text("0"))
    enabled: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default=text("1"))
    do_ingest: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default=text("1"))
    auto_judge: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default=text("1"))
    next_run_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_run_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
    last_result: Mapped[object | None] = mapped_column(JSON_TYPE, nullable=True)
    retries: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default=text("0"))
    spec: Mapped[dict] = mapped_column(JSON_TYPE, nullable=False, default=dict, server_default=text("'{}'"))
    request_key: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, server_default=func.now(), onupdate=func.now()
    )

    __table_args__ = (
        Index("idx_schedule_next_run", "enabled", "next_run_at"),
    )


class CollectJob(Base):
    """An asynchronous collection run submitted by a client and polled for progress.

    ``POST /collector/collect`` blocks for the whole crawl (40 sources x 30s
    timeout / concurrency 8 is ~150s worst case), which no mobile HTTP client
    will wait out. A job row decouples submission from execution: the request
    handler inserts ``status="queued"`` and returns immediately, a background
    task drives it through the phases, and the client polls.

    ``progress`` maps ``source_id`` -> ``{state, item_count, elapsed_ms,
    error_code, error_msg}`` where ``state`` is ``queued`` | ``running`` |
    ``ok`` | ``fail``, so the UI can render per-source status while the run is
    still in flight. Booleans are stored as ``Integer`` 0/1 to match the
    ``Schedule`` convention, and timestamps are naive CN-local like the rest of
    the collector schema.
    """

    __tablename__ = "collect_job"

    id: Mapped[int] = mapped_column(PK_INT, primary_key=True, autoincrement=True)
    lottery: Mapped[str] = mapped_column(String(16), nullable=False, default="macau")
    period: Mapped[str | None] = mapped_column(String(16), nullable=True)
    source_ids: Mapped[list[str] | None] = mapped_column(JSON_TYPE, nullable=True)
    concurrency: Mapped[int] = mapped_column(Integer, nullable=False, default=8, server_default=text("8"))
    do_ingest: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default=text("1"))
    auto_judge: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default=text("1"))
    # queued | running | done | failed | cancelled | interrupted
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="queued", server_default=text("'queued'"))
    # queued | collecting | ingesting | judging | done
    phase: Mapped[str] = mapped_column(String(16), nullable=False, default="queued", server_default=text("'queued'"))
    progress: Mapped[dict] = mapped_column(JSON_TYPE, nullable=False, default=dict, server_default=text("'{}'"))
    result: Mapped[dict | None] = mapped_column(JSON_TYPE, nullable=True)
    error: Mapped[str | None] = mapped_column(String(512), nullable=True)
    run_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    source_total: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default=text("0"))
    source_done: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default=text("0"))
    source_ok: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default=text("0"))
    cancel_requested: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default=text("0"))
    # App-database user id; deliberately not a ForeignKey because users live in
    # the other database and the two are only sometimes the same Postgres host.
    created_by: Mapped[str | None] = mapped_column(String(64), nullable=True)
    schedule_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())
    started_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    __table_args__ = (
        Index("idx_collect_job_status", "status", "created_at"),
        Index("idx_collect_job_created", "created_at"),
    )


class ConsensusLeader(Base):
    """Last-known consensus leader per (lottery, period, play_type).

    ``consensus_leader_changed`` notifications cannot be derived from the other
    tables, because consensus is computed on the fly and nothing records what the
    leader used to be. This table is written by the collect-job worker after
    ingest — the only moment consensus can actually change — so the events
    endpoint stays a pure read and works correctly for any number of polling
    devices. ``changed_at`` is the event cursor.
    """

    __tablename__ = "consensus_leader"

    lottery: Mapped[str] = mapped_column(String(16), primary_key=True)
    period: Mapped[str] = mapped_column(String(16), primary_key=True)
    play_type: Mapped[str] = mapped_column(String(32), primary_key=True)
    # Canonical "kind:value|kind:value" of the leading prediction, used for
    # change detection without storing the full atom list.
    leader_key: Mapped[str] = mapped_column(String(512), nullable=False, default="")
    leader_votes: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default=text("0"))
    previous_key: Mapped[str | None] = mapped_column(String(512), nullable=True)
    changed_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())

    __table_args__ = (
        Index("idx_consensus_leader_changed", "changed_at"),
    )


class AiReport(Base):
    """Server-side cache for generated AI analysis reports.

    Without this every client call to ``/ai/analyze-588080`` makes the API
    process scrape 588080 and bill an LLM request, because ``fetch_fresh``
    defaults to true. Reports are keyed by ``(lottery, period, prompt_id)`` and
    upserted, so readers get a cached report and only staff can pay to refresh.
    """

    __tablename__ = "ai_report"

    id: Mapped[int] = mapped_column(PK_INT, primary_key=True, autoincrement=True)
    lottery: Mapped[str] = mapped_column(String(16), nullable=False, default="macau")
    period: Mapped[str] = mapped_column(String(16), nullable=False)
    prompt_id: Mapped[str] = mapped_column(String(64), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    provider: Mapped[str | None] = mapped_column(String(32), nullable=True)
    model: Mapped[str | None] = mapped_column(String(64), nullable=True)
    elapsed_sec: Mapped[float | None] = mapped_column(Float, nullable=True)
    scraped_summary: Mapped[dict | None] = mapped_column(JSON_TYPE, nullable=True)
    generated_by: Mapped[str | None] = mapped_column(String(64), nullable=True)
    generated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("lottery", "period", "prompt_id", name="uk_ai_report"),
        Index("idx_ai_report_lookup", "lottery", "period"),
    )


def _migrate_schedule(conn) -> None:
    """Ensure schedule table schema is compatible with cron and start_at."""
    inspector = inspect(conn)
    if "schedule" not in inspector.get_table_names():
        return
    cols = {c["name"]: c for c in inspector.get_columns("schedule")}
    if "next_run_at" in cols and not cols["next_run_at"].get("nullable", True) and conn.dialect.name == "sqlite":
        count = conn.execute(text("SELECT COUNT(*) FROM schedule")).scalar()
        if count == 0:
            conn.execute(text("DROP TABLE schedule"))
            Schedule.__table__.create(conn)




def _migrate_prediction_groups(conn) -> None:
    """Add independent prediction groups without losing existing rows."""
    inspector = inspect(conn)
    if "prediction" not in inspector.get_table_names():
        return
    columns = {column["name"] for column in inspector.get_columns("prediction")}
    old_key = ["source_id", "lottery", "play_type", "period"]
    old_constraint = next(
        (
            row
            for row in inspector.get_unique_constraints("prediction")
            if row.get("column_names") == old_key
        ),
        None,
    )

    if conn.dialect.name == "sqlite" and old_constraint:
        conn.execute(text("ALTER TABLE prediction RENAME TO prediction_without_groups"))
        conn.execute(text("""
            CREATE TABLE prediction (
                id INTEGER NOT NULL PRIMARY KEY,
                source_id VARCHAR(64) NOT NULL,
                lottery VARCHAR(16) NOT NULL,
                play_type VARCHAR(32) NOT NULL,
                hit_mode VARCHAR(8) NOT NULL,
                period VARCHAR(16) NOT NULL,
                group_key VARCHAR(32) NOT NULL DEFAULT '',
                period_raw VARCHAR(16) NOT NULL,
                preds_json JSON NOT NULL,
                claimed_status VARCHAR(16) NOT NULL,
                claimed_xiao VARCHAR(8),
                claimed_num VARCHAR(2),
                claimed_raw VARCHAR(64),
                raw_text VARCHAR(1024) NOT NULL,
                content_hash VARCHAR(64) NOT NULL,
                final_url VARCHAR(512),
                fetched_at DATETIME NOT NULL,
                first_seen_at DATETIME NOT NULL,
                last_seen_at DATETIME NOT NULL,
                last_run_id VARCHAR(64) NOT NULL,
                CONSTRAINT uk_pred UNIQUE (source_id, lottery, play_type, period, group_key)
            )
        """))
        if "group_key" in columns:
            copy_sql = """
                INSERT INTO prediction (
                    id, source_id, lottery, play_type, hit_mode, period, group_key, period_raw,
                    preds_json, claimed_status, claimed_xiao, claimed_num, claimed_raw, raw_text,
                    content_hash, final_url, fetched_at, first_seen_at, last_seen_at, last_run_id
                )
                SELECT
                    id, source_id, lottery, play_type, hit_mode, period, group_key, period_raw,
                    preds_json, claimed_status, claimed_xiao, claimed_num, claimed_raw, raw_text,
                    content_hash, final_url, fetched_at, first_seen_at, last_seen_at, last_run_id
                FROM prediction_without_groups
            """
        else:
            copy_sql = """
                INSERT INTO prediction (
                    id, source_id, lottery, play_type, hit_mode, period, group_key, period_raw,
                    preds_json, claimed_status, claimed_xiao, claimed_num, claimed_raw, raw_text,
                    content_hash, final_url, fetched_at, first_seen_at, last_seen_at, last_run_id
                )
                SELECT
                    id, source_id, lottery, play_type, hit_mode, period, '', period_raw,
                    preds_json, claimed_status, claimed_xiao, claimed_num, claimed_raw, raw_text,
                    content_hash, final_url, fetched_at, first_seen_at, last_seen_at, last_run_id
                FROM prediction_without_groups
            """
        conn.execute(text(copy_sql))
        conn.execute(text("DROP TABLE prediction_without_groups"))
        conn.execute(text("CREATE INDEX idx_period_play ON prediction (lottery, period, play_type)"))
        conn.execute(text("CREATE INDEX idx_source_period ON prediction (source_id, period)"))
        return

    if "group_key" not in columns:
        conn.execute(text("ALTER TABLE prediction ADD COLUMN group_key VARCHAR(32) NOT NULL DEFAULT ''"))
    if old_constraint and conn.dialect.name == "postgresql":
        name = old_constraint.get("name") or "uk_pred"
        quoted_name = conn.dialect.identifier_preparer.quote(name)
        conn.execute(text(f"ALTER TABLE prediction DROP CONSTRAINT {quoted_name}"))
        conn.execute(text(
            "ALTER TABLE prediction ADD CONSTRAINT uk_pred "
            "UNIQUE (source_id, lottery, play_type, period, group_key)"
        ))


def _create_all_locked(conn) -> None:
    """Create and migrate the schema on one already-transactional connection."""
    Base.metadata.create_all(conn)
    from common.draw_tags import POSITIONS, draw_tags
    from sqlalchemy.orm import Session

    _migrate_prediction_groups(conn)
    _migrate_schedule(conn)
    kind = "JSONB" if conn.dialect.name == "postgresql" else "JSON"
    additions = {
        "schedule": {
            "period": "VARCHAR(16) NULL",
            "cron": "VARCHAR(64) NULL",
            "start_at": "TIMESTAMP NULL",
            "end_at": "TIMESTAMP NULL",
            "do_ingest": "INTEGER NOT NULL DEFAULT 1",
            "auto_judge": "INTEGER NOT NULL DEFAULT 1",
            "last_run_at": "TIMESTAMP NULL",
            "last_status": "VARCHAR(32) NULL",
            "last_result": f"{kind} NULL",
            "spec": f"{kind} NOT NULL DEFAULT '{{}}'",
            "request_key": "VARCHAR(64) NULL",
            "created_at": "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP",
            "updated_at": "TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP",
        },
    }
    existing = set(inspect(conn).get_table_names())
    for table, fields in additions.items():
        if table not in existing:
            # The table is not part of Base.metadata (e.g. a leftover from an
            # older revision). Skip it instead of aborting the whole DDL
            # transaction, which would roll back every table created above.
            continue
        known = {c["name"] for c in inspect(conn).get_columns(table)}
        for name, ddl in fields.items():
            if name not in known:
                conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}"))
        for name in ("request_key", "pending_key"):
            if name in fields:
                conn.execute(text(f"CREATE UNIQUE INDEX IF NOT EXISTS uk_{table}_{name} ON {table} ({name})"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_schedule_next_run ON schedule (enabled, next_run_at)"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_collect_job_status ON collect_job (status, created_at)"))
    conn.execute(text("CREATE INDEX IF NOT EXISTS idx_collect_job_created ON collect_job (created_at)"))
    columns = {c["name"] for c in inspect(conn).get_columns("draw")}
    if "opened_at" not in columns:
        conn.execute(text("ALTER TABLE draw ADD COLUMN opened_at TIMESTAMP NULL"))
    tag_column_added = "tag" not in columns
    if tag_column_added:
        conn.execute(text(f"ALTER TABLE draw ADD COLUMN tag {kind} NOT NULL DEFAULT '{{}}'"))
    # Widen draw.source from VARCHAR(64) to VARCHAR(256) for existing databases.
    if conn.dialect.name == "postgresql":
        for col_info in inspect(conn).get_columns("draw"):
            if col_info["name"] == "source":
                length = getattr(col_info.get("type"), "length", None)
                if length is not None and length < 256:
                    conn.execute(text("ALTER TABLE draw ALTER COLUMN source TYPE VARCHAR(256)"))
                break
    with Session(bind=conn) as session:
        tag_marker = session.get(Setting, "schema.draw_tags")
        marker_value = tag_marker.value if tag_marker and isinstance(tag_marker.value, dict) else {}
        if tag_column_added or marker_value.get("version") != 1:
            last_id = 0
            while True:
                rows = list(session.scalars(
                    select(Draw).where(Draw.id > last_id).order_by(Draw.id).limit(500)
                ))
                if not rows:
                    break
                for row in rows:
                    tags = draw_tags([getattr(row, position) for position in POSITIONS], row.draw_date, row.tag)
                    if row.tag != tags:
                        row.tag = tags
                last_id = rows[-1].id
                session.flush()
            session.merge(Setting(key="schema.draw_tags", value={"version": 1}))
            session.flush()


def create_all(url: str | None = None) -> None:
    engine = get_engine(url)
    with engine.begin() as conn:
        if engine.dialect.name == "postgresql":
            # The transaction-scoped lock and DDL share one connection. This
            # remains safe when PRED_DB_POOL_SIZE=1 and serializes replicas.
            conn.execute(text("SELECT pg_advisory_xact_lock(5880802026)"))
        _create_all_locked(conn)


def seed_numbers() -> dict[str, int]:
    from common.attr import bose, head, heshu_odd, odd, pad_num, size, wei

    inserted = 0
    with session_scope() as s:
        for n in range(1, 50):
            num = pad_num(n)
            row = s.get(NumberInfo, num)
            fields = dict(bose=bose(n), size=size(n), odd=odd(n), head=head(n), wei=wei(n), sum=heshu_odd(n))
            if row is None:
                s.add(NumberInfo(num=num, **fields))
                inserted += 1
            else:
                for key, value in fields.items():
                    setattr(row, key, value)
    return {"inserted": inserted, "total": 49}


def seed_number_attrs() -> dict[str, int]:
    """Persist per-lunar-year 生肖 / 家野 / 五行 for 01–49 across 2000–2040.

    生肖 and 家野 are derived from the lunar calendar; 五行 comes from the
    authoritative per-year tables in ``common.wuxing`` (null when unknown).
    """
    from datetime import date

    from common.attr import pad_num
    from common.wuxing import num_to_wuxing
    from common.xiao import CNY_MD, jia_ye, num_to_xiao

    rows = 0
    with session_scope() as s:
        for year, md in CNY_MD.items():
            ref = date(year, md[0], md[1])  # a date guaranteed to be in that lunar year
            for n in range(1, 50):
                num = pad_num(n)
                xiao = num_to_xiao(n, ref)
                fields = dict(xiao=xiao, jiaye=jia_ye(xiao), wuxing=num_to_wuxing(n, ref))
                existing = s.get(NumberYearAttr, (year, num))
                if existing is None:
                    s.add(NumberYearAttr(lunar_year=year, num=num, **fields))
                else:
                    for k, v in fields.items():
                        setattr(existing, k, v)
                rows += 1
    return {"years": len(CNY_MD), "rows": rows}


def seed_number_code_meta() -> dict[str, int]:
    """Seed 2026 灵码称谓、花、时辰、地支和生肖附加分类。"""
    from common.attr import pad_num
    rows = {
        "鼠": [(7,"国师"),(19,"叛贼"),(31,"神偷"),(43,"太后")],
        "牛": [(6,"元帅"),(18,"大将"),(30,"员外"),(42,"大将")],
        "虎": [(5,"大将"),(17,"大王"),(29,"武士"),(41,"都督")],
        "兔": [(4,"玉帝"),(16,"东宫"),(28,"皇后"),(40,"小姐")],
        "龙": [(3,"皇帝"),(15,"状元"),(27,"君主"),(39,"国君")],
        "蛇": [(2,"宫女"),(14,"才子"),(26,"美人"),(38,"宫妃")],
        "马": [(1,"太子"),(13,"元帅"),(25,"秀才"),(37,"牛童"),(49,"笛声")],
        "羊": [(12,"相将"),(24,"西宫"),(36,"夫人"),(48,"宰相")],
        "猴": [(11,"太监"),(23,"寇王"),(35,"游侠"),(47,"侠士")],
        "鸡": [(10,"东宫"),(22,"贵妃"),(34,"歌女"),(46,"奴婢")],
        "狗": [(9,"文官"),(21,"先锋"),(33,"管家"),(45,"奴才")],
        "猪": [(8,"西宫"),(20,"太监"),(32,"商贾"),(44,"丞相")],
    }
    extras = {
        "鼠": ("梅花","23-01","子水"), "牛": ("荷花","01-03","丑土"),
        "虎": ("桃花","03-05","寅木"), "兔": ("兰花","05-07","卯木"),
        "龙": ("梨花","07-09","辰土"), "蛇": ("竹花","09-11","巳火"),
        "马": ("杏花","11-13","午火"), "羊": ("樱花","13-15","未土"),
        "猴": ("松花","15-17","申金"), "鸡": ("葵花","17-19","酉金"),
        "狗": ("菊花","19-21","戌土"), "猪": ("桂花","21-23","亥水"),
    }
    colors = {"马":"红","兔":"红","鼠":"红","鸡":"红","羊":"绿","龙":"绿","牛":"绿","狗":"绿","蛇":"蓝","虎":"蓝","猪":"蓝","猴":"蓝"}
    singles = {"鼠","龙","马","蛇","鸡","猪"}
    with session_scope() as s:
        count = 0
        for xiao, entries in rows.items():
            flower, hour, dizhi = extras[xiao]
            for n, role in entries:
                fields = dict(role=role, flower=flower, hour=hour, dizhi=dizhi, xiao_color=colors[xiao], stroke="单" if xiao in singles else "双")
                row = s.get(NumberCodeMeta, (2026, pad_num(n)))
                if row is None:
                    s.add(NumberCodeMeta(lunar_year=2026, num=pad_num(n), **fields))
                else:
                    for k, v in fields.items(): setattr(row, k, v)
                count += 1
    return {"inserted_or_updated": count, "total": 49}


def seed_xiao_year_meta() -> dict[str, int]:
    rows = {
        "鼠": ("地肖","阴肖","男肖","凶肖","冬","北"),
        "牛": ("天肖","阳肖","男肖","凶肖","冬","北"),
        "虎": ("地肖","阳肖","男肖","凶肖","春","东"),
        "兔": ("天肖","阳肖","女肖","吉肖","春","东"),
        "龙": ("天肖","阴肖","男肖","吉肖","春","东"),
        "蛇": ("地肖","阴肖","女肖","吉肖","夏","南"),
        "马": ("天肖","阴肖","男肖","吉肖","夏","南"),
        "羊": ("地肖","阳肖","女肖","吉肖","夏","南"),
        "猴": ("天肖","阳肖","男肖","凶肖","秋","西"),
        "鸡": ("地肖","阳肖","女肖","吉肖","秋","西"),
        "狗": ("地肖","阴肖","男肖","凶肖","秋","西"),
        "猪": ("天肖","阴肖","女肖","凶肖","冬","北"),
    }
    with session_scope() as s:
        for xiao, (td, yy, gender, luck, season, direction) in rows.items():
            row = s.get(XiaoYearMeta, (2026, xiao))
            fields = dict(tian_di=td, yin_yang=yy, gender=gender, luck=luck, season=season, direction=direction)
            if row is None: s.add(XiaoYearMeta(lunar_year=2026, xiao=xiao, **fields))
            else:
                for k,v in fields.items(): setattr(row,k,v)
    return {"total": len(rows)}


def seed_sources() -> dict[str, int]:
    cfg = load_yaml()
    rows = cfg.get("sources") or []
    inserted = updated = 0
    with session_scope() as s:
        for row in rows:
            sid = row["source_id"]
            existing = s.get(Source, sid)
            fields = dict(
                source_name=row["source_name"],
                site_family=row["site_family"],
                lottery=row["lottery"],
                play_type=row["play_type"],
                hit_mode=row.get("hit_mode", "any"),
                script_path=row["script_path"],
                timeout_sec=int(row.get("timeout_sec", 30)),
                enabled=1 if row.get("enabled", True) else 0,
                remark=row.get("remark"),
            )
            if existing is None:
                s.add(Source(source_id=sid, **fields))
                inserted += 1
            else:
                for k, v in fields.items():
                    setattr(existing, k, v)
                updated += 1
    return {"inserted": inserted, "updated": updated, "total": inserted + updated}


def main() -> None:
    p = argparse.ArgumentParser(description="init schema / seed sources")
    p.add_argument("cmd", choices=["init", "seed", "numbers", "url"])
    args = p.parse_args()
    if args.cmd == "url":
        from common.config import database_url
        from sqlalchemy.engine import make_url

        print(make_url(database_url()).render_as_string(hide_password=True))
        return
    if args.cmd in {"init", "numbers"}:
        create_all()
        print("tables created")
        print("numbers seeded", seed_numbers())
        print("number attrs seeded", seed_number_attrs())
        print("number code meta seeded", seed_number_code_meta())
        print("xiao metadata seeded", seed_xiao_year_meta())
        if args.cmd == "numbers":
            return
        stats = seed_sources()
        print("sources seeded", stats)
        return
    print(seed_sources())


if __name__ == "__main__":
    main()
