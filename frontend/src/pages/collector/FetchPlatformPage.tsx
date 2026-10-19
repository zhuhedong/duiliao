import { useCallback, useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Alert, AlertDescription } from "../../components/ui/alert";
import { toast } from "../../components/ui/toast";
import { useConfirm } from "../../components/ui/confirm";
import { CardSkeleton } from "../../components/ui/skeleton";
import { ApiError } from "../../lib/api";
import {
  collectorApi,
  type BackfillPreview,
  type CatalogBatchEnableItem,
  type CatalogSuggestions,
  type FetchObservationRow,
  type HostPoolSchedulerStatus,
  type HostPoolStatus,
  type Lottery,
  type SiteDumpLatest,
} from "../../lib/collector";
import {
  LOTTERIES,
  PageWorkspace,
  ReadOnlyNote,
  SectionCard,
  Select,
  StatusPill,
  TableContainer,
  tableTdClass,
  tableThClass,
  tableRowClass,
  useCanWrite,
} from "./shared";
import { ActivityIcon, RefreshIcon, DatabaseIcon, GlobeIcon } from "../../components/icons";

function shortHost(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
}

export function CollectorFetchPlatformPage() {
  const canWrite = useCanWrite();
  const confirm = useConfirm();
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const [pool, setPool] = useState<HostPoolStatus | null>(null);
  const [scheduler, setScheduler] = useState<HostPoolSchedulerStatus | null>(null);
  const [suggestions, setSuggestions] = useState<CatalogSuggestions | null>(null);
  const [dump, setDump] = useState<SiteDumpLatest | null>(null);
  const [dumpMissing, setDumpMissing] = useState(false);
  const [observations, setObservations] = useState<FetchObservationRow[]>([]);

  const [lottery, setLottery] = useState<Lottery>("macau");
  const [period, setPeriod] = useState("");
  const [preview, setPreview] = useState<BackfillPreview | null>(null);
  const [selectedEnable, setSelectedEnable] = useState<Set<string>>(new Set());
  const [batchMsg, setBatchMsg] = useState<string | null>(null);

  const loadCore = useCallback(async (silent = false) => {
    setError(null);
    try {
      const [poolBody, schedBody, suggestBody, obsBody] = await Promise.all([
        collectorApi.hostPool(),
        collectorApi.hostPoolScheduler(),
        collectorApi.catalogSuggestions(),
        collectorApi.fetchObservations({ limit: 20, only_failures: false }),
      ]);
      setPool(poolBody);
      setScheduler(schedBody);
      setSuggestions(suggestBody);
      setObservations(obsBody.items || []);
      if (silent) toast.success("采集平台状态已刷新");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "加载采集平台状态失败");
    }
    try {
      const latest = await collectorApi.latestSiteDump({ max_age_sec: 1800 });
      setDump(latest);
      setDumpMissing(false);
    } catch (err) {
      setDump(null);
      setDumpMissing(true);
      if (!(err instanceof ApiError && err.status === 404)) {
        /* keep soft — dump is optional */
      }
    }
  }, []);

  useEffect(() => {
    void loadCore();
  }, [loadCore]);

  const enableCandidates = useMemo(() => {
    const rows: Array<{ key: string; item: CatalogBatchEnableItem; label: string; reason?: string }> = [];
    for (const sug of suggestions?.suggest_enable || []) {
      const sources = sug.sources || [];
      if (sources.length) {
        for (const src of sources) {
          if (!src.source_id) continue;
          rows.push({
            key: `enable:${src.source_id}`,
            item: { action: "enable_source", source_id: src.source_id },
            label: `${src.source_name || src.source_id}`,
            reason: sug.reason,
          });
        }
      } else if (sug.upstream_id) {
        rows.push({
          key: `enable-up:${sug.upstream_id}`,
          item: { action: "enable_source", upstream_id: String(sug.upstream_id) },
          label: sug.name || `upstream ${sug.upstream_id}`,
          reason: sug.reason,
        });
      }
    }
    return rows;
  }, [suggestions]);

  const toggleEnable = (key: string) => {
    setSelectedEnable((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const runProbe = async (forceRefresh: boolean) => {
    setBusy(forceRefresh ? "refresh" : "probe");
    setError(null);
    try {
      if (forceRefresh) {
        await collectorApi.refreshHostPool();
        toast.success("已重新发现 API 集群");
      } else {
        await collectorApi.probeHostPool(false);
        toast.success("Host 池探测完成");
      }
      await loadCore();
    } catch (err) {
      const msg = err instanceof ApiError ? err.message : "Host 池操作失败";
      setError(msg);
      toast.error("Host 池操作失败", msg);
    } finally {
      setBusy(null);
    }
  };

  const runDump = async () => {
    if (!canWrite) return;
    const ok = await confirm({
      title: "刷新 588080 全页缓存",
      description: "将抓取 588080 全页并刷新 TTL 缓存，确认继续？",
      confirmLabel: "立即刷新",
    });
    if (!ok) return;
    setBusy("dump");
    setError(null);
    try {
      await collectorApi.siteDump588080();
      toast.success("全页 Dump 缓存已刷新");
      await loadCore();
    } catch (err) {
      const msg = err instanceof ApiError ? err.message : "全页 dump 失败";
      setError(msg);
      toast.error("全页 dump 失败", msg);
    } finally {
      setBusy(null);
    }
  };

  const runPreview = async () => {
    setBusy("preview");
    setError(null);
    try {
      const res = await collectorApi.previewBackfill(lottery, period.trim() || undefined);
      setPreview(res);
      toast.info("缺期预览就绪", `检测到 ${res.missing_count ?? 0} 个缺期数据源`);
    } catch (err) {
      const msg = err instanceof ApiError ? err.message : "缺期预览失败";
      setError(msg);
      toast.error("缺期预览失败", msg);
    } finally {
      setBusy(null);
    }
  };

  const runBackfill = async () => {
    if (!canWrite || !preview?.missing_count) return;
    const ok = await confirm({
      title: "提交缺期补采任务",
      description: `将为 ${preview.lottery} 第 ${preview.period} 期补采 ${preview.missing_count} 个源，确认提交？`,
      confirmLabel: "确认提交",
    });
    if (!ok) return;
    setBusy("backfill");
    setError(null);
    try {
      const result = await collectorApi.submitBackfill({
        lottery,
        period: preview.period || undefined,
        concurrency: 8,
      });
      if (result.job?.id) {
        const msg = `已提交补采任务 #${result.job.id}（状态 ${result.job.status}）`;
        setBatchMsg(msg);
        toast.success("补采任务已提交", msg);
      } else {
        const msg = result.note || "无需补采或未提交任务";
        setBatchMsg(msg);
        toast.info(msg);
      }
      setPreview(result);
    } catch (err) {
      const msg = err instanceof ApiError ? err.message : "提交补采失败";
      setError(msg);
      toast.error("提交补采失败", msg);
    } finally {
      setBusy(null);
    }
  };

  const runBatchEnable = async (dryRun: boolean) => {
    if (!canWrite) return;
    const items = enableCandidates.filter((c) => selectedEnable.has(c.key)).map((c) => c.item);
    if (!items.length) {
      setError("请先勾选要启用的源");
      toast.warning("请先勾选要启用的源");
      return;
    }
    if (!dryRun) {
      const ok = await confirm({
        title: "批量启用数据源",
        description: `确认启用已勾选的 ${items.length} 个数据源？`,
        confirmLabel: "确认启用",
      });
      if (!ok) return;
    }
    setBusy(dryRun ? "batch-dry" : "batch");
    setError(null);
    setBatchMsg(null);
    try {
      const result = await collectorApi.catalogBatchEnable({
        items,
        dry_run: dryRun,
        confirm: !dryRun,
      });
      const counts = result.counts || {};
      const msg = dryRun
        ? `干跑：将启用 ${counts.enable ?? counts.create ?? items.length} 项` +
          (counts.rejected ? `，拒绝 ${counts.rejected}` : "")
        : `已应用：启用 ${counts.enable ?? 0}，创建 ${counts.create ?? 0}` +
          (counts.rejected ? `，拒绝 ${counts.rejected}` : "");
      setBatchMsg(msg);
      toast.success(dryRun ? "干跑预览完成" : "批量启用成功", msg);
      if (!dryRun) {
        setSelectedEnable(new Set());
        await loadCore();
      }
    } catch (err) {
      const msg = err instanceof ApiError ? err.message : "批量启用失败";
      setError(msg);
      toast.error("批量启用失败", msg);
    } finally {
      setBusy(null);
    }
  };

  const healthEntries = Object.entries(pool?.health || {});

  return (
    <PageWorkspace
      summary="588080 Host 池、栏目建议、缺期补采与 dump 缓存——员工可探测/启用/补采，普通用户只读。"
      actions={
        <div className="flex items-center gap-2">
          {!canWrite && <ReadOnlyNote />}
          <button
            type="button"
            onClick={() => void loadCore(true)}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium bento-subtle cursor-pointer"
          >
            <RefreshIcon size={14} />
            刷新
          </button>
        </div>
      }
    >
      {error && (
        <Alert
          variant="error"
          className="rounded-2xl border border-rose-400/40 dark:border-rose-400/25 bg-rose-500/10 text-rose-700 dark:text-rose-300"
        >
          <AlertDescription className="text-sm">{error}</AlertDescription>
        </Alert>
      )}
      {batchMsg && (
        <Alert className="rounded-2xl border border-emerald-400/30 bg-emerald-500/10 text-emerald-800 dark:text-emerald-200">
          <AlertDescription className="text-sm">{batchMsg}</AlertDescription>
        </Alert>
      )}

      <SectionCard
        title={
          <div className="flex items-center gap-2">
            <GlobeIcon size={18} className="text-primary" />
            <span>588080 Host 池</span>
          </div>
        }
        subtitle="入口探测 / 健康检查 / 定时调度状态。刷新会重新发现 API 集群；探测只检查池内主机。"
        action={
          canWrite ? (
            <div className="flex items-center gap-2">
              <button
                type="button"
                disabled={!!busy}
                onClick={() => void runProbe(false)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold bento-subtle cursor-pointer disabled:opacity-50"
              >
                {busy === "probe" ? "探测中…" : "立即探测"}
              </button>
              <button
                type="button"
                disabled={!!busy}
                onClick={() => void runProbe(true)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold glow-button border-0 cursor-pointer disabled:opacity-50"
              >
                {busy === "refresh" ? "刷新中…" : "重新发现"}
              </button>
            </div>
          ) : null
        }
      >
        {!pool ? (
          <CardSkeleton lines={3} />
        ) : (
          <div className="space-y-4">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <div className="p-3.5 bento-subtle rounded-2xl">
                <span className="text-2xs font-semibold text-slate-400 block uppercase">状态</span>
                <div className="mt-1">
                  {pool.ok ? (
                    <StatusPill variant="success">可用</StatusPill>
                  ) : (
                    <StatusPill variant="warning">无健康主机</StatusPill>
                  )}
                </div>
              </div>
              <div className="p-3.5 bento-subtle rounded-2xl">
                <span className="text-2xs font-semibold text-slate-400 block uppercase">主机数</span>
                <div className="mt-1 text-lg font-bold">{pool.host_count ?? pool.hosts?.length ?? 0}</div>
              </div>
              <div className="p-3.5 bento-subtle rounded-2xl col-span-2">
                <span className="text-2xs font-semibold text-slate-400 block uppercase">主用</span>
                <div className="mt-1 text-sm font-mono truncate">{pool.primary || "—"}</div>
              </div>
            </div>
            {scheduler && (
              <div className="text-xs text-slate-500 dark:text-slate-400 flex flex-wrap gap-x-4 gap-y-1">
                <span>
                  调度：{scheduler.enabled === false ? "关闭" : "开启"} / 间隔{" "}
                  {Math.round((scheduler.interval_seconds || 0) / 60)} 分钟
                </span>
                <span>上次运行：{scheduler.last_run_at || "—"}</span>
                <span>上次成功：{scheduler.last_success_at || "—"}</span>
                {scheduler.last_error && (
                  <span className="text-rose-500">错误：{scheduler.last_error}</span>
                )}
              </div>
            )}
            {healthEntries.length > 0 && (
              <TableContainer>
                <thead>
                  <tr>
                    <th className={tableThClass}>主机</th>
                    <th className={tableThClass}>健康</th>
                    <th className={tableThClass}>耗时</th>
                    <th className={tableThClass}>连续失败</th>
                    <th className={tableThClass}>上次成功</th>
                  </tr>
                </thead>
                <tbody>
                  {healthEntries.map(([host, h]) => (
                    <tr key={host} className={tableRowClass}>
                      <td className={tableTdClass}>
                        <span className="font-mono text-xs">{shortHost(host)}</span>
                      </td>
                      <td className={tableTdClass}>
                        {h.ok ? (
                          <StatusPill variant="success">OK</StatusPill>
                        ) : (
                          <StatusPill variant="danger">{h.error || "失败"}</StatusPill>
                        )}
                      </td>
                      <td className={tableTdClass}>
                        <span className="font-mono text-xs">
                          {h.elapsed_ms != null ? `${h.elapsed_ms} ms` : "—"}
                        </span>
                      </td>
                      <td className={tableTdClass}>
                        <span className="font-mono text-xs">{h.consecutive_failures ?? 0}</span>
                      </td>
                      <td className={tableTdClass}>
                        <span className="text-xs text-slate-500">{h.last_ok_at || "—"}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </TableContainer>
            )}
            {pool.updated_at && (
              <p className="text-2xs text-slate-400">池更新于 {pool.updated_at}</p>
            )}
          </div>
        )}
      </SectionCard>

      <SectionCard
        title={
          <div className="flex items-center gap-2">
            <DatabaseIcon size={18} className="text-primary" />
            <span>栏目建议 / 批量启用</span>
          </div>
        }
        subtitle="基于最近巡检：新栏、可重新启用、建议停用。批量启用仅支持 enable_source（需确认）；新建源仍需已验收 parser。"
        action={
          <Link
            to="/collector/monitor"
            className="text-xs font-semibold text-primary hover:underline"
          >
            去服务监控巡检 →
          </Link>
        }
      >
        {!suggestions ? (
          <CardSkeleton lines={3} />
        ) : (
          <div className="space-y-4">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              {(
                [
                  ["新栏", suggestions.counts?.new ?? 0],
                  ["可启用", suggestions.counts?.enable ?? 0],
                  ["建议停用", suggestions.counts?.disable ?? 0],
                  ["改名", suggestions.counts?.renamed ?? 0],
                ] as const
              ).map(([label, n]) => (
                <div key={label} className="p-3.5 bento-subtle rounded-2xl">
                  <span className="text-2xs font-semibold text-slate-400 block uppercase">
                    {label}
                  </span>
                  <div className="mt-1 text-lg font-bold">{n}</div>
                </div>
              ))}
            </div>
            {enableCandidates.length > 0 ? (
              <div className="space-y-2">
                <p className="text-xs text-slate-500">勾选后干跑或确认启用（不会盲开未知 parser）：</p>
                <div className="max-h-56 overflow-y-auto space-y-1.5 pr-1">
                  {enableCandidates.map((c) => (
                    <label
                      key={c.key}
                      className="flex items-start gap-2 p-2.5 rounded-xl bento-subtle cursor-pointer"
                    >
                      <input
                        type="checkbox"
                        className="mt-1"
                        checked={selectedEnable.has(c.key)}
                        onChange={() => toggleEnable(c.key)}
                        disabled={!canWrite}
                      />
                      <span className="min-w-0">
                        <span className="text-sm font-medium text-slate-800 dark:text-slate-100 block truncate">
                          {c.label}
                        </span>
                        {c.reason && (
                          <span className="text-2xs text-slate-400 block">{c.reason}</span>
                        )}
                      </span>
                    </label>
                  ))}
                </div>
                {canWrite && (
                  <div className="flex gap-2">
                    <button
                      type="button"
                      disabled={!!busy || selectedEnable.size === 0}
                      onClick={() => void runBatchEnable(true)}
                      className="px-3 py-1.5 rounded-xl text-xs font-semibold bento-subtle disabled:opacity-50 cursor-pointer"
                    >
                      {busy === "batch-dry" ? "干跑中…" : "干跑预览"}
                    </button>
                    <button
                      type="button"
                      disabled={!!busy || selectedEnable.size === 0}
                      onClick={() => void runBatchEnable(false)}
                      className="px-3 py-1.5 rounded-xl text-xs font-semibold glow-button border-0 disabled:opacity-50 cursor-pointer"
                    >
                      {busy === "batch" ? "启用中…" : "确认启用"}
                    </button>
                  </div>
                )}
              </div>
            ) : (
              <p className="text-sm text-slate-400 py-4 text-center">暂无可重新启用的建议。</p>
            )}
            {(suggestions.suggest_new?.length ?? 0) > 0 && (
              <p className="text-xs text-amber-600 dark:text-amber-300">
                另有 {suggestions.suggest_new.length} 个上游新栏待人工配置 parser 后接入（本页不自动创建）。
              </p>
            )}
            {(suggestions.suggest_disable?.length ?? 0) > 0 && (
              <p className="text-xs text-slate-500">
                {suggestions.suggest_disable.length} 个源上游已消失，请到{" "}
                <Link to="/collector/monitor" className="text-primary underline">
                  服务监控
                </Link>{" "}
                执行「停用已下线源」。
              </p>
            )}
          </div>
        )}
      </SectionCard>

      <SectionCard
        title={
          <div className="flex items-center gap-2">
            <ActivityIcon size={18} className="text-primary" />
            <span>缺期补采</span>
          </div>
        }
        subtitle="预览缺少预测的启用源，员工可提交异步 collect_job 回填。"
      >
        <div className="flex flex-wrap items-end gap-3 mb-4">
          <div>
            <label className="text-2xs font-semibold text-slate-400 uppercase block mb-1">
              彩种
            </label>
            <Select
              value={lottery}
              onChange={(v) => setLottery(v as Lottery)}
              options={LOTTERIES}
            />
          </div>
          <div>
            <label className="text-2xs font-semibold text-slate-400 uppercase block mb-1">
              期号（空=最新开奖期）
            </label>
            <input
              value={period}
              onChange={(e) => setPeriod(e.target.value)}
              placeholder="例如 2026286"
              className="px-3 py-2 rounded-xl text-sm bento-subtle border-0 outline-none w-40 font-mono"
            />
          </div>
          <button
            type="button"
            disabled={!!busy}
            onClick={() => void runPreview()}
            className="px-4 py-2 rounded-xl text-xs font-semibold bento-subtle cursor-pointer disabled:opacity-50"
          >
            {busy === "preview" ? "预览中…" : "预览缺期"}
          </button>
          {canWrite && (
            <button
              type="button"
              disabled={!!busy || !(preview?.missing_count)}
              title={!preview ? "请先预览缺期" : !preview.missing_count ? "当前无缺期，无需补采" : undefined}
              onClick={() => void runBackfill()}
              className="px-4 py-2 rounded-xl text-xs font-semibold glow-button border-0 cursor-pointer"
            >
              {busy === "backfill" ? "提交中…" : "提交补采"}
            </button>
          )}
        </div>
        {preview && (
          <div className="space-y-2">
            <p className="text-sm">
              {preview.period ? (
                <>
                  {preview.lottery} 第 <span className="font-mono">{preview.period}</span> 期：缺{" "}
                  <strong>{preview.missing_count}</strong> 个源
                </>
              ) : (
                <>无开奖期可对账（{preview.note || "no_draws"}）</>
              )}
            </p>
            {preview.missing_sources?.length > 0 && (
              <TableContainer>
                <thead>
                  <tr>
                    <th className={tableThClass}>源</th>
                    <th className={tableThClass}>玩法</th>
                    <th className={tableThClass}>站点族</th>
                  </tr>
                </thead>
                <tbody>
                  {preview.missing_sources.map((s) => (
                    <tr key={s.source_id} className={tableRowClass}>
                      <td className={tableTdClass}>
                        <div className="font-medium">{s.source_name}</div>
                        <div className="text-2xs font-mono text-slate-400">{s.source_id}</div>
                      </td>
                      <td className={tableTdClass}>
                        <span className="text-xs">{s.play_type || "—"}</span>
                      </td>
                      <td className={tableTdClass}>
                        <span className="text-xs">{s.site_family || "—"}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </TableContainer>
            )}
          </div>
        )}
      </SectionCard>

      <SectionCard
        title="全页 Dump 缓存"
        subtitle="AI / APP 优先读 TTL 缓存，避免每次外连。员工可手动刷新。"
        action={
          canWrite ? (
            <button
              type="button"
              disabled={!!busy}
              onClick={() => void runDump()}
              className="px-3 py-1.5 rounded-xl text-xs font-semibold glow-button border-0 cursor-pointer disabled:opacity-50"
            >
              {busy === "dump" ? "抓取中…" : "刷新 dump"}
            </button>
          ) : null
        }
      >
        {dumpMissing && !dump ? (
          <p className="text-sm text-slate-400 py-4">
            暂无新鲜缓存（默认 TTL 30 分钟）。员工点击「刷新 dump」生成。
          </p>
        ) : dump ? (
          <div className="space-y-2 text-sm">
            <div>
              站点：<strong>{dump.site_title || "—"}</strong>
            </div>
            <div className="text-xs text-slate-500 font-mono break-all">
              cache: {JSON.stringify(dump.cache || {})}
            </div>
            <div className="text-xs text-slate-500 font-mono break-all">
              summary: {JSON.stringify(dump.summary || {})}
            </div>
          </div>
        ) : (
          <CardSkeleton lines={2} />
        )}
      </SectionCard>

      <SectionCard title="最近抓取观测" subtitle="content_hash / 失败原因，便于排查突变与连续失败。">
        {observations.length === 0 ? (
          <p className="text-sm text-slate-400 py-4 text-center">暂无观测记录。</p>
        ) : (
          <TableContainer>
            <thead>
              <tr>
                <th className={tableThClass}>源</th>
                <th className={tableThClass}>期号</th>
                <th className={tableThClass}>结果</th>
                <th className={tableThClass}>hash</th>
                <th className={tableThClass}>时间</th>
              </tr>
            </thead>
            <tbody>
              {observations.map((row, idx) => (
                <tr key={row.id ?? idx} className={tableRowClass}>
                  <td className={tableTdClass}>
                    <span className="font-mono text-xs">{row.source_id}</span>
                  </td>
                  <td className={tableTdClass}>
                    <span className="font-mono text-xs">{row.period || "—"}</span>
                  </td>
                  <td className={tableTdClass}>
                    {row.ok ? (
                      <StatusPill variant="success">OK</StatusPill>
                    ) : (
                      <StatusPill variant="danger">{row.error_code || "fail"}</StatusPill>
                    )}
                  </td>
                  <td className={tableTdClass}>
                    <span className="font-mono text-2xs truncate max-w-[8rem] inline-block">
                      {row.content_hash || "—"}
                    </span>
                  </td>
                  <td className={tableTdClass}>
                    <span className="text-2xs text-slate-400">{row.created_at || "—"}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </TableContainer>
        )}
      </SectionCard>
    </PageWorkspace>
  );
}
