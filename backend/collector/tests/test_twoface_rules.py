import sys
from pathlib import Path
COLLECTOR_ROOT = Path(__file__).resolve().parent.parent
if str(COLLECTOR_ROOT) not in sys.path:
    sys.path.insert(0, str(COLLECTOR_ROOT))

from datetime import date
import pytest
from common.attr import ball_attrs
from common.xiao import gender_xiao, tiandi_xiao, yinyang_xiao, luck_xiao, season_xiao, direction_xiao
from judge import j_tema_twoface
from rules import validate


def test_zodiac_classifications():
    # 2026-09-21: year of horse (马)
    d = date(2026, 9, 21)

    # 01 is 马
    a01 = ball_attrs(1, d)
    assert a01["xiao"] == "马"
    assert a01["gender"] == "男肖"
    assert a01["tian_di"] == "天肖"
    assert a01["yin_yang"] == "阴肖"
    assert a01["luck"] == "吉肖"
    assert a01["season"] == "夏"
    assert a01["direction"] == "南"

    # 04 is 兔 (4 steps back from 马: 马->蛇->龙->兔)
    a04 = ball_attrs(4, d)
    assert a04["xiao"] == "兔"
    assert a04["gender"] == "女肖"
    assert a04["tian_di"] == "天肖"
    assert a04["yin_yang"] == "阳肖"
    assert a04["luck"] == "吉肖"
    assert a04["season"] == "春"
    assert a04["direction"] == "东"

    # 07 is 鼠 (7 steps back from 马: 马->蛇->龙->兔->虎->牛->鼠)
    a07 = ball_attrs(7, d)
    assert a07["xiao"] == "鼠"
    assert a07["gender"] == "男肖"
    assert a07["tian_di"] == "地肖"
    assert a07["yin_yang"] == "阴肖"
    assert a07["luck"] == "凶肖"
    assert a07["season"] == "冬"
    assert a07["direction"] == "北"


def test_twoface_validation():
    # Valid twoface predictions
    validate("tema_twoface", [{"kind": "xiao", "value": "男肖"}], "any")
    validate("tema_twoface", [{"kind": "xiao", "value": "女"}], "any")
    validate("tema_twoface", [{"kind": "gender", "value": "男"}], "any")
    validate("tema_twoface", [{"kind": "gender", "value": "女肖"}], "any")
    validate("tema_twoface", [{"kind": "tian_di", "value": "天肖"}], "any")
    validate("tema_twoface", [{"kind": "yin_yang", "value": "阳"}], "any")
    validate("tema_twoface", [{"kind": "luck", "value": "吉肖"}], "any")
    validate("tema_twoface", [{"kind": "xiao", "value": "家禽"}], "any")

    # Invalid values
    with pytest.raises(ValueError):
        validate("tema_twoface", [{"kind": "gender", "value": "未知"}], "any")

    with pytest.raises(ValueError):
        validate("tema_twoface", [{"kind": "tian_di", "value": "神肖"}], "any")


def test_twoface_judgment_gender_and_tiandi():
    d = date(2026, 9, 21)
    # Context with tema=04 (兔 -> 女肖, 天肖, 阳肖, 吉肖, 小, 双)
    ctx_tu = {
        "tema": "04",
        "tema_attrs": ball_attrs(4, d),
    }

    # Hit 女肖
    hit, detail = j_tema_twoface([{"kind": "xiao", "value": "女肖"}], "any", ctx_tu)
    assert hit is True
    assert detail["checks"][0]["hit"] is True

    # Miss 男肖
    hit, detail = j_tema_twoface([{"kind": "xiao", "value": "男肖"}], "any", ctx_tu)
    assert hit is False
    assert detail["checks"][0]["hit"] is False

    # Single character "女"
    hit, detail = j_tema_twoface([{"kind": "gender", "value": "女"}], "any", ctx_tu)
    assert hit is True

    # Single character "男"
    hit, detail = j_tema_twoface([{"kind": "gender", "value": "男"}], "any", ctx_tu)
    assert hit is False

    # 天肖 -> True, 地肖 -> False
    hit_tian, _ = j_tema_twoface([{"kind": "tian_di", "value": "天肖"}], "any", ctx_tu)
    hit_di, _ = j_tema_twoface([{"kind": "tian_di", "value": "地肖"}], "any", ctx_tu)
    assert hit_tian is True
    assert hit_di is False

    # Multi-atom mode="all": 女肖 + 双 -> Both hit -> True
    hit, _ = j_tema_twoface([{"kind": "xiao", "value": "女肖"}, {"kind": "odd", "value": "双"}], "all", ctx_tu)
    assert hit is True

    # Multi-atom mode="all": 女肖 + 单 -> One miss -> False
    hit, _ = j_tema_twoface([{"kind": "xiao", "value": "女肖"}, {"kind": "odd", "value": "单"}], "all", ctx_tu)
    assert hit is False
