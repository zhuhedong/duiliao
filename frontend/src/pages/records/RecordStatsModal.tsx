import { Portal } from "../../components/Portal";
import { Button, DonutRing, LotteryBall, Sparkline } from "../../components/ui";
import { CloseIcon, BarChartIcon } from "../../components/icons";
import { getBose, getXiao } from "../../lib/lotteryAttr";
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
    50,
  );

  return (
    <Portal onClose={onClose}>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-slate-900/50 dark:bg-black/70 animate-overlay backdrop-blur-xs">
        <div className="w-full max-w-2xl max-h-[92vh] bento-card rounded-3xl animate-scale-in flex flex-col overflow-hidden shadow-2xl">
          {/* Header */}
          <div className="flex items-center justify-between border-b border-slate-200/60 dark:border-white/[0.07] px-6 py-4 shrink-0">
            <div>
              <h3 className="text-lg font-bold text-slate-900 dark:text-white flex items-center gap-2">
                <BarChartIcon size={20} className="text-indigo-600 dark:text-indigo-400" />
                <span>投注盈亏与命中率统计</span>
              </h3>
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                {lotteryLabel} · 基于官方对奖结算数据
              </p>
            </div>
            <button
              type="button"
              onClick={onClose}
              aria-label="关闭统计报表"
              className="p-2 rounded-xl text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-white/5 transition-colors cursor-pointer"
            >
              <CloseIcon size={18} />
            </button>
          </div>

          {/* Body */}
          <div className="overflow-y-auto px-6 py-5 space-y-5 flex-1">
            {/* KPI Overview Grid */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <div className="p-4 rounded-2xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] text-center space-y-1">
                <div className="text-[11px] text-slate-500 dark:text-slate-400">总投入</div>
                <div className="text-xl font-bold font-mono text-slate-900 dark:text-white">
                  ¥{stats.total_stake}
                </div>
                <div className="text-[10px] text-slate-400">
                  {stats.settled_orders} 单 · {stats.total_notes} 注
                </div>
              </div>

              <div className="p-4 rounded-2xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] text-center space-y-1">
                <div className="text-[11px] text-slate-500 dark:text-slate-400">总派彩</div>
                <div className="text-xl font-bold font-mono text-emerald-600 dark:text-emerald-400">
                  ¥{stats.total_payout}
                </div>
                <div className="text-[10px] text-slate-400">
                  中 {stats.hit_notes} 注
                </div>
              </div>

              <div className="p-4 rounded-2xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] text-center space-y-1">
                <div className="text-[11px] text-slate-500 dark:text-slate-400">净盈亏</div>
                <div
                  className={`text-xl font-extrabold font-mono ${
                    stats.net_profit >= 0
                      ? "text-emerald-600 dark:text-emerald-400"
                      : "text-rose-600 dark:text-rose-400"
                  }`}
                >
                  {stats.net_profit >= 0 ? `+¥${stats.net_profit}` : `¥${stats.net_profit}`}
                </div>
                <div className="text-[10px] text-slate-400">
                  回报率 {stats.roi_pct}%
                </div>
              </div>

              <div className="p-3.5 rounded-2xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] flex items-center justify-between gap-2">
                <div className="text-left space-y-0.5">
                  <div className="text-[11px] text-slate-500 dark:text-slate-400">中单率</div>
                  <div className="text-lg font-bold font-mono text-indigo-600 dark:text-indigo-400">
                    {stats.win_rate}%
                  </div>
                  <div className="text-[10px] text-slate-400">
                    {stats.won_count}/{stats.settled_orders} 胜
                  </div>
                </div>
                <DonutRing value={stats.win_rate} size={46} tone="indigo" />
              </div>
            </div>

            {/* Period P&L Bar Chart */}
            {stats.period_bars.length > 0 && (
              <div className="p-5 rounded-2xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] space-y-3">
                <div className="flex items-center justify-between gap-2">
                  <div>
                    <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                      近 {stats.period_bars.length} 期盈亏走势
                    </span>
                    <p className="text-[11px] text-slate-400 mt-0.5">
                      零轴上方为盈利期，下方为亏损期
                    </p>
                  </div>
                  {stats.period_bars.length > 1 && (
                    <Sparkline
                      data={stats.period_bars.map((p) => p.net_profit)}
                      width={96}
                      height={28}
                      tone={stats.net_profit >= 0 ? "emerald" : "rose"}
                    />
                  )}
                </div>

                <div className="pt-6 pb-2">
                  <div className="relative h-32 flex items-center justify-between gap-2 border-b border-slate-200 dark:border-white/10">
                    {/* Zero center axis line */}
                    <div className="absolute left-0 right-0 top-1/2 h-[1px] bg-slate-300 dark:bg-white/20 z-0" />

                    {stats.period_bars.map((p) => {
                      const isPos = p.net_profit >= 0;
                      const heightPercent = Math.min(
                        100,
                        Math.round((Math.abs(p.net_profit) / maxAbsProfit) * 50),
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
                                className="w-3/4 max-w-[28px] rounded-t-md bg-emerald-500 hover:bg-emerald-400 animate-grow-bar transition-all shadow-xs"
                                style={{ height: `${heightPercent * 2}%` }}
                                title={`第 ${p.period} 期: +¥${p.net_profit}`}
                              />
                            )}
                          </div>

                          {/* Lower half: negative bar */}
                          <div className="w-full flex-1 flex items-start justify-center">
                            {!isPos && (
                              <div
                                className="w-3/4 max-w-[28px] rounded-b-md bg-rose-500 hover:bg-rose-400 transition-all shadow-xs"
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
              <div className="p-5 rounded-2xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] space-y-3">
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
                              pb.net_profit >= 0
                                ? "text-emerald-600 dark:text-emerald-400"
                                : "text-rose-600 dark:text-rose-400"
                            }`}
                          >
                            {pb.net_profit >= 0 ? `+¥${pb.net_profit}` : `¥${pb.net_profit}`}
                          </span>
                        </div>
                      </div>

                      {/* Progress bar */}
                      <div className="h-1.5 w-full bg-slate-200/70 dark:bg-white/5 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-indigo-500 animate-grow-x rounded-full"
                          style={{ width: `${Math.min(100, pb.share_pct)}%` }}
                        />
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Hot Betting Numbers TOP 10 */}
            {stats.hot_numbers && stats.hot_numbers.length > 0 && (
              <div className="p-5 rounded-2xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] space-y-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
                    <span>🔥 投注热度号码 TOP {stats.hot_numbers.length}</span>
                  </span>
                  <span className="text-[11px] text-slate-400">
                    按全量记录下注频次与资金排序
                  </span>
                </div>

                <div className="grid grid-cols-2 sm:grid-cols-5 gap-2.5 pt-1">
                  {stats.hot_numbers.map((hn, idx) => (
                    <div
                      key={hn.number}
                      className="p-3 rounded-2xl bg-white dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] flex items-center gap-2.5 relative overflow-hidden"
                    >
                      <div className="absolute top-1 right-2 text-[10px] font-mono font-bold text-slate-300 dark:text-slate-600">
                        #{idx + 1}
                      </div>
                      <LotteryBall
                        number={hn.number}
                        colorHint={hn.bose || getBose(hn.number)}
                        zodiac={hn.xiao || getXiao(hn.number)}
                        size="sm"
                        isHit={hn.hit_count > 0}
                      />
                      <div className="min-w-0 flex-1">
                        <div className="text-xs font-bold text-slate-900 dark:text-white truncate">
                          {hn.count} 次下注
                        </div>
                        <div className="text-[10px] font-mono text-slate-500 dark:text-slate-400">
                          ¥{hn.total_stake}
                          {hn.hit_count > 0 && (
                            <span className="ml-1 text-emerald-600 dark:text-emerald-400 font-semibold">
                              · 中{hn.hit_count}次
                            </span>
                          )}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Frequent Winning Numbers */}
            {stats.frequent_hits.length > 0 && (
              <div className="p-5 rounded-2xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] space-y-3">
                <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                  常中高频幸运号码 TOP 5
                </span>

                <div className="grid grid-cols-5 gap-2 pt-1">
                  {stats.frequent_hits.map((h) => (
                    <div
                      key={h.number}
                      className="p-3 rounded-2xl bg-white dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] text-center flex flex-col items-center gap-1.5"
                    >
                      <LotteryBall
                        number={h.number}
                        colorHint={getBose(h.number)}
                        zodiac={getXiao(h.number)}
                        size="md"
                        isHit
                      />
                      <div className="text-[11px] font-semibold text-slate-900 dark:text-white mt-0.5">
                        中 {h.count} 次
                      </div>
                      <div className="text-[10px] font-mono text-emerald-600 dark:text-emerald-400 font-bold">
                        +¥{h.profit}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Footer */}
          <div className="flex items-center justify-end border-t border-slate-200/60 dark:border-white/[0.07] px-6 py-4 bg-slate-50/50 dark:bg-white/[0.02] shrink-0">
            <Button type="button" onClick={onClose}>
              完成
            </Button>
          </div>
        </div>
      </div>
    </Portal>
  );
}
