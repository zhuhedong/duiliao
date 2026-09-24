import { useMemo, useState } from "react";
import { DatabaseIcon, CloseIcon } from "../../../components/icons";
import type { ScrapedModule, ScrapedSummary } from "./types";

interface DataPanelProps {
  data: ScrapedSummary | null;
  isScraping: boolean;
  error: string | null;
  onScrape: () => void;
}

function StatCell({ label, value, unit, tone }: { label: string; value: string | number; unit?: string; tone?: string }) {
  return (
    <div className="rounded-2xl glass-subtle px-4 py-3">
      <div className="text-2xs text-slate-400">{label}</div>
      <div className={`mt-0.5 text-lg font-bold text-slate-900 dark:text-white ${tone || ""}`}>
        {value}
        {unit && <span className="ml-0.5 text-2xs font-normal text-slate-400">{unit}</span>}
      </div>
    </div>
  );
}

/** 帖文模式的上下文数据面板：抓取状态、模块清单、原始 HTML */
export function DataPanel({ data, isScraping, error, onScrape }: DataPanelProps) {
  const [searchTerm, setSearchTerm] = useState("");
  const [filterType, setFilterType] = useState("all");
  const [selected, setSelected] = useState<ScrapedModule | null>(null);
  const [showRaw, setShowRaw] = useState(false);
  const [rawView, setRawView] = useState<"source" | "render">("source");

  const modules = useMemo(() => {
    return (data?.modules || []).filter((m) => {
      if (filterType !== "all" && m.type !== filterType) return false;
      if (searchTerm && !m.name.toLowerCase().includes(searchTerm.toLowerCase())) return false;
      return true;
    });
  }, [data, filterType, searchTerm]);

  const downloadHtml = () => {
    if (!data?.html) return;
    const blob = new Blob([data.html], { type: "text/html;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "prediction_full_page.html";
    a.click();
    URL.revokeObjectURL(url);
  };

  if (!data) {
    return (
      <div className="flex flex-col items-center gap-3 rounded-3xl border border-dashed border-slate-300/70 p-10 text-center glass-card dark:border-white/10">
        <DatabaseIcon size={32} className="text-slate-400" />
        <p className="text-sm text-slate-600 dark:text-slate-300">
          尚未抓取站外预测数据
        </p>
        <p className="max-w-md text-2xs leading-relaxed text-slate-400">
          点击「开始研判」时会自动抓取并注入；也可以先手动抓取，在这里检查每个预测栏目的内容质量。
        </p>
        <button
          onClick={onScrape}
          disabled={isScraping}
          className="cursor-pointer rounded-xl px-4 py-2 text-xs font-semibold text-slate-700 glass-subtle transition-all hover:bg-violet-500/5 disabled:opacity-50 dark:text-slate-300 dark:hover:bg-violet-400/5"
        >
          {isScraping ? "正在抓取..." : "立即抓取数据"}
        </button>
        {error && <p className="text-xs text-rose-500">{error}</p>}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* 统计带 */}
      <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-4">
        <StatCell label="页面模块" value={data.total_modules} unit="个" />
        <StatCell
          label="核心预测卡片"
          value={`${data.loaded_content_count}/${data.content_modules_count}`}
          tone="text-emerald-600 dark:text-emerald-400"
        />
        <StatCell label="拼装 HTML" value={(data.html_size_bytes / 1024).toFixed(1)} unit="KB" />
        <StatCell label="抓取耗时" value={data.elapsed_sec} unit="秒" tone="text-violet-600 dark:text-violet-400" />
      </div>

      {/* 模块清单 */}
      <div className="space-y-3 rounded-3xl glass-card p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h4 className="text-sm font-bold text-slate-900 dark:text-white">
            注入模块清单 <span className="font-normal text-slate-400">({modules.length})</span>
          </h4>
          <button onClick={downloadHtml} className="cursor-pointer text-2xs font-semibold text-primary hover:underline">
            下载单文件 HTML
          </button>
          <div className="ml-auto flex items-center gap-2">
            <input
              type="text"
              placeholder="按栏目名搜索..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="h-8 w-36 rounded-lg glass-input px-3 text-xs text-slate-800 placeholder:text-slate-400 dark:text-slate-200 dark:placeholder:text-slate-500"
            />
            <select
              value={filterType}
              onChange={(e) => setFilterType(e.target.value)}
              className="h-8 cursor-pointer rounded-lg glass-input px-2 text-xs text-slate-800 dark:text-slate-200"
            >
              <option value="all">全部类型</option>
              <option value="content">核心预测</option>
              <option value="code">注入代码</option>
              <option value="publicCode">广告/跑量</option>
              <option value="system">系统模块</option>
              <option value="style">样式</option>
            </select>
          </div>
        </div>

        <div className="grid max-h-64 grid-cols-1 gap-2 overflow-y-auto pr-1 sm:grid-cols-2 lg:grid-cols-3">
          {modules.map((m) => {
            const hasContent = !!(m.content && m.content.trim().length > 0);
            const isContent = m.type === "content";
            return (
              <button
                key={m.id}
                onClick={() => setSelected(m)}
                className="cursor-pointer rounded-xl glass-subtle p-3 text-left transition-all hover:border-violet-400/40 dark:hover:border-violet-400/30"
              >
                <div className="flex items-start justify-between gap-2">
                  <span className="truncate text-xs font-semibold text-slate-900 dark:text-white">{m.name}</span>
                  <span
                    className={`shrink-0 rounded px-1.5 py-0.5 font-mono text-2xs ${
                      isContent
                        ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                        : "bg-slate-500/10 text-slate-500 dark:text-slate-400"
                    }`}
                  >
                    {m.type}
                  </span>
                </div>
                <div className="mt-1.5 flex items-center justify-between text-2xs text-slate-400">
                  <span>ID: {m.id}</span>
                  <span>{hasContent ? `${(m.content || "").length} 字符` : "无独立文本"}</span>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* 原始 HTML（按需展开） */}
      <div className="rounded-3xl glass-card p-4">
        <button
          onClick={() => setShowRaw((v) => !v)}
          className="flex w-full cursor-pointer items-center justify-between text-left"
        >
          <div>
            <h4 className="text-sm font-bold text-slate-900 dark:text-white">浏览器原始 HTML</h4>
            <p className="mt-0.5 text-2xs text-slate-400">
              Playwright 实开线路后的页面 DOM
              {data.raw_html ? ` · ${(new TextEncoder().encode(data.raw_html).length / 1024).toFixed(1)} KB` : ""}
            </p>
          </div>
          <span className="text-2xs font-medium text-primary">{showRaw ? "收起 ▲" : "展开 ▼"}</span>
        </button>

        {showRaw && (
          <div className="mt-3 space-y-3">
            {data.raw_html_error && !data.raw_html && (
              <div className="rounded-xl border border-amber-400/40 bg-amber-500/10 p-3 text-xs text-amber-700 dark:border-amber-400/25 dark:text-amber-300">
                原始 HTML 没抓到：{data.raw_html_error}。模块清单仍来自接口。
              </div>
            )}
            {data.raw_html && (
              <>
                <div className="flex gap-2">
                  {(["source", "render"] as const).map((v) => (
                    <button
                      key={v}
                      onClick={() => setRawView(v)}
                      className={`cursor-pointer rounded-lg px-3 py-1.5 text-xs font-medium ${
                        rawView === v ? "glow-button border-0" : "glass-subtle text-slate-500 dark:text-slate-400"
                      }`}
                    >
                      {v === "source" ? "源码" : "静态预览"}
                    </button>
                  ))}
                </div>
                {rawView === "source" ? (
                  <pre className="max-h-96 overflow-auto whitespace-pre-wrap rounded-xl border border-white/10 bg-slate-950/90 p-3 font-mono text-xs leading-relaxed text-slate-300">
                    {data.raw_html}
                  </pre>
                ) : (
                  <iframe
                    title="原始页面预览"
                    sandbox=""
                    srcDoc={data.raw_html}
                    className="h-[480px] w-full rounded-xl border border-slate-200/50 bg-white dark:border-white/10"
                  />
                )}
              </>
            )}
          </div>
        )}
      </div>

      {/* 模块详情弹层 */}
      {selected && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4 backdrop-blur-sm"
          onClick={() => setSelected(null)}
        >
          <div
            className="w-full max-w-2xl space-y-3 rounded-3xl glass-panel p-5"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between">
              <div className="min-w-0">
                <span className="truncate text-sm font-bold text-slate-900 dark:text-white">【{selected.name}】</span>
                <span className="ml-2 font-mono text-2xs text-slate-400">
                  {selected.type} · ID {selected.id}
                </span>
              </div>
              <button
                onClick={() => setSelected(null)}
                className="cursor-pointer rounded-lg p-1.5 text-slate-400 hover:bg-slate-500/10 hover:text-slate-600 dark:hover:text-slate-200"
              >
                <CloseIcon size={16} />
              </button>
            </div>
            <pre className="max-h-[60vh] overflow-auto whitespace-pre-wrap rounded-xl border border-white/10 bg-slate-950/90 p-3 font-mono text-xs leading-relaxed text-slate-300">
              {selected.content || "(空)"}
            </pre>
          </div>
        </div>
      )}
    </div>
  );
}
