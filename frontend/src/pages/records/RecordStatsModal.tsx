import { Portal } from "../../components/Portal";
import { Button } from "../../components/ui/button";
import { CloseIcon, BarChartIcon } from "../../components/icons";
import { BOSE_COLORS, getBose } from "../../lib/lotteryAttr";
import type { RecordStats } from "../../lib/records";

interface RecordStatsModalProps {
  stats: RecordStats | null;
  isOpen: boolean;
  onClose: () => void;
  lotteryLabel?: string;
}

export function RecordStatsModal({
  stats,
  isOpen,
  onClose,
  lotteryLabel = "全部彩种",
}: RecordStatsModalProps) {
  if (!isOpen || !stats) return null;

  const maxAbsProfit = Math.max(
    ...stats.period_bars.map((p) => Math.abs(p.net_profit)),
    50
  );

  return (
    <Portal onClose={onClose}>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-slate-900/50 dark:bg-black/70 animate-fadeIn backdrop-blur-sm">
        <div className="w-full max-w-2xl max-h-[92vh] glass-card rounded-3xl animate-fadeIn flex flex-col overflow-hidden shadow-2xl border border-slate-200/50 dark:border-white/10 bg-white dark:bg-slate-900">
          {/* Header */}
          <div className="flex items-center justify-between border-b border-slate-200/50 dark:border-white/10 px-6 py-4 shrink-0">
            <div>
              <h3 className="text-lg font-bold text-slate-900 dark:text-white flex items-center gap-2">
                <BarChartIcon size={20} className="text-primary" />
                <span>投注盈亏与命中率统计</span>
              </h3>
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                {lotteryLabel} · 基于官方对奖结算数据
              </p>
            </div>
            <button
              onClick={onClose}
              className="p-2 rounded-xl text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-white/5 transition-colors"
            >
              <CloseIcon size={20} />
            </button>
          </div>

          {/* Body */}
          <div className="overflow-y-auto px-6 py-5 space-y-6 flex-1">
            {/* KPI Overview Grid */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <div className="p-4 rounded-2xl glass-card text-center space-y-1">
                <div className="text-[11px] text-slate-500 dark:text-slate-400">总投入</div>
                <div className="text-xl font-bold font-mono text-slate-900 dark:text-white">
                  ¥{stats.total_stake}
                </div>
                <div className="text-[10px] text-slate-400">
                  {stats.settled_orders} 单 · {stats.total_notes} 注
                </div>
              </div>

              <div className="p-4 rounded-2xl glass-card text-center space-y-1">
                <div className="text-[11px] text-slate-500 dark:text-slate-400">总派彩</div>
                <div className="text-xl font-bold font-mono text-emerald-500">
                  ¥{stats.total_payout}
                </div>
                <div className="text-[10px] text-slate-400">
                  中 {stats.hit_notes} 注
                </div>
              </div>

              <div className="p-4 rounded-2xl glass-card text-center space-y-1">
                <div className="text-[11px] text-slate-500 dark:text-slate-400">净盈亏</div>
                <div
                  className={`text-xl font-extrabold font-mono ${
                    stats.net_profit >= 0 ? "text-emerald-500" : "text-rose-500"
                  }`}
                >
                  {stats.net_profit >= 0 ? `+¥${stats.net_profit}` : `¥${stats.net_profit}`}
                </div>
                <div className="text-[10px] text-slate-400">
                  回报率 {stats.roi_pct}%
                </div>
              </div>

              <div className="p-4 rounded-2xl glass-card text-center space-y-1">
                <div className="text-[11px] text-slate-500 dark:text-slate-400">中单率</div>
                <div className="text-xl font-bold font-mono text-primary">
                  {stats.win_rate}%
                </div>
                <div className="text-[10px] text-slate-400">
                  {stats.won_count}/{stats.settled_orders} 胜单
                </div>
              </div>
            </div>

            {/* Period P&L Bar Chart */}
            {stats.period_bars.length > 0 && (
              <div className="p-5 rounded-2xl glass-card space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                    近 {stats.period_bars.length} 期盈亏走势
                  </span>
                  <span className="text-xs text-slate-400">
                    柱高代表当期净盈亏金额
                  </span>
                </div>

                <div className="pt-6 pb-2">
                  <div className="relative h-32 flex items-center justify-between gap-2 border-b border-slate-200 dark:border-white/10">
                    {/* Zero center axis line */}
                    <div className="absolute left-0 right-0 top-1/2 h-[1px] bg-slate-300 dark:bg-white/20 z-0" />

                    {stats.period_bars.map((p) => {
                      const isPos = p.net_profit >= 0;
                      const heightPercent = Math.min(
                        100,
                        Math.round((Math.abs(p.net_profit) / maxAbsProfit) * 50)
                      );

                      return (
                        <div
                          key={p.period}
                          className="flex-1 flex flex-col items-center justify-center h-full relative z-10 group"
                        >
                          {/* Value tooltip */}
                          <div className="absolute -top-7 text-[10px] font-mono font-bold opacity-0 group-hover:opacity-100 transition-opacity bg-slate-800 text-white dark:bg-white dark:text-slate-900 px-1.5 py-0.5 rounded shadow pointer-events-none">
                            {isPos ? `+¥${p.net_profit}` : `¥${p.net_profit}`}
                          </div>

                          {/* Upper half: positive bar */}
                          <div className="w-full flex-1 flex items-end justify-center">
                            {isPos && (
                              <div
                                className="w-3/4 max-w-[28px] rounded-t-md bg-emerald-500 hover:bg-emerald-400 transition-all shadow-sm"
                                style={{ height: `${heightPercent * 2}%` }}
                                title={`第 ${p.period} 期: +¥${p.net_profit}`}
                              />
                            )}
                          </div>

                          {/* Lower half: negative bar */}
                          <div className="w-full flex-1 flex items-start justify-center">
                            {!isPos && (
                              <div
                                className="w-3/4 max-w-[28px] rounded-b-md bg-rose-500 hover:bg-rose-400 transition-all shadow-sm"
                                style={{ height: `${heightPercent * 2}%` }}
                                title={`第 ${p.period} 期: ¥${p.net_profit}`}
                              />
                            )}
                          </div>
                        </div>
                      );
                    })}
                  </div>

                  {/* Period labels below */}
                  <div className="flex items-center justify-between gap-2 mt-2">
                    {stats.period_bars.map((p) => (
                      <span
                        key={p.period}
                        className="flex-1 text-center font-mono text-[10px] text-slate-500 truncate"
                      >
                        {p.period.slice(-3)}期
                      </span>
                    ))}
                  </div>
                </div>
              </div>
            )}

            {/* Play Type Breakdown */}
            {stats.play_breakdown.length > 0 && (
              <div className="p-5 rounded-2xl glass-card space-y-3">
                <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                  各玩法资金分布与回报
                </span>

                <div className="space-y-3 pt-1">
                  {stats.play_breakdown.map((pb) => (
                    <div key={pb.play_type} className="space-y-1">
                      <div className="flex items-center justify-between text-xs">
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-slate-900 dark:text-white">
                            {pb.play_type}
                          </span>
                          <span className="text-[11px] text-slate-400">
                            {pb.count}单 (胜率 {pb.win_rate}%)
                          </span>
                        </div>
                        <div className="flex items-center gap-3 font-mono">
                          <span className="text-slate-600 dark:text-slate-300">
                            投入 ¥{pb.stake} ({pb.share_pct}%)
                          </span>
                          <span
                            className={`font-bold ${
                              pb.net_profit >= 0 ? "text-emerald-500" : "text-rose-500"
                            }`}
                          >
                            {pb.net_profit >= 0 ? `+¥${pb.net_profit}` : `¥${pb.net_profit}`}
                          </span>
                        </div>
                      </div>

                      {/* Progress bar */}
                      <div className="h-1.5 w-full bg-slate-100 dark:bg-white/5 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-primary rounded-full"
                          style={{ width: `${Math.min(100, pb.share_pct)}%` }}
                        />
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Frequent Winning Numbers */}
            {stats.frequent_hits.length > 0 && (
              <div className="p-5 rounded-2xl glass-card space-y-3">
                <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                  常中高频幸运号码 TOP 5
                </span>

                <div className="grid grid-cols-5 gap-2 pt-1">
                  {stats.frequent_hits.map((h) => {
                    const bColor = BOSE_COLORS[getBose(h.number)] || { bg: "#64748b" };
                    return (
                      <div
                        key={h.number}
                        className="p-3 rounded-2xl bg-slate-50/70 dark:bg-white/[0.03] border border-slate-200/50 dark:border-white/5 text-center flex flex-col items-center gap-1.5"
                      >
                        <span
                          className="inline-flex items-center justify-center w-9 h-9 rounded-full text-xs font-bold text-white shadow-md ring-2 ring-white/20"
                          style={{ backgroundColor: bColor.bg }}
                        >
                          {h.number}
                        </span>
                        <div className="text-[11px] font-semibold text-slate-900 dark:text-white">
                          中 {h.count} 次
                        </div>
                        <div className="text-[10px] font-mono text-emerald-500 font-bold">
                          +¥{h.profit}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end border-t border-slate-200/50 dark:border-white/10 px-6 py-4 bg-slate-50/50 dark:bg-white/[0.02] shrink-0">
            <Button type="button" onClick={onClose}>
              完成
            </Button>
          </div>
        </div>
      </div>
    </Portal>
  );
}
