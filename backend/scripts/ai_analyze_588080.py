#!/usr/bin/env python3
"""CLI utility to run AI analysis with specialized prompts on 588080.com scraped data.

Usage examples:
  # Using default consensus synthesis prompt with DeepSeek / OpenAI-compatible API:
  python backend/scripts/ai_analyze_588080.py --provider openai --prompt consensus_synthesis -o out/report.md

  # Using Google Gemini with structured extraction prompt:
  python backend/scripts/ai_analyze_588080.py --provider gemini --prompt structured_extraction

  # Using Anthropic Claude:
  python backend/scripts/ai_analyze_588080.py --provider anthropic --prompt risk_and_kill
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Add backend directory and backend/collector to sys.path
BACKEND_DIR = Path(__file__).resolve().parent.parent
COLLECTOR_DIR = BACKEND_DIR / "collector"

if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))
if str(COLLECTOR_DIR) not in sys.path:
    sys.path.insert(0, str(COLLECTOR_DIR))

from app.services.ai.analyzer import analyze_scraped_data
from app.services.ai.prompts import list_prompt_templates


def main() -> None:
    parser = argparse.ArgumentParser(description="588080.com 网页数据 AI 智能对料与提示词分析工具")
    parser.add_argument(
        "-p",
        "--prompt",
        default="macau_analyst_expert",
        help="提示词模板 ID: macau_analyst_expert (默认推荐), consensus_synthesis, structured_extraction, risk_and_kill, summary_digest",
    )
    parser.add_argument("--period", help="目标期号（如 262，若不传则自动从数据中识别）")
    parser.add_argument("--custom-prompt", help="自定义提示词（覆盖内置模板）")
    parser.add_argument(
        "--provider",
        choices=["openai", "gemini", "anthropic"],
        help="AI 服务商: openai (默认, 支持 DeepSeek/Qwen/Kimi/OpenAI), gemini, anthropic",
    )
    parser.add_argument("--model", help="指定大模型名称（如 deepseek-chat, gemini-2.5-flash, claude-3-5-sonnet）")
    parser.add_argument("--api-key", help="覆盖环境变量中的 API Key")
    parser.add_argument("--base-url", help="覆盖环境变量中的 Base URL")
    parser.add_argument(
        "--format",
        default="modules_summary",
        choices=["modules_summary", "raw_html"],
        help="上下文格式: modules_summary (去噪核心预测, 推荐) 或 raw_html (全量原始代码)",
    )
    parser.add_argument("-i", "--input", help="指定已抓取的 JSON 文件路径（若不传则实时自动抓取 588080 最新数据）")
    parser.add_argument("-o", "--output", help="输出 Markdown 报告文件路径")
    parser.add_argument("--list-prompts", action="store_true", help="列出所有内置提示词模板")

    args = parser.parse_args()

    if args.list_prompts:
        print("\n=== 内置提示词模板列表 ===")
        for p in list_prompt_templates():
            tag = " [默认]" if p["is_default"] else ""
            print(f"• ID: {p['id']}{tag}\n  名称: {p['name']}\n  说明: {p['description']}\n")
        return

    scraped_data = None
    if args.input:
        in_path = Path(args.input)
        if not in_path.exists():
            print(f"错误: 输入文件 {args.input} 不存在")
            sys.exit(1)
        print(f"正在从本地读取抓取数据: {args.input}")
        scraped_data = json.loads(in_path.read_text(encoding="utf-8"))

    print(f"正在执行 AI 分析 (提示词: {args.prompt}, 期号: {args.period or '自动检测'}, 服务商: {args.provider or '默认'})...")
    result = analyze_scraped_data(
        scraped_data=scraped_data,
        prompt_id=args.prompt,
        period=args.period,
        custom_prompt=args.custom_prompt,
        provider=args.provider,
        model=args.model,
        format_mode=args.format,
        api_key=args.api_key,
        base_url=args.base_url,
    )


    if not result.ok:
        print(f"\n❌ AI 分析失败: {result.error}")
        sys.exit(1)

    print("\n=======================================================")
    print(f"                AI 智能研判分析报告 ({result.provider} / {result.model})                ")
    print("=======================================================")
    print(f"模板: {result.prompt_id} | 耗时: {result.elapsed_sec}s | Token: {result.usage}")
    print("-------------------------------------------------------\n")
    print(result.analysis)
    print("\n=======================================================")

    if args.output:
        out_p = Path(args.output)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(result.analysis, encoding="utf-8")
        print(f"报告已保存至: {args.output}")


if __name__ == "__main__":
    main()
