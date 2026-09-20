"""Prompt templates and prompt registry for lottery prediction and scraped data analysis."""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any


@dataclass
class PromptTemplate:
    id: str
    name: str
    description: str
    system_prompt: str
    user_template: str

    def render(self, context_data: str = "", period: str = "262", **extra: Any) -> list[dict[str, str]]:
        str_ctx = str(context_data or "")
        str_per = str(period or "262")
        # Defensive check: if caller accidentally passed (period, context_data) positionally
        if len(str_per) > len(str_ctx) and len(str_ctx) <= 15:
            str_ctx, str_per = str_per, str_ctx

        user_content = self.user_template.format(context_data=str_ctx, period=str_per, **extra)
        return [
            {"role": "system", "content": self.system_prompt},
            {"role": "user", "content": user_content},
        ]


# --------------------------------------------------------------------------- #
# Prompt 1: 澳门六合彩专业实码研判 (用户定制 - 严格过滤“發”“猫”“？”“0O”)
# --------------------------------------------------------------------------- #
MACAU_ANALYST_EXPERT_SYSTEM = """你现在是专业的澳门六合彩分析师。
你的专业分析准则：
1. 【只分析实码与生肖】：仅针对帖文内容里的真实号码（实码）和正统十二生肖（鼠、牛、虎、兔、龙、蛇、马、羊、猴、鸡、狗、猪）进行交叉统计与共识分析；
2. 【严格过滤无效干扰项】：必须无条件严格过滤并剔除所有“發”、“猫”、“？”、“0O”等假生肖、印刷乱码、占位符、混淆词及一切商业广告导流暗号；
3. 【精算统计与交叉验证】：严格聚焦用户指定的期号，交叉比对抓取到的各大专家心水栏目，计算出确切的高频生肖与重点实码，输出排版专业严谨的研判报告。"""

MACAU_ANALYST_EXPERT_USER = """你现在是专业的澳门六合彩分析师，只分析帖文里的实码和生肖，严格过滤所有“發”“猫”“？”“0O”，给出{period}期热度最高的5个生肖以及重点6个号码10个号码。

【抓取到的当期全部预测数据如下】：
---
{context_data}
---

请严格基于上述抓取数据中的第 {period} 期内容展开精算，并按以下标准格式输出分析报告：

### 🎯 【澳门六合彩 第 {period} 期】实码与生肖研判精选

#### 一、 过滤与数据清洗说明
* 已严格过滤剔除所有包含“發”、“猫”、“？”、“0O”等无效假肖与乱码干扰；
* 统计到包含第 {period} 期实码预测的专家栏目列表。

#### 二、 第 {period} 期热度最高的 5 个生肖 (Top 5)
1. **[生肖1]** - 出现频次及推荐专家
2. **[生肖2]** - 出现频次及推荐专家
3. **[生肖3]** - 出现频次及推荐专家
4. **[生肖4]** - 出现频次及推荐专家
5. **[生肖5]** - 出现频次及推荐专家

#### 三、 重点号码精选
* 🏆 **重点 6 个号码（核心精选）**：[ 00, 00, 00, 00, 00, 00 ]
* 🛡️ **重点 10 个号码（大底防守）**：[ 00, 00, 00, 00, 00, 00, 00, 00, 00, 00 ]

#### 四、 核心对料研判依据
* 简要说明上述 5 肖与 6 码、10 码在各大核心专家栏目中的重合交集理由。
"""


# --------------------------------------------------------------------------- #
# Prompt 2: 综合对料共识研判与心水精选
# --------------------------------------------------------------------------- #
CONSENSUS_SYNTHESIS_SYSTEM = """你是一位顶级专业彩研数据精算师与对料分析专家，精通六合彩、澳门彩等开奖规律及各大民间心水专家的预测流派。
你的核心任务是：对用户提供的当期多源抓取预测数据进行客观、严谨、深度的交叉验证与共识提炼。
你具备极强的信息去噪能力，能够完全无视输入中混杂的广告、导流暗号、无关代码及失效链接，仅聚焦于真实预测内容。
输出必须逻辑清晰、数据严谨、分段排版优雅，使用专业得体的中文 Markdown 呈现。"""

CONSENSUS_SYNTHESIS_USER = """以下是从目标网站最新抓取到的第 {period} 期全部核心预测资料数据：

---
{context_data}
---

请结合各大专家的预测内容，进行深度综合对料研判，并按以下结构输出 Markdown 报告：

### 一、 数据概况与去噪速览
* 简要说明第 {period} 期抓取到的有效专家栏目数，去除广告噪音后的核心有效信息汇总。

### 二、 生肖热度与共识交叉分析
* **【绝杀/重合热肖】**：统计各家重点推荐且重合频次最高的生肖（列出频次与推荐专家）；
* **【防守生肖】**：次高频出现的补充生肖；
* **【争议生肖】**：部分专家力荐但有其他专家明确杀掉或严重冲突的生肖。

### 三、 特码与号码交集精选
* 提取各栏目（如四码、六码、一码中特等）共识重合度最高的号码；
* 归纳本期的【核心特码精选 (3~5码)】及【平特防守码】。

### 四、 单双/波色/两面盘风向
* 综合单双、大小、红绿蓝波色倾向性统计。

### 五、 专家避坑预警与综合建议
* 综合研判风险点，指出哪几类观点存在盲区，给出当期对料投资风控指引。
"""


# --------------------------------------------------------------------------- #
# Prompt 3: 结构化 JSON 精准抽取
# --------------------------------------------------------------------------- #
STRUCTURED_EXTRACTION_SYSTEM = """你是一位专业的数据挖掘与结构化抽取专家。
你的任务是从混杂的抓取文本或 HTML 中精确抽取出结构化预测数据，并严格输出符合 JSON 规范的格式。
绝对不要输出任何非 JSON 的前缀、后缀、说明或 Markdown 标签，确保结果能直接被 json.loads 解析。"""

STRUCTURED_EXTRACTION_USER = """请从以下抓取的第 {period} 期预测内容中，提取所有专家的期号、生肖预测、号码预测与胜负状态：

---
{context_data}
---

请严格按如下 JSON Schema 输出纯 JSON 对象：
{{
  "period": "{period}",
  "sources_count": 提取到的有效专家数,
  "sources": [
    {{
      "source_name": "专家或栏目名称（如：云顶心水四码）",
      "period": "该专家的期号",
      "xiao": ["生肖1", "生肖2"],
      "numbers": ["01", "12"],
      "twoface": "单/双/大/小（如有）",
      "claimed_status": "win/loss/unknown"
    }}
  ],
  "top_xiao_frequency": {{
    "生肖名": 出现次数
  }},
  "top_numbers_frequency": {{
    "号码": 出现次数
  }}
}}
"""


# --------------------------------------------------------------------------- #
# Prompt 4: 杀肖杀码与冷热风控预警
# --------------------------------------------------------------------------- #
RISK_AND_KILL_SYSTEM = """你是一位专业的彩票对料风控精算师。你的特长是识别多源预测中的虚假共识、互斥矛盾以及高风险陷阱号码。
请对抓取到的第 {period} 期多栏目预测展开严厉的交叉审查，找出盲点与高危号码。"""

RISK_AND_KILL_USER = """以下是第 {period} 期当期各专家预测与公开资料：

---
{context_data}
---

请输出一份【第 {period} 期当期对料风控与杀号预警报告】：
1. **矛盾对立点**：哪些专家预测存在完全相反的观点（例如一家推荐特肖马，另一家杀马）；
2. **杀肖杀码汇编**：综合汇总各家给出的明确杀肖、杀码建议；
3. **高危生肖与号码警报**：标注哪些号码看似热门但缺乏多源支撑或已被高信度源排除；
4. **避坑实操建议**：如何合理配置组合以规避冷门与对立风险。
"""


# --------------------------------------------------------------------------- #
# Prompt 5: 当期预测极简速览快报
# --------------------------------------------------------------------------- #
SUMMARY_DIGEST_SYSTEM = """你是一位精炼干练的情报简报员。请为移动端用户提供极速速览体验。"""

SUMMARY_DIGEST_USER = """请对以下第 {period} 期对料数据提炼出一份 400 字以内的【第 {period} 期心水极速快报】：

---
{context_data}
---

请以要点列表呈现：
* 🎯 **本期三肖**：
* 🔢 **金牌四码**：
* 🛡️ **防守两肖**：
* ⚠️ **重点杀肖**：
* 💡 **一句话评述**：
"""


PROMPT_TEMPLATES: dict[str, PromptTemplate] = {
    "macau_analyst_expert": PromptTemplate(
        id="macau_analyst_expert",
        name="澳门六合彩实码严析 Top5肖+6码+10码 (定制推荐)",
        description="专业澳门六合彩分析师设定，严格过滤“發”“猫”“？”“0O”，动态注入期号，给出热度最高5肖及重点6码、10码",
        system_prompt=MACAU_ANALYST_EXPERT_SYSTEM,
        user_template=MACAU_ANALYST_EXPERT_USER,
    ),
    "consensus_synthesis": PromptTemplate(
        id="consensus_synthesis",
        name="综合对料共识研判与全景分析",
        description="过滤广告噪音，交叉验证21家预测栏目，提炼高概率共识生肖、特码交集与全景评分",
        system_prompt=CONSENSUS_SYNTHESIS_SYSTEM,
        user_template=CONSENSUS_SYNTHESIS_USER,
    ),
    "structured_extraction": PromptTemplate(
        id="structured_extraction",
        name="结构化 JSON 精准抽取",
        description="将各模块图文预测自动清洗解析为标准的期号、生肖列表与特码 JSON 结构",
        system_prompt=STRUCTURED_EXTRACTION_SYSTEM,
        user_template=STRUCTURED_EXTRACTION_USER,
    ),
    "risk_and_kill": PromptTemplate(
        id="risk_and_kill",
        name="杀肖杀码与冷热风控预警",
        description="分析各家观点分歧与矛盾对立点，排查虚假共识，输出杀号避坑指南",
        system_prompt=RISK_AND_KILL_SYSTEM,
        user_template=RISK_AND_KILL_USER,
    ),
    "summary_digest": PromptTemplate(
        id="summary_digest",
        name="当期预测极简速览快报",
        description="面向手机移动端的 400 字精简速读版心水卡片",
        system_prompt=SUMMARY_DIGEST_SYSTEM,
        user_template=SUMMARY_DIGEST_USER,
    ),
}


def detect_period_from_data(data: Any, default: str = "262") -> str:
    """Detect the most prominent period number in the scraped data."""
    if not data:
        return default
    text = ""
    if isinstance(data, dict):
        modules = data.get("modules") or []
        text = " ".join((m.get("content") or "") for m in modules) + " " + (data.get("html") or "")
    elif hasattr(data, "modules"):
        text = " ".join((m.get("content") or "") for m in getattr(data, "modules", []))
    elif isinstance(data, str):
        text = data

    found = re.findall(r"(?:第\s*)?(\d{2,7})\s*期", text)
    if not found:
        return default

    from collections import Counter
    counter = Counter(found)
    # Prefer 3-digit period numbers (e.g. 262, 263, 260)
    for p, _ in counter.most_common(10):
        if len(p) == 3 and p.isdigit():
            return p
    return counter.most_common(1)[0][0]


def get_prompt_template(prompt_id: str) -> PromptTemplate:
    """Get prompt template by ID, falling back to macau_analyst_expert."""
    if prompt_id in PROMPT_TEMPLATES:
        return PROMPT_TEMPLATES[prompt_id]
    return PROMPT_TEMPLATES["macau_analyst_expert"]


def list_prompt_templates() -> list[dict[str, Any]]:
    """List all available prompt templates."""
    return [
        {
            "id": p.id,
            "name": p.name,
            "description": p.description,
            "user_template": p.user_template,
            "system_prompt": p.system_prompt,
            "is_default": p.id == "macau_analyst_expert",
        }
        for p in PROMPT_TEMPLATES.values()
    ]
