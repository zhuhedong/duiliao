import { useCallback, useEffect, useMemo, useState } from "react";
import { Alert, AlertDescription } from "../../components/ui/alert";
import { Button } from "../../components/ui/button";
import { Spinner } from "../../components/ui/spinner";
import { RefreshIcon, SearchIcon } from "../../components/icons";
import { ApiError } from "../../lib/api";
import {
  collectorApi,
  LOTTERY_LABEL,
  type Lottery,
  type PingteRankingResult,
} from "../../lib/collector";
import { BOSE_COLORS, WUXING_COLORS } from "../../lib/lotteryAttr";
import {
  LOTTERIES,
  PageWorkspace,
  SegmentedTabs,
  TableContainer,
  tableThClass,
  tableTdClass,
  tableRowClass,
} from "./shared";

type RankingTab = "zodiac" | "tail" | "number" | "bose" | "wuxing";
type SortOption =
  | "count_desc"
  | "count_asc"
  | "current_consecutive_desc"
  | "omission_desc"
  | "consecutive_desc";

export function PingteRankingPage() {
  const [lottery, setLottery] = useState<Lottery>("macau");
  const [limit, setLimit] = useState<number>(0); // 0 = 当年全部期数
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

  const filteredZodiacs = useMemo(() => {
    if (!rankingData?.zodiac_ranking) return [];
    if (!keyword.trim()) return rankingData.zodiac_ranking;
    const kw = keyword.trim().toLowerCase();
    return rankingData.zodiac_ranking.filter(
      (z) =>
        z.name.includes(kw) ||
        z.label.includes(kw) ||
        z.numbers.some((n) => n.includes(kw)),
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
        t.numbers.some((n) => n.includes(kw)),
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
        n.wuxing.includes(kw),
    );
  }, [rankingData, keyword]);

  const topStreakZodiac = useMemo(() => {
    if (!rankingData?.zodiac_ranking?.length) return null;
    const sorted = [...rankingData.zodiac_ranking].sort(
      (a, b) => b.current_consecutive - a.current_consecutive,
    );
    return sorted[0]?.current_consecutive > 0 ? sorted[0] : null;
  }, [rankingData]);

  return (
    <PageWorkspace
      summary="基于官方落球 7 码（6 正码 + 1 特码）平特全域统计；默认统计当年全部开奖期，支持切换窗口与热冷连开排序。"
      actions={
        <Button
          type="button"
          size="sm"
          onClick={() => void loadData()}
          disabled={loading}
        >
          <RefreshIcon size={14} className={loading ? "animate-spin" : ""} />
          <span>刷新榜单</span>
        </Button>
      }
    >
      {/* Overview Stat Ribbon */}
      {rankingData && (
        <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
          <div className="bento-card rounded-2xl p-4">
            <div className="text-[11px] font-medium text-slate-500 dark:text-slate-400">
              统计彩种 / 样本期数
            </div>
            <div className="text-base font-bold text-slate-900 dark:text-white mt-1 tabular-nums">
              {LOTTERY_LABEL[rankingData.lottery] || rankingData.lottery} ·{" "}
              {rankingData.sample_scope === "year" || limit === 0
                ? `当年 ${rankingData.sample_periods} 期`
                : `${rankingData.sample_periods} 期`}
            </div>
          </div>

          <div className="bento-card rounded-2xl p-4">
            <div className="text-[11px] font-medium text-slate-500 dark:text-slate-400">
              统计期号区间
            </div>
            <div className="text-base font-bold text-indigo-600 dark:text-indigo-400 mt-1 font-mono tabular-nums">
              {rankingData.earliest_period} ~ {rankingData.latest_period}
            </div>
          </div>

          <div className="bento-card rounded-2xl p-4">
            <div className="text-[11px] font-medium text-slate-500 dark:text-slate-400">
              最热平特生肖
            </div>
            <div className="text-base font-bold text-rose-600 dark:text-rose-400 mt-1 tabular-nums">
              {rankingData.zodiac_ranking[0]?.label} ({rankingData.zodiac_ranking[0]?.count}次 ·{" "}
              {rankingData.zodiac_ranking[0]?.frequency}%)
            </div>
          </div>

          <div className="bento-card rounded-2xl p-4">
            <div className="text-[11px] font-medium text-slate-500 dark:text-slate-400">
              最热平特尾数
            </div>
            <div className="text-base font-bold text-amber-600 dark:text-amber-400 mt-1 tabular-nums">
              {rankingData.tail_ranking[0]?.label} ({rankingData.tail_ranking[0]?.count}次 ·{" "}
              {rankingData.tail_ranking[0]?.frequency}%)
            </div>
          </div>

          <div className="col-span-2 lg:col-span-1 bento-card rounded-2xl p-4">
            <div className="text-[11px] font-medium text-slate-500 dark:text-slate-400">
              当前连开领跑
            </div>
            <div className="text-base font-bold text-emerald-600 dark:text-emerald-400 mt-1 tabular-nums">
              {topStreakZodiac
                ? `${topStreakZodiac.label} (连开 ${topStreakZodiac.current_consecutive} 期)`
                : "当前无连开"}
            </div>
          </div>
        </div>
      )}

      {/* Bento Controls Card */}
      <div className="bento-card rounded-2xl p-4 space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-2">
            {/* Lottery Selector */}
            <SegmentedTabs
              tabs={LOTTERIES.map((l) => ({ id: l.value, label: l.label }))}
              activeTab={lottery}
              onChange={(v) => setLottery(v as Lottery)}
            />

            {/* Sample Periods Selector */}
            <SegmentedTabs
              tabs={([0, 30, 50, 100, 200, 500] as const).map((lim) => ({
                id: String(lim),
                label: lim === 0 ? "当年" : `${lim}期`,
              }))}
              activeTab={String(limit)}
              onChange={(v) => setLimit(Number(v))}
            />

            {/* Sort Order Selector */}
            <SegmentedTabs
              tabs={[
                { id: "count_desc", label: "🔥 热号榜" },
                { id: "count_asc", label: "❄️ 冷号榜" },
                { id: "current_consecutive_desc", label: "⚡ 连开榜" },
                { id: "omission_desc", label: "⏳ 遗漏榜" },
                { id: "consecutive_desc", label: "👑 连出王" },
              ]}
              activeTab={sortBy}
              onChange={(v) => setSortBy(v as SortOption)}
            />
          </div>

          <div className="relative flex items-center">
            <SearchIcon
              size={14}
              className="absolute left-3 text-slate-400 pointer-events-none"
            />
            <input
              type="text"
              value={keyword}
              onChange={(e) => setKeyword(e.target.value)}
              placeholder="搜索号码 / 生肖…"
              className="h-9 pl-8 pr-3 text-xs rounded-xl bento-input w-44"
            />
          </div>
        </div>

        {/* Category Tab Bar */}
        <div className="pt-3 border-t border-slate-100 dark:border-white/[0.06]">
          <SegmentedTabs
            tabs={[
              { id: "zodiac", label: "平特生肖榜 (12肖)" },
              { id: "tail", label: "平特尾数榜 (0-9尾)" },
              { id: "number", label: "平特号码榜 (01-49)" },
              { id: "bose", label: "平特波色榜" },
              { id: "wuxing", label: "平特五行榜" },
            ]}
            activeTab={activeTab}
            onChange={(v) => setActiveTab(v as RankingTab)}
          />
        </div>
      </div>

      {error && (
        <Alert variant="error">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {loading && !rankingData ? (
        <div className="bento-card rounded-2xl flex items-center justify-center p-16">
          <Spinner className="w-7 h-7 text-indigo-600" />
        </div>
      ) : (
        <>
          {/* TAB 1: 平特生肖榜 */}
          {activeTab === "zodiac" && (
            <TableContainer>
              <thead>
                <tr>
                  <th className={`${tableThClass} w-16 text-center`}>排名</th>
                  <th className={`${tableThClass} w-32`}>平特生肖</th>
                  <th className={`${tableThClass} w-28 text-center`}>总出现次数</th>
                  <th className={`${tableThClass} w-28 text-center`}>开出期数</th>
                  <th className={`${tableThClass} min-w-[160px]`}>出号率 (热度)</th>
                  <th className={`${tableThClass} w-24 text-center`}>当前遗漏</th>
                  <th className={`${tableThClass} w-24 text-center`}>当前连开</th>
                  <th className={`${tableThClass} w-24 text-center`}>最大连出</th>
                  <th className={`${tableThClass} w-24 text-center`}>最大遗漏</th>
                  <th className={`${tableThClass} min-w-[200px]`}>包含号码</th>
                </tr>
              </thead>
              <tbody>
                {filteredZodiacs.map((z, idx) => {
                  const rankMedal =
                    idx === 0 ? "🥇" : idx === 1 ? "🥈" : idx === 2 ? "🥉" : `#${idx + 1}`;

                  return (
                    <tr key={z.name} className={tableRowClass}>
                      <td className={`${tableTdClass} text-center font-bold`}>{rankMedal}</td>
                      <td className={tableTdClass}>
                        <div className="flex items-center gap-2">
                          <span className="w-8 h-8 rounded-xl bg-slate-100 dark:bg-white/[0.06] text-slate-900 dark:text-slate-100 font-bold flex items-center justify-center text-sm border border-slate-200/70 dark:border-white/10">
                            {z.name}
                          </span>
                          <span className="font-semibold text-slate-900 dark:text-slate-100">
                            {z.label}
                          </span>
                          {z.is_hot && (
                            <span className="px-1.5 py-0.5 rounded-md text-[10px] font-bold bg-rose-50 text-rose-600 dark:bg-rose-500/15 dark:text-rose-300">
                              热
                            </span>
                          )}
                          {z.is_cold && (
                            <span className="px-1.5 py-0.5 rounded-md text-[10px] font-bold bg-sky-50 text-sky-600 dark:bg-sky-500/15 dark:text-sky-300">
                              冷
                            </span>
                          )}
                        </div>
                      </td>
                      <td className={`${tableTdClass} text-center font-bold text-indigo-600 dark:text-indigo-400 font-mono tabular-nums`}>
                        {z.count}
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        {z.periods_count} 期
                      </td>
                      <td className={tableTdClass}>
                        <div className="flex items-center gap-3">
                          <div className="flex-1 bg-slate-100 dark:bg-white/[0.06] h-2 rounded-full overflow-hidden">
                            <div
                              className="bg-indigo-500 h-full rounded-full transition-all"
                              style={{ width: `${Math.min(100, z.frequency)}%` }}
                            />
                          </div>
                          <span className="w-12 text-right font-mono text-xs font-semibold tabular-nums">
                            {z.frequency}%
                          </span>
                        </div>
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        <span
                          className={`px-2 py-0.5 rounded-md text-xs font-semibold ${
                            z.current_omission === 0
                              ? "bg-emerald-50 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300"
                              : z.current_omission > 5
                                ? "bg-amber-50 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300"
                                : "text-slate-500 dark:text-slate-400"
                          }`}
                        >
                          {z.current_omission === 0 ? "本期开出" : `${z.current_omission}期`}
                        </span>
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        {z.current_consecutive > 0 ? (
                          <span className="px-2 py-0.5 rounded-md text-xs font-bold bg-rose-50 text-rose-600 dark:bg-rose-500/15 dark:text-rose-300">
                            连开 {z.current_consecutive} 期
                          </span>
                        ) : (
                          <span className="text-slate-400 dark:text-slate-500 text-xs">0 期</span>
                        )}
                      </td>
                      <td className={`${tableTdClass} text-center font-semibold font-mono tabular-nums`}>
                        {z.max_consecutive} 期
                      </td>
                      <td className={`${tableTdClass} text-center text-slate-500 dark:text-slate-400 font-mono tabular-nums`}>
                        {z.max_omission} 期
                      </td>
                      <td className={tableTdClass}>
                        <div className="flex flex-wrap items-center gap-1">
                          {z.numbers.map((num) => (
                            <span
                              key={num}
                              className="px-1.5 py-0.5 rounded-md font-mono text-[11px] bg-slate-100 dark:bg-white/[0.06] text-slate-700 dark:text-slate-300 font-medium"
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
            </TableContainer>
          )}

          {/* TAB 2: 平特尾数榜 */}
          {activeTab === "tail" && (
            <TableContainer>
              <thead>
                <tr>
                  <th className={`${tableThClass} w-16 text-center`}>排名</th>
                  <th className={`${tableThClass} w-32`}>平特尾数</th>
                  <th className={`${tableThClass} w-28 text-center`}>总开出球数</th>
                  <th className={`${tableThClass} w-28 text-center`}>开出期数</th>
                  <th className={`${tableThClass} min-w-[160px]`}>出号率</th>
                  <th className={`${tableThClass} w-24 text-center`}>当前遗漏</th>
                  <th className={`${tableThClass} w-24 text-center`}>当前连开</th>
                  <th className={`${tableThClass} w-24 text-center`}>最大连出</th>
                  <th className={`${tableThClass} w-24 text-center`}>最大遗漏</th>
                  <th className={`${tableThClass} min-w-[200px]`}>包含号码</th>
                </tr>
              </thead>
              <tbody>
                {filteredTails.map((t, idx) => {
                  const rankMedal =
                    idx === 0 ? "🥇" : idx === 1 ? "🥈" : idx === 2 ? "🥉" : `#${idx + 1}`;

                  return (
                    <tr key={t.name} className={tableRowClass}>
                      <td className={`${tableTdClass} text-center font-bold`}>{rankMedal}</td>
                      <td className={tableTdClass}>
                        <div className="flex items-center gap-2">
                          <span className="w-7 h-7 rounded-lg bg-indigo-50 text-indigo-600 dark:bg-indigo-500/15 dark:text-indigo-300 font-bold flex items-center justify-center text-xs font-mono">
                            {t.name}
                          </span>
                          <span className="font-semibold text-slate-900 dark:text-slate-100">
                            {t.label}
                          </span>
                          {t.is_hot && (
                            <span className="px-1.5 py-0.5 rounded-md text-[10px] font-bold bg-rose-50 text-rose-600 dark:bg-rose-500/15 dark:text-rose-300">
                              热
                            </span>
                          )}
                          {t.is_cold && (
                            <span className="px-1.5 py-0.5 rounded-md text-[10px] font-bold bg-sky-50 text-sky-600 dark:bg-sky-500/15 dark:text-sky-300">
                              冷
                            </span>
                          )}
                        </div>
                      </td>
                      <td className={`${tableTdClass} text-center font-bold text-indigo-600 dark:text-indigo-400 font-mono tabular-nums`}>
                        {t.count}
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        {t.periods_count} 期
                      </td>
                      <td className={tableTdClass}>
                        <div className="flex items-center gap-3">
                          <div className="flex-1 bg-slate-100 dark:bg-white/[0.06] h-2 rounded-full overflow-hidden">
                            <div
                              className="bg-indigo-500 h-full rounded-full transition-all"
                              style={{ width: `${Math.min(100, t.frequency)}%` }}
                            />
                          </div>
                          <span className="w-12 text-right font-mono text-xs font-semibold tabular-nums">
                            {t.frequency}%
                          </span>
                        </div>
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        <span
                          className={`px-2 py-0.5 rounded-md text-xs font-semibold ${
                            t.current_omission === 0
                              ? "bg-emerald-50 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300"
                              : t.current_omission > 5
                                ? "bg-amber-50 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300"
                                : "text-slate-500 dark:text-slate-400"
                          }`}
                        >
                          {t.current_omission === 0 ? "本期开出" : `${t.current_omission}期`}
                        </span>
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        {t.current_consecutive > 0 ? (
                          <span className="px-2 py-0.5 rounded-md text-xs font-bold bg-rose-50 text-rose-600 dark:bg-rose-500/15 dark:text-rose-300">
                            连开 {t.current_consecutive} 期
                          </span>
                        ) : (
                          <span className="text-slate-400 dark:text-slate-500 text-xs">0 期</span>
                        )}
                      </td>
                      <td className={`${tableTdClass} text-center font-semibold font-mono tabular-nums`}>
                        {t.max_consecutive} 期
                      </td>
                      <td className={`${tableTdClass} text-center text-slate-500 dark:text-slate-400 font-mono tabular-nums`}>
                        {t.max_omission} 期
                      </td>
                      <td className={tableTdClass}>
                        <div className="flex flex-wrap items-center gap-1 font-mono">
                          {t.numbers.map((n) => (
                            <span
                              key={n}
                              className="px-1.5 py-0.5 rounded-md text-[11px] bg-slate-100 dark:bg-white/[0.06] text-slate-700 dark:text-slate-300 font-medium"
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
            </TableContainer>
          )}

          {/* TAB 3: 平特号码榜 */}
          {activeTab === "number" && (
            <TableContainer>
              <thead>
                <tr>
                  <th className={`${tableThClass} w-16 text-center`}>排名</th>
                  <th className={`${tableThClass} w-24`}>号码</th>
                  <th className={`${tableThClass} w-28 text-center`}>平特总次数</th>
                  <th className={`${tableThClass} w-24 text-center`}>正码次数</th>
                  <th className={`${tableThClass} w-24 text-center`}>特码次数</th>
                  <th className={`${tableThClass} min-w-[140px]`}>出号率</th>
                  <th className={`${tableThClass} w-24 text-center`}>当前遗漏</th>
                  <th className={`${tableThClass} w-24 text-center`}>当前连开</th>
                  <th className={`${tableThClass} w-24 text-center`}>最大连出</th>
                  <th className={`${tableThClass} w-24 text-center`}>最大遗漏</th>
                  <th className={`${tableThClass} w-28 text-center`}>生肖 / 五行</th>
                </tr>
              </thead>
              <tbody>
                {filteredNumbers.map((n, idx) => {
                  const bColor = BOSE_COLORS[n.bose] || { bg: "#64748b" };

                  return (
                    <tr key={n.number} className={tableRowClass}>
                      <td className={`${tableTdClass} text-center font-bold font-mono tabular-nums`}>
                        #{idx + 1}
                      </td>
                      <td className={tableTdClass}>
                        <div className="flex items-center gap-2">
                          <div
                            className="w-7 h-7 rounded-full flex items-center justify-center font-bold font-mono text-xs text-white shadow-2xs"
                            style={{ backgroundColor: bColor.bg }}
                          >
                            {n.number}
                          </div>
                          {n.is_hot && (
                            <span className="px-1.5 py-0.5 rounded-md text-[10px] font-bold bg-rose-50 text-rose-600 dark:bg-rose-500/15 dark:text-rose-300">
                              热
                            </span>
                          )}
                          {n.is_cold && (
                            <span className="px-1.5 py-0.5 rounded-md text-[10px] font-bold bg-sky-50 text-sky-600 dark:bg-sky-500/15 dark:text-sky-300">
                              冷
                            </span>
                          )}
                        </div>
                      </td>
                      <td className={`${tableTdClass} text-center font-bold text-indigo-600 dark:text-indigo-400 font-mono tabular-nums`}>
                        {n.count}
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        {n.ping_count}
                      </td>
                      <td className={`${tableTdClass} text-center text-amber-600 dark:text-amber-400 font-bold font-mono tabular-nums`}>
                        {n.tema_count}
                      </td>
                      <td className={tableTdClass}>
                        <div className="flex items-center gap-3">
                          <div className="flex-1 bg-slate-100 dark:bg-white/[0.06] h-2 rounded-full overflow-hidden">
                            <div
                              className="bg-indigo-500 h-full rounded-full transition-all"
                              style={{ width: `${Math.min(100, n.frequency * 2)}%` }}
                            />
                          </div>
                          <span className="w-12 text-right font-mono text-xs font-semibold tabular-nums">
                            {n.frequency}%
                          </span>
                        </div>
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        <span
                          className={`px-2 py-0.5 rounded-md text-xs font-semibold ${
                            n.current_omission === 0
                              ? "bg-emerald-50 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300"
                              : n.current_omission > 15
                                ? "bg-amber-50 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300"
                                : "text-slate-500 dark:text-slate-400"
                          }`}
                        >
                          {n.current_omission === 0 ? "本期开出" : `${n.current_omission}期`}
                        </span>
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        {n.current_consecutive > 0 ? (
                          <span className="px-2 py-0.5 rounded-md text-xs font-bold bg-rose-50 text-rose-600 dark:bg-rose-500/15 dark:text-rose-300">
                            连开 {n.current_consecutive} 期
                          </span>
                        ) : (
                          <span className="text-slate-400 dark:text-slate-500 text-xs">0 期</span>
                        )}
                      </td>
                      <td className={`${tableTdClass} text-center font-semibold font-mono tabular-nums`}>
                        {n.max_consecutive} 期
                      </td>
                      <td className={`${tableTdClass} text-center text-slate-500 dark:text-slate-400 font-mono tabular-nums`}>
                        {n.max_omission} 期
                      </td>
                      <td className={`${tableTdClass} text-center`}>
                        <span className="font-semibold text-slate-800 dark:text-slate-200">
                          {n.xiao}肖
                        </span>{" "}
                        <span className="text-slate-300 dark:text-slate-600">·</span>{" "}
                        <span className="text-slate-500 dark:text-slate-400">
                          {n.wuxing || "—"}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </TableContainer>
          )}

          {/* TAB 4: 平特波色榜 */}
          {activeTab === "bose" && rankingData && (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {rankingData.bose_ranking.map((b) => {
                const cfg = BOSE_COLORS[b.name] || { bg: "#64748b" };
                return (
                  <div
                    key={b.name}
                    className="bento-card rounded-2xl p-5 flex flex-col justify-between gap-4"
                  >
                    <div>
                      <div className="flex items-center justify-between mb-3 pb-3 border-b border-slate-100 dark:border-white/[0.06]">
                        <div className="flex items-center gap-2.5">
                          <span
                            className="w-4 h-4 rounded-full shadow-2xs"
                            style={{ backgroundColor: cfg.bg }}
                          />
                          <span className="font-bold text-base text-slate-900 dark:text-white">
                            {b.label}
                          </span>
                        </div>
                        <span className="font-mono text-sm font-bold text-indigo-600 dark:text-indigo-400 tabular-nums">
                          {b.percentage}%
                        </span>
                      </div>

                      <div className="space-y-2 text-xs">
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>总出现球数:</span>
                          <span className="font-bold font-mono tabular-nums">{b.count} 个</span>
                        </div>
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>出现期数:</span>
                          <span className="font-bold font-mono tabular-nums">
                            {b.periods_count} 期
                          </span>
                        </div>
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>当前遗漏:</span>
                          <span className="font-bold font-mono tabular-nums">
                            {b.current_omission} 期
                          </span>
                        </div>
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>当前连开:</span>
                          <span
                            className={`font-bold font-mono tabular-nums ${
                              b.current_consecutive > 0
                                ? "text-rose-600 dark:text-rose-400"
                                : "text-slate-400 dark:text-slate-500"
                            }`}
                          >
                            {b.current_consecutive > 0
                              ? `连开 ${b.current_consecutive} 期`
                              : "0 期"}
                          </span>
                        </div>
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>最大连出:</span>
                          <span className="font-bold font-mono tabular-nums">
                            {b.max_consecutive} 期
                          </span>
                        </div>
                      </div>
                    </div>

                    <div className="pt-3 border-t border-slate-100 dark:border-white/[0.06]">
                      <div className="text-[11px] text-slate-400 dark:text-slate-500 mb-2 font-medium">
                        包含号码:
                      </div>
                      <div className="flex flex-wrap gap-1 font-mono text-[11px]">
                        {b.numbers.map((n) => (
                          <span
                            key={n}
                            className="px-1.5 py-0.5 rounded-md bg-slate-100 dark:bg-white/[0.06] text-slate-700 dark:text-slate-200 font-medium"
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
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3.5">
              {rankingData.wuxing_ranking.map((w) => {
                const color = WUXING_COLORS[w.name] || "#64748b";
                return (
                  <div
                    key={w.name}
                    className="bento-card rounded-2xl p-4 flex flex-col justify-between gap-3"
                  >
                    <div>
                      <div className="flex items-center justify-between mb-3 pb-2.5 border-b border-slate-100 dark:border-white/[0.06]">
                        <span
                          className="w-7 h-7 rounded-lg font-bold text-xs text-white flex items-center justify-center shadow-2xs"
                          style={{ backgroundColor: color }}
                        >
                          {w.name}
                        </span>
                        <span className="font-mono text-xs font-bold text-indigo-600 dark:text-indigo-400 tabular-nums">
                          {w.percentage}%
                        </span>
                      </div>

                      <div className="space-y-1.5 text-xs">
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>总球数:</span>
                          <span className="font-bold font-mono tabular-nums">{w.count}</span>
                        </div>
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>出现期数:</span>
                          <span className="font-bold font-mono tabular-nums">
                            {w.periods_count}期
                          </span>
                        </div>
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>当前遗漏:</span>
                          <span className="font-bold font-mono tabular-nums">
                            {w.current_omission}期
                          </span>
                        </div>
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>当前连开:</span>
                          <span
                            className={`font-bold font-mono tabular-nums ${
                              w.current_consecutive > 0
                                ? "text-rose-600 dark:text-rose-400"
                                : "text-slate-400 dark:text-slate-500"
                            }`}
                          >
                            {w.current_consecutive > 0 ? `连开 ${w.current_consecutive}期` : "0期"}
                          </span>
                        </div>
                        <div className="flex justify-between text-slate-600 dark:text-slate-300">
                          <span>最大连出:</span>
                          <span className="font-bold font-mono tabular-nums">
                            {w.max_consecutive}期
                          </span>
                        </div>
                      </div>
                    </div>

                    <div className="pt-2.5 border-t border-slate-100 dark:border-white/[0.06]">
                      <div className="flex flex-wrap gap-1 font-mono text-[10px]">
                        {w.numbers.map((n) => (
                          <span
                            key={n}
                            className="px-1.5 py-0.5 rounded bg-slate-100 dark:bg-white/[0.06] text-slate-700 dark:text-slate-200 font-medium"
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
        </>
      )}
    </PageWorkspace>
  );
}
