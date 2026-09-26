/**
 * 工作台 — 业务数据总览。
 *
 * 数据来自 GET /collector/overview（单次请求聚合）：头部 KPI、最新开奖、
 * 近 7 日对料趋势、源命中率排行、玩法分布、采集告警与调度动态。
 * 进入页面加载一次，之后每 2 分钟静默刷新，也可手动刷新。
 */
import { useCallback, useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import { ApiError } from "../lib/api";
import {
  collectorApi,
  LOTTERY_LABEL,
  type DrawRow,
  type OverviewResult,
} from "../lib/collector";
import { BOSE_COLORS, ensureDrawDetails } from "../lib/lotteryAttr";
import {
  ActivityIcon,
  AlertIcon,
  ArrowRightIcon,
  CalendarIcon,
  CheckIcon,
  ClockIcon,
  CompareIcon,
  DatabaseIcon,
  HashIcon,
  RefreshIcon,
  SettingsIcon,
  SparklesIcon,
  StarIcon,
  TargetIcon,
  TrendIcon,
  TrophyIcon,
} from "../components/icons";
import { StatusPill, playLabel } from "./collector/shared";

const AUTO_REFRESH_MS = 120_000;

// --------------------------------------------------------------------------- //
// 小工具
// --------------------------------------------------------------------------- //
function pct(v: number | null | undefined, digits = 1): string {
  if (v === null || v === undefined) return "—";
  return `${(v * 100).toFixed(digits)}%`;
}

/** 命中率配色：≥60 优，≥45 良，≥35 中，否则偏弱。 */
function rateTone(v: number | null | undefined): string {
  if (v === null || v === undefined) return "text-slate-400";
  if (v >= 0.6) return "text-emerald-600 dark:text-emerald-300";
  if (v >= 0.45) return "text-violet-600 dark:text-violet-300";
  if (v >= 0.35) return "text-amber-600 dark:text-amber-300";
  return "text-rose-600 dark:text-rose-300";
}

function rateBar(v: number | null | undefined): string {
  if (v === null || v === undefined) return "bg-slate-400/40";
  if (v >= 0.6) return "bg-emerald-500";
  if (v >= 0.45) return "bg-violet-500";
  if (v >= 0.35) return "bg-amber-500";
  return "bg-rose-500";
}

/** "YYYY-MM-DD HH:MM:SS" → "MM-DD HH:MM" */
function fmtMinute(s: string | null | undefined): string {
  if (!s) return "—";
  const m = s.match(/^\d{4}-(\d{2}-\d{2})[ T](\d{2}:\d{2})/);
  return m ? `${m[1]} ${m[2]}` : s;
}

function fmtDay(s: string): string {
  return s.slice(5); // "2026-09-26" → "09-26"
}

function greet(): string {
  const h = new Date().getHours();
  if (h < 6) return "夜深了";
  if (h < 12) return "上午好";
  if (h < 14) return "中午好";
  if (h < 18) return "下午好";
  return "晚上好";
}

// --------------------------------------------------------------------------- //
// 页面
// --------------------------------------------------------------------------- //
export function DashboardPage() {
  const { user } = useAuth();
  const [data, setData] = useState<OverviewResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const mounted = useRef(true);

  const load = useCallback(async (silent = false) => {
    if (silent) setRefreshing(true);
    else setLoading(true);
    try {
      const res = await collectorApi.overview();
      if (!mounted.current) return;
      setData(res);
      setError(null);
    } catch (err) {
      if (!mounted.current) return;
      setError(err instanceof ApiError ? err.message : "工作台数据加载失败");
    } finally {
      if (mounted.current) {
        setLoading(false);
        setRefreshing(false);
      }
    }
  }, []);

  useEffect(() => {
    mounted.current = true;
    void load();
    const timer = setInterval(() => void load(true), AUTO_REFRESH_MS);
    return () => {
      mounted.current = false;
      clearInterval(timer);
    };
  }, [load]);

  if (!user) return null;

  return (
    <div className="workspace-fill w-full flex flex-col gap-3 content-start">
      {/* 顶部：问候 + 刷新 */}
      <header className="rounded-[28px] glass-panel px-5 sm:px-6 py-4 flex items-center gap-4 flex-wrap">
        <div className="min-w-0 flex-1">
          <div className="text-[11px] uppercase tracking-[0.18em] text-violet-600 dark:text-violet-300">
            工作台 · {data?.today.date ?? new Date().toISOString().slice(0, 10)}
          </div>
          <h2 className="mt-1 text-xl sm:text-2xl font-bold tracking-tight text-slate-900 dark:text-white truncate">
            {greet()}，{user.display_name || user.email}
          </h2>
          <p className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
            采集、对料、判定与调度的实时经营总览
            {data ? ` · 数据更新于 ${data.generated_at.slice(11)}` : ""}
          </p>
        </div>
        <button
          type="button"
          onClick={() => void load(true)}
          disabled={loading || refreshing}
          className="inline-flex items-center gap-2 h-9 px-4 rounded-xl text-xs font-semibold glass-subtle text-slate-700 dark:text-slate-200 hover:bg-violet-500/10 transition-colors cursor-pointer disabled:opacity-60"
        >
          <RefreshIcon size={14} className={refreshing ? "animate-spin" : ""} />
          刷新数据
        </button>
      </header>

      {error && (
        <div className="rounded-2xl border border-rose-400/40 dark:border-rose-400/25 bg-rose-500/10 text-rose-700 dark:text-rose-300 backdrop-blur-md px-4 py-3 text-sm flex items-center justify-between gap-3">
          <span>{error}</span>
          <button
            type="button"
            onClick={() => void load()}
            className="shrink-0 text-xs font-semibold underline underline-offset-2 cursor-pointer"
          >
            重试
          </button>
        </div>
      )}

      {loading && !data ? (
        <DashboardSkeleton />
      ) : data ? (
        <>
          <KpiRow data={data} />

          <div className="grid grid-cols-1 xl:grid-cols-12 gap-3">
            <section className="xl:col-span-7">
              <LatestDrawsPanel draws={data.latest_draws} />
            </section>
            <section className="xl:col-span-5">
              <TrendPanel data={data} />
            </section>
            <section className="xl:col-span-7">
              <LeaderboardPanel data={data} />
            </section>
            <section className="xl:col-span-5">
              <PlayTypePanel data={data} />
            </section>
            <section className="xl:col-span-5">
              <AlertsPanel data={data} />
            </section>
            <section className="xl:col-span-7">
              <SchedulePanel data={data} />
            </section>
          </div>

          <QuickNav />
        </>
      ) : null}
    </div>
  );
}

// --------------------------------------------------------------------------- //
// 加载骨架
// --------------------------------------------------------------------------- //
function DashboardSkeleton() {
  return (
    <div className="flex flex-col gap-3 animate-pulse">
      <div className="grid grid-cols-2 xl:grid-cols-4 gap-3">
        {[0, 1, 2, 3].map((i) => (
          <div key={i} className="rounded-3xl glass-card h-28" />
        ))}
      </div>
      <div className="grid grid-cols-1 xl:grid-cols-12 gap-3">
        <div className="xl:col-span-7 rounded-3xl glass-card h-64" />
        <div className="xl:col-span-5 rounded-3xl glass-card h-64" />
        <div className="xl:col-span-7 rounded-3xl glass-card h-72" />
        <div className="xl:col-span-5 rounded-3xl glass-card h-72" />
      </div>
    </div>
  );
}

// --------------------------------------------------------------------------- //
// KPI 指标卡
// --------------------------------------------------------------------------- //
function KpiRow({ data }: { data: OverviewResult }) {
  const { judge, today, totals, alerts } = data;
  const collectRate = today.source_total > 0 ? today.source_ok / today.source_total : null;
  const coverageRate = totals.sources > 0 ? totals.sources_enabled / totals.sources : null;
  const alertTotal = alerts.lagging_sources + judge.pending_judge;

  const cards: {
    icon: ReactNode;
    label: string;
    value: string;
    valueClass: string;
    sub: string;
    bar?: number | null;
    to: string;
  }[] = [
    {
      icon: <TargetIcon size={18} />,
      label: "综合命中率",
      value: pct(judge.hit_rate),
      valueClass: rateTone(judge.hit_rate),
      sub: `中 ${judge.hits.toLocaleString()} / 判定 ${judge.judged.toLocaleString()} · 今日 ${pct(judge.today_hit_rate)}`,
      bar: judge.hit_rate,
      to: "/collector/ratings",
    },
    {
      icon: <DatabaseIcon size={18} />,
      label: "数据覆盖",
      value: `${totals.sources_enabled}/${totals.sources}`,
      valueClass: "text-violet-600 dark:text-violet-300",
      sub: `启用源 · ${totals.predictions.toLocaleString()} 条预测 · ${totals.draws.toLocaleString()} 期开奖`,
      bar: coverageRate,
      to: "/collector/sources",
    },
    {
      icon: <ActivityIcon size={18} />,
      label: "今日采集",
      value: today.source_total > 0 ? `${today.source_ok}/${today.source_total}` : "未采集",
      valueClass:
        today.source_total === 0
          ? "text-slate-400"
          : collectRate !== null && collectRate >= 0.95
            ? "text-emerald-600 dark:text-emerald-300"
            : "text-amber-600 dark:text-amber-300",
      sub: `${today.crawl_runs} 轮 · 新增预测 ${today.new_predictions.toLocaleString()} 条`,
      bar: collectRate,
      to: "/collector/sources",
    },
    {
      icon: <AlertIcon size={18} />,
      label: "待办告警",
      value: alertTotal > 0 ? String(alertTotal) : "全部同步",
      valueClass:
        alertTotal > 0
          ? "text-amber-600 dark:text-amber-300"
          : "text-emerald-600 dark:text-emerald-300",
      sub: `缺期源 ${alerts.lagging_sources} · 待判定 ${judge.pending_judge} · 未采集 ${alerts.never_collected}`,
      to: "/collector/monitor",
    },
  ];

  return (
    <div className="grid grid-cols-2 xl:grid-cols-4 gap-3">
      {cards.map((c) => (
        <Link
          key={c.label}
          to={c.to}
          className="rounded-3xl glass-card p-4 sm:p-5 flex flex-col justify-between gap-3 no-underline text-inherit hover:bg-violet-500/5 transition-colors group"
        >
          <div className="flex items-center justify-between">
            <span className="inline-flex items-center gap-1.5 text-xs text-slate-500 dark:text-slate-400">
              <span className="text-violet-500 dark:text-violet-300">{c.icon}</span>
              {c.label}
            </span>
            <ArrowRightIcon
              size={13}
              className="text-slate-300 dark:text-slate-600 group-hover:text-violet-500 group-hover:translate-x-0.5 transition-all"
            />
          </div>
          <div>
            <div className={`text-2xl sm:text-[26px] font-extrabold tracking-tight leading-none ${c.valueClass}`}>
              {c.value}
            </div>
            <div className="mt-1.5 text-[11px] text-slate-400 dark:text-slate-500">{c.sub}</div>
            {c.bar !== undefined && (
              <div className="mt-2.5 h-1 rounded-full bg-slate-200/60 dark:bg-white/8 overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all ${rateBar(c.bar)}`}
                  style={{ width: `${Math.round((c.bar ?? 0) * 100)}%` }}
                />
              </div>
            )}
          </div>
        </Link>
      ))}
    </div>
  );
}

// --------------------------------------------------------------------------- //
// 最新开奖
// --------------------------------------------------------------------------- //
function LatestDrawsPanel({ draws }: { draws: DrawRow[] }) {
  const [active, setActive] = useState(0);
  if (draws.length === 0) {
    return (
      <PanelShell title="最新开奖" icon={<TrophyIcon size={16} />} more={{ to: "/collector/draws", label: "开奖管理" }}>
        <EmptyHint text="暂无开奖数据，请先执行开奖同步" />
      </PanelShell>
    );
  }
  const idx = Math.min(active, draws.length - 1);
  const draw = draws[idx];
  const { ballsDetail, temaDetail, summary } = ensureDrawDetails(draw);

  return (
    <PanelShell
      title="最新开奖"
      icon={<TrophyIcon size={16} />}
      more={{ to: "/collector/draws", label: "开奖管理" }}
      tabs={
        <div className="inline-flex items-center gap-1 p-0.5 rounded-xl glass-subtle">
          {draws.map((d, i) => (
            <button
              key={d.lottery}
              type="button"
              onClick={() => setActive(i)}
              className={`px-2.5 py-1 rounded-[10px] text-[11px] font-semibold transition-colors cursor-pointer ${
                i === idx
                  ? "bg-white/80 dark:bg-white/10 text-violet-700 dark:text-violet-200 shadow-sm"
                  : "text-slate-500 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-200"
              }`}
            >
              {LOTTERY_LABEL[d.lottery] ?? d.lottery}
            </button>
          ))}
        </div>
      }
    >
      <div className="flex items-baseline gap-2 flex-wrap">
        <span className="text-lg font-extrabold tracking-tight text-slate-900 dark:text-white">
          第 {draw.period} 期
        </span>
        <span className="text-xs text-slate-400">{draw.draw_date ?? "日期待定"}</span>
      </div>

      {/* 号码球 */}
      <div className="mt-4 flex items-end gap-2 sm:gap-2.5 flex-wrap">
        {ballsDetail.map((b) => (
          <MiniBall key={b.num} num={b.num} xiao={b.xiao} bose={b.bose} lianxiao={b.is_lianxiao} />
        ))}
        <span className="self-center text-slate-300 dark:text-slate-600 font-light text-xl px-0.5">+</span>
        <MiniBall
          num={temaDetail.num}
          xiao={temaDetail.xiao}
          bose={temaDetail.bose}
          lianxiao={temaDetail.is_lianxiao}
          tema
        />
      </div>

      {/* 汇总标签 */}
      <div className="mt-4 flex flex-wrap gap-1.5">
        <SummaryChip>
          总分 {summary.sum7} · {summary.sum7_size}
          {summary.sum7_odd}
        </SummaryChip>
        <SummaryChip>
          特码 {summary.tema_xiao} · {summary.tema_bose}波 · {summary.tema_size}
          {summary.tema_odd}
        </SummaryChip>
        <SummaryChip accent={summary.has_lianxiao}>{summary.lianxiao_text ?? "7肖各异"}</SummaryChip>
      </div>
    </PanelShell>
  );
}

function MiniBall({
  num,
  xiao,
  bose,
  lianxiao = false,
  tema = false,
}: {
  num: string;
  xiao?: string;
  bose?: string;
  lianxiao?: boolean;
  tema?: boolean;
}) {
  const cfg = BOSE_COLORS[bose ?? "红"] ?? BOSE_COLORS["红"];
  return (
    <div className="inline-flex flex-col items-center gap-1">
      <div
        className={`flex items-center justify-center rounded-full font-bold font-mono text-white select-none ${
          tema
            ? "w-9 h-9 text-sm ring-2 ring-amber-400 ring-offset-1 ring-offset-transparent shadow-md shadow-amber-500/25"
            : "w-8 h-8 text-xs"
        } ${lianxiao && !tema ? "ring-2 ring-purple-500/70" : ""}`}
        style={{ backgroundColor: cfg.bg }}
        title={`${num}号 ${xiao ?? ""}`}
      >
        {num}
      </div>
      <span
        className={`text-[10px] leading-none ${
          lianxiao ? "text-purple-600 dark:text-purple-400 font-bold" : "text-slate-500 dark:text-slate-400"
        }`}
      >
        {xiao ?? "—"}
      </span>
    </div>
  );
}

function SummaryChip({ children, accent = false }: { children: ReactNode; accent?: boolean }) {
  return (
    <span
      className={`inline-flex items-center px-2.5 py-1 rounded-lg text-[11px] font-medium border ${
        accent
          ? "bg-purple-500/10 text-purple-700 dark:text-purple-300 border-purple-400/30"
          : "glass-subtle text-slate-600 dark:text-slate-300 border-transparent"
      }`}
    >
      {children}
    </span>
  );
}

// --------------------------------------------------------------------------- //
// 近 7 日对料趋势
// --------------------------------------------------------------------------- //
function TrendPanel({ data }: { data: OverviewResult }) {
  const trend = data.trend_7d;
  const judgedDays = trend.filter((t) => t.judged > 0);
  const avg =
    judgedDays.length > 0
      ? judgedDays.reduce((a, t) => a + t.hits, 0) / judgedDays.reduce((a, t) => a + t.judged, 0)
      : null;

  return (
    <PanelShell
      title="近 7 日对料趋势"
      icon={<TrendIcon size={16} />}
      subtitle={avg !== null ? `日均命中率 ${pct(avg)}` : "近 7 日暂无判定记录"}
    >
      <div className="mt-2 flex items-end gap-2 sm:gap-3 h-44">
        {trend.map((t) => {
          const isToday = t.date === data.today.date;
          const h = t.hit_rate !== null ? Math.max(t.hit_rate * 100, 6) : 0;
          return (
            <div key={t.date} className="flex-1 min-w-0 flex flex-col items-center gap-1.5 h-full">
              <div
                className={`text-[10px] font-bold leading-none ${t.hit_rate !== null ? rateTone(t.hit_rate) : "text-slate-300 dark:text-slate-600"}`}
              >
                {t.hit_rate !== null ? pct(t.hit_rate, 0) : "—"}
              </div>
              <div className="flex-1 w-full flex items-end">
                {t.hit_rate !== null ? (
                  <div
                    className={`w-full rounded-t-lg ${rateBar(t.hit_rate)} ${isToday ? "" : "opacity-70"}`}
                    style={{ height: `${h}%` }}
                    title={`${t.date}：中 ${t.hits} / 判定 ${t.judged}`}
                  />
                ) : (
                  <div className="w-full rounded-t-lg bg-slate-200/50 dark:bg-white/5" style={{ height: "4%" }} />
                )}
              </div>
              <div
                className={`text-[10px] leading-none ${
                  isToday
                    ? "font-bold text-violet-600 dark:text-violet-300"
                    : "text-slate-400 dark:text-slate-500"
                }`}
              >
                {isToday ? "今天" : fmtDay(t.date)}
              </div>
              <div className="text-[9px] leading-none text-slate-300 dark:text-slate-600">
                {t.judged > 0 ? `${t.hits}/${t.judged}` : "·"}
              </div>
            </div>
          );
        })}
      </div>
    </PanelShell>
  );
}

// --------------------------------------------------------------------------- //
// 源命中率排行
// --------------------------------------------------------------------------- //
function LeaderboardPanel({ data }: { data: OverviewResult }) {
  const rows = data.leaderboard;
  return (
    <PanelShell
      title="源命中率排行"
      icon={<StarIcon size={16} />}
      subtitle="判定 ≥10 期的数据源，按命中率排序"
      more={{ to: "/collector/ratings", label: "完整评级" }}
    >
      {rows.length === 0 ? (
        <EmptyHint text="暂无足够的判定数据生成排行" />
      ) : (
        <ol className="flex flex-col divide-y divide-slate-200/50 dark:divide-white/6">
          {rows.map((r, i) => (
            <li key={r.source_id} className="flex items-center gap-3 py-2.5">
              <span
                className={`w-6 h-6 shrink-0 rounded-lg flex items-center justify-center text-[11px] font-extrabold ${
                  i === 0
                    ? "bg-amber-500/15 text-amber-600 dark:text-amber-300"
                    : i === 1
                      ? "bg-slate-400/15 text-slate-500 dark:text-slate-300"
                      : i === 2
                        ? "bg-orange-500/15 text-orange-600 dark:text-orange-300"
                        : "text-slate-400"
                }`}
              >
                {i + 1}
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-semibold truncate text-slate-800 dark:text-slate-100">
                    {r.source_name}
                  </span>
                  <span className="shrink-0 text-[10px] px-1.5 py-0.5 rounded-md glass-subtle text-slate-500 dark:text-slate-400">
                    {r.play_type ? playLabel(r.play_type) : "—"}
                  </span>
                  {r.streak_hit !== null && r.current_streak >= 2 && (
                    <span
                      className={`shrink-0 text-[10px] font-bold ${
                        r.streak_hit
                          ? "text-emerald-600 dark:text-emerald-300"
                          : "text-rose-600 dark:text-rose-300"
                      }`}
                    >
                      {r.streak_hit ? `连中${r.current_streak}` : `连挂${r.current_streak}`}
                    </span>
                  )}
                </div>
                <div className="mt-1.5 flex items-center gap-2">
                  <div className="flex-1 h-1.5 rounded-full bg-slate-200/60 dark:bg-white/8 overflow-hidden">
                    <div
                      className={`h-full rounded-full ${rateBar(r.hit_rate)}`}
                      style={{ width: `${Math.round((r.hit_rate ?? 0) * 100)}%` }}
                    />
                  </div>
                  {/* 近期战绩点 */}
                  <span className="hidden sm:inline-flex items-center gap-[3px] shrink-0">
                    {r.recent.slice(0, 8).map((hit, j) => (
                      <span
                        key={j}
                        className={`w-1.5 h-1.5 rounded-full ${hit ? "bg-emerald-500" : "bg-rose-400"}`}
                      />
                    ))}
                  </span>
                </div>
              </div>
              <div className="shrink-0 text-right">
                <div className={`text-sm font-extrabold ${rateTone(r.hit_rate)}`}>{pct(r.hit_rate)}</div>
                <div className="text-[10px] text-slate-400">
                  {r.hits}/{r.judged} 期
                </div>
              </div>
            </li>
          ))}
        </ol>
      )}
    </PanelShell>
  );
}

// --------------------------------------------------------------------------- //
// 玩法命中率分布
// --------------------------------------------------------------------------- //
function PlayTypePanel({ data }: { data: OverviewResult }) {
  const rows = data.play_type_dist.slice(0, 8);
  const maxJudged = Math.max(1, ...rows.map((r) => r.judged));
  return (
    <PanelShell
      title="玩法命中率分布"
      icon={<CompareIcon size={16} />}
      subtitle={`共 ${data.totals.judge_results.toLocaleString()} 条判定记录`}
    >
      {rows.length === 0 ? (
        <EmptyHint text="暂无判定数据" />
      ) : (
        <div className="flex flex-col gap-2.5 mt-1">
          {rows.map((r) => (
            <div key={r.play_type} className="flex items-center gap-3">
              <span className="w-14 shrink-0 text-xs font-semibold text-slate-700 dark:text-slate-200 truncate">
                {playLabel(r.play_type)}
              </span>
              <div className="flex-1 min-w-0">
                <div className="h-4 rounded-lg bg-slate-200/50 dark:bg-white/6 overflow-hidden relative">
                  <div
                    className={`h-full rounded-lg ${rateBar(r.hit_rate)} opacity-80`}
                    style={{ width: `${(r.judged / maxJudged) * 100}%` }}
                  />
                  <span className="absolute inset-0 flex items-center px-2 text-[10px] font-medium text-slate-600 dark:text-slate-300">
                    {r.judged.toLocaleString()} 期
                  </span>
                </div>
              </div>
              <span className={`w-14 shrink-0 text-right text-xs font-extrabold ${rateTone(r.hit_rate)}`}>
                {pct(r.hit_rate)}
              </span>
            </div>
          ))}
        </div>
      )}
      <p className="mt-3 text-[10px] text-slate-400 dark:text-slate-500 leading-relaxed">
        条形长度代表判定样本量，颜色代表命中率水平。
      </p>
    </PanelShell>
  );
}

// --------------------------------------------------------------------------- //
// 采集告警
// --------------------------------------------------------------------------- //
function AlertsPanel({ data }: { data: OverviewResult }) {
  const { alerts, judge } = data;
  const ok = alerts.lagging_sources === 0 && judge.pending_judge === 0 && alerts.never_collected === 0;
  return (
    <PanelShell
      title="采集告警"
      icon={<AlertIcon size={16} />}
      more={{ to: "/collector/monitor", label: "缺期监控" }}
      subtitle={ok ? "所有启用源均已同步到最新期" : undefined}
    >
      <div className="grid grid-cols-3 gap-2 mb-3">
        <AlertStat label="缺期源" value={alerts.lagging_sources} danger={alerts.lagging_sources > 0} />
        <AlertStat label="待判定" value={judge.pending_judge} danger={judge.pending_judge > 0} />
        <AlertStat
          label="确认缺期"
          value={alerts.confirmed_missing_total}
          danger={false}
        />
      </div>
      {ok && alerts.items.length === 0 ? (
        <div className="flex items-center gap-2 rounded-2xl bg-emerald-500/8 border border-emerald-400/25 px-4 py-3 text-xs text-emerald-700 dark:text-emerald-300">
          <CheckIcon size={14} />
          数据覆盖完整，无需处理
        </div>
      ) : (
        <ul className="flex flex-col divide-y divide-slate-200/50 dark:divide-white/6">
          {alerts.items.map((a) => (
            <li key={a.source_id} className="flex items-center gap-3 py-2.5">
              <div className="min-w-0 flex-1">
                <div className="text-sm font-semibold truncate text-slate-800 dark:text-slate-100">
                  {a.source_name}
                </div>
                <div className="text-[11px] text-slate-400 mt-0.5">
                  {LOTTERY_LABEL[a.lottery] ?? a.lottery} · {playLabel(a.play_type)} · 最新 {a.latest_period}
                </div>
              </div>
              {a.lag > 0 && <StatusPill variant="warning">缺 {a.lag} 期</StatusPill>}
              {a.missing > 0 && <StatusPill variant="neutral">确认缺 {a.missing}</StatusPill>}
            </li>
          ))}
        </ul>
      )}
      {alerts.items.length > 0 && (
        <p className="mt-3 text-[10px] text-slate-400 dark:text-slate-500">
          缺期 = 已开奖但该源尚未采集入库的期数，前往缺期监控可批量确认。
        </p>
      )}
    </PanelShell>
  );
}

function AlertStat({ label, value, danger }: { label: string; value: number; danger: boolean }) {
  return (
    <div
      className={`rounded-2xl px-3 py-2.5 text-center border ${
        danger
          ? "bg-amber-500/8 border-amber-400/25"
          : "bg-slate-500/5 border-slate-300/20 dark:border-white/6"
      }`}
    >
      <div
        className={`text-lg font-extrabold leading-none ${
          danger ? "text-amber-600 dark:text-amber-300" : "text-slate-700 dark:text-slate-200"
        }`}
      >
        {value.toLocaleString()}
      </div>
      <div className="mt-1 text-[10px] text-slate-400">{label}</div>
    </div>
  );
}

// --------------------------------------------------------------------------- //
// 调度与最近采集
// --------------------------------------------------------------------------- //
function SchedulePanel({ data }: { data: OverviewResult }) {
  const sched = data.scheduler;
  const draw = sched?.draw;
  const next = data.upcoming_schedules[0];

  return (
    <PanelShell
      title="调度与最近采集"
      icon={<ClockIcon size={16} />}
      more={{ to: "/collector/sources", label: "任务管理" }}
    >
      {/* 开奖同步 + 采集调度状态行 */}
      <div className="flex flex-wrap gap-2">
        <StatusPill variant={draw?.enabled ? (draw.in_window ? "success" : "info") : "neutral"}>
          开奖自动同步{draw?.enabled ? (draw.in_window ? " · 窗口内运行中" : " · 已启用") : " · 已停用"}
        </StatusPill>
        {draw?.next_run_at && (
          <StatusPill variant="neutral" dot={false}>
            下次同步 {fmtMinute(draw.next_run_at)}
          </StatusPill>
        )}
        {sched?.source && (
          <StatusPill variant={sched.source.active_tasks_count > 0 ? "warning" : "success"}>
            {sched.source.active_tasks_count > 0
              ? `${sched.source.active_tasks_count} 个采集任务进行中`
              : "采集调度空闲"}
          </StatusPill>
        )}
      </div>

      {/* 下一个定时任务 */}
      {next && (
        <div className="mt-3 rounded-2xl bg-violet-500/6 border border-violet-400/20 px-4 py-3 flex items-center gap-3">
          <CalendarIcon size={16} className="text-violet-500 dark:text-violet-300 shrink-0" />
          <div className="min-w-0 flex-1">
            <div className="text-xs font-semibold text-slate-800 dark:text-slate-100 truncate">{next.name}</div>
            <div className="text-[11px] text-slate-400 mt-0.5">
              {LOTTERY_LABEL[next.lottery] ?? next.lottery}
              {next.cron ? ` · ${next.cron}` : ""}
            </div>
          </div>
          <div className="shrink-0 text-right">
            <div className="text-[10px] text-slate-400">下次执行</div>
            <div className="text-xs font-bold text-violet-600 dark:text-violet-300">
              {fmtMinute(next.next_run_at)}
            </div>
          </div>
        </div>
      )}

      {/* 最近采集日志 */}
      <div className="mt-4">
        <div className="text-[11px] font-semibold text-slate-400 uppercase tracking-wider mb-2">最近执行</div>
        {data.recent_logs.length === 0 ? (
          <EmptyHint text="暂无采集执行记录" />
        ) : (
          <ol className="relative space-y-3 pl-4 border-l border-violet-400/25">
            {data.recent_logs.slice(0, 5).map((log) => (
              <li key={log.id} className="relative">
                <span
                  className={`absolute -left-[21px] top-1.5 w-2 h-2 rounded-full ${
                    log.status === "success"
                      ? "bg-emerald-500 shadow-[0_0_5px_rgba(16,185,129,0.6)]"
                      : log.status === "running"
                        ? "bg-amber-500 shadow-[0_0_5px_rgba(245,158,11,0.6)]"
                        : "bg-rose-500 shadow-[0_0_5px_rgba(244,63,94,0.6)]"
                  }`}
                />
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-xs font-semibold text-slate-800 dark:text-slate-100">
                    {log.schedule_name}
                  </span>
                  <span className="text-[10px] text-slate-400">{log.action}</span>
                  <span className="ml-auto text-[10px] text-slate-400 shrink-0">
                    {fmtMinute(log.created_at)}
                  </span>
                </div>
                <div className="text-[11px] text-slate-500 dark:text-slate-400 mt-0.5">
                  {log.status === "success" ? "成功" : log.status === "running" ? "执行中" : "失败"}
                  {log.source_total > 0 && ` · 源 ${log.source_ok}/${log.source_total}`}
                  {log.duration_sec !== null && ` · 耗时 ${log.duration_sec.toFixed(1)}s`}
                  {log.period ? ` · 期号 ${log.period}` : ""}
                </div>
              </li>
            ))}
          </ol>
        )}
      </div>
    </PanelShell>
  );
}

// --------------------------------------------------------------------------- //
// 业务入口
// --------------------------------------------------------------------------- //
function QuickNav() {
  const items = [
    { to: "/collector/ai-analysis", label: "AI 研判", icon: <SparklesIcon size={18} /> },
    { to: "/collector/sources", label: "数据源采集", icon: <DatabaseIcon size={18} /> },
    { to: "/collector/draws", label: "开奖管理", icon: <TrophyIcon size={18} /> },
    { to: "/collector/consensus", label: "多源对照", icon: <CompareIcon size={18} /> },
    { to: "/collector/ratings", label: "源可信评级", icon: <StarIcon size={18} /> },
    { to: "/collector/monitor", label: "服务监控", icon: <ActivityIcon size={18} /> },
    { to: "/collector/numbers", label: "号码分析", icon: <HashIcon size={18} /> },
    { to: "/settings", label: "系统设置", icon: <SettingsIcon size={18} /> },
  ];
  return (
    <nav className="rounded-[28px] glass-card p-4">
      <div className="px-1 pb-3 text-sm font-semibold text-slate-900 dark:text-white">业务入口</div>
      <div className="grid grid-cols-4 sm:grid-cols-8 gap-2">
        {items.map((it) => (
          <Link
            key={it.to}
            to={it.to}
            className="flex flex-col items-center gap-2 py-3 rounded-2xl no-underline text-inherit hover:bg-violet-500/8 transition-colors group"
          >
            <span className="w-10 h-10 rounded-2xl bg-gradient-to-br from-violet-500/15 to-fuchsia-500/10 border border-violet-400/25 flex items-center justify-center text-violet-600 dark:text-violet-300 group-hover:scale-105 transition-transform">
              {it.icon}
            </span>
            <span className="text-[11px] font-medium text-slate-600 dark:text-slate-300">{it.label}</span>
          </Link>
        ))}
      </div>
    </nav>
  );
}

// --------------------------------------------------------------------------- //
// 通用面板容器 / 空态
// --------------------------------------------------------------------------- //
function PanelShell({
  title,
  icon,
  subtitle,
  more,
  tabs,
  children,
}: {
  title: string;
  icon?: ReactNode;
  subtitle?: string;
  more?: { to: string; label: string };
  tabs?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="rounded-[28px] glass-card p-5 h-full flex flex-col">
      <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
        <div className="min-w-0">
          <h3 className="text-sm font-bold text-slate-900 dark:text-white flex items-center gap-2">
            {icon && <span className="text-violet-500 dark:text-violet-300">{icon}</span>}
            {title}
          </h3>
          {subtitle && <p className="text-[11px] text-slate-400 dark:text-slate-500 mt-0.5">{subtitle}</p>}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          {tabs}
          {more && (
            <Link
              to={more.to}
              className="inline-flex items-center gap-1 text-[11px] font-semibold text-violet-600 dark:text-violet-300 hover:underline underline-offset-2 no-underline"
            >
              {more.label}
              <ArrowRightIcon size={12} />
            </Link>
          )}
        </div>
      </div>
      <div className="flex-1 min-h-0">{children}</div>
    </div>
  );
}

function EmptyHint({ text }: { text: string }) {
  return (
    <div className="rounded-2xl border border-dashed border-slate-300/50 dark:border-white/10 px-4 py-6 text-center text-xs text-slate-400 dark:text-slate-500">
      {text}
    </div>
  );
}
