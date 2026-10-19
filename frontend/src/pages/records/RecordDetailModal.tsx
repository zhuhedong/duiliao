import { useState } from "react";
import { Portal } from "../../components/Portal";
import { Button } from "../../components/ui/button";
import { Spinner } from "../../components/ui/spinner";
import {
  CloseIcon,
  CopyIcon,
  TrashIcon,
  CheckIcon,
} from "../../components/icons";
import { LOTTERY_LABEL, type Lottery } from "../../lib/collector";
import { BOSE_COLORS, getBose, getXiao } from "../../lib/lotteryAttr";
import { recordsApi, type BettingRecord } from "../../lib/records";

interface RecordDetailModalProps {
  record: BettingRecord | null;
  isOpen: boolean;
  onClose: () => void;
  onDeleted: (recordId: string) => void;
  onCopyRequested: (record: BettingRecord) => void;
}

export function RecordDetailModal({
  record,
  isOpen,
  onClose,
  onDeleted,
  onCopyRequested,
}: RecordDetailModalProps) {
  const [deleting, setDeleting] = useState(false);

  if (!isOpen || !record) return null;

  const isWon = record.status === "won";
  const isLost = record.status === "lost";
  const isPending = record.status === "pending";

  const drawBalls = record.draw?.balls || record.draw_numbers || [];
  const drawTema = record.draw?.tema || record.special_number || "";

  const handleDelete = async () => {
    if (!window.confirm("确定要删除此条投注记录吗？删除后不可恢复。")) return;
    setDeleting(true);
    try {
      const res = await recordsApi.delete(record.id);
      if (res.ok) {
        onDeleted(record.id);
        onClose();
      }
    } catch (err: any) {
      alert(err?.message || "删除失败");
    } finally {
      setDeleting(false);
    }
  };

  return (
    <Portal onClose={onClose}>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-slate-900/50 dark:bg-black/70 animate-fadeIn backdrop-blur-sm">
        <div className="w-full max-w-xl max-h-[92vh] glass-card rounded-3xl animate-fadeIn flex flex-col overflow-hidden shadow-2xl border border-slate-200/50 dark:border-white/10 bg-white dark:bg-slate-900">
          {/* Header */}
          <div className="flex items-center justify-between border-b border-slate-200/50 dark:border-white/10 px-6 py-4 shrink-0">
            <div className="flex items-center gap-2">
              <span className="text-xs px-2.5 py-0.5 rounded-full bg-primary/10 text-primary font-bold">
                {LOTTERY_LABEL[record.lottery as Lottery] || record.lottery}
              </span>
              <span className="text-sm font-bold text-slate-900 dark:text-white font-mono">
                第 {record.period} 期
              </span>
              <span className="text-xs px-2 py-0.5 rounded-md glass-subtle text-slate-600 dark:text-slate-400">
                {record.play_type}
              </span>
            </div>
            <button
              onClick={onClose}
              className="p-2 rounded-xl text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-white/5 transition-colors"
            >
              <CloseIcon size={20} />
            </button>
          </div>

          {/* Scrollable Body */}
          <div className="overflow-y-auto px-6 py-5 space-y-6 flex-1">
            {/* Hero Settle Status */}
            <div
              className={`p-6 rounded-3xl text-center space-y-2 border transition-all ${
                isWon
                  ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-600 dark:text-emerald-400"
                  : isLost
                  ? "bg-rose-500/10 border-rose-500/30 text-rose-600 dark:text-rose-400"
                  : "bg-amber-500/10 border-amber-500/30 text-amber-600 dark:text-amber-400"
              }`}
            >
              <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-white/60 dark:bg-black/30 backdrop-blur-sm">
                <span
                  className={`w-2 h-2 rounded-full ${
                    isWon
                      ? "bg-emerald-500 animate-pulse"
                      : isLost
                      ? "bg-rose-500"
                      : "bg-amber-500 animate-pulse"
                  }`}
                />
                <span>
                  {isWon
                    ? record.win_pill_label || "已中奖"
                    : isLost
                    ? "未中"
                    : "待开奖 · 盘口锁定"}
                </span>
              </div>

              <div className="text-4xl font-extrabold font-mono tracking-tight">
                {isWon ? (
                  `+¥${record.net_profit}`
                ) : isLost ? (
                  `-¥${record.total_amount}`
                ) : (
                  <span className="text-2xl">¥{record.total_amount} (已投注)</span>
                )}
              </div>

              <div className="text-xs text-slate-500 dark:text-slate-400">
                第 {record.period} 期 · {record.mode} · 赔率 1:{record.odds}
              </div>
            </div>

            {/* My Numbers / Selection */}
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                  我的投注内容
                  {record.hit_numbers?.length > 0 && (
                    <span className="text-emerald-500 ml-2 font-mono">
                      (命中 {record.hit_numbers.length} 码)
                    </span>
                  )}
                </span>
                <span className="text-xs text-slate-400">
                  共 {record.notes_count} 注 · 单注 ¥{record.stake_per_note}
                  {record.multiplier > 1 && ` · ${record.multiplier}倍`}
                </span>
              </div>

              {/* Balls Grid */}
              {record.numbers?.length > 0 && (
                <div className="p-4 rounded-2xl glass-card flex flex-wrap gap-3 justify-center">
                  {record.numbers.map((n) => {
                    const isHit = record.hit_numbers?.includes(n);
                    const bColor = BOSE_COLORS[getBose(n)] || { bg: "#64748b" };
                    return (
                      <div
                        key={n}
                        className="flex flex-col items-center gap-1"
                        style={{ opacity: !isPending && !isHit ? 0.45 : 1 }}
                      >
                        <div
                          className={`relative flex items-center justify-center w-11 h-11 rounded-full text-sm font-bold text-white shadow-md transition-all select-none ${
                            isHit
                              ? "ring-4 ring-emerald-500 shadow-[0_0_16px_rgba(16,185,129,0.55)] scale-110"
                              : ""
                          }`}
                          style={{ backgroundColor: bColor.bg }}
                        >
                          {n}
                        </div>
                        <span
                          className={`text-[11px] font-semibold ${
                            isHit
                              ? "text-emerald-500 font-bold"
                              : "text-slate-400 dark:text-slate-500"
                          }`}
                        >
                          {isHit ? "中" : getXiao(n)}
                        </span>
                      </div>
                    );
                  })}
                </div>
              )}

              {/* Zodiacs */}
              {record.xiaos?.length > 0 && (
                <div className="p-4 rounded-2xl glass-card flex flex-wrap gap-2.5 justify-center">
                  {record.xiaos.map((x) => {
                    const isHit = record.hit_numbers?.includes(x);
                    return (
                      <div
                        key={x}
                        className={`px-4 py-2 rounded-2xl text-sm font-bold flex items-center gap-1.5 transition-all ${
                          isHit
                            ? "bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 border border-emerald-500/50 shadow-md"
                            : "bg-primary/10 text-primary border border-primary/20"
                        }`}
                      >
                        <span>{x}</span>
                        {isHit && <CheckIcon size={14} className="text-emerald-500" />}
                      </div>
                    );
                  })}
                </div>
              )}
            </div>

            {/* Official Draw Comparison */}
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                  官方开奖对照
                </span>
                <span className="text-xs text-slate-400 font-mono">
                  {record.draw_time || record.draw?.opened_at || "开奖状态"}
                </span>
              </div>

              <div className="p-4 rounded-2xl glass-card space-y-3">
                {drawBalls.length > 0 ? (
                  <>
                    <div className="flex items-center justify-center gap-2 flex-wrap">
                      {drawBalls.slice(0, 6).map((b, i) => {
                        const bColor = BOSE_COLORS[getBose(b)] || { bg: "#64748b" };
                        const isMyHit = record.numbers?.includes(b);
                        return (
                          <div key={i} className="flex flex-col items-center gap-1">
                            <span
                              className={`inline-flex items-center justify-center w-8 h-8 rounded-full text-xs font-bold text-white shadow-sm ${
                                isMyHit ? "ring-2 ring-emerald-400 shadow-md" : ""
                              }`}
                              style={{ backgroundColor: bColor.bg }}
                            >
                              {b}
                            </span>
                            <span className="text-[10px] text-slate-400">
                              {getXiao(b)}
                            </span>
                          </div>
                        );
                      })}
                      <span className="text-slate-400 font-bold px-1">+</span>
                      {drawTema && (
                        <div className="flex flex-col items-center gap-1">
                          <span
                            className={`inline-flex items-center justify-center w-8 h-8 rounded-full text-xs font-bold text-white shadow-sm ring-2 ring-amber-400 ${
                              record.numbers?.includes(drawTema)
                                ? "shadow-[0_0_12px_rgba(251,191,36,0.6)]"
                                : ""
                            }`}
                            style={{
                              backgroundColor:
                                BOSE_COLORS[getBose(drawTema)]?.bg || "#ef4444",
                            }}
                          >
                            {drawTema}
                          </span>
                          <span className="text-[10px] text-amber-500 font-bold">
                            特·{getXiao(drawTema)}
                          </span>
                        </div>
                      )}
                    </div>

                    <div className="text-center pt-2 border-t border-slate-200/50 dark:border-white/10 text-xs text-slate-500 dark:text-slate-400">
                      号码命中 <b className="text-emerald-500 font-mono font-bold">{record.hit_numbers?.length || 0}</b> 个
                      {record.numbers?.length > 0 && (
                        <span>
                          {" "}· 命中率{" "}
                          <span className="font-mono font-bold text-slate-700 dark:text-slate-200">
                            {Math.round(
                              ((record.hit_numbers?.length || 0) /
                                record.numbers.length) *
                                100
                            )}
                            %
                          </span>
                        </span>
                      )}
                    </div>
                  </>
                ) : (
                  <div className="text-center py-3 text-xs text-slate-400">
                    本期官方尚未开奖，开奖后系统将自动核算派彩
                  </div>
                )}
              </div>
            </div>

            {/* Financial Breakdown Table */}
            <div className="space-y-3">
              <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                结算明细
              </span>

              <div className="rounded-2xl glass-card divide-y divide-slate-200/50 dark:divide-white/10 text-xs">
                <div className="flex items-center justify-between px-4 py-3">
                  <div>
                    <div className="font-semibold text-slate-900 dark:text-white">投入金额</div>
                    <div className="text-slate-400 mt-0.5">
                      {record.notes_count} 注 × ¥{record.stake_per_note} × {record.multiplier} 倍
                    </div>
                  </div>
                  <div className="font-mono font-bold text-slate-900 dark:text-white text-sm">
                    ¥{record.total_amount}
                  </div>
                </div>

                <div className="flex items-center justify-between px-4 py-3">
                  <div>
                    <div className="font-semibold text-slate-900 dark:text-white">中奖注数</div>
                    <div className="text-slate-400 mt-0.5">
                      赔率 1:{record.odds} · 命中 {record.hit_notes} 注
                    </div>
                  </div>
                  <div className="font-mono font-bold text-slate-900 dark:text-white text-sm">
                    {record.hit_notes} 注
                  </div>
                </div>

                <div className="flex items-center justify-between px-4 py-3">
                  <div>
                    <div className="font-semibold text-slate-900 dark:text-white">派彩金额</div>
                    <div className="text-slate-400 mt-0.5">
                      {record.hit_notes} 注 × ¥{record.stake_per_note} × {record.odds} 赔率
                    </div>
                  </div>
                  <div className="font-mono font-bold text-emerald-500 text-sm">
                    ¥{record.payout}
                  </div>
                </div>

                <div className="flex items-center justify-between px-4 py-3 bg-slate-50/50 dark:bg-white/[0.02] rounded-b-2xl">
                  <div>
                    <div className="font-bold text-slate-900 dark:text-white">净盈亏</div>
                    <div className="text-slate-400 mt-0.5">派彩 ¥{record.payout} − 投入 ¥{record.total_amount}</div>
                  </div>
                  <div
                    className={`font-mono font-extrabold text-base ${
                      record.net_profit > 0
                        ? "text-emerald-500"
                        : record.net_profit < 0
                        ? "text-rose-500"
                        : "text-slate-500"
                    }`}
                  >
                    {record.net_profit > 0 ? `+¥${record.net_profit}` : `¥${record.net_profit}`}
                  </div>
                </div>
              </div>
            </div>

            {/* Raw Input and Notes */}
            {(record.raw_input || record.note || record.source_badge) && (
              <div className="space-y-3">
                <span className="text-xs font-bold text-slate-700 dark:text-slate-300 uppercase tracking-wider">
                  原始录入与备注
                </span>
                <div className="p-4 rounded-2xl glass-subtle space-y-2">
                  {record.raw_input && (
                    <div className="font-mono text-xs text-slate-800 dark:text-slate-200 bg-black/5 dark:bg-white/5 p-2.5 rounded-xl break-all">
                      {record.raw_input}
                    </div>
                  )}
                  {record.note && (
                    <div className="text-xs text-slate-600 dark:text-slate-400">
                      备注：{record.note}
                    </div>
                  )}
                  <div className="flex items-center justify-between text-[11px] text-slate-400 pt-1">
                    <span>来源：{record.source_badge || "手工录入"}</span>
                    <span>录入时间：{record.created_at || record.time_label || "未知"}</span>
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* Footer Actions */}
          <div className="flex items-center justify-between border-t border-slate-200/50 dark:border-white/10 px-6 py-4 bg-slate-50/50 dark:bg-white/[0.02] shrink-0">
            <Button
              type="button"
              variant="outline"
              onClick={handleDelete}
              disabled={deleting}
              className="text-rose-500 hover:text-rose-600 hover:bg-rose-50 dark:hover:bg-rose-950/20 gap-1.5"
            >
              {deleting ? <Spinner className="size-4" /> : <TrashIcon size={16} />}
              <span>删除本单</span>
            </Button>

            <div className="flex items-center gap-3">
              <Button
                type="button"
                variant="outline"
                onClick={() => {
                  onCopyRequested(record);
                  onClose();
                }}
                className="gap-1.5"
              >
                <CopyIcon size={16} />
                <span>复制到其它期</span>
              </Button>
              <Button type="button" onClick={onClose}>
                关闭
              </Button>
            </div>
          </div>
        </div>
      </div>
    </Portal>
  );
}
