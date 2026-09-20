import { useEffect, useState } from "react";
import { Spinner } from "@appica/ui-react/spinner";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { ApiError } from "../../lib/api";
import { collectorApi, type CatalogStatus, type Lottery, type MonitorResult } from "../../lib/collector";
import {
  LOTTERIES,
  PageHeader,
  ReadOnlyNote,
  Select,
  playLabel,
  useCanWrite,
  SectionCard,
  TableContainer,
  tableThClass,
  tableTdClass,
  tableRowClass,
  StatusPill,
} from "./shared";
import { ActivityIcon, RefreshIcon } from "../../components/icons";

export function CollectorMonitorPage() {
  const canWrite = useCanWrite();
  const [lottery, setLottery] = useState<Lottery>("macau");
  const [monitor, setMonitor] = useState<MonitorResult | null>(null);
  const [catalog, setCatalog] = useState<CatalogStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [scanning, setScanning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadMonitor = async (lot: Lottery) => {
    setLoading(true);
    setError(null);
    try {
      setMonitor(await collectorApi.monitor(lot));
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "加载缺期监控失败");
    } finally {
      setLoading(false);
    }
  };

  const loadCatalog = async () => {
    try {
      setCatalog(await collectorApi.catalogStatus());
    } catch {
      /* catalog is optional */
    }
  };

  useEffect(() => {
    void loadMonitor(lottery);
  }, [lottery]);

  useEffect(() => {
    void loadCatalog();
  }, []);

  const scan = async () => {
    setScanning(true);
    setError(null);
    try {
      setCatalog(await collectorApi.catalogScan(true));
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "巡检失败");
    } finally {
      setScanning(false);
    }
  };

  const handleConfirmMissing = async (sourceId: string, periods: string[]) => {
    try {
      await collectorApi.confirmMissing(sourceId, periods);
      await loadMonitor(lottery);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "确认缺期失败");
    }
  };

  const items = monitor?.items ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="缺期监控与栏目巡检"
        desc="按实际官方已开奖期号统计各来源落后缺期情况，并定时核验上游网站栏目与目录结构的存活健康度。"
        right={canWrite ? null : <ReadOnlyNote />}
      />

      {error && (
        <Alert variant="error" className="rounded-2xl border border-rose-200 dark:border-rose-900 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200">
          <AlertDescription className="text-sm">{error}</AlertDescription>
        </Alert>
      )}

      {/* 栏目巡检 */}
      <SectionCard
        title={
          <div className="flex items-center gap-2">
            <ActivityIcon size={18} className="text-primary" />
            <span>上游站群栏目巡检 (588080 / 顶尖大师)</span>
          </div>
        }
        subtitle="实时嗅探网站是否发生改版、栏目下架、URL变更或接口不可用"
        action={
          <button
            type="button"
            onClick={scan}
            disabled={!canWrite || scanning}
            className="inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-semibold bg-primary hover:bg-primary/90 text-white shadow-xs transition-all disabled:opacity-50 cursor-pointer"
          >
            <RefreshIcon size={14} className={scanning ? "animate-spin" : ""} />
            <span>{scanning ? "巡检中…" : "立即巡检上游"}</span>
          </button>
        }
      >
        <div className="space-y-3">
          {catalog ? (
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
              <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
                <span className="text-2xs font-semibold text-slate-400 block uppercase">巡检状态</span>
                <div className="mt-1">
                  {catalog.ok ? (
                    <StatusPill variant="success">正常通畅</StatusPill>
                  ) : (
                    <StatusPill variant="danger">异常拦截</StatusPill>
                  )}
                </div>
              </div>

              <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
                <span className="text-2xs font-semibold text-slate-400 block uppercase">自动巡检频率</span>
                <span className="text-sm font-bold mt-1 text-slate-900 dark:text-white block">
                  {catalog.enabled ? `每 ${catalog.interval_minutes} 分钟` : "已关闭"}
                </span>
              </div>

              <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
                <span className="text-2xs font-semibold text-slate-400 block uppercase">发现有效栏目</span>
                <span className="text-sm font-bold mt-1 text-primary block font-mono">
                  {catalog.content_total} 个
                </span>
              </div>

              <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
                <span className="text-2xs font-semibold text-slate-400 block uppercase">新发现待接入</span>
                <span className="text-sm font-bold mt-1 text-slate-900 dark:text-white block font-mono">
                  {catalog.pending?.length ?? 0}
                </span>
              </div>

              <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
                <span className="text-2xs font-semibold text-slate-400 block uppercase">已消失栏目</span>
                <span className="text-sm font-bold mt-1 text-slate-900 dark:text-white block font-mono">
                  {catalog.missing?.length ?? 0}
                </span>
              </div>

              <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
                <span className="text-2xs font-semibold text-slate-400 block uppercase">未处理异常</span>
                <span className={`text-sm font-bold mt-1 block font-mono ${
                  (catalog.open_issue_count ?? 0) > 0 ? "text-rose-500" : "text-emerald-500"
                }`}>
                  {catalog.open_issue_count ?? 0} 项
                </span>
              </div>
            </div>
          ) : (
            <p className="text-xs text-slate-400">尚无巡检记录。</p>
          )}

          {catalog?.last_error && (
            <div className="p-3 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 text-xs">
              最近错误：{catalog.last_error}
            </div>
          )}
        </div>
      </SectionCard>

      {/* 缺期监控 */}
      <SectionCard
        title={
          <div className="flex items-center gap-3">
            <span>各数据源缺期滞后监控</span>
            <span className="text-xs font-mono px-2.5 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 border border-slate-200 dark:border-slate-700">
              共 {items.length} 个来源
            </span>
          </div>
        }
        action={
          <div className="flex items-center gap-3">
            <Select value={lottery} onChange={(v) => setLottery(v as Lottery)} options={LOTTERIES} />
            <button
              type="button"
              onClick={() => loadMonitor(lottery)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
            >
              <RefreshIcon size={14} className={loading ? "animate-spin" : ""} />
              <span>刷新</span>
            </button>
          </div>
        }
      >
        {loading ? (
          <div className="p-12 flex justify-center">
            <Spinner aria-label="加载中" />
          </div>
        ) : items.length === 0 ? (
          <div className="py-12 text-center text-sm text-slate-400">
            暂无来源。
          </div>
        ) : (
          <TableContainer>
            <thead>
              <tr>
                <th className={tableThClass}>数据源名称 / ID</th>
                <th className={tableThClass}>玩法类型</th>
                <th className={tableThClass}>最新抓取期数</th>
                <th className={tableThClass}>官方最新开奖</th>
                <th className={tableThClass}>落后状态</th>
                <th className={tableThClass}>待补抓 / 异常期</th>
                <th className={tableThClass}>已确认缺期</th>
              </tr>
            </thead>
            <tbody>
              {items.map((m) => (
                <tr key={m.source_id} className={tableRowClass}>
                  <td className={tableTdClass}>
                    <div className="font-semibold text-slate-900 dark:text-white">
                      {m.source_name}
                    </div>
                    <div className="text-xs font-mono text-slate-400 mt-0.5">{m.source_id}</div>
                  </td>
                  <td className={tableTdClass}>
                    <span className="text-xs font-medium px-2 py-0.5 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300">
                      {playLabel(m.play_type)}
                    </span>
                  </td>
                  <td className={tableTdClass}>
                    <span className="font-mono text-xs">
                      {m.latest_period ? `第 ${m.latest_period} 期` : (m.never_collected ? "未采集" : "—")}
                    </span>
                  </td>
                  <td className={tableTdClass}>
                    <span className="font-mono text-xs text-slate-500 dark:text-slate-400">
                      {m.latest_draw ? `第 ${m.latest_draw} 期` : "—"}
                    </span>
                  </td>
                  <td className={tableTdClass}>
                    {m.lag == null ? (
                      <span className="text-slate-400">—</span>
                    ) : m.lag > 0 ? (
                      <StatusPill variant="warning">落后 {m.lag} 期</StatusPill>
                    ) : (
                      <StatusPill variant="success">已跟进最新</StatusPill>
                    )}
                  </td>
                  <td className={tableTdClass}>
                    <div className="flex items-center gap-2">
                      <span className={`font-mono text-xs ${m.pending_total > 0 ? "font-bold text-amber-500" : "text-slate-400"}`}>
                        {m.pending_total} 期
                      </span>
                      {canWrite && m.pending_total > 0 && m.pending.length > 0 && (
                        <button
                          type="button"
                          onClick={() => handleConfirmMissing(m.source_id, m.pending)}
                          className="px-2.5 py-0.5 rounded-lg text-xs font-medium text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-950/40 border border-amber-200 dark:border-amber-800 transition-colors cursor-pointer"
                        >
                          确认缺期
                        </button>
                      )}
                    </div>
                  </td>
                  <td className={tableTdClass}>
                    <span className="font-mono text-xs text-slate-400">
                      {m.confirmed_total} 期
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </TableContainer>
        )}
      </SectionCard>
    </div>
  );
}
