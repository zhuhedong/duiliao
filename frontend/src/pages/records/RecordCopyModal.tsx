import { useState, useEffect } from "react";
import { Portal } from "../../components/Portal";
import { Button } from "../../components/ui/button";
import { Spinner } from "../../components/ui/spinner";
import { Alert, AlertDescription } from "../../components/ui/alert";
import { CloseIcon, CopyIcon } from "../../components/icons";
import { recordsApi, type BettingRecord } from "../../lib/records";

interface RecordCopyModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: (count: number) => void;
  sourceRecord?: BettingRecord | null;
  sourcePeriod?: string;
  lottery?: string;
}

export function RecordCopyModal({
  isOpen,
  onClose,
  onSuccess,
  sourceRecord,
  sourcePeriod = "",
  lottery = "macau",
}: RecordCopyModalProps) {
  const [targetPeriod, setTargetPeriod] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const baseP = sourceRecord?.period || sourcePeriod;
    if (baseP) {
      const num = parseInt(baseP, 10);
      if (!isNaN(num)) {
        setTargetPeriod(String(num + 1));
      } else {
        setTargetPeriod(baseP);
      }
    }
  }, [sourceRecord, sourcePeriod]);

  if (!isOpen) return null;

  const handleCopy = async (e: React.FormEvent) => {
    e.preventDefault();
    const tp = targetPeriod.trim();
    if (!tp) {
      setError("请填写目标期号");
      return;
    }

    setLoading(true);
    setError(null);
    try {
      if (sourceRecord) {
        const res = await recordsApi.copySingle(sourceRecord.id, tp);
        if (res.ok) {
          onSuccess(1);
          onClose();
        }
      } else {
        const res = await recordsApi.copy({
          target_period: tp,
          source_period: sourcePeriod || undefined,
          lottery: lottery !== "all" ? lottery : undefined,
        });
        if (res.ok) {
          onSuccess(res.copied_count || 1);
          onClose();
        }
      }
    } catch (err: any) {
      setError(err?.message || "复制失败，请重试");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Portal onClose={onClose}>
      <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-slate-900/50 dark:bg-black/70 animate-fadeIn backdrop-blur-sm">
        <div className="w-full max-w-md glass-card rounded-3xl animate-fadeIn flex flex-col overflow-hidden shadow-2xl border border-slate-200/50 dark:border-white/10 bg-white dark:bg-slate-900">
          {/* Header */}
          <div className="flex items-center justify-between border-b border-slate-200/50 dark:border-white/10 px-6 py-4">
            <h3 className="text-base font-bold text-slate-900 dark:text-white flex items-center gap-2">
              <CopyIcon size={18} className="text-primary" />
              <span>{sourceRecord ? "复制此单到新期" : "批量复制记录到新期"}</span>
            </h3>
            <button
              onClick={onClose}
              className="p-1.5 rounded-xl text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-white/5 transition-colors"
            >
              <CloseIcon size={18} />
            </button>
          </div>

          <form onSubmit={handleCopy} className="p-6 space-y-4">
            {error && (
              <Alert variant="error">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            <div className="text-xs text-slate-500 dark:text-slate-400 leading-relaxed">
              {sourceRecord ? (
                <>
                  将第 <span className="font-mono font-bold text-slate-900 dark:text-white">{sourceRecord.period}</span> 期
                  的投注单（{sourceRecord.play_type} · {sourceRecord.notes_count}注 · ¥{sourceRecord.total_amount}）复制到目标期号并生成待开奖记录。
                </>
              ) : (
                <>
                  将第 <span className="font-mono font-bold text-slate-900 dark:text-white">{sourcePeriod || "当前"}</span> 期
                  的所有投注记录复制到目标期号，自动重置为待开奖状态。
                </>
              )}
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider mb-2">
                目标期号
              </label>
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  required
                  value={targetPeriod}
                  onChange={(e) => setTargetPeriod(e.target.value)}
                  placeholder="如 2026278"
                  className="flex-1 px-3.5 py-2 text-sm rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50/50 dark:bg-white/5 focus:outline-none focus:ring-2 focus:ring-primary/50 text-slate-900 dark:text-white font-mono"
                />
                <button
                  type="button"
                  onClick={() => {
                    const num = parseInt(targetPeriod, 10);
                    if (!isNaN(num)) setTargetPeriod(String(num + 1));
                  }}
                  className="px-3 py-2 text-xs rounded-xl glass-subtle text-slate-700 dark:text-slate-300 hover:text-primary transition-colors font-medium"
                >
                  +1期
                </button>
              </div>
            </div>

            <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-200/50 dark:border-white/10">
              <Button type="button" variant="outline" onClick={onClose} disabled={loading}>
                取消
              </Button>
              <Button type="submit" disabled={loading} className="gap-2">
                {loading && <Spinner className="size-4" />}
                <span>确认复制</span>
              </Button>
            </div>
          </form>
        </div>
      </div>
    </Portal>
  );
}
