from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

Lottery = Literal["hk", "macau", "taiwan", "new"]
HitMode = Literal["any", "all", "none"]
Kind = Literal["num", "xiao", "wei", "head", "bose", "size", "odd"]
ClaimedStatus = Literal["pending", "hit", "miss", "unknown"]

REMOVED_PLAYS = frozenset({"lianma_4all", "lianma_techuan", "sum_size_odd", "total_xiao", "seven_bose"})


def validate_regular_combo(preds: list[dict], count: int, mode: str) -> None:
    from common.attr import pad_num
    if mode not in {"any", "all"}:
        raise ValueError("二中二、三中三仅支持全部正码命中，不支持反选")
    if len(preds) != count or any(p.get("kind") != "num" for p in preds):
        raise ValueError(f"需要恰好 {count} 个号码")
    if len({pad_num(p["value"]) for p in preds}) != count:
        raise ValueError("组合号码不能重复")

PLAY_TYPES = (
    "tema_n",
    "texiao",
    "tema_wei_n",
    "tema_head_n",
    "tema_bose",
    "tema_twoface",
    "tema_halfwave",
    "hexiao",
    "pingte_xiao",
    "pingte_wei",
    "lianxiao_n",
    "lianwei_n",
    "zhengma_n",
    "zhengxiao",
    "lianma_2all",
    "lianma_3all",
    "lianma_3z2",
    "lianma_2zt",
    "buzhong_num",
    "buzhong_xiao",
    "buzhong_wei",
)


class PredAtom(BaseModel):
    kind: Kind
    value: str
    text: str | None = None

    @field_validator("value")
    @classmethod
    def strip_value(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("empty value")
        if v in {"合单", "合双", "合單", "合雙"}:
            raise ValueError("合单双玩法已移除")
        return v


class Claimed(BaseModel):
    status: ClaimedStatus = "unknown"
    xiao: str | None = None
    num: str | None = None
    raw: str | None = None


class ErrorBody(BaseModel):
    code: str
    message: str


class PredItem(BaseModel):
    period_raw: str
    period: str
    group_key: str = ""
    published_at: datetime | None = None
    preds: list[PredAtom]
    claimed: Claimed
    raw_text: str

    @field_validator("group_key")
    @classmethod
    def check_group_key(cls, value: str) -> str:
        value = value.strip()
        if len(value) > 32 or any(ord(ch) < 32 for ch in value):
            raise ValueError("group_key 必须是不超过 32 字符的单行文本")
        return value


class PredV1(BaseModel):
    ok: bool
    schema_name: Literal["pred.v1"] = Field(alias="schema")
    source_id: str
    source_name: str
    site_family: str
    lottery: Lottery
    play_type: str
    hit_mode: HitMode = "any"
    fetched_at: datetime
    final_url: str | None = None
    content_hash: str
    items: list[PredItem] = Field(default_factory=list)
    error: ErrorBody | None = None

    model_config = {"populate_by_name": True}

    @field_validator("play_type")
    @classmethod
    def check_play(cls, v: str) -> str:
        if v in REMOVED_PLAYS:
            raise ValueError(f"玩法已移除: {v}")
        if v not in PLAY_TYPES:
            # still allow through — judge will dead-letter unknown types
            pass
        return v

    @model_validator(mode="after")
    def check_regular_combos(self):
        count = {"lianma_2all": 2, "lianma_3all": 3}.get(self.play_type)
        if count:
            for item in self.items:
                validate_regular_combo([p.model_dump() for p in item.preds], count, self.hit_mode)
        return self


class RunSourceResult(BaseModel):
    source_id: str
    ok: bool
    exit_code: int | None = None
    elapsed_ms: int | None = None
    item_count: int = 0
    data: dict[str, Any] | None = None
    error_code: str | None = None
    error_msg: str | None = None


class RunV1(BaseModel):
    ok: bool
    schema_name: Literal["run.v1"] = Field(alias="schema")
    run_id: str
    run_at: datetime
    lottery: Lottery | None = None
    period: str | None = None
    results: list[RunSourceResult] = Field(default_factory=list)

    model_config = {"populate_by_name": True}


def pred_dumps(model: PredV1) -> str:
    return model.model_dump_json(by_alias=True, exclude_none=False)


def pred_loads(raw: str | dict[str, Any]) -> PredV1:
    if isinstance(raw, str):
        return PredV1.model_validate_json(raw)
    return PredV1.model_validate(raw)


def run_loads(raw: str | dict[str, Any]) -> RunV1:
    if isinstance(raw, str):
        return RunV1.model_validate_json(raw)
    return RunV1.model_validate(raw)
