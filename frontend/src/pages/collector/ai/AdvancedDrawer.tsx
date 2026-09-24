import { useEffect, useState } from "react";
import type { AISettings } from "../../../lib/api";
import { CheckBadgeIcon, CloseIcon, SettingsIcon } from "../../../components/icons";

interface AdvancedDrawerProps {
  open: boolean;
  onClose: () => void;
  provider: "openai" | "gemini" | "anthropic";
  aiSettings: AISettings | null;
  model: string;
  onModelChange: (v: string) => void;
  formatMode: "modules_summary" | "raw_html";
  onFormatModeChange: (v: "modules_summary" | "raw_html") => void;
  temperature: number;
  onTemperatureChange: (v: number) => void;
  period: string;
  promptPreview: string;
  dataPreview: string;
  dataReadyLabel: string;
  onGoSettings: () => void;
}

const PROVIDER_LABEL: Record<string, string> = {
  openai: "OpenAI/DeepSeek",
  gemini: "Google Gemini",
  anthropic: "Anthropic Claude",
};

/** 右侧高级设置抽屉：把低频参数从主流程里收起来 */
export function AdvancedDrawer({
  open,
  onClose,
  provider,
  aiSettings,
  model,
  onModelChange,
  formatMode,
  onFormatModeChange,
  temperature,
  onTemperatureChange,
  period,
  promptPreview,
  dataPreview,
  dataReadyLabel,
  onGoSettings,
}: AdvancedDrawerProps) {
  const [showPayload, setShowPayload] = useState(false);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50" role="dialog" aria-modal="true">
      <div className="absolute inset-0 bg-slate-950/40 backdrop-blur-sm" onClick={onClose} />
      <aside className="absolute inset-y-0 right-0 flex w-full max-w-md flex-col gap-4 overflow-y-auto glass-panel p-5 shadow-2xl">
        <div className="flex items-center justify-between">
          <h3 className="flex items-center gap-2 text-base font-bold text-slate-900 dark:text-white">
            <SettingsIcon size={17} className="text-primary" />
            高级研判参数
          </h3>
          <button
            onClick={onClose}
            className="cursor-pointer rounded-lg p-1.5 text-slate-400 hover:bg-slate-500/10 hover:text-slate-600 dark:hover:text-slate-200"
          >
            <CloseIcon size={17} />
          </button>
        </div>

        {/* 密钥状态 */}
        {aiSettings && (
          <div className="flex items-center justify-between rounded-2xl glass-subtle px-3.5 py-2.5 text-2xs">
            <div className="flex items-center gap-1.5">
              <span className="text-slate-400">{PROVIDER_LABEL[provider]} 密钥:</span>
              {aiSettings[provider]?.is_configured ? (
                <span className="flex items-center gap-1 font-medium text-emerald-600 dark:text-emerald-400">
                  <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
                  已配置 ({aiSettings[provider]?.api_key})
                </span>
              ) : (
                <span className="flex items-center gap-1 font-medium text-amber-500">
                  <span className="h-1.5 w-1.5 rounded-full bg-amber-500" />
                  未配置
                </span>
              )}
            </div>
            <button
              onClick={onGoSettings}
              className="cursor-pointer font-medium text-primary hover:underline"
            >
              去配置 →
            </button>
          </div>
        )}

        {/* 模型覆盖 */}
        <div className="space-y-1.5">
          <div className="flex items-center justify-between">
            <label className="text-xs font-semibold text-slate-700 dark:text-slate-300">
              模型名称覆盖 (Model Override)
            </label>
            {aiSettings?.[provider]?.model && (
              <span className="text-2xs text-slate-400">
                系统: <strong className="font-mono text-primary">{aiSettings[provider].model}</strong>
              </span>
            )}
          </div>
          <input
            type="text"
            value={model}
            onChange={(e) => onModelChange(e.target.value)}
            placeholder={
              aiSettings?.[provider]?.model
                ? `留空使用系统配置: ${aiSettings[provider].model}`
                : provider === "openai"
                  ? "默认: deepseek-chat (或 qwen-plus, gpt-4o)"
                  : provider === "gemini"
                    ? "默认: gemini-2.5-flash"
                    : "默认: claude-3-5-sonnet"
            }
            className="h-9 w-full rounded-xl glass-input px-3 text-xs text-slate-800 placeholder:text-slate-400 dark:text-slate-200 dark:placeholder:text-slate-500"
          />
          <div className="flex items-center justify-between text-2xs text-slate-400">
            <span>
              当前生效:{" "}
              <strong className="font-mono font-medium text-emerald-600 dark:text-emerald-400">
                {model.trim() || aiSettings?.[provider]?.model || "默认模型"}
              </strong>
            </span>
            {model.trim() && (
              <button
                onClick={() => onModelChange("")}
                className="cursor-pointer text-primary hover:underline"
              >
                清除覆盖
              </button>
            )}
          </div>
        </div>

        {/* 上下文模式 */}
        <div className="space-y-1.5">
          <label className="text-xs font-semibold text-slate-700 dark:text-slate-300">
            数据上下文模式 (Context Mode)
          </label>
          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={() => onFormatModeChange("modules_summary")}
              className={`cursor-pointer rounded-xl border p-2.5 text-left text-xs transition-all ${
                formatMode === "modules_summary"
                  ? "border-violet-400/45 bg-white/75 font-semibold text-violet-700 dark:border-violet-400/30 dark:bg-violet-400/10 dark:text-violet-200"
                  : "glass-subtle text-slate-600 dark:text-slate-400"
              }`}
            >
              <div>🚀 智能去噪 (推荐)</div>
              <div className="mt-0.5 text-2xs font-normal text-slate-400">压缩至 12KB 核心预测</div>
            </button>
            <button
              onClick={() => onFormatModeChange("raw_html")}
              className={`cursor-pointer rounded-xl border p-2.5 text-left text-xs transition-all ${
                formatMode === "raw_html"
                  ? "border-violet-400/45 bg-white/75 font-semibold text-violet-700 dark:border-violet-400/30 dark:bg-violet-400/10 dark:text-violet-200"
                  : "glass-subtle text-slate-600 dark:text-slate-400"
              }`}
            >
              <div>🌐 原始全量 HTML</div>
              <div className="mt-0.5 text-2xs font-normal text-slate-400">320KB 完整代码结构</div>
            </button>
          </div>
        </div>

        {/* 温度 */}
        <div className="space-y-1.5">
          <div className="flex justify-between text-xs font-semibold text-slate-700 dark:text-slate-300">
            <span>生成发散度 (Temperature)</span>
            <span>{temperature}</span>
          </div>
          <input
            type="range"
            min="0"
            max="1.5"
            step="0.1"
            value={temperature}
            onChange={(e) => onTemperatureChange(parseFloat(e.target.value))}
            className="w-full accent-primary"
          />
        </div>

        {/* 组合载荷预览 */}
        <div className="space-y-2 rounded-2xl glass-subtle p-3.5">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-800 dark:text-slate-200">
              📦 组合发送内容
              <span className="ml-1.5 rounded bg-emerald-500/10 px-1.5 py-0.5 text-2xs font-medium text-emerald-600 dark:text-emerald-400">
                自动打包
              </span>
            </span>
            <button
              onClick={() => setShowPayload((v) => !v)}
              className="cursor-pointer text-2xs font-medium text-primary hover:underline"
            >
              {showPayload ? "收起 ▲" : "预览完整载荷 ▼"}
            </button>
          </div>
          <p className="text-2xs leading-relaxed text-slate-500 dark:text-slate-400">
            提示词指令与抓取数据将合并为同一请求上下文发送给大模型。
          </p>

          {showPayload && (
            <div className="space-y-3 border-t border-slate-200/50 pt-3 dark:border-white/8">
              <div>
                <div className="mb-1 flex items-center justify-between text-2xs font-semibold text-slate-600 dark:text-slate-400">
                  <span>1. 提示词指令</span>
                  <span className="text-slate-400">第 {period || "262"} 期</span>
                </div>
                <div className="max-h-32 overflow-y-auto whitespace-pre-wrap rounded-xl glass-subtle p-2.5 font-mono text-2xs text-slate-700 dark:text-slate-300">
                  {promptPreview}
                </div>
              </div>
              <div>
                <div className="mb-1 flex items-center justify-between text-2xs font-semibold text-slate-600 dark:text-slate-400">
                  <span>2. 注入数据</span>
                  <span className="text-slate-400">{dataReadyLabel}</span>
                </div>
                <div className="max-h-36 overflow-y-auto whitespace-pre-wrap rounded-xl glass-subtle p-2.5 font-mono text-2xs text-slate-700 dark:text-slate-300">
                  {dataPreview}
                </div>
              </div>
              <div className="flex items-center gap-1.5 rounded-lg border border-emerald-400/40 bg-emerald-500/10 p-2 text-2xs text-emerald-700 dark:border-emerald-400/25 dark:text-emerald-300">
                <CheckBadgeIcon size={13} className="shrink-0 text-emerald-500" />
                提示词与数据已组合为同一请求载荷。
              </div>
            </div>
          )}
        </div>
      </aside>
    </div>
  );
}
