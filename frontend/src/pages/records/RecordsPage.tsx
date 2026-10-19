import { useState, useEffect, useCallback, useMemo } from "react";
import { Button } from "../../components/ui/button";
import { Spinner } from "../../components/ui/spinner";
import { Alert, AlertDescription } from "../../components/ui/alert";
import {
  ClipboardListIcon,
  PlusIcon,
  RefreshIcon,
  BarChartIcon,
  CopyIcon,
  TrashIcon,
  SparklesIcon,
} from "../../components/icons";
import { LOTTERIES } from "../collector/shared";
import { LOTTERY_LABEL, type Lottery } from "../../lib/collector";
import { BOSE_COLORS, getBose, getXiao } from "../../lib/lotteryAttr";
import {
  recordsApi,
  type BettingRecord,
  type RecordStats,
} from "../../lib/records";
import { RecordAddModal } from "./RecordAddModal";
import { RecordDetailModal } from "./RecordDetailModal";
import { RecordStatsModal } from "./RecordStatsModal";
import { RecordCopyModal } from "./RecordCopyModal";

export function RecordsPage() {
  const [lottery, setLottery] = useState<string>("macau");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [searchQuery, setSearchQuery] = useState<string>("");
  const [records, setRecords] = useState<BettingRecord[]>([]);
  const [stats, setStats] = useState<RecordStats | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [settling, setSettling] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Modals state
  const [addModalOpen, setAddModalOpen] = useState(false);
  const [detailRecord, setDetailRecord] = useState<BettingRecord | null>(null);
  const [statsModalOpen, setStatsModalOpen] = useState(false);
  const [copyModalOpen, setCopyModalOpen] = useState(false);
  const [copySourceRecord, setCopySourceRecord] = useState<BettingRecord | null>(null);
  const [copySourcePeriod, setCopySourcePeriod] = useState<string>("");

  const fetchRecords = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await recordsApi.list({
        lottery: lottery !== "all" ? lottery : undefined,
        status: statusFilter,
      });
      if (res.ok) {
        setRecords(res.items || []);
        setStats(res.stats || null);
      }
    } catch (err: any) {
      setError(err?.message || "获取记录列表失败");
    } finally {
      setLoading(false);
    }
  }, [lottery, statusFilter]);

  useEffect(() => {
    fetchRecords();
  }, [fetchRecords]);

  // One-click settle
  const handleSettle = async () => {
    setSettling(true);
    try {
      await recordsApi.settle(lottery !== "all" ? lottery : undefined);
      await fetchRecords();
    } catch (err: any) {
      alert(err?.message || "对奖结算失败");
    } finally {
      setSettling(false);
    }
  };

  // Clear records with confirmation
  const handleClear = async () => {
    const lotLabel = LOTTERY_LABEL[lottery as Lottery] || (lottery === "all" ? "全部" : lottery);
    if (!window.confirm(`确定要清空 ${lotLabel} 彩种下的所有投注记录吗？操作不可恢复。`)) {
      return;
    }
    try {
      await recordsApi.clear({
        lottery: lottery !== "all" ? lottery : undefined,
        status: statusFilter !== "all" ? statusFilter : undefined,
      });
      await fetchRecords();
    } catch (err: any) {
      alert(err?.message || "清空失败");
    }
  };

  // Single record delete
  const handleDeleteRecord = async (recordId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!window.confirm("确定删除该记录吗？")) return;
    try {
      await recordsApi.delete(recordId);
      setRecords((prev) => prev.filter((r) => r.id !== recordId));
    } catch (err: any) {
      alert(err?.message || "删除失败");
    }
  };

  // Filter records by search query
  const filteredRecords = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return records;
    return records.filter((r) => {
      const matchPeriod = r.period.includes(q);
      const matchNumbers = r.numbers?.some((n) => n.includes(q));
      const matchXiaos = r.xiaos?.some((x) => x.includes(q));
      const matchNote = r.note?.toLowerCase().includes(q);
      const matchRaw = r.raw_input?.toLowerCase().includes(q);
      const matchPlay = r.play_type?.toLowerCase().includes(q);
      return matchPeriod || matchNumbers || matchXiaos || matchNote || matchRaw || matchPlay;
    });
  }, [records, searchQuery]);

  // Group records by period
  const groupedPeriods = useMemo(() => {
    const map = new Map<string, BettingRecord[]>();
    for (const r of filteredRecords) {
      const arr = map.get(r.period) || [];
      arr.push(r);
      map.set(r.period, arr);
    }
    // Return sorted periods descending
    return Array.from(map.entries()).sort((a, b) => b[0].localeCompare(a[0]));
  }, [filteredRecords]);

  // Latest active period for suggestions
  const latestPeriod = records[0]?.period || "";

  return (
    <div className="space-y-6 max-w-7xl mx-auto px-4 sm:px-6 py-4 animate-fadeIn">
      {/* Top Banner / Hero Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-2.5 flex-wrap">
            <h1 className="text-2xl font-extrabold tracking-tight text-slate-900 dark:text-white flex items-center gap-2">
              <ClipboardListIcon size={26} className="text-primary" />
              <span>投注记录 · 智能对奖</span>
            </h1>
            <span className="text-xs px-2.5 py-0.5 rounded-full bg-primary/10 text-primary font-semibold">
              自动识别 · 官方核算
            </span>
          </div>
          <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">
            支持智能文本速录、生肖一键包码、开奖全自动化比对与盈亏复盘
          </p>
        </div>

        {/* Action Buttons Toolbar */}
        <div className="flex items-center gap-2 flex-wrap">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => setStatsModalOpen(true)}
            className="gap-1.5 text-xs shadow-sm"
          >
            <BarChartIcon size={14} />
            <span>统计分析</span>
          </Button>

          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={handleSettle}
            disabled={settling}
            className="gap-1.5 text-xs shadow-sm text-emerald-600 dark:text-emerald-400 hover:text-emerald-700"
          >
            {settling ? <Spinner className="size-4" /> : <RefreshIcon size={14} />}
            <span>一键对奖</span>
          </Button>

          <Button
            type="button"
            size="sm"
            onClick={() => setAddModalOpen(true)}
            className="gap-1.5 text-xs shadow-md shadow-primary/20"
          >
            <PlusIcon size={16} />
            <span>新增记录</span>
          </Button>
        </div>
      </div>

      {/* KPI Overview Summary Banner */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
        {/* Card 1: Pending Stake */}
        <div className="p-4 sm:p-5 rounded-3xl glass-card relative overflow-hidden">
          <div className="text-xs font-semibold text-slate-500 dark:text-slate-400">
            待开奖投入
          </div>
          <div className="text-2xl sm:text-3xl font-extrabold font-mono text-slate-900 dark:text-white mt-2">
            ¥{stats?.pending_stake ?? 0}
          </div>
          <div className="text-[11px] text-slate-400 mt-1 flex items-center gap-1.5">
            <span className="inline-block w-2 h-2 rounded-full bg-amber-400 animate-pulse" />
            <span>
              {stats?.pending_count ?? 0} 单 · {stats?.pending_notes ?? 0} 注待开
            </span>
          </div>
        </div>

        {/* Card 2: Net Profit / Loss */}
        <div className="p-4 sm:p-5 rounded-3xl glass-card relative overflow-hidden">
          <div className="text-xs font-semibold text-slate-500 dark:text-slate-400">
            累计净盈亏
          </div>
          <div
            className={`text-2xl sm:text-3xl font-extrabold font-mono mt-2 ${
              (stats?.net_profit ?? 0) >= 0 ? "text-emerald-500" : "text-rose-500"
            }`}
          >
            {(stats?.net_profit ?? 0) >= 0 ? `+¥${stats?.net_profit ?? 0}` : `¥${stats?.net_profit ?? 0}`}
          </div>
          <div className="text-[11px] text-slate-400 mt-1">
            投资回报率 (ROI): <span className="font-mono font-bold">{stats?.roi_pct ?? 0}%</span>
          </div>
        </div>

        {/* Card 3: Total Payout vs Stake */}
        <div className="p-4 sm:p-5 rounded-3xl glass-card relative overflow-hidden">
          <div className="text-xs font-semibold text-slate-500 dark:text-slate-400">
            已结算派彩
          </div>
          <div className="text-2xl sm:text-3xl font-extrabold font-mono text-emerald-500 mt-2">
            ¥{stats?.total_payout ?? 0}
          </div>
          <div className="text-[11px] text-slate-400 mt-1">
            总投入: <span className="font-mono">¥{stats?.total_stake ?? 0}</span> · 中 {stats?.hit_notes ?? 0} 注
          </div>
        </div>

        {/* Card 4: Win Rate */}
        <div className="p-4 sm:p-5 rounded-3xl glass-card relative overflow-hidden">
          <div className="text-xs font-semibold text-slate-500 dark:text-slate-400">
            中单胜率
          </div>
          <div className="text-2xl sm:text-3xl font-extrabold font-mono text-primary mt-2">
            {stats?.win_rate ?? 0}%
          </div>
          <div className="text-[11px] text-slate-400 mt-1">
            胜单: <span className="font-mono font-bold text-slate-700 dark:text-slate-300">{stats?.won_count ?? 0}</span> / {stats?.settled_orders ?? 0} 单
          </div>
        </div>
      </div>

      {/* Lottery & Filter Tabs & Search Bar */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-3 p-3 rounded-2xl glass-card">
        {/* Left: Lottery Pills */}
        <div className="flex items-center gap-1.5 flex-wrap">
          <button
            type="button"
            onClick={() => setLottery("all")}
            className={`px-3 py-1.5 text-xs font-semibold rounded-xl transition-all ${
              lottery === "all"
                ? "bg-slate-900 text-white dark:bg-white dark:text-slate-900 shadow-sm"
                : "text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-white/5"
            }`}
          >
            全部彩种
          </button>
          {LOTTERIES.map((l) => (
            <button
              key={l.value}
              type="button"
              onClick={() => setLottery(l.value)}
              className={`px-3 py-1.5 text-xs font-semibold rounded-xl transition-all ${
                lottery === l.value
                  ? "bg-primary text-white shadow-md shadow-primary/25"
                  : "text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-white/5"
              }`}
            >
              {l.label}
            </button>
          ))}
        </div>

        {/* Right: Status Tabs + Search */}
        <div className="flex items-center gap-2 flex-wrap">
          <div className="flex items-center gap-1 bg-slate-100 dark:bg-white/5 p-1 rounded-xl text-xs">
            {(
              [
                { id: "all", label: "全部", count: stats?.total_records },
                { id: "pending", label: "待开奖", count: stats?.pending_count },
                { id: "won", label: "已中奖", count: stats?.won_count },
                { id: "lost", label: "未中", count: stats?.lost_count },
              ] as const
            ).map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => setStatusFilter(t.id)}
                className={`px-2.5 py-1 rounded-lg font-medium transition-all flex items-center gap-1 ${
                  statusFilter === t.id
                    ? "bg-white dark:bg-violet-600 text-slate-900 dark:text-white shadow-sm font-bold"
                    : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white"
                }`}
              >
                <span>{t.label}</span>
                {typeof t.count === "number" && t.count > 0 && (
                  <span
                    className={`text-[10px] px-1.5 rounded-full font-mono ${
                      t.id === "won"
                        ? "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400"
                        : t.id === "pending"
                        ? "bg-amber-500/15 text-amber-600 dark:text-amber-400"
                        : "bg-slate-200 dark:bg-white/10"
                    }`}
                  >
                    {t.count}
                  </span>
                )}
              </button>
            ))}
          </div>

          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="搜索期号/号码/备注..."
            className="px-3 py-1.5 text-xs rounded-xl border border-slate-200 dark:border-white/10 bg-white dark:bg-white/5 text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:ring-1 focus:ring-primary w-40 sm:w-48"
          />

          {records.length > 0 && (
            <button
              type="button"
              onClick={handleClear}
              title="清空当前筛选记录"
              className="p-2 rounded-xl text-slate-400 hover:text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-950/20 transition-colors"
            >
              <TrashIcon size={16} />
            </button>
          )}
        </div>
      </div>

      {/* Error alert */}
      {error && (
        <Alert variant="error">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {/* Main Content: Period Groups */}
      {loading ? (
        <div className="flex flex-col items-center justify-center py-24 space-y-3">
          <Spinner className="size-8 text-primary" />
          <span className="text-xs text-slate-400">正在加载投注对奖数据...</span>
        </div>
      ) : groupedPeriods.length === 0 ? (
        /* Empty State */
        <div className="p-12 rounded-3xl glass-card text-center space-y-4 max-w-lg mx-auto my-8">
          <div className="w-16 h-16 rounded-3xl bg-primary/10 text-primary flex items-center justify-center mx-auto shadow-inner">
            <ClipboardListIcon size={32} />
          </div>
          <div>
            <h3 className="text-base font-bold text-slate-900 dark:text-white">
              暂无投注记录
            </h3>
            <p className="text-xs text-slate-500 dark:text-slate-400 mt-1 max-w-xs mx-auto">
              通过智能文本或号码选板快速添加投注单，开奖后系统将全自动进行中奖计算与盈亏复盘。
            </p>
          </div>
          <div className="flex items-center justify-center gap-3 pt-2">
            <Button
              type="button"
              onClick={() => setAddModalOpen(true)}
              className="gap-1.5 shadow-md shadow-primary/25"
            >
              <PlusIcon size={16} />
              <span>立即录入第一单</span>
            </Button>
          </div>
        </div>
      ) : (
        /* Period Sections */
        <div className="space-y-6">
          {groupedPeriods.map(([periodStr, periodRecords]) => {
            const hasPending = periodRecords.some((r) => r.status === "pending");
            const periodNet = periodRecords.reduce((acc, r) => acc + (r.net_profit || 0), 0);
            const periodStake = periodRecords.reduce((acc, r) => acc + (r.total_amount || 0), 0);

            return (
              <section key={periodStr} className="space-y-3">
                {/* Period Group Header */}
                <div className="flex items-center justify-between px-2">
                  <div className="flex items-center gap-2.5">
                    <span className="w-2 h-2 rounded-full bg-primary shadow-sm" />
                    <h2 className="text-base font-extrabold text-slate-900 dark:text-white font-mono">
                      第 {periodStr} 期
                    </h2>
                    <span className="text-xs text-slate-400">
                      ({periodRecords.length} 单 · 投入 ¥{periodStake})
                    </span>
                  </div>

                  <div className="flex items-center gap-2">
                    {/* Period Status Badge */}
                    {hasPending ? (
                      <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-amber-500/15 text-amber-600 dark:text-amber-400 border border-amber-500/30">
                        <span className="w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse" />
                        待开奖
                      </span>
                    ) : (
                      <span
                        className={`inline-flex items-center px-3 py-1 rounded-full text-xs font-bold font-mono ${
                          periodNet >= 0
                            ? "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 border border-emerald-500/30"
                            : "bg-rose-500/15 text-rose-600 dark:text-rose-400 border border-rose-500/30"
                        }`}
                      >
                        本期盈亏 {periodNet >= 0 ? `+¥${periodNet}` : `¥${periodNet}`}
                      </span>
                    )}

                    {/* Copy Period Button */}
                    <button
                      type="button"
                      onClick={() => {
                        setCopySourceRecord(null);
                        setCopySourcePeriod(periodStr);
                        setCopyModalOpen(true);
                      }}
                      className="text-xs px-2.5 py-1 rounded-xl glass-subtle text-slate-600 dark:text-slate-300 hover:text-primary hover:bg-primary/10 transition-colors flex items-center gap-1"
                      title="复制本期所有单到下一期"
                    >
                      <CopyIcon size={12} />
                      <span className="hidden sm:inline">复制整期</span>
                    </button>
                  </div>
                </div>

                {/* Cards Grid / List */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3.5">
                  {periodRecords.map((r) => {
                    const isWon = r.status === "won";
                    const isLost = r.status === "lost";
                    const isPend = r.status === "pending";

                    return (
                      <div
                        key={r.id}
                        onClick={() => setDetailRecord(r)}
                        className="group p-4 sm:p-5 rounded-3xl glass-card hover:border-primary/40 hover:shadow-lg transition-all cursor-pointer flex flex-col justify-between space-y-3 relative overflow-hidden"
                      >
                        {/* Top row: Balls or Zodiacs */}
                        <div className="flex items-start justify-between gap-3">
                          {r.numbers && r.numbers.length > 0 ? (
                            <div className="flex flex-wrap gap-1.5">
                              {r.numbers.map((n) => {
                                const isHit = r.hit_numbers?.includes(n);
                                const bColor = BOSE_COLORS[getBose(n)] || { bg: "#64748b" };
                                return (
                                  <span
                                    key={n}
                                    className={`inline-flex items-center justify-center w-7 h-7 rounded-full text-xs font-bold text-white shadow-sm select-none transition-all ${
                                      isHit
                                        ? "ring-2 ring-emerald-400 shadow-[0_0_10px_rgba(16,185,129,0.5)] scale-105"
                                        : ""
                                    }`}
                                    style={{
                                      backgroundColor: bColor.bg,
                                      opacity: !isPend && !isHit ? 0.45 : 1,
                                    }}
                                    title={`${n} (${getXiao(n)})`}
                                  >
                                    {n}
                                  </span>
                                );
                              })}
                            </div>
                          ) : r.xiaos && r.xiaos.length > 0 ? (
                            <div className="flex flex-wrap gap-1.5">
                              {r.xiaos.map((x) => (
                                <span
                                  key={x}
                                  className="px-2.5 py-1 rounded-xl text-xs font-bold bg-primary/10 text-primary border border-primary/20"
                                >
                                  {x}
                                </span>
                              ))}
                            </div>
                          ) : (
                            <div className="text-xs text-slate-400">
                              {r.raw_input || "单式投注"}
                            </div>
                          )}

                          {/* Status Pill on Card */}
                          <div className="shrink-0">
                            {isWon ? (
                              <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-bold bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 border border-emerald-500/30">
                                {r.win_pill_label || `已中奖 +¥${r.net_profit}`}
                              </span>
                            ) : isLost ? (
                              <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold bg-rose-500/10 text-rose-500 border border-rose-500/20">
                                未中 −¥{r.total_amount}
                              </span>
                            ) : (
                              <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-amber-500/10 text-amber-500 border border-amber-500/20">
                                <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />
                                待开奖
                              </span>
                            )}
                          </div>
                        </div>

                        {/* Bottom Row: Bet Details, Tag Badges, Actions */}
                        <div className="flex items-center justify-between text-xs pt-2 border-t border-slate-200/40 dark:border-white/5 flex-wrap gap-2">
                          <div className="flex items-center gap-2 flex-wrap text-slate-500 dark:text-slate-400">
                            <span>
                              单注 <b className="text-slate-900 dark:text-white font-mono">¥{r.stake_per_note}</b> ×
                              <span className="font-mono"> {r.notes_count}</span> 注 =
                              <b className="text-slate-900 dark:text-white font-mono ml-0.5">
                                ¥{r.total_amount}
                              </b>
                            </span>

                            <span className="px-2 py-0.5 rounded-md text-[11px] font-semibold bg-slate-100 dark:bg-white/5 text-slate-700 dark:text-slate-300">
                              {r.play_type}
                            </span>

                            {r.source_badge && (
                              <span className="px-2 py-0.5 rounded-md text-[10px] bg-primary/10 text-primary flex items-center gap-1">
                                <SparklesIcon size={10} />
                                {r.source_badge}
                              </span>
                            )}

                            {r.time_label && (
                              <span className="text-[11px] text-slate-400 font-mono">
                                {r.time_label}
                              </span>
                            )}
                          </div>

                          {/* Quick Card Hover Actions */}
                          <div className="flex items-center gap-1 opacity-70 group-hover:opacity-100 transition-opacity">
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                setCopySourceRecord(r);
                                setCopyModalOpen(true);
                              }}
                              title="复制到新期"
                              className="p-1.5 rounded-lg text-slate-400 hover:text-primary hover:bg-primary/10 transition-colors"
                            >
                              <CopyIcon size={14} />
                            </button>
                            <button
                              type="button"
                              onClick={(e) => handleDeleteRecord(r.id, e)}
                              title="删除记录"
                              className="p-1.5 rounded-lg text-slate-400 hover:text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-950/20 transition-colors"
                            >
                              <TrashIcon size={14} />
                            </button>
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </section>
            );
          })}
        </div>
      )}

      {/* Add Modal */}
      <RecordAddModal
        isOpen={addModalOpen}
        onClose={() => setAddModalOpen(false)}
        onSuccess={() => {
          fetchRecords();
        }}
        defaultLottery={lottery !== "all" ? lottery : "macau"}
        defaultPeriod={latestPeriod}
      />

      {/* Detail Modal */}
      <RecordDetailModal
        record={detailRecord}
        isOpen={detailRecord !== null}
        onClose={() => setDetailRecord(null)}
        onDeleted={(id) => {
          setRecords((prev) => prev.filter((r) => r.id !== id));
        }}
        onCopyRequested={(rec) => {
          setCopySourceRecord(rec);
          setCopyModalOpen(true);
        }}
      />

      {/* Stats Modal */}
      <RecordStatsModal
        stats={stats}
        isOpen={statsModalOpen}
        onClose={() => setStatsModalOpen(false)}
        lotteryLabel={LOTTERY_LABEL[lottery as Lottery] || (lottery === "all" ? "全部彩种" : lottery)}
      />

      {/* Copy Modal */}
      <RecordCopyModal
        isOpen={copyModalOpen}
        onClose={() => {
          setCopyModalOpen(false);
          setCopySourceRecord(null);
        }}
        onSuccess={() => {
          fetchRecords();
        }}
        sourceRecord={copySourceRecord}
        sourcePeriod={copySourcePeriod}
        lottery={lottery !== "all" ? lottery : "macau"}
      />
    </div>
  );
}
