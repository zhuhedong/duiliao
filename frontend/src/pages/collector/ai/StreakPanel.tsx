import { DatabaseIcon } from "../../../components/icons";
import type { StreakRow } from "./types";

const STREAK_KINDS = ["三连", "四连", "五连", "N连"] as const;

function streakLabel(row: StreakRow): string {
  return row.length >= 6 ? `${row.length}连` : row.kind || `${row.length}连`;
}

function ChipGroup<T extends number | string>({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: { value: T; label: string }[];
  value: T;
  onChange: (v: T) => void;
}) {
  return (
    <div className="flex items-center gap-2">
      <span className="shrink-0 text-2xs font-semibold text-slate-500 dark:text-slate-400">{label}</span>
      <div className="flex gap-1">
        {options.map((o) => (
          <button
            key={String(o.value)}
            onClick={() => onChange(o.value)}
            className={`cursor-pointer rounded-lg px-2.5 py-1.5 text-xs font-medium transition-all ${
              value === o.value
                ? "glow-button border-0 shadow-xs"
                : "glass-subtle text-slate-600 dark:text-slate-400"
            }`}
          >
            {o.label}
          </button>
        ))}
      </div>
    </div>
  );
}

/** 连肖模式的紧凑参数条（置于指挥条下方） */
export function StreakConfigBar({
  lottery,
  numPeriods,
  minStreak,
  onLottery,
  onNumPeriods,
  onMinStreak,
  onLoadData,
  isLoadingData,
}: {
  lottery: "macau" | "hk";
  numPeriods: number;
  minStreak: number;
  onLottery: (v: "macau" | "hk") => void;
  onNumPeriods: (v: number) => void;
  onMinStreak: (v: number) => void;
  onLoadData: () => void;
  isLoadingData: boolean;
}) {
  return (
    <div className="flex flex-wrap items-center gap-x-5 gap-y-2.5 rounded-2xl glass-card px-4 py-3">
      <ChipGroup
        label="彩种"
        options={[
          { value: "macau" as const, label: "🇲🇴 澳门" },
          { value: "hk" as const, label: "🇭🇰 香港" },
        ]}
        value={lottery}
        onChange={onLottery}
      />
      <ChipGroup
        label="期数"
        options={[10, 20, 30, 50, 100].map((n) => ({ value: n, label: `${n}期` }))}
        value={numPeriods}
        onChange={onNumPeriods}
      />
      <ChipGroup
        label="最小连"
        options={[2, 3, 4, 5].map((n) => ({ value: n, label: `≥${n}连` }))}
        value={minStreak}
        onChange={onMinStreak}
      />
      <button
        onClick={onLoadData}
        disabled={isLoadingData}
        className="ml-auto inline-flex cursor-pointer items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold text-slate-700 glass-subtle transition-all hover:bg-fuchsia-500/5 disabled:opacity-50 dark:text-slate-300 dark:hover:bg-fuchsia-400/5"
      >
        <DatabaseIcon size={13} />
        {isLoadingData ? "查询中..." : "查看连肖数据"}
      </button>
    </div>
  );
}

function StreakBuckets({
  buckets,
}: {
  buckets: Record<string, StreakRow[] | Record<string, StreakRow[]>>;
}) {
  const fushi = (buckets["复式"] || {}) as Record<string, StreakRow[]>;
  const kinds = [
    ...(Array.isArray(buckets["二连"]) ? (["二连"] as const) : []),
    ...STREAK_KINDS,
  ];
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {kinds.map((kind) => {
        const rows = (buckets[kind] as StreakRow[] | undefined) || [];
        const fushiRows = fushi[kind] || [];
        return (
          <div key={kind} className="space-y-1.5 rounded-2xl glass-subtle p-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold text-fuchsia-700 dark:text-fuchsia-300">{kind}</span>
              <span className="text-2xs text-slate-400">
                {rows.length} 条 · 复式 {fushiRows.length} 组
              </span>
            </div>
            {rows.length === 0 && fushiRows.length === 0 ? (
              <div className="px-1 text-2xs text-slate-400">无</div>
            ) : (
              <>
                {rows.slice(0, 5).map((row, i) => (
                  <div
                    key={`${kind}-${row.xiao}-${row.start_period}-${i}`}
                    className="flex items-center justify-between rounded-lg bg-white/40 px-2.5 py-1 text-2xs dark:bg-white/5"
                  >
                    <span className="font-bold text-fuchsia-700 dark:text-fuchsia-300">
                      {row.xiao}
                      {row.is_active && (
                        <span className="ml-1 font-normal text-emerald-600 dark:text-emerald-400">活跃</span>
                      )}
                    </span>
                    <span className="text-slate-500">
                      {streakLabel(row)} ({row.start_period}→{row.end_period})
                    </span>
                  </div>
                ))}
                {fushiRows.slice(0, 4).map((row, i) => (
                  <div
                    key={`fushi-${kind}-${i}`}
                    className="flex items-center justify-between rounded-lg bg-white/40 px-2.5 py-1 text-2xs dark:bg-white/5"
                  >
                    <span className="font-bold text-violet-700 dark:text-violet-300">
                      {(row.xiaos || []).join(" + ")}
                      {row.is_active && (
                        <span className="ml-1 font-normal text-emerald-600 dark:text-emerald-400">活跃</span>
                      )}
                    </span>
                    <span className="text-slate-500">
                      复式{streakLabel(row)} ({row.start_period}→{row.end_period})
                    </span>
                  </div>
                ))}
              </>
            )}
          </div>
        );
      })}
    </div>
  );
}

/** 连肖数据预览（统计 + 各期明细） */
export function StreakDataView({ data }: { data: any }) {
  if (!data) return null;
  return (
    <div className="space-y-4 rounded-3xl glass-card p-4">
      <div className="flex items-center justify-between">
        <h4 className="text-sm font-bold text-slate-900 dark:text-white">📊 连肖统计概览</h4>
        <span className="text-2xs text-slate-400">
          第 {data.streaks?.period_range?.from} - {data.streaks?.period_range?.to} 期
        </span>
      </div>

      {data.streaks?.buckets && <StreakBuckets buckets={data.streaks.buckets} />}

      <div className="space-y-2">
        <div className="text-xs font-semibold text-slate-600 dark:text-slate-400">十二生肖出现统计</div>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-slate-200/60 dark:border-white/8">
                <th className="px-2 py-1.5 text-left text-slate-500">生肖</th>
                <th className="px-2 py-1.5 text-center text-slate-500">出现次数</th>
                <th className="px-2 py-1.5 text-center text-slate-500">出现率</th>
                <th className="px-2 py-1.5 text-center text-slate-500">最长连码</th>
                <th className="px-2 py-1.5 text-center text-slate-500">当前连码</th>
              </tr>
            </thead>
            <tbody>
              {data.streaks?.summary &&
                Object.entries(data.streaks.summary).map(([xiao, s]: [string, any]) => (
                  <tr
                    key={xiao}
                    className={`border-b border-slate-200/40 dark:border-white/5 ${
                      s.current_streak >= 3 ? "bg-fuchsia-500/5" : ""
                    }`}
                  >
                    <td className="px-2 py-1.5 font-bold text-slate-900 dark:text-white">{xiao}</td>
                    <td className="px-2 py-1.5 text-center">{s.total_appearances}</td>
                    <td className="px-2 py-1.5 text-center">{s.appearance_rate}%</td>
                    <td className="px-2 py-1.5 text-center font-bold text-amber-600 dark:text-amber-400">
                      {s.max_streak}
                    </td>
                    <td
                      className={`px-2 py-1.5 text-center font-bold ${
                        s.current_streak >= 3
                          ? "text-fuchsia-600 dark:text-fuchsia-400"
                          : "text-slate-500 dark:text-slate-400"
                      }`}
                    >
                      {s.current_streak > 0 ? s.current_streak : "-"}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </div>

      <div className="space-y-2">
        <div className="text-xs font-semibold text-slate-600 dark:text-slate-400">
          各期生肖明细（最近 {data.periods?.length || 0} 期）
        </div>
        <div className="max-h-60 overflow-auto">
          <table className="w-full whitespace-nowrap text-xs">
            <thead className="sticky top-0 glass-panel">
              <tr className="border-b border-slate-200/60 dark:border-white/8">
                <th className="px-2 py-1.5 text-left text-slate-500">期号</th>
                {["正1", "正2", "正3", "正4", "正5", "正6"].map((h) => (
                  <th key={h} className="px-1 py-1.5 text-center text-slate-500">
                    {h}
                  </th>
                ))}
                <th className="border-l border-slate-200/60 px-1 py-1.5 text-center text-slate-500 dark:border-white/10">
                  特码
                </th>
                <th className="border-l border-slate-200/60 px-2 py-1.5 text-left text-slate-500 dark:border-white/10">
                  去重生肖
                </th>
              </tr>
            </thead>
            <tbody>
              {(data.periods || []).slice().reverse().map((p: any) => (
                <tr
                  key={p.period}
                  className="border-b border-slate-200/40 hover:bg-fuchsia-500/5 dark:border-white/5 dark:hover:bg-fuchsia-400/5"
                >
                  <td className="px-2 py-1 font-mono font-bold text-slate-900 dark:text-white">{p.period}</td>
                  {p.xiaos.slice(0, 6).map((x: string, i: number) => (
                    <td key={i} className="px-1 py-1 text-center">
                      {x}
                    </td>
                  ))}
                  <td className="border-l border-slate-200/60 px-1 py-1 text-center font-bold text-amber-600 dark:border-white/10 dark:text-amber-400">
                    {p.xiaos[6] || "-"}
                  </td>
                  <td className="border-l border-slate-200/60 px-2 py-1 text-slate-500 dark:border-white/10">
                    {p.unique_xiaos?.join("、")}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
