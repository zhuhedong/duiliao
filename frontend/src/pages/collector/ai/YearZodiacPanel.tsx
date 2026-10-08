import { useState } from "react";
import { ChevronDownIcon, DatabaseIcon } from "../../../components/icons";
import { api } from "../../../lib/api";

interface YearZodiacData {
  ok: boolean;
  lottery: "macau" | "hk";
  year: number;
  total_periods: number;
  periods: {
    period: string;
    date: string;
    balls: string[];
    xiaos: string[];
    has_repeated_xiao: boolean;
    repeated_xiaos: { xiao: string; count: number; positions: string[] }[];
  }[];
}

export function YearZodiacPanel() {
  const [lottery, setLottery] = useState<"macau" | "hk">("macau");
  const [data, setData] = useState<YearZodiacData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copyStatus, setCopyStatus] = useState("");
  const [expanded, setExpanded] = useState(true);
  const json = data ? JSON.stringify(data.periods, null, 2) : "";

  const load = async () => {
    setLoading(true);
    setError(null);
    setCopyStatus("");
    setData(null);
    try {
      const result = await api.get<YearZodiacData>(`/ai/zodiac-year-data?lottery=${lottery}`);
      setData(result);
      setExpanded(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : "获取当年生肖失败，请重试");
    } finally {
      setLoading(false);
    }
  };

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(json);
      setCopyStatus("已复制完整 JSON");
    } catch {
      setCopyStatus("复制失败，请在下方选择文本复制，或下载 JSON");
    }
  };

  const download = () => {
    if (!data) return;
    const url = URL.createObjectURL(new Blob([json], { type: "application/json;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = `${data.lottery}-${data.year}-zodiac.json`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 0);
  };

  return (
    <section className="rounded-3xl glass-card p-4" aria-labelledby="year-zodiac-title">
      <div className="flex flex-wrap items-center gap-3">
        <h3 id="year-zodiac-title" className="flex items-center gap-2 text-sm font-bold text-slate-900 dark:text-white">
          <DatabaseIcon size={16} className="text-violet-500" />
          当年逐期生肖 · 重肖 JSON
        </h3>
        <div className="ml-auto flex flex-wrap items-center gap-2">
          <select
            aria-label="当年生肖彩种"
            value={lottery}
            disabled={loading}
            onChange={(e) => {
              setLottery(e.target.value as "macau" | "hk");
              setData(null);
              setError(null);
              setCopyStatus("");
            }}
            className="h-8 rounded-lg glass-input px-2 text-xs text-slate-800 disabled:opacity-50 dark:text-slate-200"
          >
            <option value="macau">澳门</option>
            <option value="hk">香港</option>
          </select>
          <button
            onClick={load}
            disabled={loading}
            className="cursor-pointer rounded-xl glass-subtle px-3 py-2 text-xs font-semibold text-primary disabled:opacity-50"
          >
            {loading ? "获取中..." : "获取当年生肖"}
          </button>
        </div>
      </div>
      <p className="mt-2 text-xs leading-6 text-slate-500 dark:text-slate-400">
        按北京时间当年查询已同步的开奖记录。生肖数组顺序为正1至正6、特码，保留重复项；同一期出现至少两次的生肖标为重肖，列出次数和位置。
      </p>
      {error && <p role="alert" className="mt-3 text-sm text-rose-600 dark:text-rose-400">{error}</p>}
      {data && (
        <div className="mt-3 space-y-3">
          <div className="flex flex-wrap items-center gap-3 text-xs">
            <span className="font-semibold text-slate-700 dark:text-slate-300">
              {data.year} 年 · {data.lottery === "macau" ? "澳门" : "香港"} · 共 {data.total_periods} 期
              · {data.periods.filter((row) => row.has_repeated_xiao).length} 期有重肖
            </span>
            <button onClick={copy} className="cursor-pointer font-semibold text-primary hover:underline">复制 JSON</button>
            <button onClick={download} className="cursor-pointer font-semibold text-primary hover:underline">下载 JSON</button>
            <button
              onClick={() => setExpanded((value) => !value)}
              aria-expanded={expanded}
              aria-controls="year-zodiac-json"
              className="ml-auto inline-flex cursor-pointer items-center gap-1 text-slate-500"
            >
              {expanded ? "收起" : "查看 JSON"}
              <ChevronDownIcon size={14} className={expanded ? "rotate-180" : ""} />
            </button>
          </div>
          {data.total_periods === 0 && (
            <p className="text-xs text-slate-500">该彩种当年暂无已同步的开奖记录，请先同步开奖数据。</p>
          )}
          {expanded && (
            <div id="year-zodiac-json" className="space-y-2">
              <p className="text-2xs text-slate-500">
                xiaos：全部 7 球生肖；repeated_xiaos：重肖、count 次数、positions 位置；无重肖时为 []。生肖按各期开奖日期换算。
              </p>
              <textarea
                aria-label="当年逐期生肖 JSON 数组"
                readOnly
                spellCheck={false}
                value={json}
                rows={16}
                className="w-full resize-y rounded-xl glass-input p-3 font-mono text-xs leading-6 text-slate-800 dark:text-slate-200"
              />
            </div>
          )}
          <p role="status" className="text-xs text-slate-500">{copyStatus}</p>
        </div>
      )}
    </section>
  );
}
