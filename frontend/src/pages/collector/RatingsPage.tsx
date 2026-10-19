import React, { useCallback, useEffect, useState } from "react";
import { Spinner } from "../../components/ui/spinner";
import { Button } from "../../components/ui/button";
import { Alert, AlertDescription } from "../../components/ui/alert";
import { ApiError } from "../../lib/api";
import { collectorApi, type Lottery, type RatingsResult, type RuleRow } from "../../lib/collector";
import {
  LOTTERIES,
  PageWorkspace,
  Select,
  TextInput,
  SectionCard,
  SegmentedTabs,
  TableContainer,
  tableThClass,
  tableTdClass,
  tableRowClass,
  StatusPill,
} from "./shared";
import { StarIcon, CalendarIcon, RefreshIcon } from "../../components/icons";
import { SourceHistoryModal } from "./SourceHistoryModal";

function pct(v: unknown): string {
  if (v == null || typeof v !== "number") return "—";
  return `${(v * 100).toFixed(1)}%`;
}

function parseWindows(value: string): number[] | null {
  const parts = value.split(",").map((item) => item.trim());
  if (!parts.length || parts.some((item) => !/^\d+$/.test(item))) return null;
  const parsed = parts.map(Number);
  if (parsed.some((item) => !Number.isSafeInteger(item) || item <= 0)) return null;
  return [...new Set(parsed)];
}

export function CollectorRatingsPage() {
  const [lottery, setLottery] = useState<Lottery>("macau");
  const [playType, setPlayType] = useState("pingte_xiao");
  const [windows, setWindows] = useState("30,50,100");
  const [rules, setRules] = useState<RuleRow[]>([]);
  const [data, setData] = useState<RatingsResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [sortCol, setSortCol] = useState<string | null>(null);
  const [sortDesc, setSortDesc] = useState(true);
  const [historyModal, setHistoryModal] = useState<{ sourceId: string; lottery: Lottery } | null>(
    null,
  );

  useEffect(() => {
    collectorApi.rules().then(setRules).catch(() => undefined);
  }, []);

  const run = useCallback(
    async (lot = lottery, pt = playType, winStr = windows) => {
      const parsedWindows = parseWindows(winStr);
      if (!parsedWindows) {
        setError("窗口必须是逗号分隔的正整数，例如 30,50,100");
        return;
      }

      const normalizedWindows = parsedWindows.join(",");
      setLoading(true);
      setError(null);
      try {
        setData(await collectorApi.ratings(lot, pt, normalizedWindows));
      } catch (err) {
        setError(err instanceof ApiError ? err.message : "查询失败");
      } finally {
        setLoading(false);
      }
    },
    [lottery, playType, windows],
  );

  useEffect(() => {
    void run(lottery, playType, windows);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lottery, playType]);

  const handleSort = (col: string) => {
    if (sortCol === col) {
      setSortDesc(!sortDesc);
    } else {
      setSortCol(col);
      setSortDesc(true);
    }
  };

  const playOptions = rules.length
    ? rules.map((r) => ({ value: r.play_type, label: r.name }))
    : [{ value: "pingte_xiao", label: "平特肖" }];

  const winList = data?.windows ?? [];

  const sortedSources = React.useMemo(() => {
    if (!data || !sortCol) return data?.sources ?? [];
    return [...data.sources].sort((a, b) => {
      let valA = (a as any)[sortCol];
      let valB = (b as any)[sortCol];
      if (valA == null) valA = -Infinity;
      if (valB == null) valB = -Infinity;

      if (valA < valB) return sortDesc ? 1 : -1;
      if (valA > valB) return sortDesc ? -1 : 1;
      return 0;
    });
  }, [data, sortCol, sortDesc]);

  const renderTh = (col: string, label: string) => (
    <th
      className={`${tableThClass} cursor-pointer hover:bg-slate-100/80 dark:hover:bg-white/[0.05] transition-colors select-none`}
      onClick={() => handleSort(col)}
      title="点击按此列排序"
    >
      <div className="flex items-center gap-1.5">
        <span>{label}</span>
        {sortCol === col ? (
          <span className="text-indigo-600 dark:text-indigo-400 font-bold text-xs">
            {sortDesc ? "▼" : "▲"}
          </span>
        ) : (
          <span className="text-slate-300 dark:text-slate-600 text-xs">↕</span>
        )}
      </div>
    </th>
  );

  return (
    <PageWorkspace summary="在同一滑动期号窗口下横向对比各数据源真实命中率、缺期数、连中连挂表现与虚假报喜记录。">
      {error && (
        <Alert variant="error">
          <AlertDescription className="text-sm">{error}</AlertDescription>
        </Alert>
      )}

      {/* 参数查询工具栏 */}
      <SectionCard
        title={
          <div className="flex items-center gap-2">
            <StarIcon size={17} className="text-indigo-600 dark:text-indigo-400" />
            <span>评级查询与滑动窗口配置</span>
          </div>
        }
        subtitle="切换彩种与玩法，或自定义多个观察窗口跨度（半角逗号分隔）"
      >
        <div className="flex items-center gap-3 flex-wrap">
          <SegmentedTabs
            tabs={LOTTERIES.map((l) => ({ id: l.value, label: l.label }))}
            activeTab={lottery}
            onChange={(v) => setLottery(v as Lottery)}
          />
          <Select
            value={playType}
            onChange={setPlayType}
            options={playOptions}
            className="min-w-[140px]"
          />
          <TextInput
            value={windows}
            onChange={setWindows}
            onKeyDown={(event) => {
              if (event.key === "Enter") void run();
            }}
            placeholder="窗口，如 30,50,100"
            className="w-40 font-mono"
          />
          <Button type="button" onClick={() => void run()} disabled={loading}>
            <RefreshIcon size={14} className={loading ? "animate-spin" : ""} />
            <span>{loading ? "计算评级中…" : "更新评级矩阵"}</span>
          </Button>
        </div>
      </SectionCard>

      {/* 评级结果表格 */}
      <SectionCard
        title={
          <div className="flex items-center gap-2.5 flex-wrap">
            <span>评级排行榜明细</span>
            {data && (
              <span className="text-xs font-mono px-2.5 py-0.5 rounded-lg bg-slate-100 dark:bg-white/[0.06] text-slate-600 dark:text-slate-400 font-normal">
                样本期号：{data.periods.length} 期 ({data.period_from ?? "—"} ~{" "}
                {data.period_to ?? "—"})
              </span>
            )}
          </div>
        }
      >
        {loading && !data ? (
          <div className="p-12 flex justify-center">
            <Spinner aria-label="加载中" />
          </div>
        ) : !data || data.sources.length === 0 ? (
          <div className="py-12 text-center text-sm text-slate-400">
            该条件下暂无匹配的数据源历史评级样本。
          </div>
        ) : (
          <TableContainer>
            <thead>
              <tr>
                <th className={tableThClass}>数据源名称 / ID</th>
                {winList.map((w) => renderTh(`hit_${w}`, `近 ${w} 期命中率`))}
                {renderTh("longest_hit", "最大连中")}
                {renderTh("longest_miss", "最大连挂")}
                {renderTh("missing", "缺期数")}
                {renderTh("pending", "待对奖")}
                {renderTh("dirty_flags", "虚假报喜(不一致)")}
                <th className={`${tableThClass} text-right`}>历史流水</th>
              </tr>
            </thead>
            <tbody>
              {sortedSources.map((s, idx) => (
                <tr key={s.source_id} className={tableRowClass}>
                  <td className={tableTdClass}>
                    <div
                      className="font-semibold text-slate-900 dark:text-white flex items-center gap-1.5 cursor-pointer hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors group"
                      onClick={() => setHistoryModal({ sourceId: s.source_id, lottery })}
                      title="点击查看该源全量历史对奖流水"
                    >
                      <span className="text-xs font-mono text-slate-400 group-hover:text-indigo-500 tabular-nums">
                        #{idx + 1}
                      </span>
                      <span className="underline decoration-dotted decoration-slate-300 dark:decoration-slate-600 underline-offset-2 group-hover:decoration-indigo-500">
                        {s.source_name}
                      </span>
                    </div>
                    <div className="text-xs font-mono text-slate-400 mt-0.5">{s.source_id}</div>
                  </td>
                  {winList.map((w) => {
                    const rateVal = s[`hit_${w}` as keyof typeof s] as number | null;
                    const countVal = (s as any)[`n_${w}`] ?? 0;
                    return (
                      <td key={w} className={tableTdClass}>
                        <div className="flex items-baseline gap-1.5 tabular-nums">
                          <span
                            className={`font-mono font-bold text-sm ${
                              rateVal && rateVal >= 0.5
                                ? "text-emerald-600 dark:text-emerald-400"
                                : "text-slate-800 dark:text-slate-200"
                            }`}
                          >
                            {pct(rateVal)}
                          </span>
                          <span className="text-xs text-slate-400 font-mono">({countVal})</span>
                        </div>
                      </td>
                    );
                  })}
                  <td className={tableTdClass}>
                    <span className="font-mono font-semibold text-emerald-600 dark:text-emerald-400 tabular-nums">
                      {s.longest_hit} 期
                    </span>
                  </td>
                  <td className={tableTdClass}>
                    <span className="font-mono text-slate-500 dark:text-slate-400 tabular-nums">
                      {s.longest_miss} 期
                    </span>
                  </td>
                  <td className={tableTdClass}>
                    <span
                      className={`font-mono tabular-nums ${
                        s.missing > 0 ? "text-amber-600 dark:text-amber-400 font-bold" : "text-slate-400"
                      }`}
                    >
                      {s.missing}
                    </span>
                  </td>
                  <td className={tableTdClass}>
                    <span className="font-mono text-slate-400 tabular-nums">{s.pending}</span>
                  </td>
                  <td className={tableTdClass}>
                    {s.dirty_flags > 0 ? (
                      <StatusPill variant="danger">{s.dirty_flags} 次不符</StatusPill>
                    ) : (
                      <StatusPill variant="success" dot={false}>
                        0 异常
                      </StatusPill>
                    )}
                  </td>
                  <td className={`${tableTdClass} text-right`}>
                    <button
                      type="button"
                      onClick={() => setHistoryModal({ sourceId: s.source_id, lottery })}
                      className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-medium bg-indigo-50 text-indigo-700 hover:bg-indigo-100 dark:bg-indigo-500/15 dark:text-indigo-300 dark:hover:bg-indigo-500/25 transition-colors cursor-pointer"
                      title="查看该源全部历史对奖与预测数据"
                    >
                      <CalendarIcon size={12} />
                      <span>历史</span>
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </TableContainer>
        )}
      </SectionCard>

      {/* 数据源历史数据详情弹窗 */}
      <SourceHistoryModal
        sourceId={historyModal?.sourceId ?? null}
        lottery={historyModal?.lottery}
        isOpen={!!historyModal}
        onClose={() => setHistoryModal(null)}
      />
    </PageWorkspace>
  );
}
