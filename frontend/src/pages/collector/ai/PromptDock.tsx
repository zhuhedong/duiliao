import { SparklesIcon, CheckIcon, EditIcon } from "../../../components/icons";
import type { PromptInfo } from "./types";

export const DEFAULT_ANALYST_PROMPT =
  "你现在是专业的澳门六合彩分析师，只分析帖文里的实码和生肖，严格过滤所有“發”“猫”“？”“0O”，给出{period}期热度最高的5个生肖以及重点6个号码10个号码";

interface PromptDockProps {
  prompts: PromptInfo[];
  selectedId: string;
  onSelect: (id: string) => void;
  customPrompt: string;
  onCustomPromptChange: (v: string) => void;
  period: string;
}

/** 横向卡片坞：提示词模板一排滑选，自定义模板行内展开编辑 */
export function PromptDock({
  prompts,
  selectedId,
  onSelect,
  customPrompt,
  onCustomPromptChange,
  period,
}: PromptDockProps) {
  const templates = prompts.filter((p) => p.id !== "zodiac_streak_analysis");

  const fillDefault = () => {
    onCustomPromptChange(DEFAULT_ANALYST_PROMPT.replace(/{period}/g, period.trim() || "262"));
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between px-1">
        <span className="flex items-center gap-1.5 text-xs font-bold text-slate-700 dark:text-slate-300">
          <SparklesIcon size={14} className="text-primary" />
          提示词模板
        </span>
        <span className="text-2xs text-slate-400">{templates.length} 个内置 · 横向滑动选择</span>
      </div>

      <div className="flex snap-x snap-mandatory gap-2.5 overflow-x-auto pb-1">
        {templates.map((p) => {
          const active = selectedId === p.id;
          return (
            <button
              key={p.id}
              onClick={() => onSelect(p.id)}
              className={`group w-52 shrink-0 cursor-pointer snap-start rounded-2xl border p-3.5 text-left transition-all ${
                active
                  ? "border-violet-400/45 bg-white/75 shadow-[0_2px_12px_-4px_rgba(139,92,246,0.35),inset_0_1px_0_rgba(255,255,255,0.5)] dark:border-violet-400/30 dark:bg-violet-400/10"
                  : "glass-subtle hover:border-violet-400/40 dark:hover:border-violet-400/30"
              }`}
            >
              <div className="flex items-center justify-between gap-2">
                <span className={`truncate text-xs font-bold ${active ? "text-violet-700 dark:text-violet-200" : "text-slate-800 dark:text-slate-100"}`}>
                  {p.name}
                </span>
                {active ? (
                  <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-violet-500 text-white">
                    <CheckIcon size={11} />
                  </span>
                ) : p.is_default ? (
                  <span className="shrink-0 rounded bg-primary/10 px-1.5 py-0.5 text-2xs font-medium text-primary">推荐</span>
                ) : null}
              </div>
              <p className="mt-1.5 line-clamp-2 text-2xs leading-relaxed text-slate-500 dark:text-slate-400">
                {p.description}
              </p>
            </button>
          );
        })}

        {/* 自定义卡片 */}
        <button
          onClick={() => {
            onSelect("custom");
            if (!customPrompt.trim()) fillDefault();
          }}
          className={`w-52 shrink-0 cursor-pointer snap-start rounded-2xl border border-dashed p-3.5 text-left transition-all ${
            selectedId === "custom"
              ? "border-violet-400/45 bg-white/75 shadow-[0_2px_12px_-4px_rgba(139,92,246,0.35),inset_0_1px_0_rgba(255,255,255,0.5)] dark:border-violet-400/30 dark:bg-violet-400/10"
              : "border-slate-300/80 glass-subtle hover:border-violet-400/40 dark:border-white/15 dark:hover:border-violet-400/30"
          }`}
        >
          <div className="flex items-center justify-between gap-2">
            <span className={`flex items-center gap-1.5 text-xs font-bold ${selectedId === "custom" ? "text-violet-700 dark:text-violet-200" : "text-slate-800 dark:text-slate-100"}`}>
              <EditIcon size={13} />
              自定义提示词
            </span>
            {selectedId === "custom" && (
              <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-violet-500 text-white">
                <CheckIcon size={11} />
              </span>
            )}
          </div>
          <p className="mt-1.5 line-clamp-2 text-2xs leading-relaxed text-slate-500 dark:text-slate-400">
            自己编写指令，对抓取到的当期数据做特定问答
          </p>
        </button>
      </div>

      {/* 自定义编辑器（行内展开） */}
      {selectedId === "custom" && (
        <div className="space-y-2 rounded-2xl glass-subtle p-3.5">
          <div className="flex items-center justify-between">
            <label className="text-2xs font-semibold text-slate-600 dark:text-slate-400">
              自定义 Prompt
            </label>
            <button
              type="button"
              onClick={fillDefault}
              className="cursor-pointer text-2xs font-medium text-primary hover:underline"
            >
              填入预设专家提示词
            </button>
          </div>
          <textarea
            rows={3}
            value={customPrompt}
            onChange={(e) => onCustomPromptChange(e.target.value)}
            placeholder="例如：你现在是专业的澳门六合彩分析师，只分析帖文里的实码和生肖……"
            className="w-full rounded-xl glass-input p-3 text-sm text-slate-800 placeholder:text-slate-400 dark:text-slate-200 dark:placeholder:text-slate-500"
          />
          <p className="text-2xs text-slate-400">
            支持 <code className="font-mono font-semibold text-primary">{"{period}"}</code> 期号变量；指令会与抓取模块内容自动拼接发送。
          </p>
        </div>
      )}
    </div>
  );
}
