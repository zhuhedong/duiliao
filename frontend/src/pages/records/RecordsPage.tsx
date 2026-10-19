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
  SearchIcon,
} from "../../components/icons";
import { LOTTERIES, PageWorkspace, SegmentedTabs, StatusPill } from "../collector/shared";
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
    void fetchRecords();
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
    return Array.from(map.entries()).sort((a, b) => b[0].localeCompare(a[0]));
  }, [filteredRecords]);

  const latestPeriod = records[0]?.period || "";

  const lotteryTabs = useMemo(
    () => [
      { id: "all", label: "全部彩种" },
      ...LOTTERIES.map((l) => ({ id: l.value, label: l.label })),
    ],
    [],
  );

  const statusTabs = useMemo(
    () => [
      { id: "all", label: "全部", count: stats?.total_records },
      { id: "pending", label: "待开奖", count: stats?.pending_count },
      { id: "won", label: "已中奖", count: stats?.won_count },
      { id: "lost", label: "未中", count: stats?.lost_count },
    ],
    [stats],
  );

  return (
    <PageWorkspace
      summary="支持智能文本速录、生肖一键包码、官方开奖自动比对结算与多期盈亏复盘。"
      actions={
        <div className="flex items-center gap-2 flex-wrap">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => setStatsModalOpen(true)}
          >
            <BarChartIcon size={14} />
            <span>统计报表</span>
          </Button>

          <Button
            type="button"
            variant="secondary"
            size="sm"
            onClick={handleSettle}
            disabled={settling}
            className="text-emerald-700 dark:text-emerald-300"
          >
            {settling ? <Spinner className="size-3.5" /> : <RefreshIcon size={14} />}
            <span>一键对奖</span>
          </Button>

          <Button type="button" size="sm" onClick={() => setAddModalOpen(true)}>
            <PlusIcon size={15} />
            <span>新增记录</span>
          </Button>
        </div>
      }
    >
      {/* Bento 4-Column KPI Summary */}
      <div className="bento-grid">
        <div className="bento-span-3 bento-card rounded-2xl p-5 flex flex-col justify-between gap-2">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-slate-500 dark:text-slate-400">
              待开奖投入
            </span>
            <span className="w-2 h-2 rounded-full bg-amber-500" />
          </div>
          <div className="text-2xl sm:text-3xl font-bold font-mono tabular-nums text-slate-900 dark:text-white">
            ¥{stats?.pending_stake ?? 0}
          </div>
          <div className="text-[11px] text-slate-400 dark:text-slate-500">
            {stats?.pending_count ?? 0} 单 · {stats?.pending_notes ?? 0} 注待结算
          </div>
        </div>

        <div className="bento-span-3 bento-card rounded-2xl p-5 flex flex-col justify-between gap-2">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-slate-500 dark:text-slate-400">
              累计净盈亏
            </span>
            <span className="text-[11px] font-mono font-semibold text-slate-400 dark:text-slate-500">
              ROI {stats?.roi_pct ?? 0}%
            </span>
          </div>
          <div
            className={`text-2xl sm:text-3xl font-bold font-mono tabular-nums ${
              (stats?.net_profit ?? 0) >= 0
                ? "text-emerald-600 dark:text-emerald-400"
                : "text-rose-600 dark:text-rose-400"
            }`}
          >
            {(stats?.net_profit ?? 0) >= 0
              ? `+¥${stats?.net_profit ?? 0}`
              : `¥${stats?.net_profit ?? 0}`}
          </div>
          <div className="text-[11px] text-slate-400 dark:text-slate-500">
            已结清记录净收益汇总
          </div>
        </div>

        <div className="bento-span-3 bento-card rounded-2xl p-5 flex flex-col justify-between gap-2">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-slate-500 dark:text-slate-400">
              已结算派彩
            </span>
            <span className="text-[11px] text-emerald-600 dark:text-emerald-400 font-medium">
              中 {stats?.hit_notes ?? 0} 注
            </span>
          </div>
          <div className="text-2xl sm:text-3xl font-bold font-mono tabular-nums text-emerald-600 dark:text-emerald-400">
            ¥{stats?.total_payout ?? 0}
          </div>
          <div className="text-[11px] text-slate-400 dark:text-slate-500 font-mono">
            累计总投入 ¥{stats?.total_stake ?? 0}
          </div>
        </div>

        <div className="bento-span-3 bento-card rounded-2xl p-5 flex flex-col justify-between gap-2">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-slate-500 dark:text-slate-400">
              中单胜率
            </span>
            <span className="text-[11px] text-indigo-600 dark:text-indigo-400 font-semibold">
              官方核验
            </span>
          </div>
          <div className="text-2xl sm:text-3xl font-bold font-mono tabular-nums text-indigo-600 dark:text-indigo-400">
            {stats?.win_rate ?? 0}%
          </div>
          <div className="text-[11px] text-slate-400 dark:text-slate-500">
            胜单 <b className="text-slate-700 dark:text-slate-200">{stats?.won_count ?? 0}</b> /{" "}
            {stats?.settled_orders ?? 0} 已结单
          </div>
        </div>
      </div>

      {/* Filter & Search Bento Toolbar */}
      <div className="bento-card rounded-2xl p-3.5 sm:p-4 flex flex-col lg:flex-row lg:items-center justify-between gap-3">
        <SegmentedTabs
          tabs={lotteryTabs}
          activeTab={lottery}
          onChange={setLottery}
        />

        <div className="flex items-center gap-2.5 flex-wrap">
          <SegmentedTabs
            tabs={statusTabs}
            activeTab={statusFilter}
            onChange={setStatusFilter}
          />

          <div className="relative flex items-center">
            <SearchIcon
              size={14}
              className="absolute left-3 text-slate-400 pointer-events-none"
            />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="搜索期号 / 号码 / 备注…"
              className="h-9 pl-8 pr-3 text-xs rounded-xl bento-input w-44 sm:w-52"
            />
          </div>

          {records.length > 0 && (
            <button
              type="button"
              onClick={handleClear}
              title="清空当前筛选记录"
              className="inline-flex items-center justify-center h-9 w-9 rounded-xl text-slate-400 hover:text-rose-600 hover:bg-rose-50 dark:hover:bg-rose-500/10 border border-slate-200/70 dark:border-white/10 transition-colors cursor-pointer"
            >
              <TrashIcon size={15} />
            </button>
          )}
        </div>
      </div>

      {error && (
        <Alert variant="error">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {/* Main Content: Period Groups */}
      {loading ? (
        <div className="bento-card rounded-2xl flex flex-col items-center justify-center py-20 gap-3">
          <Spinner className="size-6 text-indigo-600" />
          <span className="text-xs text-slate-400">正在加载投注对奖数据...</span>
        </div>
      ) : groupedPeriods.length === 0 ? (
        <div className="bento-card rounded-2xl p-12 text-center space-y-3">
          <div className="w-12 h-12 rounded-2xl bg-indigo-50 text-indigo-600 dark:bg-indigo-500/15 dark:text-indigo-400 flex items-center justify-center mx-auto">
            <ClipboardListIcon size={24} />
          </div>
          <div>
            <h3 className="text-sm font-semibold text-slate-900 dark:text-white">
              暂无符合条件的投注记录
            </h3>
            <p className="text-xs text-slate-500 dark:text-slate-400 mt-1 max-w-sm mx-auto leading-relaxed">
              通过智能文本或号码选板快速添加投注单，官方开奖后系统将自动计算中奖结果与盈亏。
            </p>
          </div>
          <div className="pt-2">
            <Button type="button" size="sm" onClick={() => setAddModalOpen(true)}>
              <PlusIcon size={15} />
              <span>立即录入第一单</span>
            </Button>
          </div>
        </div>
      ) : (
        <div className="space-y-5">
          {groupedPeriods.map(([periodStr, periodRecords]) => {
            const hasPending = periodRecords.some((r) => r.status === "pending");
            const periodNet = periodRecords.reduce((acc, r) => acc + (r.net_profit || 0), 0);
            const periodStake = periodRecords.reduce((acc, r) => acc + (r.total_amount || 0), 0);

            return (
              <section key={periodStr} className="space-y-2.5">
                {/* Period Group Header */}
                <div className="flex items-center justify-between px-1 flex-wrap gap-2">
                  <div className="flex items-center gap-2.5">
                    <span className="w-2 h-2 rounded-full bg-indigo-500" />
                    <h2 className="text-sm sm:text-base font-bold text-slate-900 dark:text-white font-mono tabular-nums">
                      第 {periodStr} 期
                    </h2>
                    <span className="text-xs text-slate-400 dark:text-slate-500 tabular-nums">
                      {periodRecords.length} 单 · 投入 ¥{periodStake}
                    </span>
                  </div>

                  <div className="flex items-center gap-2">
                    {hasPending ? (
                      <StatusPill variant="warning">待开奖</StatusPill>
                    ) : (
                      <StatusPill variant={periodNet >= 0 ? "success" : "danger"} dot={false}>
                        本期盈亏 {periodNet >= 0 ? `+¥${periodNet}` : `¥${periodNet}`}
                      </StatusPill>
                    )}

                    <button
                      type="button"
                      onClick={() => {
                        setCopySourceRecord(null);
                        setCopySourcePeriod(periodStr);
                        setCopyModalOpen(true);
                      }}
                      className="text-xs px-2.5 py-1 rounded-lg bg-white dark:bg-white/[0.05] border border-slate-200/70 dark:border-white/10 text-slate-600 dark:text-slate-300 hover:text-indigo-600 dark:hover:text-indigo-300 transition-colors flex items-center gap-1 cursor-pointer"
                      title="复制本期所有单到下一期"
                    >
                      <CopyIcon size={12} />
                      <span className="hidden sm:inline">复制整期</span>
                    </button>
                  </div>
                </div>

                {/* Cards Grid */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3.5">
                  {periodRecords.map((r) => {
                    const isWon = r.status === "won";
                    const isLost = r.status === "lost";
                    const isPend = r.status === "pending";

                    return (
                      <div
                        key={r.id}
                        onClick={() => setDetailRecord(r)}
                        className="group p-4 sm:p-5 rounded-2xl bento-card hover:border-indigo-500/35 dark:hover:border-indigo-400/35 transition-all cursor-pointer flex flex-col justify-between gap-3.5"
                      >
                        <div className="flex items-start justify-between gap-3">
                          {r.numbers && r.numbers.length > 0 ? (
                            <div className="flex flex-wrap gap-1.5">
                              {r.numbers.map((n) => {
                                const isHit = r.hit_numbers?.includes(n);
                                const bColor = BOSE_COLORS[getBose(n)] || { bg: "#64748b" };
                                return (
                                  <span
                                    key={n}
                                    className={`inline-flex items-center justify-center w-7 h-7 rounded-full text-xs font-bold font-mono text-white shadow-2xs select-none transition-all ${
                                      isHit
                                        ? "ring-2 ring-emerald-400 ring-offset-1 ring-offset-white dark:ring-offset-[#13161d] scale-105"
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
                                  className="px-2.5 py-1 rounded-lg text-xs font-semibold bg-indigo-50 text-indigo-700 border border-indigo-200/70 dark:bg-indigo-500/15 dark:text-indigo-300 dark:border-indigo-500/25"
                                >
                                  {x}
                                </span>
                              ))}
                            </div>
                          ) : (
                            <div className="text-xs text-slate-500 dark:text-slate-400">
                              {r.raw_input || "单式投注"}
                            </div>
                          )}

                          <div className="shrink-0">
                            {isWon ? (
                              <StatusPill variant="success" dot={false}>
                                {r.win_pill_label || `已中奖 +¥${r.net_profit}`}
                              </StatusPill>
                            ) : isLost ? (
                              <StatusPill variant="danger" dot={false}>
                                未中 −¥{r.total_amount}
                              </StatusPill>
                            ) : (
                              <StatusPill variant="warning">待开奖</StatusPill>
                            )}
                          </div>
                        </div>

                        <div className="flex items-center justify-between text-xs pt-2.5 border-t border-slate-100 dark:border-white/[0.05] flex-wrap gap-2">
                          <div className="flex items-center gap-2 flex-wrap text-slate-500 dark:text-slate-400">
                            <span className="tabular-nums">
                              单注{" "}
                              <b className="text-slate-900 dark:text-white font-mono">
                                ¥{r.stake_per_note}
                              </b>{" "}
                              × <span className="font-mono">{r.notes_count}</span> 注 ={" "}
                              <b className="text-slate-900 dark:text-white font-mono">
                                ¥{r.total_amount}
                              </b>
                            </span>

                            <span className="px-2 py-0.5 rounded-md text-[11px] font-medium bg-slate-100 dark:bg-white/[0.06] text-slate-700 dark:text-slate-300">
                              {r.play_type}
                            </span>

                            {r.source_badge && (
                              <span className="px-2 py-0.5 rounded-md text-[10px] font-medium bg-indigo-50 text-indigo-700 dark:bg-indigo-500/15 dark:text-indigo-300 flex items-center gap-1">
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

                          <div className="flex items-center gap-1 opacity-75 group-hover:opacity-100 transition-opacity">
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                setCopySourceRecord(r);
                                setCopyModalOpen(true);
                              }}
                              title="复制到新期"
                              className="p-1.5 rounded-lg text-slate-400 hover:text-indigo-600 dark:hover:text-indigo-400 hover:bg-indigo-50 dark:hover:bg-indigo-500/10 transition-colors cursor-pointer"
                            >
                              <CopyIcon size={14} />
                            </button>
                            <button
                              type="button"
                              onClick={(e) => handleDeleteRecord(r.id, e)}
                              title="删除记录"
                              className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 dark:hover:bg-rose-500/10 transition-colors cursor-pointer"
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

      <RecordAddModal
        isOpen={addModalOpen}
        onClose={() => setAddModalOpen(false)}
        onSuccess={() => {
          void fetchRecords();
        }}
        defaultLottery={lottery !== "all" ? lottery : "macau"}
        defaultPeriod={latestPeriod}
      />

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

      <RecordStatsModal
        stats={stats}
        isOpen={statsModalOpen}
        onClose={() => setStatsModalOpen(false)}
        lotteryLabel={
          LOTTERY_LABEL[lottery as Lottery] || (lottery === "all" ? "全部彩种" : lottery)
        }
      />

      <RecordCopyModal
        isOpen={copyModalOpen}
        onClose={() => {
          setCopyModalOpen(false);
          setCopySourceRecord(null);
        }}
        onSuccess={() => {
          void fetchRecords();
        }}
        sourceRecord={copySourceRecord}
        sourcePeriod={copySourcePeriod}
        lottery={lottery !== "all" ? lottery : "macau"}
      />
    </PageWorkspace>
  );
}
