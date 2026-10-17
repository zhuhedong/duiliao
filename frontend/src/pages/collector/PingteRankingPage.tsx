import { useCallback, useEffect, useMemo, useState } from "react";
import { Alert, AlertDescription } from "../../components/ui/alert";
import { Spinner } from "../../components/ui/spinner";
import { RefreshIcon } from "../../components/icons";
import { ApiError } from "../../lib/api";
import {
  collectorApi,
  LOTTERY_LABEL,
  type Lottery,
  type PingteRankingResult,
} from "../../lib/collector";
import { BOSE_COLORS, WUXING_COLORS } from "../../lib/lotteryAttr";
import { LOTTERIES, PageWorkspace } from "./shared";

type RankingTab = "zodiac" | "tail" | "number" | "bose" | "wuxing";
type SortOption = "count_desc" | "count_asc" | "omission_desc" | "consecutive_desc";

export function PingteRankingPage() {
  const [lottery, setLottery] = useState<Lottery>("macau");
  const [limit, setLimit] = useState<number>(100);
  const [activeTab, setActiveTab] = useState<RankingTab>("zodiac");
  const [sortBy, setSortBy] = useState<SortOption>("count_desc");
  const [keyword, setKeyword] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rankingData, setRankingData] = useState<PingteRankingResult | null>(null);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await collectorApi.getPingteRanking(lottery, limit, "all", sortBy);
      setRankingData(res);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "获取平特排行榜数据失败");
    } finally {
      setLoading(false);
    }
  }, [lottery, limit, sortBy]);

  useEffect(() => {
    void loadData();
  }, [loadData]);

  // Filter lists based on keyword
  const filteredZodiacs = useMemo(() => {
    if (!rankingData?.zodiac_ranking) return [];
    if (!keyword.trim()) return rankingData.zodiac_ranking;
    const kw = keyword.trim().toLowerCase();
    return rankingData.zodiac_ranking.filter(
      (z) =>
        z.name.includes(kw) ||
        z.label.includes(kw) ||
        z.numbers.some((n) => n.includes(kw))
    );
  }, [rankingData, keyword]);

  const filteredTails = useMemo(() => {
    if (!rankingData?.tail_ranking) return [];
    if (!keyword.trim()) return rankingData.tail_ranking;
    const kw = keyword.trim().toLowerCase();
    return rankingData.tail_ranking.filter(
      (t) =>
        t.name.includes(kw) ||
        t.label.includes(kw) ||
        t.numbers.some((n) => n.includes(kw))
    );
  }, [rankingData, keyword]);

  const filteredNumbers = useMemo(() => {
    if (!rankingData?.number_ranking) return [];
    if (!keyword.trim()) return rankingData.number_ranking;
    const kw = keyword.trim().toLowerCase();
    return rankingData.number_ranking.filter(
      (n) =>
        n.number.includes(kw) ||
        n.xiao.includes(kw) ||
        n.bose.includes(kw) ||
        n.wuxing.includes(kw)
    );
  }, [rankingData, keyword]);

  return (
    <PageWorkspace
      summary="基于官方落球顺序 7 码（6 正码 + 1 特码）平特全域统计，涵盖平特生肖、尾数、号码、波色与五行出现频次、出号率与遗漏榜单"
    >
      {/* Top Controls Card */}
      <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-4 shadow-xs mb-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-2">
            {/* Lottery Selector */}
            <div className="flex items-center gap-1 bg-slate-100 dark:bg-slate-800/80 p-1 rounded-xl text-xs font-medium">
              {LOTTERIES.map((l) => (
                <button
                  key={l.value}
                  type="button"
                  onClick={() => setLottery(l.value)}
                  className={`px-3 py-1.5 rounded-lg transition-all ${
                    lottery === l.value
                      ? "bg-white dark:bg-slate-700 text-sky-600 dark:text-sky-400 font-semibold shadow-xs"
                      : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200"
                  }`}
                >
                  {l.label}
                </button>
              ))}
            </div>

            {/* Sample Periods Selector */}
            <div className="flex items-center gap-1 bg-slate-100 dark:bg-slate-800/80 p-1 rounded-xl text-xs">
              {[30, 50, 100, 200, 500].map((lim) => (
                <button
                  key={lim}
                  type="button"
                  onClick={() => setLimit(lim)}
                  className={`px-2.5 py-1.5 rounded-lg transition-all ${
                    limit === lim
                      ? "bg-white dark:bg-slate-700 text-slate-900 dark:text-white font-semibold shadow-xs"
                      : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200"
                  }`}
                >
                  {lim}期
                </button>
              ))}
            </div>

            {/* Sort Order Selector */}
            <div className="flex items-center gap-1 bg-slate-100 dark:bg-slate-800/80 p-1 rounded-xl text-xs">
              {[
                { value: "count_desc", label: "🔥 热号榜" },
                { value: "count_asc", label: "❄️ 冷号榜" },
                { value: "omission_desc", label: "⚡ 遗漏榜" },
                { value: "consecutive_desc", label: "👑 连出王" },
              ].map((s) => (
                <button
                  key={s.value}
                  type="button"
                  onClick={() => setSortBy(s.value as SortOption)}
                  className={`px-3 py-1.5 rounded-lg transition-all ${
                    sortBy === s.value
                      ? "bg-sky-500 text-white font-semibold shadow-xs"
                      : "text-slate-600 dark:text-slate-400 hover:text-slate-900"
                  }`}
                >
                  {s.label}
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            {/* Search Input */}
            <input
              type="text"
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
              placeholder="搜索号码/生肖..."
              className="px-3 py-1.5 text-xs bg-slate-100 dark:bg-slate-800 border border-transparent rounded-xl focus:outline-none focus:border-sky-500 w-36 transition-all"
            />

            {/* Refresh Button */}
            <button
              type="button"
              onClick={() => void loadData()}
              disabled={loading}
              className="flex items-center gap-1.5 px-3.5 py-2 rounded-xl text-xs font-semibold bg-sky-500 hover:bg-sky-600 text-white transition-colors disabled:opacity-50 cursor-pointer shadow-xs"
            >
              <RefreshIcon size={14} className={loading ? "animate-spin" : ""} />
              <span>刷新榜单</span>
            </button>
          </div>
        </div>

        {/* Tab Bar */}
        <div className="flex items-center gap-2 mt-4 border-t border-slate-100 dark:border-slate-800/80 pt-3 overflow-x-auto">
          {[
            { key: "zodiac", label: "平特生肖榜 (12肖)" },
            { key: "tail", label: "平特尾数榜 (0-9尾)" },
            { key: "number", label: "平特号码榜 (01-49)" },
            { key: "bose", label: "平特波色榜" },
            { key: "wuxing", label: "平特五行榜" },
          ].map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setActiveTab(tab.key as RankingTab)}
              className={`px-4 py-2 rounded-xl text-xs font-medium transition-all ${
                activeTab === tab.key
                  ? "bg-slate-900 text-white dark:bg-white dark:text-slate-900 font-bold shadow-xs"
                  : "bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700"
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      {error && (
        <Alert variant="error" className="mb-4">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {/* Overview Stat Ribbon */}
      {rankingData && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
          <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-3 shadow-xs">
            <div className="text-[11px] text-slate-500 dark:text-slate-400">统计彩种 / 样本期数</div>
            <div className="text-base font-bold text-slate-800 dark:text-slate-100 mt-1">
              {LOTTERY_LABEL[rankingData.lottery] || rankingData.lottery} · {rankingData.sample_periods} 期
            </div>
          </div>
          <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-3 shadow-xs">
            <div className="text-[11px] text-slate-500 dark:text-slate-400">统计期号区间</div>
            <div className="text-base font-bold text-sky-600 dark:text-sky-400 mt-1 font-mono">
              {rankingData.earliest_period} ~ {rankingData.latest_period}
            </div>
          </div>
          <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-3 shadow-xs">
            <div className="text-[11px] text-slate-500 dark:text-slate-400">最热平特生肖</div>
            <div className="text-base font-bold text-rose-500 mt-1">
              {rankingData.zodiac_ranking[0]?.label} ({rankingData.zodiac_ranking[0]?.count}次 · {rankingData.zodiac_ranking[0]?.frequency}%)
            </div>
          </div>
          <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl p-3 shadow-xs">
            <div className="text-[11px] text-slate-500 dark:text-slate-400">最热平特尾数</div>
            <div className="text-base font-bold text-amber-500 mt-1">
              {rankingData.tail_ranking[0]?.label} ({rankingData.tail_ranking[0]?.count}次 · {rankingData.tail_ranking[0]?.frequency}%)
            </div>
          </div>
        </div>
      )}

      {loading && !rankingData ? (
        <div className="flex items-center justify-center p-16">
          <Spinner className="w-8 h-8 text-sky-500" />
        </div>
      ) : (
        <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl overflow-hidden shadow-xs">
          {/* TAB 1: 平特生肖榜 */}
          {activeTab === "zodiac" && (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs border-collapse">
                <thead>
                  <tr className="bg-slate-50 dark:bg-slate-800/70 border-b border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-300 font-semibold">
                    <th className="py-3 px-4 w-16 text-center">排名</th>
                    <th className="py-3 px-4 w-28">平特生肖</th>
                    <th className="py-3 px-4 w-28 text-center">总出现次数</th>
                    <th className="py-3 px-4 w-28 text-center">开出期数</th>
                    <th className="py-3 px-4 min-w-[160px]">出号率 (热度)</th>
                    <th className="py-3 px-4 w-24 text-center">当前遗漏</th>
                    <th className="py-3 px-4 w-24 text-center">最大遗漏</th>
                    <th className="py-3 px-4 w-24 text-center">最大连出</th>
                    <th className="py-3 px-4 min-w-[200px]">包含号码(2026)</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {filteredZodiacs.map((z, idx) => {
                    const rankMedal =
                      idx === 0
                        ? "🥇"
                        : idx === 1
                        ? "🥈"
                        : idx === 2
                        ? "🥉"
                        : `#${idx + 1}`;

                    return (
                      <tr
                        key={z.name}
                        className="hover:bg-slate-50/60 dark:hover:bg-slate-800/30 transition-colors"
                      >
                        <td className="py-3 px-4 text-center font-bold text-sm">
                          {rankMedal}
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-2">
                            <span className="w-8 h-8 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-800 dark:text-slate-100 font-bold flex items-center justify-center text-sm shadow-xs border border-slate-200/60 dark:border-slate-700">
                              {z.name}
                            </span>
                            <span className="font-semibold text-slate-800 dark:text-slate-200">
                              {z.label}
                            </span>
                            {z.is_hot && (
                              <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-rose-500/15 text-rose-600 dark:text-rose-400">
                                热
                              </span>
                            )}
                            {z.is_cold && (
                              <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-blue-500/15 text-blue-600 dark:text-blue-400">
                                冷
                              </span>
                            )}
                          </div>
                        </td>
                        <td className="py-3 px-4 text-center font-bold text-sm text-sky-600 dark:text-sky-400 font-mono">
                          {z.count}
                        </td>
                        <td className="py-3 px-4 text-center text-slate-600 dark:text-slate-300 font-mono">
                          {z.periods_count} 期
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-3">
                            <div className="flex-1 bg-slate-100 dark:bg-slate-800 h-2 rounded-full overflow-hidden">
                              <div
                                className="bg-sky-500 h-full rounded-full transition-all"
                                style={{ width: `${Math.min(100, z.frequency)}%` }}
                              />
                            </div>
                            <span className="w-12 text-right font-mono text-[11px] font-semibold text-slate-700 dark:text-slate-300">
                              {z.frequency}%
                            </span>
                          </div>
                        </td>
                        <td className="py-3 px-4 text-center font-mono">
                          <span
                            className={`px-2 py-0.5 rounded text-xs font-semibold ${
                              z.current_omission === 0
                                ? "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400"
                                : z.current_omission > 5
                                ? "bg-amber-500/15 text-amber-600 dark:text-amber-400"
                                : "text-slate-500"
                            }`}
                          >
                            {z.current_omission === 0 ? "本期开出" : `${z.current_omission}期`}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-center text-slate-500 font-mono">
                          {z.max_omission} 期
                        </td>
                        <td className="py-3 px-4 text-center text-slate-600 dark:text-slate-300 font-semibold font-mono">
                          {z.max_consecutive} 期
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex flex-wrap items-center gap-1">
                            {z.numbers.map((num) => (
                              <span
                                key={num}
                                className="px-1.5 py-0.5 rounded font-mono text-[11px] bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 font-medium"
                              >
                                {num}
                              </span>
                            ))}
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {/* TAB 2: 平特尾数榜 */}
          {activeTab === "tail" && (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs border-collapse">
                <thead>
                  <tr className="bg-slate-50 dark:bg-slate-800/70 border-b border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-300 font-semibold">
                    <th className="py-3 px-4 w-16 text-center">排名</th>
                    <th className="py-3 px-4 w-28">平特尾数</th>
                    <th className="py-3 px-4 w-28 text-center">总开出球数</th>
                    <th className="py-3 px-4 w-28 text-center">开出期数</th>
                    <th className="py-3 px-4 min-w-[160px]">出号率</th>
                    <th className="py-3 px-4 w-24 text-center">当前遗漏</th>
                    <th className="py-3 px-4 w-24 text-center">最大遗漏</th>
                    <th className="py-3 px-4 w-24 text-center">最大连出</th>
                    <th className="py-3 px-4 min-w-[200px]">包含号码</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {filteredTails.map((t, idx) => {
                    const rankMedal =
                      idx === 0
                        ? "🥇"
                        : idx === 1
                        ? "🥈"
                        : idx === 2
                        ? "🥉"
                        : `#${idx + 1}`;

                    return (
                      <tr
                        key={t.name}
                        className="hover:bg-slate-50/60 dark:hover:bg-slate-800/30 transition-colors"
                      >
                        <td className="py-3 px-4 text-center font-bold text-sm">
                          {rankMedal}
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-2">
                            <span className="w-7 h-7 rounded-lg bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 font-bold flex items-center justify-center text-xs font-mono">
                              {t.name}
                            </span>
                            <span className="font-semibold text-slate-800 dark:text-slate-200">
                              {t.label}
                            </span>
                            {t.is_hot && (
                              <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-rose-500/15 text-rose-600 dark:text-rose-400">
                                热
                              </span>
                            )}
                            {t.is_cold && (
                              <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-blue-500/15 text-blue-600 dark:text-blue-400">
                                冷
                              </span>
                            )}
                          </div>
                        </td>
                        <td className="py-3 px-4 text-center font-bold text-sm text-sky-600 dark:text-sky-400 font-mono">
                          {t.count}
                        </td>
                        <td className="py-3 px-4 text-center text-slate-600 dark:text-slate-300 font-mono">
                          {t.periods_count} 期
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-3">
                            <div className="flex-1 bg-slate-100 dark:bg-slate-800 h-2 rounded-full overflow-hidden">
                              <div
                                className="bg-indigo-500 h-full rounded-full transition-all"
                                style={{ width: `${Math.min(100, t.frequency)}%` }}
                              />
                            </div>
                            <span className="w-12 text-right font-mono text-[11px] font-semibold text-slate-700 dark:text-slate-300">
                              {t.frequency}%
                            </span>
                          </div>
                        </td>
                        <td className="py-3 px-4 text-center font-mono">
                          <span
                            className={`px-2 py-0.5 rounded text-xs font-semibold ${
                              t.current_omission === 0
                                ? "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400"
                                : t.current_omission > 5
                                ? "bg-amber-500/15 text-amber-600 dark:text-amber-400"
                                : "text-slate-500"
                            }`}
                          >
                            {t.current_omission === 0 ? "本期开出" : `${t.current_omission}期`}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-center text-slate-500 font-mono">
                          {t.max_omission} 期
                        </td>
                        <td className="py-3 px-4 text-center text-slate-600 dark:text-slate-300 font-semibold font-mono">
                          {t.max_consecutive} 期
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex flex-wrap items-center gap-1 font-mono">
                            {t.numbers.map((n) => (
                              <span
                                key={n}
                                className="px-1.5 py-0.5 rounded text-[11px] bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 font-medium"
                              >
                                {n}
                              </span>
                            ))}
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {/* TAB 3: 平特号码榜 */}
          {activeTab === "number" && (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs border-collapse">
                <thead>
                  <tr className="bg-slate-50 dark:bg-slate-800/70 border-b border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-300 font-semibold">
                    <th className="py-3 px-4 w-16 text-center">排名</th>
                    <th className="py-3 px-4 w-24">号码</th>
                    <th className="py-3 px-4 w-28 text-center">平特总次数</th>
                    <th className="py-3 px-4 w-24 text-center">正码次数</th>
                    <th className="py-3 px-4 w-24 text-center">特码次数</th>
                    <th className="py-3 px-4 min-w-[140px]">出号率</th>
                    <th className="py-3 px-4 w-24 text-center">当前遗漏</th>
                    <th className="py-3 px-4 w-24 text-center">最大遗漏</th>
                    <th className="py-3 px-4 w-24 text-center">最大连出</th>
                    <th className="py-3 px-4 w-28 text-center">生肖 / 五行</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {filteredNumbers.map((n, idx) => {
                    const bColor = BOSE_COLORS[n.bose] || { bg: "#64748b" };

                    return (
                      <tr
                        key={n.number}
                        className="hover:bg-slate-50/60 dark:hover:bg-slate-800/30 transition-colors"
                      >
                        <td className="py-3 px-4 text-center font-bold font-mono">
                          #{idx + 1}
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-2">
                            <div
                              className="w-7 h-7 rounded-full flex items-center justify-center font-bold font-mono text-xs text-white shadow-xs"
                              style={{ backgroundColor: bColor.bg }}
                            >
                              {n.number}
                            </div>
                            {n.is_hot && (
                              <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-rose-500/15 text-rose-600 dark:text-rose-400">
                                热
                              </span>
                            )}
                            {n.is_cold && (
                              <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-blue-500/15 text-blue-600 dark:text-blue-400">
                                冷
                              </span>
                            )}
                          </div>
                        </td>
                        <td className="py-3 px-4 text-center font-bold text-sm text-sky-600 dark:text-sky-400 font-mono">
                          {n.count}
                        </td>
                        <td className="py-3 px-4 text-center text-slate-600 dark:text-slate-300 font-mono">
                          {n.ping_count}
                        </td>
                        <td className="py-3 px-4 text-center text-amber-600 dark:text-amber-400 font-bold font-mono">
                          {n.tema_count}
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-3">
                            <div className="flex-1 bg-slate-100 dark:bg-slate-800 h-2 rounded-full overflow-hidden">
                              <div
                                className="bg-sky-500 h-full rounded-full transition-all"
                                style={{ width: `${Math.min(100, n.frequency * 2)}%` }}
                              />
                            </div>
                            <span className="w-12 text-right font-mono text-[11px] font-semibold text-slate-700 dark:text-slate-300">
                              {n.frequency}%
                            </span>
                          </div>
                        </td>
                        <td className="py-3 px-4 text-center font-mono">
                          <span
                            className={`px-2 py-0.5 rounded text-xs font-semibold ${
                              n.current_omission === 0
                                ? "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400"
                                : n.current_omission > 15
                                ? "bg-amber-500/15 text-amber-600 dark:text-amber-400"
                                : "text-slate-500"
                            }`}
                          >
                            {n.current_omission === 0 ? "本期开出" : `${n.current_omission}期`}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-center text-slate-500 font-mono">
                          {n.max_omission} 期
                        </td>
                        <td className="py-3 px-4 text-center text-slate-600 dark:text-slate-300 font-semibold font-mono">
                          {n.max_consecutive} 期
                        </td>
                        <td className="py-3 px-4 text-center">
                          <span className="font-semibold text-slate-700 dark:text-slate-300">
                            {n.xiao}肖
                          </span>{" "}
                          <span className="text-slate-400">·</span>{" "}
                          <span className="text-slate-500 dark:text-slate-400">
                            {n.wuxing || "—"}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}

          {/* TAB 4: 平特波色榜 */}
          {activeTab === "bose" && rankingData && (
            <div className="p-4 grid grid-cols-1 md:grid-cols-3 gap-4">
              {rankingData.bose_ranking.map((b) => {
                const cfg = BOSE_COLORS[b.name] || { bg: "#64748b" };
                return (
                  <div
                    key={b.name}
                    className="border border-slate-200 dark:border-slate-800 rounded-xl p-4 bg-slate-50/50 dark:bg-slate-800/30"
                  >
                    <div className="flex items-center justify-between mb-3">
                      <div className="flex items-center gap-2">
                        <span
                          className="w-4 h-4 rounded-full"
                          style={{ backgroundColor: cfg.bg }}
                        />
                        <span className="font-bold text-base text-slate-800 dark:text-slate-100">
                          {b.label}
                        </span>
                      </div>
                      <span className="font-mono text-sm font-bold text-sky-600 dark:text-sky-400">
                        {b.percentage}%
                      </span>
                    </div>

                    <div className="space-y-2 text-xs">
                      <div className="flex justify-between text-slate-600 dark:text-slate-300">
                        <span>总出现球数:</span>
                        <span className="font-bold font-mono">{b.count} 个</span>
                      </div>
                      <div className="flex justify-between text-slate-600 dark:text-slate-300">
                        <span>出现期数:</span>
                        <span className="font-bold font-mono">{b.periods_count} 期</span>
                      </div>
                      <div className="flex justify-between text-slate-600 dark:text-slate-300">
                        <span>当前遗漏:</span>
                        <span className="font-bold font-mono">{b.current_omission} 期</span>
                      </div>
                      <div className="flex justify-between text-slate-600 dark:text-slate-300">
                        <span>最大连出:</span>
                        <span className="font-bold font-mono">{b.max_consecutive} 期</span>
                      </div>
                    </div>

                    <div className="mt-4 pt-3 border-t border-slate-200/60 dark:border-slate-700/60">
                      <div className="text-[11px] text-slate-500 mb-1.5 font-medium">包含号码:</div>
                      <div className="flex flex-wrap gap-1 font-mono text-[11px]">
                        {b.numbers.map((n) => (
                          <span
                            key={n}
                            className="px-1.5 py-0.5 rounded bg-white dark:bg-slate-700 text-slate-700 dark:text-slate-200 shadow-2xs"
                          >
                            {n}
                          </span>
                        ))}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {/* TAB 5: 平特五行榜 */}
          {activeTab === "wuxing" && rankingData && (
            <div className="p-4 grid grid-cols-1 md:grid-cols-5 gap-3">
              {rankingData.wuxing_ranking.map((w) => {
                const color = WUXING_COLORS[w.name] || "#64748b";
                return (
                  <div
                    key={w.name}
                    className="border border-slate-200 dark:border-slate-800 rounded-xl p-3.5 bg-slate-50/50 dark:bg-slate-800/30"
                  >
                    <div className="flex items-center justify-between mb-2">
                      <span
                        className="w-6 h-6 rounded-md font-bold text-xs text-white flex items-center justify-center shadow-xs"
                        style={{ backgroundColor: color }}
                      >
                        {w.name}
                      </span>
                      <span className="font-mono text-xs font-bold text-sky-600 dark:text-sky-400">
                        {w.percentage}%
                      </span>
                    </div>

                    <div className="space-y-1.5 text-[11px]">
                      <div className="flex justify-between text-slate-600 dark:text-slate-300">
                        <span>总球数:</span>
                        <span className="font-bold font-mono">{w.count}</span>
                      </div>
                      <div className="flex justify-between text-slate-600 dark:text-slate-300">
                        <span>出现期数:</span>
                        <span className="font-bold font-mono">{w.periods_count}期</span>
                      </div>
                      <div className="flex justify-between text-slate-600 dark:text-slate-300">
                        <span>当前遗漏:</span>
                        <span className="font-bold font-mono">{w.current_omission}期</span>
                      </div>
                    </div>

                    <div className="mt-3 pt-2.5 border-t border-slate-200/60 dark:border-slate-700/60">
                      <div className="flex flex-wrap gap-1 font-mono text-[10px]">
                        {w.numbers.map((n) => (
                          <span
                            key={n}
                            className="px-1 py-0.5 rounded bg-white dark:bg-slate-700 text-slate-700 dark:text-slate-200"
                          >
                            {n}
                          </span>
                        ))}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </PageWorkspace>
  );
}
