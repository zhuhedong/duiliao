/**
 * 工作台 — Bento Studio 业务数据总览。
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
import { ensureDrawDetails } from "../lib/lotteryAttr";
import {
  ActivityIcon,
  AlertIcon,
  ArrowRightIcon,
  CalendarIcon,
  CheckIcon,
  ClipboardListIcon,
  ClockIcon,
  CompareIcon,
  DatabaseIcon,
  RefreshIcon,
  SettingsIcon,
  SparklesIcon,
  StarIcon,
  TargetIcon,
  TrendIcon,
  TrophyIcon,
} from "../components/icons";
import {
  CardSkeleton,
  DonutRing,
  KpiSkeleton,
  LotteryBall,
  Sparkline,
  toast,
} from "../components/ui";
import { SegmentedTabs, StatusPill, playLabel } from "./collector/shared";

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
  if (v === null || v === undefined) return "text-slate-400 dark:text-slate-500";
  if (v >= 0.6) return "text-emerald-600 dark:text-emerald-400";
  if (v >= 0.45) return "text-indigo-600 dark:text-indigo-400";
  if (v >= 0.35) return "text-amber-600 dark:text-amber-400";
  return "text-rose-600 dark:text-rose-400";
}

function rateBar(v: number | null | undefined): string {
  if (v === null || v === undefined) return "bg-slate-300 dark:bg-slate-700";
  if (v >= 0.6) return "bg-emerald-500";
  if (v >= 0.45) return "bg-indigo-500";
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

  const load = useCallback(async (silent = false, notifySuccess = false) => {
    if (silent) setRefreshing(true);
    else setLoading(true);
    try {
      const res = await collectorApi.overview();
      if (!mounted.current) return;
      setData(res);
      setError(null);
      if (notifySuccess) {
        toast.success("工作台数据已同步至最新状态");
      }
    } catch (err) {
      if (!mounted.current) return;
      const msg = err instanceof ApiError ? err.message : "工作台数据加载失败";
      setError(msg);
      if (notifySuccess) toast.error(msg);
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
    <div className="workspace-fill w-full flex flex-col gap-4 content-start">
      {/* Bento Hero Card */}
      <header className="bento-card bento-hero rounded-2xl px-5 sm:px-6 py-5">
        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2.5 flex-wrap">
              <span className="display-kicker">
                Overview · {data?.today.date ?? new Date().toISOString().slice(0, 10)}
              </span>
              {data && (
                <span className="inline-flex items-center gap-1.5 text-[11px] text-slate-400 dark:text-slate-500 font-mono">
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 pulse-dot" />
                  实时快照 {data.generated_at.slice(11)}
                </span>
              )}
            </div>
            <h2 className="text-xl sm:text-2xl font-bold tracking-tight text-slate-900 dark:text-white mt-1 truncate">
              {greet()}，{user.display_name || user.email}
            </h2>
            <p className="mt-1 text-xs sm:text-sm text-slate-500 dark:text-slate-400 max-w-2xl leading-relaxed">
              实时汇总多源采集进度、全站开奖对料命中率、连中榜单与后台定时任务动态。
            </p>
          </div>

          <div className="flex items-center gap-2 flex-wrap shrink-0">
            <Link
              to="/records"
              className="inline-flex items-center gap-1.5 h-9 px-3.5 rounded-xl text-xs font-semibold bg-slate-100 hover:bg-slate-200/80 text-slate-700 dark:bg-white/[0.06] dark:hover:bg-white/[0.1] dark:text-slate-200 border border-slate-200/70 dark:border-white/10 no-underline transition-colors"
            >
              <ClipboardListIcon size={14} />
              <span>投注记账</span>
            </Link>
            <Link
              to="/collector/ai-analysis"
              className="inline-flex items-center gap-1.5 h-9 px-3.5 rounded-xl text-xs font-semibold bg-indigo-50 hover:bg-indigo-100/80 text-indigo-700 dark:bg-indigo-500/15 dark:hover:bg-indigo-500/25 dark:text-indigo-300 border border-indigo-200/70 dark:border-indigo-500/30 no-underline transition-colors"
            >
              <SparklesIcon size={14} />
              <span>AI 研判</span>
            </Link>
            <button
              type="button"
              onClick={() => void load(true, true)}
              disabled={loading || refreshing}
              className="inline-flex items-center gap-1.5 h-9 px-4 rounded-xl text-xs font-semibold glow-button cursor-pointer disabled:opacity-60"
            >
              <RefreshIcon size={14} className={refreshing ? "animate-spin" : ""} />
              <span>刷新数据</span>
            </button>
          </div>
        </div>
      </header>

      {error && (
        <div className="rounded-2xl border border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-500/25 dark:bg-rose-500/10 dark:text-rose-300 px-4 py-3 text-sm flex items-center justify-between gap-3">
          <span>{error}</span>
          <button
            type="button"
            onClick={() => void load(false, true)}
            className="shrink-0 text-xs font-semibold underline underline-offset-2 cursor-pointer"
          >
            重试
          </button>
        </div>
      )}

      {loading && !data ? (
        <DashboardSkeleton />
      ) : data ? (
        <div className="bento-grid stagger">
          {/* Row 1: 4 Symmetrical KPI Bento Cards */}
          <section className="bento-span-3">
            <KpiTile data={data} index={0} />
          </section>
          <section className="bento-span-3">
            <KpiTile data={data} index={1} />
          </section>
          <section className="bento-span-3">
            <KpiTile data={data} index={2} />
          </section>
          <section className="bento-span-3">
            <KpiTile data={data} index={3} />
          </section>

          {/* Row 2: Latest Draws + Alerts */}
          <section className="bento-span-7">
            <LatestDrawsPanel draws={data.latest_draws} />
          </section>
          <section className="bento-span-5">
            <AlertsPanel data={data} />
          </section>

          {/* Row 3: 7-Day Trend + Leaderboard */}
          <section className="bento-span-5">
            <TrendPanel data={data} />
          </section>
          <section className="bento-span-7">
            <LeaderboardPanel data={data} />
          </section>

          {/* Row 4: Play Type Distribution + Scheduler */}
          <section className="bento-span-6">
            <PlayTypePanel data={data} />
          </section>
          <section className="bento-span-6">
            <SchedulePanel data={data} />
          </section>

          {/* Row 5: Quick Navigation */}
          <section className="bento-span-12">
            <QuickNav />
          </section>
        </div>
      ) : null}
    </div>
  );
}

// --------------------------------------------------------------------------- //
// 加载骨架
// --------------------------------------------------------------------------- //
function DashboardSkeleton() {
  return (
    <div className="space-y-4">
      <KpiSkeleton count={4} />
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        <div className="lg:col-span-7">
          <CardSkeleton lines={5} />
        </div>
        <div className="lg:col-span-5">
          <CardSkeleton lines={5} />
        </div>
      </div>
    </div>
  );
}

function KpiTile({ data, index }: { data: OverviewResult; index: number }) {
  const { judge, today, totals, alerts, trend_7d } = data;
  const collectRate = today.source_total > 0 ? today.source_ok / today.source_total : null;
  const coverageRate = totals.sources > 0 ? totals.sources_enabled / totals.sources : null;
  const alertTotal = alerts.lagging_sources + judge.pending_judge;
  const sparkData = trend_7d.map((t) => Math.round((t.hit_rate ?? 0) * 100));

  const cards = [
    {
      icon: <TargetIcon size={16} />,
      iconBg: "bg-indigo-50 text-indigo-600 dark:bg-indigo-500/15 dark:text-indigo-400",
      label: "综合命中率",
      value: pct(judge.hit_rate),
      valueClass: rateTone(judge.hit_rate),
      sub: `命中 ${judge.hits.toLocaleString()} / 判定 ${judge.judged.toLocaleString()}`,
      bar: judge.hit_rate,
      to: "/collector/ratings",
      viz:
        judge.hit_rate !== null ? (
          <DonutRing
            value={judge.hit_rate * 100}
            size={46}
            tone={judge.hit_rate >= 0.5 ? "emerald" : "indigo"}
          />
        ) : null,
    },
    {
      icon: <DatabaseIcon size={16} />,
      iconBg: "bg-sky-50 text-sky-600 dark:bg-sky-500/15 dark:text-sky-400",
      label: "启用数据源",
      value: `${totals.sources_enabled}/${totals.sources}`,
      valueClass: "text-slate-900 dark:text-white",
      sub: `${totals.predictions.toLocaleString()} 预测 · ${totals.draws.toLocaleString()} 期开奖`,
      bar: coverageRate,
      to: "/collector/sources",
      viz:
        coverageRate !== null ? (
          <DonutRing value={coverageRate * 100} size={46} tone="indigo" />
        ) : null,
    },
    {
      icon: <ActivityIcon size={16} />,
      iconBg: "bg-emerald-50 text-emerald-600 dark:bg-emerald-500/15 dark:text-emerald-400",
      label: "今日采集覆盖",
      value: today.source_total > 0 ? `${today.source_ok}/${today.source_total}` : "待采集",
      valueClass:
        today.source_total === 0
          ? "text-slate-400 dark:text-slate-500"
          : collectRate !== null && collectRate >= 0.95
            ? "text-emerald-600 dark:text-emerald-400"
            : "text-amber-600 dark:text-amber-400",
      sub: `今日 ${today.crawl_runs} 轮 · 新增 ${today.new_predictions.toLocaleString()} 条`,
      bar: collectRate,
      to: "/collector/sources",
      viz:
        sparkData.length > 1 ? (
          <Sparkline data={sparkData} width={84} height={32} tone="emerald" />
        ) : null,
    },
    {
      icon: <AlertIcon size={16} />,
      iconBg:
        alertTotal > 0
          ? "bg-amber-50 text-amber-600 dark:bg-amber-500/15 dark:text-amber-400"
          : "bg-emerald-50 text-emerald-600 dark:bg-emerald-500/15 dark:text-emerald-400",
      label: "待办与缺期告警",
      value: alertTotal > 0 ? String(alertTotal) : "全部同步",
      valueClass:
        alertTotal > 0
          ? "text-amber-600 dark:text-amber-400"
          : "text-emerald-600 dark:text-emerald-400",
      sub: `缺期源 ${alerts.lagging_sources} · 待判定 ${judge.pending_judge}`,
      bar: alertTotal > 0 ? Math.max(0.1, 1 - alertTotal / Math.max(10, totals.sources_enabled)) : 1,
      to: "/collector/monitor",
      viz: null,
    },
  ];
  const c = cards[index]!;

  return (
    <Link
      to={c.to}
      className="bento-card is-interactive has-sheen rounded-2xl p-5 h-full flex flex-col justify-between gap-3.5 no-underline text-inherit group"
    >
      <div className="flex items-center justify-between">
        <span className="inline-flex items-center gap-2 text-xs font-medium text-slate-500 dark:text-slate-400">
          <span className={`w-7 h-7 rounded-lg flex items-center justify-center ${c.iconBg}`}>
            {c.icon}
          </span>
          {c.label}
        </span>
        <ArrowRightIcon
          size={14}
          className="text-slate-300 dark:text-slate-600 group-hover:text-indigo-500 group-hover:translate-x-0.5 transition-all"
        />
      </div>

      <div>
        <div className="flex items-end justify-between gap-2">
          <div>
            <div
              className={`text-2xl sm:text-3xl font-bold tracking-tight tabular-nums ${c.valueClass}`}
            >
              {c.value}
            </div>
            <div className="mt-1 text-[11px] text-slate-500 dark:text-slate-400 truncate">
              {c.sub}
            </div>
          </div>
          {c.viz}
        </div>
        {c.bar != null ? (
          <div className="mt-3 h-1.5 rounded-full bg-slate-100 dark:bg-white/[0.06] overflow-hidden">
            <div
              className={`h-full rounded-full animate-grow-x ${rateBar(c.bar)}`}
              style={{ width: `${Math.max(5, Math.min(100, c.bar * 100))}%` }}
            />
          </div>
        ) : null}
      </div>
    </Link>
  );
}

// --------------------------------------------------------------------------- //
// 最新开奖
// --------------------------------------------------------------------------- //
function LatestDrawsPanel({ draws }: { draws: DrawRow[] }) {
  const [active, setActive] = useState(0);
  if (draws.length === 0) {
    return (
      <PanelShell
        title="最新开奖"
        icon={<TrophyIcon size={16} />}
        more={{ to: "/collector/draws", label: "开奖管理" }}
      >
        <EmptyHint text="暂无开奖数据，请先执行开奖同步" />
      </PanelShell>
    );
  }
  const idx = Math.min(active, draws.length - 1);
  const draw = draws[idx]!;
  const { ballsDetail, temaDetail, summary } = ensureDrawDetails(draw);

  return (
    <PanelShell
      title="最新开奖实况"
      icon={<TrophyIcon size={16} />}
      more={{ to: "/collector/draws", label: "开奖管理" }}
      tabs={
        <SegmentedTabs
          size="sm"
          value={String(idx)}
          onChange={(v) => setActive(Number(v))}
          options={draws.map((d, i) => ({
            value: String(i),
            label: LOTTERY_LABEL[d.lottery] ?? d.lottery,
          }))}
        />
      }
    >
      <div className="flex flex-col justify-between h-full gap-4">
        <div className="p-4 sm:p-5 rounded-2xl bg-slate-50/80 dark:bg-white/[0.025] border border-slate-100 dark:border-white/[0.05]">
          <div className="flex items-center justify-between gap-2 flex-wrap mb-4">
            <div className="flex items-baseline gap-2.5">
              <span className="text-base sm:text-lg font-bold tracking-tight text-slate-900 dark:text-white tabular-nums">
                第 {draw.period} 期
              </span>
              <span className="text-xs text-slate-400 dark:text-slate-500 font-mono">
                {draw.draw_date ?? "日期待定"}
              </span>
            </div>
            <StatusPill variant="success">官方已开奖</StatusPill>
          </div>

          {/* 3D 高光号码球 */}
          <div className="flex items-end gap-2.5 sm:gap-3.5 flex-wrap">
            {ballsDetail.map((b, i) => (
              <LotteryBall
                key={`${b.num}-${i}`}
                number={b.num}
                colorHint={b.bose}
                zodiac={b.xiao}
                size="lg"
                isHit={b.is_lianxiao}
                badge={b.is_lianxiao ? "连" : null}
              />
            ))}
            <span className="self-center text-slate-300 dark:text-slate-600 font-light text-xl px-0.5 mb-5">
              +
            </span>
            <LotteryBall
              number={temaDetail.num}
              colorHint={temaDetail.bose}
              zodiac={temaDetail.xiao}
              size="lg"
              isSpecial
              badge="特"
            />
          </div>
        </div>

        {/* 汇总标签 */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
          <SummaryStat
            label="总分与单双"
            value={`${summary.sum7} 分 · ${summary.sum7_size}${summary.sum7_odd}`}
          />
          <SummaryStat
            label="特码特征"
            value={`${summary.tema_xiao} · ${summary.tema_bose}波 · ${summary.tema_size}${summary.tema_odd}`}
          />
          <SummaryStat
            label="平特连肖"
            value={summary.lianxiao_text ?? "7 肖各异"}
            accent={summary.has_lianxiao}
          />
        </div>
      </div>
    </PanelShell>
  );
}

function SummaryStat({
  label,
  value,
  accent = false,
}: {
  label: string;
  value: ReactNode;
  accent?: boolean;
}) {
  return (
    <div
      className={`px-3.5 py-2.5 rounded-xl border ${
        accent
          ? "bg-indigo-50/70 border-indigo-200/80 dark:bg-indigo-500/10 dark:border-indigo-500/25"
          : "bg-slate-50/80 border-slate-200/60 dark:bg-white/[0.025] dark:border-white/[0.06]"
      }`}
    >
      <div className="text-[10px] font-medium text-slate-400 dark:text-slate-500">{label}</div>
      <div
        className={`text-xs font-semibold mt-0.5 truncate ${
          accent ? "text-indigo-700 dark:text-indigo-300" : "text-slate-800 dark:text-slate-200"
        }`}
      >
        {value}
      </div>
    </div>
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
      ? judgedDays.reduce((a, t) => a + t.hits, 0) /
        judgedDays.reduce((a, t) => a + t.judged, 0)
      : null;

  return (
    <PanelShell
      title="近 7 日对料趋势"
      icon={<TrendIcon size={16} />}
      subtitle={avg !== null ? `7 日平均命中率 ${pct(avg)}` : "近 7 日暂无判定记录"}
      tabs={
        judgedDays.length > 1 ? (
          <Sparkline
            data={trend.map((t) => Math.round((t.hit_rate ?? 0) * 100))}
            width={92}
            height={28}
            tone="indigo"
          />
        ) : undefined
      }
    >
      <div className="p-4 rounded-2xl bg-slate-50/70 dark:bg-white/[0.02] border border-slate-100 dark:border-white/[0.05] flex items-end gap-2 sm:gap-3 h-52">
        {trend.map((t) => {
          const isToday = t.date === data.today.date;
          const h = t.hit_rate !== null ? Math.max(t.hit_rate * 100, 8) : 0;
          return (
            <div key={t.date} className="flex-1 min-w-0 flex flex-col items-center gap-1.5 h-full">
              <div
                className={`text-[10px] font-bold tabular-nums leading-none ${
                  t.hit_rate !== null ? rateTone(t.hit_rate) : "text-slate-300 dark:text-slate-600"
                }`}
              >
                {t.hit_rate !== null ? pct(t.hit_rate, 0) : "—"}
              </div>
              <div className="flex-1 w-full flex items-end bg-slate-200/40 dark:bg-white/[0.04] rounded-lg overflow-hidden p-0.5">
                {t.hit_rate !== null ? (
                  <div
                    className={`w-full rounded-md animate-grow-bar ${rateBar(t.hit_rate)} ${
                      isToday ? "ring-1 ring-indigo-400/50" : "opacity-85 hover:opacity-100"
                    }`}
                    style={{ height: `${h}%` }}
                    title={`${t.date}：命中 ${t.hits} / 判定 ${t.judged}`}
                  />
                ) : (
                  <div className="w-full rounded-md bg-slate-200 dark:bg-white/10" style={{ height: "4%" }} />
                )}
              </div>
              <div
                className={`text-[11px] leading-none tabular-nums ${
                  isToday
                    ? "font-bold text-indigo-600 dark:text-indigo-400"
                    : "text-slate-500 dark:text-slate-400"
                }`}
              >
                {isToday ? "今天" : fmtDay(t.date)}
              </div>
              <div className="text-[10px] leading-none text-slate-400 dark:text-slate-500 tabular-nums">
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
      title="数据源命中率排行"
      icon={<StarIcon size={16} />}
      subtitle="统计样本 ≥10 期的数据源，按实测命中率降序"
      more={{ to: "/collector/ratings", label: "完整评级" }}
    >
      {rows.length === 0 ? (
        <EmptyHint text="暂无足够的判定数据生成排行" />
      ) : (
        <ol className="flex flex-col divide-y divide-slate-100 dark:divide-white/[0.05]">
          {rows.map((r, i) => (
            <li key={r.source_id} className="flex items-center gap-3 py-2.5 first:pt-0 last:pb-0">
              <span
                className={`w-6 h-6 shrink-0 rounded-lg flex items-center justify-center text-xs font-bold tabular-nums ${
                  i === 0
                    ? "bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-300"
                    : i === 1
                      ? "bg-slate-200/80 text-slate-700 dark:bg-slate-400/20 dark:text-slate-200"
                      : i === 2
                        ? "bg-orange-100 text-orange-700 dark:bg-orange-500/20 dark:text-orange-300"
                        : "bg-slate-100 text-slate-500 dark:bg-white/[0.04] dark:text-slate-400"
                }`}
              >
                {i + 1}
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-semibold truncate text-slate-800 dark:text-slate-100">
                    {r.source_name}
                  </span>
                  <span className="shrink-0 text-[10px] px-1.5 py-0.5 rounded-md bg-slate-100 dark:bg-white/[0.06] text-slate-500 dark:text-slate-400 font-medium">
                    {r.play_type ? playLabel(r.play_type) : "—"}
                  </span>
                  {r.streak_hit !== null && r.current_streak >= 2 && (
                    <span
                      className={`shrink-0 text-[10px] px-1.5 py-0.5 rounded-md font-semibold ${
                        r.streak_hit
                          ? "bg-emerald-50 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300"
                          : "bg-rose-50 text-rose-700 dark:bg-rose-500/15 dark:text-rose-300"
                      }`}
                    >
                      {r.streak_hit ? `连中 ${r.current_streak}` : `连挂 ${r.current_streak}`}
                    </span>
                  )}
                </div>
                <div className="mt-1.5 flex items-center gap-2.5">
                  <div className="flex-1 h-1.5 rounded-full bg-slate-100 dark:bg-white/[0.06] overflow-hidden">
                    <div
                      className={`h-full rounded-full ${rateBar(r.hit_rate)}`}
                      style={{ width: `${Math.round((r.hit_rate ?? 0) * 100)}%` }}
                    />
                  </div>
                  {/* 近期战绩点 */}
                  <span className="hidden sm:inline-flex items-center gap-1 shrink-0">
                    {r.recent.slice(0, 8).map((hit, j) => (
                      <span
                        key={j}
                        className={`w-1.5 h-1.5 rounded-full ${
                          hit ? "bg-emerald-500" : "bg-rose-400/80"
                        }`}
                      />
                    ))}
                  </span>
                </div>
              </div>
              <div className="shrink-0 text-right tabular-nums">
                <div className={`text-sm font-bold ${rateTone(r.hit_rate)}`}>{pct(r.hit_rate)}</div>
                <div className="text-[10px] text-slate-400 dark:text-slate-500">
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
      subtitle={`累计 ${data.totals.judge_results.toLocaleString()} 条对奖判定样本`}
    >
      {rows.length === 0 ? (
        <EmptyHint text="暂无判定数据" />
      ) : (
        <div className="flex flex-col gap-2.5">
          {rows.map((r) => (
            <div key={r.play_type} className="flex items-center gap-3">
              <span className="w-16 shrink-0 text-xs font-medium text-slate-700 dark:text-slate-300 truncate">
                {playLabel(r.play_type)}
              </span>
              <div className="flex-1 min-w-0">
                <div className="h-5 rounded-lg bg-slate-100 dark:bg-white/[0.05] overflow-hidden relative">
                  <div
                    className={`h-full rounded-lg ${rateBar(r.hit_rate)} opacity-25 dark:opacity-30`}
                    style={{ width: `${Math.max(6, (r.judged / maxJudged) * 100)}%` }}
                  />
                  <span className="absolute inset-0 flex items-center px-2.5 text-[11px] font-medium text-slate-600 dark:text-slate-300 tabular-nums">
                    {r.judged.toLocaleString()} 期样本
                  </span>
                </div>
              </div>
              <span
                className={`w-14 shrink-0 text-right text-xs font-bold tabular-nums ${rateTone(
                  r.hit_rate,
                )}`}
              >
                {pct(r.hit_rate)}
              </span>
            </div>
          ))}
        </div>
      )}
    </PanelShell>
  );
}

// --------------------------------------------------------------------------- //
// 采集告警
// --------------------------------------------------------------------------- //
function AlertsPanel({ data }: { data: OverviewResult }) {
  const { alerts, judge } = data;
  const ok =
    alerts.lagging_sources === 0 && judge.pending_judge === 0 && alerts.never_collected === 0;
  return (
    <PanelShell
      title="采集与同步告警"
      icon={<AlertIcon size={16} />}
      more={{ to: "/collector/monitor", label: "缺期监控" }}
      subtitle={ok ? "所有启用源均已同步至最新期" : undefined}
    >
      <div className="grid grid-cols-3 gap-2.5 mb-3.5">
        <AlertStat
          label="缺期源"
          value={alerts.lagging_sources}
          danger={alerts.lagging_sources > 0}
        />
        <AlertStat label="待判定" value={judge.pending_judge} danger={judge.pending_judge > 0} />
        <AlertStat label="确认缺期" value={alerts.confirmed_missing_total} danger={false} />
      </div>

      {ok && alerts.items.length === 0 ? (
        <div className="flex items-center gap-2 rounded-xl bg-emerald-50 border border-emerald-200/80 dark:bg-emerald-500/10 dark:border-emerald-500/25 px-4 py-3.5 text-xs font-medium text-emerald-700 dark:text-emerald-300">
          <CheckIcon size={15} />
          <span>全站启用数据源覆盖完整，当前无需人工干预</span>
        </div>
      ) : (
        <ul className="flex flex-col divide-y divide-slate-100 dark:divide-white/[0.05] max-h-48 overflow-y-auto pr-1">
          {alerts.items.map((a) => (
            <li key={a.source_id} className="flex items-center gap-3 py-2.5 first:pt-0 last:pb-0">
              <div className="min-w-0 flex-1">
                <div className="text-xs sm:text-sm font-semibold truncate text-slate-800 dark:text-slate-100">
                  {a.source_name}
                </div>
                <div className="text-[11px] text-slate-400 dark:text-slate-500 mt-0.5">
                  {LOTTERY_LABEL[a.lottery] ?? a.lottery} · {playLabel(a.play_type)} · 停留在{" "}
                  {a.latest_period}
                </div>
              </div>
              {a.lag > 0 && <StatusPill variant="warning">缺 {a.lag} 期</StatusPill>}
              {a.missing > 0 && <StatusPill variant="neutral">确认缺 {a.missing}</StatusPill>}
            </li>
          ))}
        </ul>
      )}
    </PanelShell>
  );
}

function AlertStat({
  label,
  value,
  danger,
}: {
  label: string;
  value: number;
  danger: boolean;
}) {
  return (
    <div
      className={`rounded-xl px-3 py-2.5 text-center border ${
        danger
          ? "bg-amber-50/80 border-amber-200/80 dark:bg-amber-500/10 dark:border-amber-500/25"
          : "bg-slate-50/80 border-slate-200/60 dark:bg-white/[0.025] dark:border-white/[0.06]"
      }`}
    >
      <div
        className={`text-lg font-bold leading-none tabular-nums ${
          danger ? "text-amber-600 dark:text-amber-400" : "text-slate-800 dark:text-slate-100"
        }`}
      >
        {value.toLocaleString()}
      </div>
      <div className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">{label}</div>
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
      title="调度与最近执行"
      icon={<ClockIcon size={16} />}
      more={{ to: "/collector/sources?tab=schedules", label: "任务管理" }}
    >
      <div className="flex flex-wrap gap-2">
        <StatusPill variant={draw?.enabled ? (draw.in_window ? "success" : "info") : "neutral"}>
          开奖自动同步
          {draw?.enabled ? (draw.in_window ? " · 窗口运行中" : " · 已启用") : " · 已停用"}
        </StatusPill>
        {draw?.next_run_at && (
          <StatusPill variant="neutral" dot={false}>
            下次同步 {fmtMinute(draw.next_run_at)}
          </StatusPill>
        )}
        {sched?.source && (
          <StatusPill variant={sched.source.active_tasks_count > 0 ? "warning" : "success"}>
            {sched.source.active_tasks_count > 0
              ? `${sched.source.active_tasks_count} 个采集任务运行中`
              : "采集调度空闲"}
          </StatusPill>
        )}
      </div>

      {next && (
        <div className="mt-3 rounded-xl bg-indigo-50/60 border border-indigo-200/60 dark:bg-indigo-500/10 dark:border-indigo-500/20 px-3.5 py-2.5 flex items-center gap-3">
          <CalendarIcon size={16} className="text-indigo-600 dark:text-indigo-400 shrink-0" />
          <div className="min-w-0 flex-1">
            <div className="text-xs font-semibold text-slate-800 dark:text-slate-100 truncate">
              {next.name}
            </div>
            <div className="text-[11px] text-slate-500 dark:text-slate-400 mt-0.5 font-mono">
              {LOTTERY_LABEL[next.lottery] ?? next.lottery}
              {next.cron ? ` · ${next.cron}` : ""}
            </div>
          </div>
          <div className="shrink-0 text-right">
            <div className="text-[10px] text-slate-400 dark:text-slate-500">下次执行</div>
            <div className="text-xs font-semibold text-indigo-600 dark:text-indigo-300 tabular-nums">
              {fmtMinute(next.next_run_at)}
            </div>
          </div>
        </div>
      )}

      <div className="mt-4">
        <div className="text-[11px] font-semibold text-slate-400 dark:text-slate-500 uppercase tracking-wider mb-2.5">
          最近调度日志
        </div>
        {data.recent_logs.length === 0 ? (
          <EmptyHint text="暂无采集执行记录" />
        ) : (
          <ol className="relative space-y-2.5 pl-4 border-l border-slate-200 dark:border-white/10">
            {data.recent_logs.slice(0, 4).map((log) => (
              <li key={log.id} className="relative">
                <span
                  className={`absolute -left-[20.5px] top-1.5 w-2 h-2 rounded-full ${
                    log.status === "success"
                      ? "bg-emerald-500"
                      : log.status === "running"
                        ? "bg-amber-500"
                        : "bg-rose-500"
                  }`}
                />
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-xs font-semibold text-slate-800 dark:text-slate-100">
                    {log.schedule_name}
                  </span>
                  <span className="text-[11px] text-slate-400 dark:text-slate-500">
                    {log.action}
                  </span>
                  <span className="ml-auto text-[11px] text-slate-400 dark:text-slate-500 tabular-nums shrink-0">
                    {fmtMinute(log.created_at)}
                  </span>
                </div>
                <div className="text-[11px] text-slate-500 dark:text-slate-400 mt-0.5 tabular-nums">
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
// 快捷业务矩阵
// --------------------------------------------------------------------------- //
function QuickNav() {
  const items = [
    { to: "/records", label: "投注记账", desc: "智能速录与结算", icon: <ClipboardListIcon size={18} /> },
    { to: "/collector/ai-analysis", label: "AI 研判", desc: "帖文与连肖推理", icon: <SparklesIcon size={18} /> },
    { to: "/collector/consensus", label: "多源对照", desc: "单期与共识聚合", icon: <CompareIcon size={18} /> },
    { to: "/collector/draws", label: "开奖管理", desc: "同步与自动对奖", icon: <TrophyIcon size={18} /> },
    { to: "/collector/pingte-ranking", label: "平特排行", desc: "热冷连开统计", icon: <TargetIcon size={18} /> },
    { to: "/collector/ratings", label: "源可信评级", desc: "多窗口命中核算", icon: <StarIcon size={18} /> },
    { to: "/collector/monitor", label: "缺期巡检", desc: "上游监控与治理", icon: <ActivityIcon size={18} /> },
    { to: "/settings", label: "系统设置", desc: "模型与数据库", icon: <SettingsIcon size={18} /> },
  ];
  return (
    <nav className="bento-card rounded-2xl p-5">
      <div className="flex items-center justify-between mb-3.5">
        <span className="text-sm font-semibold text-slate-900 dark:text-white">核心模块直达</span>
        <span className="text-[11px] text-slate-400 dark:text-slate-500">支持快捷键 ⌘K 全局搜索</span>
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-8 gap-2.5">
        {items.map((it) => (
          <Link
            key={it.to}
            to={it.to}
            className="flex flex-col items-start gap-2 p-3.5 rounded-xl bg-slate-50/80 hover:bg-indigo-50/60 dark:bg-white/[0.025] dark:hover:bg-indigo-500/10 border border-slate-200/60 hover:border-indigo-200 dark:border-white/[0.06] dark:hover:border-indigo-500/30 no-underline text-inherit transition-all group"
          >
            <span className="w-9 h-9 rounded-xl bg-white dark:bg-white/[0.06] border border-slate-200/70 dark:border-white/10 flex items-center justify-center text-indigo-600 dark:text-indigo-400 shadow-2xs group-hover:scale-105 transition-transform">
              {it.icon}
            </span>
            <div className="min-w-0 w-full">
              <div className="text-xs font-semibold text-slate-800 dark:text-slate-100 truncate">
                {it.label}
              </div>
              <div className="text-[10px] text-slate-400 dark:text-slate-500 truncate mt-0.5">
                {it.desc}
              </div>
            </div>
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
    <div className="bento-card rounded-2xl p-5 sm:p-6 h-full flex flex-col">
      <div className="flex items-center justify-between gap-3 mb-4 pb-3 border-b border-slate-100 dark:border-white/[0.06] flex-wrap">
        <div className="min-w-0">
          <h3 className="text-[15px] font-semibold text-slate-900 dark:text-white flex items-center gap-2 tracking-tight">
            {icon && <span className="text-indigo-600 dark:text-indigo-400">{icon}</span>}
            {title}
          </h3>
          {subtitle && (
            <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">{subtitle}</p>
          )}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          {tabs}
          {more && (
            <Link
              to={more.to}
              className="inline-flex items-center gap-1 text-xs font-medium text-indigo-600 dark:text-indigo-400 hover:text-indigo-700 dark:hover:text-indigo-300 no-underline"
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
    <div className="rounded-xl border border-dashed border-slate-200 dark:border-white/10 px-4 py-8 text-center text-xs text-slate-400 dark:text-slate-500">
      {text}
    </div>
  );
}
