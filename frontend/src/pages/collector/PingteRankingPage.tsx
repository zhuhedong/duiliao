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
  type PingteZodiacHistoryResult,
  type PingteZodiacRank,
  type PingteSegment,
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

const ALL_XIAO = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"] as const;

type RankingTab = "zodiac" | "zodiac_history" | "tail" | "number" | "bose" | "wuxing";
type SortOption =
  | "count_desc"
  | "count_asc"
  | "current_consecutive_desc"
  | "omission_desc"
  | "consecutive_desc";

type HistoryViewMode = "segments" | "periods" | "all_zodiacs";
type SegmentTypeFilter = "all" | "hit" | "miss";
type SegmentSortOrder = "newest" | "oldest" | "length_desc";
type PeriodRecordFilter = "all" | "hit" | "miss" | "multi";

function shortPeriodRange(startPeriod?: string | null, endPeriod?: string | null): string {
  if (!startPeriod && !endPeriod) return "—";
  if (!startPeriod) return endPeriod || "—";
  if (!endPeriod) return startPeriod;
  return `${startPeriod}~${endPeriod}`;
}

export function PingteRankingPage() {
  const [lottery, setLottery] = useState<Lottery>("macau");
  const [limit, setLimit] = useState<number>(0); // 0 = 当年全部期数
  const [activeTab, setActiveTab] = useState<RankingTab>("zodiac");
  const [sortBy, setSortBy] = useState<SortOption>("count_desc");
  const [keyword, setKeyword] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [rankingData, setRankingData] = useState<PingteRankingResult | null>(null);

  // Zodiac History state
  const [selectedXiao, setSelectedXiao] = useState<string>("鼠");
  const [historyViewMode, setHistoryViewMode] = useState<HistoryViewMode>("segments");
  const [segTypeFilter, setSegTypeFilter] = useState<SegmentTypeFilter>("all");
  const [segMinLength, setSegMinLength] = useState<number>(1);
  const [segExactLength, setSegExactLength] = useState<{ type: "hit" | "miss"; length: number } | null>(null);
  const [segSortOrder, setSegSortOrder] = useState<SegmentSortOrder>("newest");
  const [periodRecordFilter, setPeriodRecordFilter] = useState<PeriodRecordFilter>("all");
  const [periodFromInput, setPeriodFromInput] = useState<string>("");
  const [periodToInput, setPeriodToInput] = useState<string>("");
  const [appliedPeriodRange, setAppliedPeriodRange] = useState<{ from?: string; to?: string }>({});
  const [historyData, setHistoryData] = useState<PingteZodiacHistoryResult | null>(null);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyError, setHistoryError] = useState<string | null>(null);

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

  const loadHistoryData = useCallback(
    async (forceRefresh = false) => {
      setHistoryLoading(true);
      setHistoryError(null);
      try {
        const res = await collectorApi.getPingteZodiacHistory(lottery, {
          xiao: selectedXiao,
          limit,
          period_from: appliedPeriodRange.from,
          period_to: appliedPeriodRange.to,
          force_refresh: forceRefresh,
        });
        setHistoryData(res);
      } catch (err) {
        setHistoryError(err instanceof ApiError ? err.message : "获取生肖平特开奖历史失败");
      } finally {
        setHistoryLoading(false);
      }
    },
    [lottery, selectedXiao, limit, appliedPeriodRange],
  );

  useEffect(() => {
    void loadData();
  }, [loadData]);

  useEffect(() => {
    if (activeTab === "zodiac_history") {
      void loadHistoryData();
    }
  }, [activeTab, loadHistoryData]);

  const openZodiacHistory = (xiaoName: string) => {
    setSelectedXiao(xiaoName);
    setSegExactLength(null);
    setActiveTab("zodiac_history");
  };

  const filteredZodiacs = useMemo(() => {
    if (!rankingData?.zodiac_ranking) return [];
    if (!keyword.trim()) return rankingData.zodiac_ranking;
    const kw = keyword.trim().toLowerCase();
    return rankingData.zodiac_ranking.filter(
      (z) =>
        z.name.includes(kw) ||
        z.label.includes(kw) ||
        z.numbers.some((n) => n.includes(kw)) ||
        (z.current_range?.text && z.current_range.text.includes(kw)) ||
        (z.max_consecutive_range?.text && z.max_consecutive_range.text.includes(kw)) ||
        (z.max_omission_range?.text && z.max_omission_range.text.includes(kw)),
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

  // Active zodiac detail for history tab (fallback to rankingData if historyData is still loading)
  const activeZodiacDetail: PingteZodiacRank | null = useMemo(() => {
    if (historyData?.selected_zodiac && historyData.selected_zodiac.name === selectedXiao) {
      return historyData.selected_zodiac;
    }
    const fromHistoryList = historyData?.zodiacs?.find((z) => z.name === selectedXiao);
    if (fromHistoryList) return fromHistoryList;
    const fromRanking = rankingData?.zodiac_ranking?.find((z) => z.name === selectedXiao);
    return fromRanking ?? null;
  }, [historyData, rankingData, selectedXiao]);

  const allZodiacsForHistory: PingteZodiacRank[] = useMemo(() => {
    if (historyData?.zodiacs?.length) return historyData.zodiacs;
    if (rankingData?.zodiac_ranking?.length) {
      return [...rankingData.zodiac_ranking].sort(
        (a, b) => ALL_XIAO.indexOf(a.name as any) - ALL_XIAO.indexOf(b.name as any),
      );
    }
    return [];
  }, [historyData, rankingData]);

  const filteredSegments: PingteSegment[] = useMemo(() => {
    const raw = activeZodiacDetail?.segments ?? [];
    const kw = keyword.trim().toLowerCase();
    const list = raw.filter((seg) => {
      if (segExactLength) {
        if (seg.type !== segExactLength.type || seg.length !== segExactLength.length) {
          return false;
        }
      } else {
        if (segTypeFilter !== "all" && seg.type !== segTypeFilter) return false;
        if (seg.length < segMinLength) return false;
      }
      if (kw) {
        const matchPeriod =
          seg.start_period.includes(kw) ||
          seg.end_period.includes(kw) ||
          (kw.length === seg.start_period.length &&
            kw >= seg.start_period &&
            kw <= seg.end_period) ||
          seg.text.toLowerCase().includes(kw) ||
          seg.periods?.some(
            (p) =>
              p.period.includes(kw) ||
              p.matched_balls?.some((b) => b.num.includes(kw) || b.pos.includes(kw)),
          );
        if (!matchPeriod) return false;
      }
      return true;
    });

    if (segSortOrder === "oldest") {
      return [...list].sort((a, b) => a.segment_id - b.segment_id);
    }
    if (segSortOrder === "length_desc") {
      return [...list].sort((a, b) => b.length - a.length || b.segment_id - a.segment_id);
    }
    return [...list].sort((a, b) => b.segment_id - a.segment_id);
  }, [activeZodiacDetail, segTypeFilter, segMinLength, segExactLength, segSortOrder, keyword]);

  const filteredPeriodHistory = useMemo(() => {
    const raw = activeZodiacDetail?.period_history ?? [];
    const kw = keyword.trim().toLowerCase();
    return raw.filter((rec) => {
      if (periodRecordFilter === "hit" && !rec.hit) return false;
      if (periodRecordFilter === "miss" && rec.hit) return false;
      if (periodRecordFilter === "multi" && rec.ball_count < 2) return false;
      if (kw) {
        const match =
          rec.period.includes(kw) ||
          rec.date.includes(kw) ||
          rec.segment_text.toLowerCase().includes(kw) ||
          rec.matched_balls.some((b) => b.num.includes(kw) || b.pos.includes(kw));
        if (!match) return false;
      }
      return true;
    });
  }, [activeZodiacDetail, periodRecordFilter, keyword]);

  return (
    <PageWorkspace
      summary="基于官方落球 7 码（6 正码 + 1 特码）平特全域统计；支持查询每个生肖从哪一期到哪一期连开多少期、从哪一期到哪一期没出多少期。"
      actions={
        <Button
          type="button"
          size="sm"
          onClick={() => {
            void loadData();
            if (activeTab === "zodiac_history") {
              void loadHistoryData(true);
            }
          }}
          disabled={loading || historyLoading}
        >
          <RefreshIcon size={14} className={loading || historyLoading ? "animate-spin" : ""} />
          <span>刷新榜单与历史</span>
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
            {topStreakZodiac?.current_range && (
              <div className="text-[10px] font-mono text-slate-400 mt-0.5">
                {topStreakZodiac.current_range.start_period}~{topStreakZodiac.current_range.end_period}
              </div>
            )}
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
              activeTab={
                appliedPeriodRange.from || appliedPeriodRange.to ? "" : String(limit)
              }
              onChange={(v) => {
                setLimit(Number(v));
                setAppliedPeriodRange({});
                setPeriodFromInput("");
                setPeriodToInput("");
              }}
            />

            {/* Sort Order Selector (shown on ranking tabs) */}
            {activeTab !== "zodiac_history" && (
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
            )}
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
              placeholder="搜索期号 / 号码 / 生肖…"
              className="h-9 pl-8 pr-3 text-xs rounded-xl bento-input w-48"
            />
          </div>
        </div>

        {/* Category Tab Bar */}
        <div className="pt-3 border-t border-slate-100 dark:border-white/[0.06]">
          <SegmentedTabs
            tabs={[
              { id: "zodiac", label: "平特生肖榜 (12肖)" },
              { id: "zodiac_history", label: "📜 生肖开奖历史 (连开/没出区间)" },
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
                  <th className={`${tableThClass} w-14 text-center`}>排名</th>
                  <th className={`${tableThClass} w-32`}>平特生肖</th>
                  <th className={`${tableThClass} w-24 text-center`}>总次数</th>
                  <th className={`${tableThClass} w-28 text-center`}>开出 / 没出</th>
                  <th className={`${tableThClass} min-w-[140px]`}>出号率 (热度)</th>
                  <th className={`${tableThClass} w-36 text-center`}>当前状态区间</th>
                  <th className={`${tableThClass} w-36 text-center`}>最大连开区间</th>
                  <th className={`${tableThClass} w-36 text-center`}>最大没出区间</th>
                  <th className={`${tableThClass} min-w-[220px]`}>近期连开/没出轨迹</th>
                  <th className={`${tableThClass} min-w-[150px]`}>包含号码</th>
                  <th className={`${tableThClass} w-28 text-center`}>历史明细</th>
                </tr>
              </thead>
              <tbody>
                {filteredZodiacs.map((z, idx) => {
                  const rankMedal =
                    idx === 0 ? "🥇" : idx === 1 ? "🥈" : idx === 2 ? "🥉" : `#${idx + 1}`;
                  const missCount =
                    z.miss_periods_count ??
                    Math.max(0, (rankingData?.sample_periods ?? 0) - z.periods_count);

                  return (
                    <tr
                      key={z.name}
                      onClick={() => openZodiacHistory(z.name)}
                      className={`${tableRowClass} cursor-pointer`}
                      title={`点击查看 ${z.label} 完整连开/没出开奖历史`}
                    >
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
                      <td className={`${tableTdClass} text-center font-mono tabular-nums text-xs`}>
                        <span className="text-emerald-600 dark:text-emerald-400 font-semibold">
                          开{z.periods_count}期
                        </span>
                        <span className="text-slate-300 dark:text-slate-600 mx-1">/</span>
                        <span className="text-slate-500 dark:text-slate-400">
                          没出{missCount}期
                        </span>
                      </td>
                      <td className={tableTdClass}>
                        <div className="flex items-center gap-2.5">
                          <div className="flex-1 bg-slate-100 dark:bg-white/[0.06] h-2 rounded-full overflow-hidden">
                            <div
                              className="bg-indigo-500 h-full rounded-full transition-all"
                              style={{ width: `${Math.min(100, z.frequency)}%` }}
                            />
                          </div>
                          <span className="w-11 text-right font-mono text-xs font-semibold tabular-nums">
                            {z.frequency}%
                          </span>
                        </div>
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        {z.current_consecutive > 0 ? (
                          <div className="flex flex-col items-center gap-0.5">
                            <span className="px-2 py-0.5 rounded-md text-xs font-bold bg-rose-50 text-rose-600 dark:bg-rose-500/15 dark:text-rose-300">
                              连开 {z.current_consecutive} 期
                            </span>
                            {z.current_range && (
                              <span className="text-[10px] text-slate-400 dark:text-slate-500">
                                {shortPeriodRange(
                                  z.current_range.start_period,
                                  z.current_range.end_period,
                                )}
                              </span>
                            )}
                          </div>
                        ) : (
                          <div className="flex flex-col items-center gap-0.5">
                            <span
                              className={`px-2 py-0.5 rounded-md text-xs font-semibold ${
                                z.current_omission > 4
                                  ? "bg-amber-50 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300"
                                  : "bg-slate-100 text-slate-600 dark:bg-white/[0.06] dark:text-slate-300"
                              }`}
                            >
                              没出 {z.current_omission} 期
                            </span>
                            {z.current_range && (
                              <span className="text-[10px] text-slate-400 dark:text-slate-500">
                                {shortPeriodRange(
                                  z.current_range.start_period,
                                  z.current_range.end_period,
                                )}
                              </span>
                            )}
                          </div>
                        )}
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        <div className="flex flex-col items-center gap-0.5">
                          <span className="font-bold text-rose-600 dark:text-rose-400 text-xs">
                            连开 {z.max_consecutive} 期
                          </span>
                          {z.max_consecutive_range && (
                            <span className="text-[10px] text-slate-400 dark:text-slate-500">
                              {shortPeriodRange(
                                z.max_consecutive_range.start_period,
                                z.max_consecutive_range.end_period,
                              )}
                            </span>
                          )}
                        </div>
                      </td>
                      <td className={`${tableTdClass} text-center font-mono tabular-nums`}>
                        <div className="flex flex-col items-center gap-0.5">
                          <span className="font-semibold text-slate-600 dark:text-slate-300 text-xs">
                            没出 {z.max_omission} 期
                          </span>
                          {z.max_omission_range && (
                            <span className="text-[10px] text-slate-400 dark:text-slate-500">
                              {shortPeriodRange(
                                z.max_omission_range.start_period,
                                z.max_omission_range.end_period,
                              )}
                            </span>
                          )}
                        </div>
                      </td>
                      <td className={tableTdClass}>
                        <div className="flex flex-wrap items-center gap-1">
                          {(z.recent_segments ?? []).slice(0, 3).map((seg, sIdx) => (
                            <span
                              key={sIdx}
                              className={`px-1.5 py-0.5 rounded text-[10px] font-mono font-medium ${
                                seg.type === "hit"
                                  ? "bg-rose-50 text-rose-700 dark:bg-rose-500/15 dark:text-rose-300"
                                  : "bg-slate-100 text-slate-600 dark:bg-white/[0.06] dark:text-slate-400"
                              }`}
                            >
                              {seg.start_period.slice(-3)}~{seg.end_period.slice(-3)}{" "}
                              {seg.type === "hit" ? `连${seg.length}` : `漏${seg.length}`}
                            </span>
                          ))}
                        </div>
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
                      <td className={`${tableTdClass} text-center`}>
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            openZodiacHistory(z.name);
                          }}
                          className="px-2.5 py-1 rounded-lg text-xs font-semibold bg-indigo-50 text-indigo-600 hover:bg-indigo-100 dark:bg-indigo-500/15 dark:text-indigo-300 dark:hover:bg-indigo-500/25 transition-colors cursor-pointer"
                        >
                          开奖历史
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </TableContainer>
          )}

          {/* TAB 1.5: 生肖平特开奖历史 (多少到多少连开多少 / 多少到多少没出) */}
          {activeTab === "zodiac_history" && (
            <div className="space-y-4">
              {/* 12 Zodiac Selector Grid */}
              <div className="bento-card rounded-2xl p-4 space-y-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="text-xs font-bold text-slate-700 dark:text-slate-200">
                    选择生肖查看平特开奖历史（多少期到多少期连开 / 没出）
                  </div>
                  <div className="flex flex-wrap items-center gap-2">
                    <input
                      type="text"
                      value={periodFromInput}
                      onChange={(e) => setPeriodFromInput(e.target.value.trim())}
                      placeholder="起始期号 如 2026001"
                      className="h-8 px-2.5 text-xs rounded-xl bento-input w-36 font-mono"
                    />
                    <span className="text-xs text-slate-400">~</span>
                    <input
                      type="text"
                      value={periodToInput}
                      onChange={(e) => setPeriodToInput(e.target.value.trim())}
                      placeholder="结束期号 如 2026285"
                      className="h-8 px-2.5 text-xs rounded-xl bento-input w-36 font-mono"
                    />
                    <Button
                      type="button"
                      size="sm"
                      onClick={() => {
                        setAppliedPeriodRange({
                          from: periodFromInput || undefined,
                          to: periodToInput || undefined,
                        });
                      }}
                    >
                      按区间查询
                    </Button>
                    {(appliedPeriodRange.from || appliedPeriodRange.to) && (
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={() => {
                          setPeriodFromInput("");
                          setPeriodToInput("");
                          setAppliedPeriodRange({});
                        }}
                      >
                        清除区间
                      </Button>
                    )}
                  </div>
                </div>

                <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-12 gap-2">
                  {ALL_XIAO.map((xName) => {
                    const zItem = allZodiacsForHistory.find((z) => z.name === xName);
                    const isSelected = selectedXiao === xName;
                    const isStreak = (zItem?.current_consecutive ?? 0) > 0;
                    return (
                      <button
                        key={xName}
                        type="button"
                        onClick={() => {
                          setSelectedXiao(xName);
                          setSegExactLength(null);
                        }}
                        className={`flex flex-col items-center justify-center p-2.5 rounded-xl border text-center transition-all cursor-pointer ${
                          isSelected
                            ? "bg-indigo-600 text-white border-indigo-600 shadow-sm"
                            : "bg-slate-50/80 dark:bg-white/[0.04] text-slate-800 dark:text-slate-200 border-slate-200/70 dark:border-white/[0.08] hover:border-indigo-400"
                        }`}
                      >
                        <span className="text-sm font-bold">{xName}肖</span>
                        {zItem && (
                          <span
                            className={`mt-1 text-[10px] font-mono px-1.5 py-0.5 rounded font-semibold ${
                              isSelected
                                ? "bg-white/20 text-white"
                                : isStreak
                                  ? "bg-rose-50 text-rose-600 dark:bg-rose-500/15 dark:text-rose-300"
                                  : "bg-slate-200/70 text-slate-600 dark:bg-white/10 dark:text-slate-400"
                            }`}
                          >
                            {isStreak
                              ? `连开${zItem.current_consecutive}期`
                              : `没出${zItem.current_omission}期`}
                          </span>
                        )}
                        {zItem && (
                          <span
                            className={`mt-0.5 text-[10px] font-mono ${
                              isSelected ? "text-indigo-100" : "text-slate-400 dark:text-slate-500"
                            }`}
                          >
                            开{zItem.periods_count}/漏
                            {zItem.miss_periods_count ??
                              Math.max(0, (zItem.sample_periods || 0) - zItem.periods_count)}
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
              </div>

              {historyError && (
                <Alert variant="error">
                  <AlertDescription>{historyError}</AlertDescription>
                </Alert>
              )}

              {/* Selected Zodiac Summary Ribbon */}
              {activeZodiacDetail && (
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                  <div className="bento-card rounded-2xl p-4">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-medium text-slate-500 dark:text-slate-400">
                        {activeZodiacDetail.label} · 样本统计
                      </span>
                      <span className="px-2 py-0.5 rounded-md text-xs font-mono font-bold bg-indigo-50 text-indigo-600 dark:bg-indigo-500/15 dark:text-indigo-300">
                        出号率 {activeZodiacDetail.frequency}%
                      </span>
                    </div>
                    <div className="mt-2 text-base font-bold text-slate-900 dark:text-white font-mono">
                      开出 {activeZodiacDetail.periods_count} 期 / 没出{" "}
                      {activeZodiacDetail.miss_periods_count ??
                        Math.max(
                          0,
                          (historyData?.sample_periods ?? rankingData?.sample_periods ?? 0) -
                            activeZodiacDetail.periods_count,
                        )}{" "}
                      期
                    </div>
                    <div className="mt-1 text-xs text-slate-500 dark:text-slate-400 font-mono">
                      共出 {activeZodiacDetail.count} 球（正码 {activeZodiacDetail.ping_count ?? 0}{" "}
                      · 特码 {activeZodiacDetail.tema_count ?? 0} · 同肖多码{" "}
                      {activeZodiacDetail.multi_ball_periods_count ?? 0} 期）
                    </div>
                  </div>

                  <div className="bento-card rounded-2xl p-4">
                    <div className="text-xs font-medium text-slate-500 dark:text-slate-400">
                      当前最新状态区间
                    </div>
                    <div
                      className={`mt-2 text-base font-bold font-mono ${
                        activeZodiacDetail.current_consecutive > 0
                          ? "text-rose-600 dark:text-rose-400"
                          : "text-amber-600 dark:text-amber-400"
                      }`}
                    >
                      {activeZodiacDetail.current_range?.text ||
                        (activeZodiacDetail.current_consecutive > 0
                          ? `连开 ${activeZodiacDetail.current_consecutive} 期`
                          : `没出 ${activeZodiacDetail.current_omission} 期`)}
                    </div>
                    {activeZodiacDetail.current_range && (
                      <div className="mt-1 text-xs text-slate-500 dark:text-slate-400 font-mono">
                        日期: {activeZodiacDetail.current_range.start_date} ~{" "}
                        {activeZodiacDetail.current_range.end_date}
                      </div>
                    )}
                  </div>

                  <div className="bento-card rounded-2xl p-4">
                    <div className="text-xs font-medium text-slate-500 dark:text-slate-400">
                      历史最长连开区间
                    </div>
                    <div className="mt-2 text-base font-bold text-rose-600 dark:text-rose-400 font-mono">
                      {activeZodiacDetail.max_consecutive_range?.text ||
                        `连开 ${activeZodiacDetail.max_consecutive} 期`}
                    </div>
                    {activeZodiacDetail.max_consecutive_range && (
                      <div className="mt-1 text-xs text-slate-500 dark:text-slate-400 font-mono">
                        {activeZodiacDetail.max_consecutive_range.start_date} ~{" "}
                        {activeZodiacDetail.max_consecutive_range.end_date} · 共出{" "}
                        {activeZodiacDetail.max_consecutive_range.total_balls} 码
                      </div>
                    )}
                  </div>

                  <div className="bento-card rounded-2xl p-4">
                    <div className="text-xs font-medium text-slate-500 dark:text-slate-400">
                      历史最长没出(遗漏)区间
                    </div>
                    <div className="mt-2 text-base font-bold text-slate-800 dark:text-slate-200 font-mono">
                      {activeZodiacDetail.max_omission_range?.text ||
                        `没出 ${activeZodiacDetail.max_omission} 期`}
                    </div>
                    {activeZodiacDetail.max_omission_range && (
                      <div className="mt-1 text-xs text-slate-500 dark:text-slate-400 font-mono">
                        {activeZodiacDetail.max_omission_range.start_date} ~{" "}
                        {activeZodiacDetail.max_omission_range.end_date}
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Streak & Omission Distributions (Click to filter exact length) */}
              {activeZodiacDetail && (
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
                  {/* 连开分布 */}
                  <div className="bento-card rounded-2xl p-4 space-y-2.5">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-rose-600 dark:text-rose-400">
                        🔥 {activeZodiacDetail.label} · 连开次数分布（共{" "}
                        {activeZodiacDetail.hit_segments_count ?? 0} 段连开）
                      </span>
                      {segExactLength?.type === "hit" && (
                        <button
                          type="button"
                          onClick={() => setSegExactLength(null)}
                          className="text-[11px] text-indigo-600 dark:text-indigo-400 hover:underline cursor-pointer"
                        >
                          取消筛选
                        </button>
                      )}
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                      {(activeZodiacDetail.streak_distribution ?? []).map((d) => {
                        const active =
                          segExactLength?.type === "hit" && segExactLength.length === d.length;
                        return (
                          <button
                            key={`hit-${d.length}`}
                            type="button"
                            onClick={() => {
                              setHistoryViewMode("segments");
                              setSegExactLength(
                                active ? null : { type: "hit", length: d.length },
                              );
                            }}
                            className={`px-2.5 py-1 rounded-xl text-xs font-mono transition-all cursor-pointer border ${
                              active
                                ? "bg-rose-600 text-white border-rose-600 font-bold"
                                : "bg-rose-50/80 text-rose-700 border-rose-200/70 dark:bg-rose-500/12 dark:text-rose-300 dark:border-rose-500/25 hover:bg-rose-100"
                            }`}
                          >
                            {d.label}: <b>{d.count}</b>次
                            {d.ranges[0] && d.length >= 3 && (
                              <span className="ml-1 opacity-80 text-[10px]">
                                ({d.ranges[0].start_period.slice(-3)}~
                                {d.ranges[0].end_period.slice(-3)})
                              </span>
                            )}
                          </button>
                        );
                      })}
                    </div>
                  </div>

                  {/* 没出分布 */}
                  <div className="bento-card rounded-2xl p-4 space-y-2.5">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-slate-700 dark:text-slate-300">
                        ❄️ {activeZodiacDetail.label} · 没出(遗漏)次数分布（共{" "}
                        {activeZodiacDetail.miss_segments_count ?? 0} 段没出）
                      </span>
                      {segExactLength?.type === "miss" && (
                        <button
                          type="button"
                          onClick={() => setSegExactLength(null)}
                          className="text-[11px] text-indigo-600 dark:text-indigo-400 hover:underline cursor-pointer"
                        >
                          取消筛选
                        </button>
                      )}
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                      {(activeZodiacDetail.omission_distribution ?? []).map((d) => {
                        const active =
                          segExactLength?.type === "miss" && segExactLength.length === d.length;
                        return (
                          <button
                            key={`miss-${d.length}`}
                            type="button"
                            onClick={() => {
                              setHistoryViewMode("segments");
                              setSegExactLength(
                                active ? null : { type: "miss", length: d.length },
                              );
                            }}
                            className={`px-2.5 py-1 rounded-xl text-xs font-mono transition-all cursor-pointer border ${
                              active
                                ? "bg-slate-800 text-white border-slate-800 dark:bg-slate-200 dark:text-slate-900 font-bold"
                                : "bg-slate-100 text-slate-700 border-slate-200/80 dark:bg-white/[0.06] dark:text-slate-300 dark:border-white/10 hover:bg-slate-200/70"
                            }`}
                          >
                            {d.label}: <b>{d.count}</b>次
                            {d.ranges[0] && d.length >= 3 && (
                              <span className="ml-1 opacity-75 text-[10px]">
                                ({d.ranges[0].start_period.slice(-3)}~
                                {d.ranges[0].end_period.slice(-3)})
                              </span>
                            )}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                </div>
              )}

              {/* View Mode Switcher & Sub-filters */}
              <div className="bento-card rounded-2xl p-4 flex flex-wrap items-center justify-between gap-3">
                <SegmentedTabs
                  tabs={[
                    {
                      id: "segments",
                      label: `📊 连开/没出区间记录 (${filteredSegments.length})`,
                    },
                    {
                      id: "periods",
                      label: `📅 逐期开奖明细 (${
                        activeZodiacDetail?.period_history?.length ??
                        historyData?.sample_periods ??
                        0
                      })`,
                    },
                    {
                      id: "all_zodiacs",
                      label: "🗂️ 12生肖连开/没出总览",
                    },
                  ]}
                  activeTab={historyViewMode}
                  onChange={(v) => setHistoryViewMode(v as HistoryViewMode)}
                />

                {historyViewMode === "segments" && (
                  <div className="flex flex-wrap items-center gap-2">
                    <SegmentedTabs
                      tabs={[
                        { id: "all", label: "全部波段" },
                        { id: "hit", label: "🔥 只看连开" },
                        { id: "miss", label: "❄️ 只看没出" },
                      ]}
                      activeTab={segExactLength ? segExactLength.type : segTypeFilter}
                      onChange={(v) => {
                        setSegExactLength(null);
                        setSegTypeFilter(v as SegmentTypeFilter);
                      }}
                    />
                    <SegmentedTabs
                      tabs={[
                        { id: "1", label: "≥1期" },
                        { id: "2", label: "≥2期" },
                        { id: "3", label: "≥3期" },
                        { id: "4", label: "≥4期" },
                        { id: "5", label: "≥5期" },
                      ]}
                      activeTab={segExactLength ? "" : String(segMinLength)}
                      onChange={(v) => {
                        setSegExactLength(null);
                        setSegMinLength(Number(v));
                      }}
                    />
                    <SegmentedTabs
                      tabs={[
                        { id: "newest", label: "最新优先" },
                        { id: "oldest", label: "从旧到新" },
                        { id: "length_desc", label: "期数最多" },
                      ]}
                      activeTab={segSortOrder}
                      onChange={(v) => setSegSortOrder(v as SegmentSortOrder)}
                    />
                  </div>
                )}

                {historyViewMode === "periods" && (
                  <div className="flex flex-wrap items-center gap-2">
                    <SegmentedTabs
                      tabs={[
                        { id: "all", label: "全部期数" },
                        { id: "hit", label: "✅ 仅看开出期" },
                        { id: "miss", label: "❄️ 仅看没出期" },
                        { id: "multi", label: "🎯 同肖多码(重肖)" },
                      ]}
                      activeTab={periodRecordFilter}
                      onChange={(v) => setPeriodRecordFilter(v as PeriodRecordFilter)}
                    />
                  </div>
                )}
              </div>

              {/* VIEW 1: 连开/没出波段区间列表 (多少到多少连开多少 / 多少到多少没出) */}
              {historyViewMode === "segments" && (
                <TableContainer>
                  <thead>
                    <tr>
                      <th className={`${tableThClass} w-16 text-center`}>波段</th>
                      <th className={`${tableThClass} w-28 text-center`}>状态类型</th>
                      <th className={`${tableThClass} w-48`}>起止期号 (从多少到多少)</th>
                      <th className={`${tableThClass} w-32 text-center`}>连开 / 没出期数</th>
                      <th className={`${tableThClass} w-56`}>完整区间描述</th>
                      <th className={`${tableThClass} min-w-[280px]`}>区间内各期平特开奖明细</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredSegments.length === 0 ? (
                      <tr>
                        <td
                          colSpan={6}
                          className="py-12 text-center text-xs text-slate-400 dark:text-slate-500"
                        >
                          暂无符合筛选条件的连开/没出区间记录
                        </td>
                      </tr>
                    ) : (
                      filteredSegments.map((seg) => {
                        const isHit = seg.type === "hit";
                        return (
                          <tr key={seg.segment_id} className={tableRowClass}>
                            <td className={`${tableTdClass} text-center font-mono text-xs text-slate-400`}>
                              #{seg.segment_id}
                            </td>
                            <td className={`${tableTdClass} text-center`}>
                              <div className="inline-flex items-center gap-1">
                                <span
                                  className={`px-2 py-0.5 rounded-md text-xs font-bold ${
                                    isHit
                                      ? "bg-rose-50 text-rose-600 dark:bg-rose-500/15 dark:text-rose-300"
                                      : "bg-slate-100 text-slate-600 dark:bg-white/[0.07] dark:text-slate-300"
                                  }`}
                                >
                                  {isHit ? "🔥 连开" : "❄️ 没出"}
                                </span>
                                {seg.is_current && (
                                  <span className="px-1.5 py-0.5 rounded text-[10px] font-bold bg-emerald-50 text-emerald-600 dark:bg-emerald-500/15 dark:text-emerald-300">
                                    当前
                                  </span>
                                )}
                              </div>
                            </td>
                            <td className={tableTdClass}>
                              <div className="font-mono font-bold text-slate-900 dark:text-white text-xs">
                                {seg.start_period} ~ {seg.end_period}
                              </div>
                              <div className="font-mono text-[10px] text-slate-400 mt-0.5">
                                {seg.start_date} ~ {seg.end_date}
                              </div>
                            </td>
                            <td className={`${tableTdClass} text-center font-mono`}>
                              <span
                                className={`px-2.5 py-1 rounded-lg text-xs font-bold ${
                                  isHit
                                    ? "bg-rose-500/10 text-rose-600 dark:text-rose-300"
                                    : "bg-amber-500/10 text-amber-700 dark:text-amber-300"
                                }`}
                              >
                                {isHit ? `连开 ${seg.length} 期` : `没出 ${seg.length} 期`}
                              </span>
                            </td>
                            <td className={`${tableTdClass} font-mono text-xs font-semibold`}>
                              <span
                                className={
                                  isHit
                                    ? "text-rose-600 dark:text-rose-400"
                                    : "text-slate-600 dark:text-slate-300"
                                }
                              >
                                {seg.text}
                              </span>
                              {isHit && (
                                <span className="ml-1.5 text-[11px] font-normal text-slate-400">
                                  (共出{seg.total_balls}球
                                  {seg.tema_hits > 0 ? ` · 含特${seg.tema_hits}次` : ""})
                                </span>
                              )}
                            </td>
                            <td className={tableTdClass}>
                              {isHit ? (
                                <div className="flex flex-wrap gap-1.5">
                                  {(seg.periods ?? []).map((p) => (
                                    <span
                                      key={p.period}
                                      className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[11px] font-mono bg-slate-100 dark:bg-white/[0.06] text-slate-700 dark:text-slate-200"
                                    >
                                      <b className="text-indigo-600 dark:text-indigo-400">
                                        {p.period.slice(-3)}期:
                                      </b>
                                      {p.matched_balls.map((b, bi) => (
                                        <span
                                          key={bi}
                                          className={
                                            b.is_tema
                                              ? "font-bold text-amber-600 dark:text-amber-400"
                                              : ""
                                          }
                                        >
                                          {b.num}({b.pos})
                                        </span>
                                      ))}
                                    </span>
                                  ))}
                                </div>
                              ) : (
                                <span className="text-xs text-slate-400 dark:text-slate-500 font-mono">
                                  {seg.start_period} 至 {seg.end_period} 连续 {seg.length} 期未开出
                                  {activeZodiacDetail?.label}
                                </span>
                              )}
                            </td>
                          </tr>
                        );
                      })
                    )}
                  </tbody>
                </TableContainer>
              )}

              {/* VIEW 2: 逐期开奖明细 */}
              {historyViewMode === "periods" && (
                <>
                  {historyLoading && !activeZodiacDetail?.period_history?.length ? (
                    <div className="bento-card rounded-2xl flex items-center justify-center p-12">
                      <Spinner className="w-6 h-6 text-indigo-600" />
                    </div>
                  ) : (
                    <TableContainer>
                      <thead>
                        <tr>
                          <th className={`${tableThClass} w-32`}>期号 / 日期</th>
                          <th className={`${tableThClass} w-28 text-center`}>
                            {activeZodiacDetail?.label}状态
                          </th>
                          <th className={`${tableThClass} w-56`}>所属连开 / 没出区间</th>
                          <th className={`${tableThClass} w-44`}>当期命中该肖号码</th>
                          <th className={`${tableThClass} min-w-[300px]`}>
                            当期平特 7 码（高亮 {activeZodiacDetail?.label}）
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {filteredPeriodHistory.length === 0 ? (
                          <tr>
                            <td
                              colSpan={5}
                              className="py-12 text-center text-xs text-slate-400 dark:text-slate-500"
                            >
                              暂无匹配的逐期开奖记录
                            </td>
                          </tr>
                        ) : (
                          filteredPeriodHistory.map((rec) => (
                            <tr key={rec.period} className={tableRowClass}>
                              <td className={tableTdClass}>
                                <div className="font-mono font-bold text-slate-900 dark:text-white text-xs">
                                  {rec.period}
                                </div>
                                <div className="font-mono text-[10px] text-slate-400">
                                  {rec.date}
                                </div>
                              </td>
                              <td className={`${tableTdClass} text-center font-mono`}>
                                {rec.hit ? (
                                  <span className="px-2 py-0.5 rounded-md text-xs font-bold bg-emerald-50 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300">
                                    开出 ({rec.ball_count}码)
                                  </span>
                                ) : (
                                  <span className="px-2 py-0.5 rounded-md text-xs font-medium bg-slate-100 text-slate-500 dark:bg-white/[0.06] dark:text-slate-400">
                                    没出
                                  </span>
                                )}
                              </td>
                              <td className={`${tableTdClass} font-mono text-xs`}>
                                <div
                                  className={`font-semibold ${
                                    rec.hit
                                      ? "text-rose-600 dark:text-rose-400"
                                      : "text-slate-600 dark:text-slate-400"
                                  }`}
                                >
                                  {rec.segment_text}
                                </div>
                                <div className="text-[10px] text-slate-400">
                                  {rec.hit
                                    ? `该段连开第 ${rec.run_step} / ${rec.segment_length} 期`
                                    : `该段没出第 ${rec.run_step} / ${rec.segment_length} 期`}
                                </div>
                              </td>
                              <td className={tableTdClass}>
                                {rec.matched_balls.length > 0 ? (
                                  <div className="flex flex-wrap gap-1 font-mono">
                                    {rec.matched_balls.map((mb, mi) => {
                                      const bColor = BOSE_COLORS[mb.bose] || { bg: "#64748b" };
                                      return (
                                        <span
                                          key={mi}
                                          className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-white text-[11px] font-bold"
                                          style={{ backgroundColor: bColor.bg }}
                                        >
                                          <span>{mb.num}</span>
                                          <span className="opacity-90 text-[10px]">({mb.pos})</span>
                                        </span>
                                      );
                                    })}
                                  </div>
                                ) : (
                                  <span className="text-xs text-slate-400">—</span>
                                )}
                              </td>
                              <td className={tableTdClass}>
                                <div className="flex flex-wrap items-center gap-1.5 font-mono">
                                  {rec.all_balls.map((ab, ai) => {
                                    const bColor = BOSE_COLORS[ab.bose] || { bg: "#64748b" };
                                    return (
                                      <span
                                        key={ai}
                                        className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded-lg text-[11px] border transition-all ${
                                          ab.is_match
                                            ? "ring-2 ring-rose-500 bg-rose-50 dark:bg-rose-500/20 border-rose-300 dark:border-rose-400 font-bold text-slate-900 dark:text-white"
                                            : "bg-slate-50 dark:bg-white/[0.04] border-slate-200/60 dark:border-white/10 text-slate-500 dark:text-slate-400 opacity-75"
                                        }`}
                                      >
                                        <span
                                          className="w-4 h-4 rounded-full text-[10px] text-white flex items-center justify-center font-bold"
                                          style={{ backgroundColor: bColor.bg }}
                                        >
                                          {ab.num}
                                        </span>
                                        <span>{ab.xiao}</span>
                                        {ab.is_tema && (
                                          <span className="text-[9px] text-amber-600 dark:text-amber-400 font-bold">
                                            特
                                          </span>
                                        )}
                                      </span>
                                    );
                                  })}
                                </div>
                              </td>
                            </tr>
                          ))
                        )}
                      </tbody>
                    </TableContainer>
                  )}
                </>
              )}

              {/* VIEW 3: 12生肖连开/没出全景对比 */}
              {historyViewMode === "all_zodiacs" && (
                <TableContainer>
                  <thead>
                    <tr>
                      <th className={`${tableThClass} w-24`}>生肖</th>
                      <th className={`${tableThClass} w-32 text-center`}>开出 / 没出期数</th>
                      <th className={`${tableThClass} w-48`}>当前最新波段 (起止期号)</th>
                      <th className={`${tableThClass} w-48`}>最长连开区间 (从哪期到哪期)</th>
                      <th className={`${tableThClass} w-48`}>最长没出区间 (从哪期到哪期)</th>
                      <th className={`${tableThClass} min-w-[280px]`}>近期连开/没出波段历史</th>
                      <th className={`${tableThClass} w-24 text-center`}>操作</th>
                    </tr>
                  </thead>
                  <tbody>
                    {allZodiacsForHistory.map((z) => {
                      const missCount =
                        z.miss_periods_count ??
                        Math.max(0, (z.sample_periods || rankingData?.sample_periods || 0) - z.periods_count);
                      return (
                        <tr key={z.name} className={tableRowClass}>
                          <td className={tableTdClass}>
                            <div className="flex items-center gap-2">
                              <span className="w-7 h-7 rounded-lg bg-slate-100 dark:bg-white/[0.06] font-bold flex items-center justify-center text-xs">
                                {z.name}
                              </span>
                              <span className="font-bold text-slate-900 dark:text-white">
                                {z.label}
                              </span>
                            </div>
                          </td>
                          <td className={`${tableTdClass} text-center font-mono text-xs`}>
                            <span className="text-emerald-600 dark:text-emerald-400 font-bold">
                              开{z.periods_count}期
                            </span>{" "}
                            / <span>没出{missCount}期</span>
                          </td>
                          <td className={`${tableTdClass} font-mono text-xs`}>
                            <span
                              className={`font-bold ${
                                z.current_consecutive > 0
                                  ? "text-rose-600 dark:text-rose-400"
                                  : "text-amber-600 dark:text-amber-400"
                              }`}
                            >
                              {z.current_range?.text || "—"}
                            </span>
                          </td>
                          <td className={`${tableTdClass} font-mono text-xs text-rose-600 dark:text-rose-400 font-semibold`}>
                            {z.max_consecutive_range?.text || `连开${z.max_consecutive}期`}
                          </td>
                          <td className={`${tableTdClass} font-mono text-xs text-slate-600 dark:text-slate-300 font-semibold`}>
                            {z.max_omission_range?.text || `没出${z.max_omission}期`}
                          </td>
                          <td className={tableTdClass}>
                            <div className="flex flex-wrap gap-1">
                              {(z.recent_segments ?? []).slice(0, 5).map((seg, i) => (
                                <span
                                  key={i}
                                  className={`px-1.5 py-0.5 rounded text-[10px] font-mono ${
                                    seg.type === "hit"
                                      ? "bg-rose-50 text-rose-700 dark:bg-rose-500/15 dark:text-rose-300"
                                      : "bg-slate-100 text-slate-600 dark:bg-white/[0.06] dark:text-slate-400"
                                  }`}
                                >
                                  {seg.text}
                                </span>
                              ))}
                            </div>
                          </td>
                          <td className={`${tableTdClass} text-center`}>
                            <button
                              type="button"
                              onClick={() => {
                                setSelectedXiao(z.name);
                                setHistoryViewMode("segments");
                              }}
                              className="px-2.5 py-1 rounded-lg text-xs font-semibold bg-indigo-50 text-indigo-600 hover:bg-indigo-100 dark:bg-indigo-500/15 dark:text-indigo-300 cursor-pointer"
                            >
                              查看明细
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </TableContainer>
              )}
            </div>
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
