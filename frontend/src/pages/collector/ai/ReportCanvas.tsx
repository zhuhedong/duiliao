import { useEffect, useRef, useState, type ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import {
  SparklesIcon,
  ActivityIcon,
  CheckBadgeIcon,
  ClockIcon,
  TrashIcon,
  CloseIcon,
} from "../../../components/icons";
import {
  formatReportTime,
  type AIResult,
  type ReportEntry,
} from "./types";

type Accent = "violet" | "fuchsia";

const ACCENT = {
  violet: {
    text: "text-violet-700 dark:text-violet-300",
    solid: "bg-violet-500",
    soft: "bg-violet-500/10",
    border: "border-violet-400/40 dark:border-violet-400/25",
    spinner: "border-violet-500/20 border-t-violet-500",
    headingBar: "bg-gradient-to-b from-violet-500 to-fuchsia-500",
    selection: "selection:bg-violet-500/20",
  },
  fuchsia: {
    text: "text-fuchsia-700 dark:text-fuchsia-300",
    solid: "bg-fuchsia-500",
    soft: "bg-fuchsia-500/10",
    border: "border-fuchsia-400/40 dark:border-fuchsia-400/25",
    spinner: "border-fuchsia-500/20 border-t-fuchsia-500",
    headingBar: "bg-gradient-to-b from-fuchsia-500 to-violet-500",
    selection: "selection:bg-fuchsia-500/20",
  },
} as const;

/** AI 报告的 Markdown 组件映射：让标题、加粗、表格、列表都有结构感 */
function buildMarkdownComponents(accent: Accent) {
  const a = ACCENT[accent];
  return {
    h1: (p: { children?: ReactNode }) => (
      <h1 className="mt-5 mb-3 text-xl font-black tracking-tight text-slate-900 dark:text-white first:mt-0">
        {p.children}
      </h1>
    ),
    h2: (p: { children?: ReactNode }) => (
      <h2 className="mt-6 mb-3 flex items-center gap-2 text-base font-bold text-slate-900 dark:text-white first:mt-0">
        <span className={`h-4 w-1 rounded-full ${a.headingBar}`} />
        {p.children}
      </h2>
    ),
    h3: (p: { children?: ReactNode }) => (
      <h3 className={`mt-4 mb-2 text-sm font-bold ${a.text}`}>{p.children}</h3>
    ),
    p: (p: { children?: ReactNode }) => (
      <p className="my-2 text-sm leading-7 text-slate-800 dark:text-slate-200">{p.children}</p>
    ),
    strong: (p: { children?: ReactNode }) => (
      <strong className={`font-bold ${a.text}`}>{p.children}</strong>
    ),
    ul: (p: { children?: ReactNode }) => (
      <ul className="my-2 list-disc space-y-1.5 pl-5 text-sm leading-6 text-slate-800 marker:text-slate-400 dark:text-slate-200">
        {p.children}
      </ul>
    ),
    ol: (p: { children?: ReactNode }) => (
      <ol className="my-2 list-decimal space-y-1.5 pl-5 text-sm leading-6 text-slate-800 marker:font-bold marker:text-slate-400 dark:text-slate-200">
        {p.children}
      </ol>
    ),
    blockquote: (p: { children?: ReactNode }) => (
      <blockquote className={`my-3 rounded-r-xl border-l-2 ${a.border} ${a.soft} px-4 py-2 text-sm text-slate-700 dark:text-slate-300`}>
        {p.children}
      </blockquote>
    ),
    code: (p: { children?: ReactNode; className?: string }) => (
      <code className="rounded-md bg-slate-500/10 px-1.5 py-0.5 font-mono text-[0.85em] text-slate-800 dark:text-slate-200">
        {p.children}
      </code>
    ),
    pre: (p: { children?: ReactNode }) => (
      <pre className="my-3 overflow-x-auto rounded-xl bg-slate-950/90 p-3.5 text-xs leading-relaxed text-slate-200">
        {p.children}
      </pre>
    ),
    table: (p: { children?: ReactNode }) => (
      <div className="my-3 overflow-x-auto rounded-xl glass-subtle">
        <table className="w-full border-collapse text-xs">{p.children}</table>
      </div>
    ),
    thead: (p: { children?: ReactNode }) => (
      <thead className="border-b border-slate-200/60 dark:border-white/10 bg-white/30 dark:bg-white/5">
        {p.children}
      </thead>
    ),
    th: (p: { children?: ReactNode }) => (
      <th className="whitespace-nowrap px-3 py-2 text-left font-semibold text-slate-600 dark:text-slate-300">
        {p.children}
      </th>
    ),
    td: (p: { children?: ReactNode }) => (
      <td className="border-t border-slate-200/40 dark:border-white/5 px-3 py-2 text-slate-700 dark:text-slate-300">
        {p.children}
      </td>
    ),
    hr: () => <hr className="my-4 border-slate-200/60 dark:border-white/10" />,
  };
}

export interface ReportCanvasProps {
  accent: Accent;
  title: string;
  contextLabel: string;
  result: AIResult | null;
  isAnalyzing: boolean;
  streamStatus: string;
  error: string | null;
  emptyHint: { title: string; subtitle: string };
  loadingHint: string;
  history: ReportEntry[];
  viewing: ReportEntry | null;
  onViewHistory: (entry: ReportEntry | null) => void;
  onClearHistory: () => void;
}

export function ReportCanvas({
  accent,
  title,
  contextLabel,
  result,
  isAnalyzing,
  streamStatus,
  error,
  emptyHint,
  loadingHint,
  history,
  viewing,
  onViewHistory,
  onClearHistory,
}: ReportCanvasProps) {
  const a = ACCENT[accent];
  const components = buildMarkdownComponents(accent);
  const bodyRef = useRef<HTMLDivElement>(null);
  const [copied, setCopied] = useState(false);

  // 流式输出期间自动跟随滚动到底部
  useEffect(() => {
    if (!isAnalyzing || viewing) return;
    const el = bodyRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [result?.analysis, isAnalyzing, viewing]);

  const display = viewing
    ? {
        analysis: viewing.analysis,
        provider: viewing.provider,
        model: viewing.model,
        elapsed_sec: viewing.elapsed_sec,
        usage: viewing.usage,
      }
    : result
      ? {
          analysis: result.analysis,
          provider: result.provider,
          model: result.model,
          elapsed_sec: result.elapsed_sec,
          usage: result.usage,
        }
      : null;

  const copyReport = () => {
    if (!display?.analysis) return;
    navigator.clipboard.writeText(display.analysis);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const usage = display?.usage;
  const hasUsage = !isAnalyzing && usage && Object.keys(usage).length > 0;
  const ModeIcon = accent === "violet" ? SparklesIcon : ActivityIcon;

  return (
    <section className="rounded-3xl glass-card flex min-h-[560px] flex-col overflow-hidden">
      {/* —— 画布头：标题 + 元信息 + 操作 —— */}
      <header className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-slate-200/50 dark:border-white/8 px-5 py-3.5">
        <h3 className="flex items-center gap-2 text-base font-bold text-slate-900 dark:text-white">
          <span
            className={`h-2.5 w-2.5 rounded-full ${
              isAnalyzing ? `${a.solid} animate-pulse` : display ? "bg-emerald-500" : "bg-slate-300 dark:bg-slate-600"
            }`}
          />
          {title}
        </h3>
        <span className={`rounded-md px-2 py-0.5 text-2xs font-semibold ${a.soft} ${a.text}`}>
          {contextLabel}
        </span>
        {viewing && (
          <span className="rounded-md bg-amber-500/10 px-2 py-0.5 text-2xs font-semibold text-amber-600 dark:text-amber-400">
            历史回放 · {formatReportTime(viewing.ts)}
          </span>
        )}
        {display && !viewing && display.elapsed_sec > 0 && (
          <span className="rounded-md glass-subtle px-2 py-0.5 font-mono text-2xs text-slate-500 dark:text-slate-400">
            {display.provider} / {display.model} · {display.elapsed_sec}s
          </span>
        )}
        {hasUsage && (
          <span className="hidden rounded-md glass-subtle px-2 py-0.5 font-mono text-2xs text-slate-400 sm:inline">
            token {usage!.prompt_tokens ?? "-"}→{usage!.completion_tokens ?? "-"} (Σ{usage!.total_tokens ?? "-"})
          </span>
        )}
        <div className="ml-auto flex items-center gap-2">
          {viewing && (
            <button
              onClick={() => onViewHistory(null)}
              className="inline-flex cursor-pointer items-center gap-1 rounded-lg px-2.5 py-1.5 text-xs font-medium text-slate-500 glass-subtle transition-colors hover:text-slate-800 dark:hover:text-slate-200"
            >
              <CloseIcon size={13} />
              返回最新
            </button>
          )}
          {display?.analysis && (
            <button
              onClick={copyReport}
              className="inline-flex cursor-pointer items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium text-slate-600 glass-subtle transition-colors hover:bg-violet-500/5 dark:text-slate-300 dark:hover:bg-violet-400/5"
            >
              {copied && <CheckBadgeIcon size={14} className="text-emerald-500" />}
              {copied ? "已复制" : "复制报告"}
            </button>
          )}
        </div>
      </header>

      {/* —— 历史报告带 —— */}
      {history.length > 0 && (
        <div className="flex items-center gap-2 overflow-x-auto border-b border-slate-200/40 dark:border-white/5 px-5 py-2">
          <span className="flex shrink-0 items-center gap-1 text-2xs font-semibold text-slate-400">
            <ClockIcon size={12} />
            历史
          </span>
          {history.map((h) => {
            const active = viewing?.id === h.id;
            return (
              <button
                key={h.id}
                onClick={() => onViewHistory(active ? null : h)}
                className={`shrink-0 cursor-pointer rounded-full border px-2.5 py-1 text-2xs font-medium transition-all ${
                  active
                    ? `${a.soft} ${a.text} ${a.border}`
                    : "border-transparent glass-subtle text-slate-500 hover:text-slate-800 dark:hover:text-slate-200"
                }`}
                title={`${h.mode === "post" ? "帖文研判" : "连肖研判"} · ${h.provider}/${h.model}`}
              >
                {h.mode === "post" ? "帖文" : "连肖"} · {h.label} · {formatReportTime(h.ts)}
              </button>
            );
          })}
          <button
            onClick={onClearHistory}
            className="ml-auto shrink-0 cursor-pointer rounded-full p-1.5 text-slate-400 transition-colors hover:bg-rose-500/10 hover:text-rose-500"
            title="清空历史报告"
          >
            <TrashIcon size={13} />
          </button>
        </div>
      )}

      {/* —— 错误 —— */}
      {error && (
        <div className="mx-5 mt-4 rounded-xl border border-rose-400/40 bg-rose-500/10 p-4 text-sm text-rose-700 backdrop-blur-md dark:border-rose-400/25 dark:text-rose-300">
          {error}
        </div>
      )}

      {/* —— 画布主体 —— */}
      <div ref={bodyRef} className="max-h-[72vh] flex-1 overflow-y-auto px-6 py-5">
        {isAnalyzing && !display?.analysis ? (
          <div className="flex h-full min-h-[380px] flex-col items-center justify-center space-y-4 text-center">
            <div className="relative">
              <div className={`h-12 w-12 animate-spin rounded-full border-4 ${a.spinner}`} />
              <ModeIcon size={20} className={`absolute inset-0 m-auto ${a.text}`} />
            </div>
            <div className="space-y-1">
              <p className="text-sm font-semibold text-slate-800 dark:text-slate-200">
                {streamStatus || "正在结合上下文数据进行 AI 精算研判..."}
              </p>
              <p className="text-xs text-slate-400">{loadingHint}</p>
            </div>
          </div>
        ) : display?.analysis ? (
          <div className="space-y-3">
            {isAnalyzing && (
              <div className={`flex items-center justify-between rounded-xl px-3.5 py-2 text-xs font-medium glass-subtle ${a.text}`}>
                <span className="flex items-center gap-2">
                  <span className={`h-2 w-2 animate-ping rounded-full ${a.solid}`} />
                  {streamStatus || "大模型正在实时流式推理输出中..."}
                </span>
                <span className="font-mono text-2xs opacity-70">流式输出中</span>
              </div>
            )}
            <article className={`max-w-none ${a.selection}`}>
              <ReactMarkdown remarkPlugins={[remarkGfm]} components={components}>
                {display.analysis}
              </ReactMarkdown>
              {isAnalyzing && (
                <span className={`ml-0.5 inline-block h-4 w-2 animate-pulse align-middle ${a.solid}`} />
              )}
            </article>
          </div>
        ) : (
          <div className="flex h-full min-h-[380px] flex-col items-center justify-center space-y-4 text-center">
            <div className={`flex h-16 w-16 items-center justify-center rounded-3xl ${a.soft}`}>
              <ModeIcon size={30} className={a.text} />
            </div>
            <div className="space-y-1.5">
              <p className="text-sm font-semibold text-slate-600 dark:text-slate-300">{emptyHint.title}</p>
              <p className="mx-auto max-w-sm text-xs leading-relaxed text-slate-400">{emptyHint.subtitle}</p>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
