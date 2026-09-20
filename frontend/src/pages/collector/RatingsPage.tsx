import React, { useEffect, useState } from "react";
import { Spinner } from "@appica/ui-react/spinner";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { ApiError } from "../../lib/api";
import { collectorApi, type Lottery, type RatingsResult, type RuleRow } from "../../lib/collector";
import {
  LOTTERIES,
  PageHeader,
  Select,
  TextInput,
  SectionCard,
  TableContainer,
  tableThClass,
  tableTdClass,
  tableRowClass,
  StatusPill,
} from "./shared";
import { StarIcon } from "../../components/icons";

function pct(v: unknown): string {
  if (v == null || typeof v !== "number") return "—";
  return `${(v * 100).toFixed(1)}%`;
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

  useEffect(() => {
    collectorApi.rules().then(setRules).catch(() => undefined);
  }, []);

  const run = async () => {
    setLoading(true);
    setError(null);
    setData(null);
    try {
      setData(await collectorApi.ratings(lottery, playType, windows.trim() || "30,50,100"));
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "查询失败");
    } finally {
      setLoading(false);
    }
  };

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
      className={`${tableThClass} cursor-pointer hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors select-none`}
      onClick={() => handleSort(col)}
      title="点击按此列排序"
    >
      <div className="flex items-center gap-1.5">
        <span>{label}</span>
        {sortCol === col ? (
          <span className="text-primary font-bold text-xs">{sortDesc ? "▼" : "▲"}</span>
        ) : (
          <span className="text-slate-300 dark:text-slate-600 text-xs">↕</span>
        )}
      </div>
    </th>
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="源可信评级度量"
        desc="按所有来源共用的最近 N 个期号滑动窗口比较真实命中率，展示样本量、缺期、未对奖、连中连挂及自称不一致(虚假宣传)核验结果。"
      />

      {error && (
        <Alert variant="error" className="rounded-2xl border border-rose-200 dark:border-rose-900 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200">
          <AlertDescription className="text-sm">{error}</AlertDescription>
        </Alert>
      )}

      {/* 参数查询工具栏 */}
      <SectionCard
        title={
          <div className="flex items-center gap-2">
            <StarIcon size={18} className="text-primary" />
            <span>评级查询与滑动窗口配置</span>
          </div>
        }
        subtitle="选择彩种与玩法，自定义多个观察窗口跨度（以半角逗号分隔）"
      >
        <div className="flex items-center gap-3 flex-wrap">
          <Select value={lottery} onChange={(v) => setLottery(v as Lottery)} options={LOTTERIES} />
          <Select value={playType} onChange={setPlayType} options={playOptions} className="min-w-[140px]" />
          <TextInput
            value={windows}
            onChange={setWindows}
            placeholder="窗口，如 30,50,100"
            className="min-w-[160px]"
          />
          <button
            type="button"
            onClick={run}
            disabled={loading}
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-semibold bg-primary hover:bg-primary/90 text-white shadow-xs transition-all disabled:opacity-50 cursor-pointer"
          >
            {loading ? "计算评级中…" : "计算评级矩阵"}
          </button>
        </div>
      </SectionCard>

      {/* 评级结果表格 */}
      {data && (
        <SectionCard
          title={
            <div className="flex items-center gap-3">
              <span>评级排行榜明细</span>
              <span className="text-xs font-mono px-2.5 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 border border-slate-200 dark:border-slate-700">
                样本期号：{data.periods.length} 期 ({data.period_from ?? "—"} ~ {data.period_to ?? "—"})
              </span>
            </div>
          }
        >
          {loading ? (
            <div className="p-12 flex justify-center">
              <Spinner aria-label="加载中" />
            </div>
          ) : data.sources.length === 0 ? (
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
                </tr>
              </thead>
              <tbody>
                {sortedSources.map((s, idx) => (
                  <tr key={s.source_id} className={tableRowClass}>
                    <td className={tableTdClass}>
                      <div className="font-semibold text-slate-900 dark:text-white flex items-center gap-1.5">
                        <span className="text-xs font-mono text-slate-400">#{idx + 1}</span>
                        <span>{s.source_name}</span>
                      </div>
                      <div className="text-xs font-mono text-slate-400 mt-0.5">{s.source_id}</div>
                    </td>
                    {winList.map((w) => {
                      const rateVal = s[`hit_${w}` as keyof typeof s] as number | null;
                      const countVal = (s as any)[`n_${w}`] ?? 0;
                      return (
                        <td key={w} className={tableTdClass}>
                          <div className="flex items-baseline gap-1.5">
                            <span className={`font-mono font-bold text-sm ${
                              rateVal && rateVal >= 0.5
                                ? "text-emerald-600 dark:text-emerald-400"
                                : "text-slate-800 dark:text-slate-200"
                            }`}>
                              {pct(rateVal)}
                            </span>
                            <span className="text-xs text-slate-400 font-mono">
                              ({countVal})
                            </span>
                          </div>
                        </td>
                      );
                    })}
                    <td className={tableTdClass}>
                      <span className="font-mono font-semibold text-emerald-600 dark:text-emerald-400">
                        {s.longest_hit} 期
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      <span className="font-mono text-slate-500 dark:text-slate-400">
                        {s.longest_miss} 期
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      <span className={`font-mono ${s.missing > 0 ? "text-amber-500 font-bold" : "text-slate-400"}`}>
                        {s.missing}
                      </span>
                    </td>
                    <td className={tableTdClass}>
                      <span className="font-mono text-slate-400">{s.pending}</span>
                    </td>
                    <td className={tableTdClass}>
                      {s.dirty_flags > 0 ? (
                        <StatusPill variant="danger">{s.dirty_flags} 次不符</StatusPill>
                      ) : (
                        <StatusPill variant="success" dot={false}>0 异常</StatusPill>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </TableContainer>
          )}
        </SectionCard>
      )}
    </div>
  );
}
