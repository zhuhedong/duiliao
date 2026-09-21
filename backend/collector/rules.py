"""Versioned descriptions of the implemented rules; no payout assumptions."""
VERSION = "2026-09-06.2"
RULES = {
    "tema_n": ("特码", "特码", "候选号码包含特码", "num"),
    "texiao": ("特肖", "特码", "候选生肖包含特码生肖", "xiao"),
    "tema_wei_n": ("特尾", "特码", "候选尾数包含特码尾数", "wei"),
    "tema_head_n": ("特头", "特码", "候选头数包含特码头数", "head"),
    "tema_bose": ("特波", "特码", "候选波色包含特码波色", "bose"),
    "tema_twoface": ("两面", "特码", "按配置任一或全部属性匹配；大小按 01–24 小、25–49 大，单双按号码奇偶", "size,odd,xiao,gender,tian_di,yin_yang,luck"),
    "tema_halfwave": ("半波", "特码", "任一预测匹配特码的波色大小、波色单双或波色大小单双", "bose"),
    "hexiao": ("合肖", "特码", "候选生肖包含特码生肖", "xiao"),
    "pingte_xiao": ("平特肖", "七球（含特码）", "任一候选生肖出现在七个开奖号码中", "xiao"),
    "pingte_wei": ("平特尾", "七球（含特码）", "任一候选尾数出现在七个开奖号码中", "wei"),
    "lianxiao_n": ("连肖", "七球（含特码）", "所有不同候选生肖均出现在七球中，重肖不增加不同生肖数量", "xiao"),
    "lianwei_n": ("连尾", "七球（含特码）", "所有不同候选尾数均出现在七球中", "wei"),
    "zhengma_n": ("正码", "六个正码", "按配置任一或全部号码在正码中，特码不计", "num"),
    "zhengxiao": ("正肖", "六个正码", "任一候选生肖出现在正码中，特码不计", "xiao"),
    "lianma_2all": ("二中二", "六个正码", "恰好两个不同号码，两个都在正码中", "num"),
    "lianma_3all": ("三中三", "六个正码", "恰好三个不同号码，三个都在正码中", "num"),
    "lianma_3z2": ("三中二", "六个正码", "恰好三个不同号码，至少两个在正码中，特码不计", "num"),
    "lianma_2zt": ("二中特", "正码与特码", "恰好两个不同号码，一个为正码，另一个为特码", "num"),
    "buzhong_num": ("不中码", "七球（含特码）", "所有候选号码均未出现在七球中", "num"),
    "buzhong_xiao": ("杀肖", "七球（含特码）", "所有候选生肖均未出现在七球中", "xiao"),
    "buzhong_wei": ("杀尾", "七球（含特码）", "所有候选尾数均未出现在七球中", "wei"),
}


def catalog():
    return [dict(play_type=k, name=v[0], scope=v[1], condition=v[2], version=VERSION,
                 modes="按配置任一或全部匹配" if k in {"zhengma_n", "tema_twoface"} else "固定按玩法条件判定") for k, v in RULES.items()]


def validate(play, preds, mode):
    from common.attr import pad_num
    from common.xiao import normalize_xiao
    if not isinstance(preds, list) or not preds:
        raise ValueError("真实预测不能为空，空内容不参与命中判断")
    allowed = RULES[play][3].split(",")
    for atom in preds:
        k, v = atom.get("kind"), str(atom.get("value", ""))
        if k not in allowed:
            raise ValueError(f"{RULES[play][0]}不接受 {k} 类型")
        if k == "num":
            pad_num(v)
        elif k == "xiao":
            twoface_xiao_extra = {
                "家", "野", "家禽", "野兽", "家肖", "野肖",
                "男", "女", "男肖", "女肖",
                "天", "地", "天肖", "地肖",
                "阳", "阴", "阳肖", "阴肖",
                "吉", "凶", "吉肖", "凶肖",
            }
            if not (play == "tema_twoface" and v in twoface_xiao_extra):
                normalize_xiao(v)
        elif k == "gender" and v not in {"男", "女", "男肖", "女肖"}:
            raise ValueError("男女肖属性不合法")
        elif k == "tian_di" and v not in {"天", "地", "天肖", "地肖"}:
            raise ValueError("天地肖属性不合法")
        elif k == "yin_yang" and v not in {"阳", "阴", "阳肖", "阴肖"}:
            raise ValueError("阴阳肖属性不合法")
        elif k == "luck" and v not in {"吉", "凶", "吉肖", "凶肖"}:
            raise ValueError("吉凶肖属性不合法")
        elif k in {"wei", "head"} and v not in (list("0123456789") if k == "wei" else list("01234")):
            raise ValueError("头尾数超出范围")
        elif (k == "size" and v not in {"大", "小"}) or (k == "odd" and v not in {"单", "双"}):
            raise ValueError("大小或单双属性不合法")
        elif k == "bose":
            values = {"红", "蓝", "绿", "红波", "蓝波", "绿波"}
            if play == "tema_halfwave":
                values = {b + x for b in "红蓝绿" for x in ["大", "小", "单", "双", "大单", "大双", "小单", "小双"]}
            if v not in values:
                raise ValueError("波色属性不合法")
    if play in {"lianma_3z2", "lianma_2zt"}:
        n = 3 if play == "lianma_3z2" else 2
        if len(preds) != n or len({pad_num(p["value"]) for p in preds}) != n:
            raise ValueError(f"需要恰好 {n} 个不同号码")


def evidence(pred, ctx, detail, hit):
    rule = RULES[pred.play_type]
    return {**detail, "rule_version": VERSION, "rule": rule[2], "scope_label": rule[1],
            "explanation": f"{rule[0]}：{rule[2]}；本条{'满足' if hit else '不满足'}条件，判定为{'中' if hit else '挂'}。",
            "draw_snapshot": {"draw_date": ctx["draw_date"].isoformat(), "zheng": ctx["z"], "tema": ctx["tema"], "tema_attrs": ctx["tema_attrs"]},
            "prediction_snapshot": {"preds": pred.preds_json, "hit_mode": pred.hit_mode}}


def save_result(s, pred, row, now):
    from sqlalchemy import select
    from schema import JudgeResult, AuditEvent
    from audit import snapshot
    from issues import resolve_judge
    existing = s.scalar(select(JudgeResult).where(JudgeResult.prediction_id == pred.id))
    old = snapshot(existing) if existing else None
    if existing is None:
        existing = JudgeResult(**row, judged_at=now)
        s.add(existing)
    else:
        if not s.scalar(select(AuditEvent.id).where(AuditEvent.entity == "judge", AuditEvent.entity_id == pred.id).limit(1)):
            s.add(AuditEvent(entity="judge", entity_id=pred.id, recorded_at=now, phase="legacy", snapshot=old))
        for k, v in row.items():
            setattr(existing, k, v)
        existing.judged_at = now
    s.flush()
    if old is None or any(old.get(k) != row.get(k) for k in ("official_hit", "claimed_hit", "hit_detail")):
        s.add(AuditEvent(entity="judge", entity_id=pred.id, recorded_at=now, phase="judged", snapshot=snapshot(existing)))
    resolve_judge(s, pred.id)


def archive_current(s, prediction_id):
    from sqlalchemy import select
    from schema import JudgeResult, AuditEvent
    from audit import snapshot, now_local
    row = s.scalar(select(JudgeResult).where(JudgeResult.prediction_id == prediction_id))
    last = s.scalar(select(AuditEvent).where(AuditEvent.entity == "judge", AuditEvent.entity_id == prediction_id).order_by(AuditEvent.id.desc()))
    if row and (not last or last.snapshot.get("hit_detail") != row.hit_detail or last.snapshot.get("official_hit") != row.official_hit):
        s.add(AuditEvent(entity="judge", entity_id=prediction_id, recorded_at=now_local(), phase="previous", snapshot=snapshot(row)))
