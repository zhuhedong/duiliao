import { Fragment, useCallback, useEffect, useState } from "react";
import { Spinner } from "@appica/ui-react/spinner";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { ApiError } from "../../lib/api";
import {
  collectorApi,
  LOTTERY_LABEL,
  type DrawRow,
  type DrawSchedulerStatus,
  type DrawSyncResult,
  type JudgeResult,
  type Lottery,
} from "../../lib/collector";
import {
  BOSE_COLORS,
  WUXING_COLORS,
  ensureDrawDetails,
  getBose,
  getXiao,
} from "../../lib/lotteryAttr";
import {
  LOTTERIES,
  PageHeader,
  ReadOnlyNote,
  ResultJson,
  Select,
  Stats,
  TextInput,
  useCanWrite,
  SectionCard,
  StatusPill,
  TableContainer,
  tableThClass,
  tableTdClass,
  tableRowClass,
} from "./shared";
import {
  ClockIcon,
  PlayIcon,
  RefreshIcon,
  CheckBadgeIcon,
  ChevronDownIcon,
  SettingsIcon,
  ActivityIcon,
} from "../../components/icons";

export function CollectorDrawsPage() {
  const canWrite = useCanWrite();
  const [lottery, setLottery] = useState<Lottery>("macau");
  const [period, setPeriod] = useState("");
  const [drawsText, setDrawsText] = useState("");
  const [busy, setBusy] = useState<"sync" | "judge" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [syncRes, setSyncRes] = useState<DrawSyncResult | null>(null);
  const [judgeRes, setJudgeRes] = useState<JudgeResult | null>(null);

  // Auto-updater state
  const [scheduler, setScheduler] = useState<DrawSchedulerStatus | null>(null);
  const [schedulerLoading, setSchedulerLoading] = useState(false);
  const [showLogs, setShowLogs] = useState(false);
  const [showConfig, setShowConfig] = useState(false);
  const [cfgStartTime, setCfgStartTime] = useState("21:33:30");
  const [cfgEndTime, setCfgEndTime] = useState("21:36:00");
  const [cfgInterval, setCfgInterval] = useState(30);

  // Draws list
  const [draws, setDraws] = useState<DrawRow[]>([]);
  const [total, setTotal] = useState(0);
  const [loadingList, setLoadingList] = useState(true);
  const [offset, setOffset] = useState(0);
  const [expandedPeriod, setExpandedPeriod] = useState<string | null>(null);
  const limit = 100;

  const loadScheduler = useCallback(async () => {
    try {
      const res = await collectorApi.getDrawSchedulerStatus();
      setScheduler(res);
    } catch {
      // ignore in read-only / unauthenticated
    }
  }, []);

  const loadList = useCallback(async () => {
    setLoadingList(true);
    try {
      const res = await collectorApi.listDraws(lottery, limit, offset);
      setDraws(res.items);
      setTotal(res.total);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "加载开奖列表失败");
    } finally {
      setLoadingList(false);
    }
  }, [lottery, limit, offset]);

  useEffect(() => {
    void loadList();
    void loadScheduler();
    const timer = setInterval(() => {
      void loadScheduler();
    }, 10000);
    return () => clearInterval(timer);
  }, [loadList, loadScheduler]);

  useEffect(() => {
    setOffset(0);
  }, [lottery]);

  useEffect(() => {
    if (scheduler) {
      setCfgStartTime(scheduler.start_time || "21:33:30");
      setCfgEndTime(scheduler.end_time || "21:36:00");
      setCfgInterval(scheduler.interval_seconds || 30);
    }
  }, [scheduler?.start_time, scheduler?.end_time, scheduler?.interval_seconds]);

  const toggleScheduler = async () => {
    if (!scheduler) return;
    setSchedulerLoading(true);
    try {
      const res = await collectorApi.updateDrawScheduler({ enabled: !scheduler.enabled });
      setScheduler(res);
      setSuccessMsg(res.enabled ? "后台自动开奖更新已开启！" : "后台自动开奖更新已暂停。");
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "更新自动调度器状态失败");
    } finally {
      setSchedulerLoading(false);
    }
  };

  const saveSchedulerConfig = async (override?: { start?: string; end?: string; interval?: number }) => {
    setSchedulerLoading(true);
    setError(null);
    setSuccessMsg(null);
    try {
      const res = await collectorApi.updateDrawScheduler({
        start_time: override?.start ?? cfgStartTime,
        end_time: override?.end ?? cfgEndTime,
        interval_seconds: override?.interval ?? cfgInterval,
      });
      setScheduler(res);
      setSuccessMsg("开奖时间窗口与轮询参数已更新成功！");
      setShowConfig(false);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "保存调度参数失败");
    } finally {
      setSchedulerLoading(false);
    }
  };

  const resetToDefaultConfig = async () => {
    setCfgStartTime("21:33:30");
    setCfgEndTime("21:36:00");
    setCfgInterval(30);
    await saveSchedulerConfig({ start: "21:33:30", end: "21:36:00", interval: 30 });
  };

  const triggerSchedulerNow = async () => {
    setSchedulerLoading(true);
    setSuccessMsg(null);
    try {
      const res = await collectorApi.updateDrawScheduler({}, true);
      setScheduler(res);
      setSuccessMsg("已向后台发送立即同步开奖信号！稍后将自动刷新。");
      setTimeout(() => {
        void loadScheduler();
        void loadList();
      }, 2500);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "立即同步失败");
    } finally {
      setSchedulerLoading(false);
    }
  };

  const sync = async () => {
    setBusy("sync");
    setError(null);
    setSyncRes(null);
    setSuccessMsg(null);
    try {
      let parsedDraws: unknown[] | undefined;
      if (drawsText.trim()) {
        const parsed = JSON.parse(drawsText);
        parsedDraws = Array.isArray(parsed) ? parsed : parsed?.draws ?? [parsed];
      }
      const res = await collectorApi.syncDraws({ lottery, period: period.trim() || undefined, draws: parsedDraws });
      setSyncRes(res);
      setSuccessMsg(`开奖同步成功：新增 ${res.inserted} 条，更新 ${res.updated} 条，自动重算对奖 ${res.judged} 条！`);
      await loadList();
    } catch (err) {
      if (err instanceof SyntaxError) setError("开奖 JSON 解析失败，请检查格式");
      else setError(err instanceof ApiError ? err.message : "同步失败");
    } finally {
      setBusy(null);
    }
  };

  const judge = async () => {
    setBusy("judge");
    setError(null);
    setJudgeRes(null);
    setSuccessMsg(null);
    try {
      const res = await collectorApi.judge({ lottery, period: period.trim() });
      setJudgeRes(res);
      setSuccessMsg(`对奖计算完成：对奖 ${res.judged} 条，命中 ${res.hits} 条，自称不符 ${res.dirty_claimed} 条！`);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "对奖失败");
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="官方开奖与自动更新"
        desc="支持后台定时自动轮询开奖并自动重算对奖，或手动导入官方开奖号码。"
        right={canWrite ? null : <ReadOnlyNote />}
      />

      {error && (
        <Alert variant="error" className="rounded-2xl border border-rose-200 dark:border-rose-900 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200">
          <AlertDescription className="text-sm">{error}</AlertDescription>
        </Alert>
      )}

      {successMsg && (
        <div className="p-4 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-600 dark:text-emerald-400 text-sm flex items-center justify-between animate-fadeIn">
          <div className="flex items-center gap-2">
            <CheckBadgeIcon size={18} />
            <span className="font-medium">{successMsg}</span>
          </div>
          <button
            type="button"
            onClick={() => setSuccessMsg(null)}
            className="text-xs font-semibold hover:underline cursor-pointer"
          >
            关闭
          </button>
        </div>
      )}

      {/* 开奖自动更新后台调度器卡片 */}
      <SectionCard
        title={
          <div className="flex items-center gap-2.5">
            <div className="p-2 rounded-xl bg-primary/10 text-primary">
              <ClockIcon size={20} />
            </div>
            <span>后台开奖自动更新服务 (Auto-Updater)</span>
            {!scheduler?.enabled ? (
              <StatusPill variant="neutral">已暂停</StatusPill>
            ) : scheduler.in_window ? (
              <StatusPill variant="success">窗口期自动同步中</StatusPill>
            ) : (
              <StatusPill variant="info">定时待机中</StatusPill>
            )}
          </div>
        }
        subtitle={
          <span>
            定时规则：每日北京时间 <strong className="text-slate-800 dark:text-slate-200">{scheduler?.start_time || "21:33:30"}</strong> 开始同步，每 <strong className="text-slate-800 dark:text-slate-200">{scheduler?.interval_seconds || 30}</strong> 秒自动同步一次，至 <strong className="text-slate-800 dark:text-slate-200">{scheduler?.end_time || "21:36:00"}</strong> 结束。发现新开奖自动入库并触发全量对奖。
          </span>
        }
        action={
          canWrite && (
            <div className="flex items-center gap-2 flex-wrap">
              <button
                type="button"
                onClick={triggerSchedulerNow}
                disabled={schedulerLoading}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-semibold bg-emerald-600 hover:bg-emerald-500 text-white shadow-xs transition-all disabled:opacity-50 cursor-pointer"
                title="不论是否在窗口期，立刻强制向官方接口发起一次检查"
              >
                <PlayIcon size={13} />
                <span>立即检查开奖</span>
              </button>
              <button
                type="button"
                onClick={() => setShowConfig(!showConfig)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
              >
                <SettingsIcon size={13} />
                <span>{showConfig ? "收起设置" : "设置窗口"}</span>
              </button>
              <button
                type="button"
                onClick={() => setShowLogs(!showLogs)}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
              >
                <ActivityIcon size={13} />
                <span>{showLogs ? "收起日志" : "查看日志"}</span>
              </button>
              <button
                type="button"
                onClick={toggleScheduler}
                disabled={schedulerLoading}
                className={`px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors cursor-pointer ${
                  scheduler?.enabled
                    ? "border-amber-200 text-amber-700 dark:border-amber-800 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-950/30"
                    : "border-emerald-200 text-emerald-700 dark:border-emerald-800 dark:text-emerald-400 hover:bg-emerald-50 dark:hover:bg-emerald-950/30"
                }`}
              >
                {schedulerLoading ? "处理中..." : scheduler?.enabled ? "暂停自动更新" : "启动自动更新"}
              </button>
            </div>
          )
        }
      >
        <div className="space-y-4">
          {/* 状态描述提示条 */}
          <div className="p-3.5 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-200/80 dark:border-slate-800/80 flex items-center justify-between text-xs text-slate-600 dark:text-slate-300">
            <div>
              {!scheduler?.enabled ? (
                <span>⚠️ 自动更新已手动暂停。后台不会在开奖窗口期拉取新开奖，您可随时点击「启动自动更新」恢复。</span>
              ) : scheduler.in_window ? (
                <span>
                  🟢 <strong>当前处于开奖窗口期！</strong> 系统正以每 <strong>{scheduler.interval_seconds} 秒</strong> 一次的频率自动检测开奖（窗口：{scheduler.start_time} ~ {scheduler.end_time}），捕获官方新球号即刻入库比对。
                </span>
              ) : (
                <span>
                  🕒 <strong>当前不在开奖时间窗口，处于待命状态。</strong> 下次开奖自动同步将于 <strong>{scheduler?.next_run_at || scheduler?.start_time}</strong> 启动。期间随时可点击「立即检查开奖」单次同步。
                </span>
              )}
            </div>
            <span className="text-slate-400 font-mono text-2xs shrink-0 ml-4 hidden sm:inline">
              北京时间: {scheduler?.current_time?.slice(11) || "—"}
            </span>
          </div>

          {/* 调度器状态指标卡片网格 */}
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
            <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
              <span className="text-2xs font-semibold text-slate-400 block uppercase">运行状态</span>
              <div className="text-sm font-bold mt-1 text-slate-900 dark:text-white">
                {!scheduler?.enabled ? (
                  <span className="text-slate-400">已暂停</span>
                ) : scheduler.in_window ? (
                  <span className="text-emerald-500">🟢 窗口期同步</span>
                ) : (
                  <span className="text-cyan-500">🕒 待命待机</span>
                )}
              </div>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
              <span className="text-2xs font-semibold text-slate-400 block uppercase">每日窗口 (北京时间)</span>
              <span className="text-sm font-bold mt-1 text-slate-900 dark:text-white block">
                {scheduler ? `${scheduler.start_time} ~ ${scheduler.end_time}` : "21:33:30 ~ 21:36:00"}
              </span>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
              <span className="text-2xs font-semibold text-slate-400 block uppercase">窗口期轮询</span>
              <span className="text-sm font-bold mt-1 text-slate-900 dark:text-white block">
                {scheduler ? `每 ${scheduler.interval_seconds} 秒` : "每 30 秒"}
              </span>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
              <span className="text-2xs font-semibold text-slate-400 block uppercase">下次预计同步</span>
              <span className="text-sm font-bold mt-1 text-slate-900 dark:text-white block truncate">
                {scheduler?.in_window ? "窗口内持续轮询" : scheduler?.next_run_at || "—"}
              </span>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
              <span className="text-2xs font-semibold text-slate-400 block uppercase">上次检查时间</span>
              <span className="text-sm font-bold mt-1 text-slate-900 dark:text-white block truncate">
                {scheduler?.last_run_at || "尚未运行"}
              </span>
            </div>

            <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/50 border border-slate-200/80 dark:border-slate-800/80">
              <span className="text-2xs font-semibold text-slate-400 block uppercase">累计成功同步</span>
              <span className="text-sm font-bold mt-1 text-primary block">
                {scheduler?.sync_count ?? 0} 次
              </span>
            </div>
          </div>

          {/* 窗口参数设置微调面板 */}
          {showConfig && canWrite && (
            <div className="p-4 rounded-2xl bg-slate-50 dark:bg-slate-900/70 border border-slate-200/80 dark:border-slate-800/80 space-y-3.5 animate-fadeIn">
              <div className="flex justify-between items-center flex-wrap gap-2">
                <span className="text-xs font-bold text-slate-800 dark:text-slate-200">
                  ⚙️ 开奖同步时间窗口与频率配置 (北京时间 UTC+8)
                </span>
                <button
                  type="button"
                  onClick={() => void resetToDefaultConfig()}
                  className="text-xs text-primary hover:underline cursor-pointer"
                >
                  恢复默认 (21:33:30 ~ 21:36:00, 30秒)
                </button>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
                    每日启动时间 (HH:MM:SS)
                  </label>
                  <TextInput
                    value={cfgStartTime}
                    onChange={setCfgStartTime}
                    placeholder="21:33:30"
                    className="w-full"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
                    每日结束时间 (HH:MM:SS)
                  </label>
                  <TextInput
                    value={cfgEndTime}
                    onChange={setCfgEndTime}
                    placeholder="21:36:00"
                    className="w-full"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-600 dark:text-slate-400 mb-1">
                    窗口期轮询间隔 (秒)
                  </label>
                  <TextInput
                    value={String(cfgInterval)}
                    onChange={(v) => setCfgInterval(Math.max(5, parseInt(v) || 30))}
                    placeholder="30"
                    className="w-full"
                  />
                </div>
              </div>

              <div className="flex justify-end gap-2 pt-1">
                <button
                  type="button"
                  onClick={() => setShowConfig(false)}
                  className="px-3.5 py-1.5 rounded-xl text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
                >
                  取消
                </button>
                <button
                  type="button"
                  disabled={schedulerLoading}
                  onClick={() => void saveSchedulerConfig()}
                  className="px-4 py-1.5 rounded-xl text-xs font-semibold bg-primary hover:bg-primary/90 text-white shadow-xs transition-all disabled:opacity-50 cursor-pointer"
                >
                  {schedulerLoading ? "保存中..." : "保存窗口配置"}
                </button>
              </div>
            </div>
          )}

          {/* 展开最近轮询日志 */}
          {showLogs && (
            <div className="p-4 rounded-2xl bg-slate-50 dark:bg-slate-900/70 border border-slate-200/80 dark:border-slate-800/80 space-y-2.5 animate-fadeIn">
              <div className="text-xs font-bold text-slate-800 dark:text-slate-200">
                最近后台自动同步日志:
              </div>
              {(scheduler?.recent_logs ?? []).length === 0 ? (
                <p className="text-xs text-slate-400">暂无同步记录。</p>
              ) : (
                <div className="max-h-48 overflow-y-auto space-y-1.5 pr-1 font-mono text-xs">
                  {scheduler?.recent_logs.map((log, idx) => (
                    <div
                      key={idx}
                      className="flex items-center gap-2.5 p-2 rounded-lg bg-white dark:bg-[#0c1220] border border-slate-200/60 dark:border-slate-800/60"
                    >
                      <span className="text-slate-400 text-2xs">{log.timestamp}</span>
                      <StatusPill variant="neutral" dot={false}>
                        {LOTTERY_LABEL[log.lottery] || log.lottery}
                      </StatusPill>
                      <StatusPill variant={log.status === "success" ? "success" : "danger"} dot={false}>
                        {log.status === "success" ? "成功" : "失败"}
                      </StatusPill>
                      <span className="flex-1 truncate text-slate-700 dark:text-slate-300">{log.message}</span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>
      </SectionCard>

      {/* 手动导入与对奖 */}
      <SectionCard
        title="手动导入或重算开奖"
        subtitle="从官方外部数据源拉取特定期号开奖，或手动录入 JSON 批量补全并执行全量对奖"
      >
        <div className="space-y-4">
          <div className="flex items-center gap-3 flex-wrap">
            <Select
              value={lottery}
              onChange={(v) => setLottery(v as Lottery)}
              options={LOTTERIES}
              className="min-w-[120px]"
            />
            <TextInput
              value={period}
              onChange={setPeriod}
              placeholder="期号（如 248，留空则拉取最新）"
              className="flex-1 min-w-[200px]"
            />
            <button
              type="button"
              onClick={sync}
              disabled={!canWrite || busy != null}
              className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold bg-primary hover:bg-primary/90 text-white shadow-xs transition-all disabled:opacity-50 cursor-pointer"
            >
              {busy === "sync" ? "同步中…" : "从外部接口拉取同步"}
            </button>
            <button
              type="button"
              onClick={judge}
              disabled={!canWrite || busy != null || !period.trim()}
              className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 shadow-xs transition-all disabled:opacity-50 cursor-pointer"
            >
              {busy === "judge" ? "计算中…" : "手动触发对奖"}
            </button>
          </div>

          <details className="text-xs text-slate-500">
            <summary className="cursor-pointer hover:text-primary font-medium select-none">
              ▶ 高级选项：直接粘贴官方开奖 JSON 数组手动录入
            </summary>
            <div className="mt-2 space-y-2">
              <textarea
                value={drawsText}
                onChange={(e) => setDrawsText(e.target.value)}
                placeholder='[{"period":"248","draw_date":"2026-04-18","numbers":["01","02","03","04","05","06"],"tema":"07"}]'
                rows={4}
                className="w-full font-mono text-xs p-3 rounded-xl border border-slate-200 dark:border-slate-800 bg-slate-950 text-emerald-400 focus:outline-none focus:ring-2 focus:ring-primary/20 shadow-inner"
              />
            </div>
          </details>

          {syncRes && (
            <div className="pt-2 border-t border-slate-100 dark:border-slate-800/80 space-y-2">
              <Stats
                items={[
                  { label: "新增入库", value: syncRes.inserted },
                  { label: "更新已有", value: syncRes.updated },
                  { label: "自动对奖", value: syncRes.judged },
                ]}
              />
              <ResultJson data={syncRes} />
            </div>
          )}

          {judgeRes && (
            <div className="pt-2 border-t border-slate-100 dark:border-slate-800/80 space-y-2">
              <Stats
                items={[
                  { label: "核验对奖", value: judgeRes.judged },
                  { label: "真实命中", value: judgeRes.hits },
                  { label: "虚假声称不符", value: judgeRes.dirty_claimed },
                ]}
              />
              <ResultJson data={judgeRes} />
            </div>
          )}
        </div>
      </SectionCard>

      {/* 历史开奖列表与全景号码分析表格 */}
      <SectionCard
        title={
          <div className="flex items-center gap-3">
            <span>{LOTTERY_LABEL[lottery]}历史开奖记录</span>
            <span className="text-xs px-2.5 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 font-semibold border border-slate-200 dark:border-slate-700">
              共 {total} 期
            </span>
          </div>
        }
        action={
          <button
            type="button"
            onClick={loadList}
            disabled={loadingList}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
          >
            <RefreshIcon size={14} className={loadingList ? "animate-spin" : ""} />
            <span>刷新列表</span>
          </button>
        }
      >
        {loadingList ? (
          <div className="p-12 flex justify-center">
            <Spinner aria-label="加载中" />
          </div>
        ) : draws.length === 0 ? (
          <div className="py-12 text-center text-sm text-slate-400">
            该彩种暂无开奖记录。
          </div>
        ) : (
          <div>
            <TableContainer>
              <thead>
                <tr>
                  <th className={tableThClass}>期号</th>
                  <th className={tableThClass}>开奖日期</th>
                  <th className={tableThClass}>落球正码 (z1–z6·带生肖/五行)</th>
                  <th className={tableThClass}>特码</th>
                  <th className={tableThClass}>连肖形态</th>
                  <th className={tableThClass}>特码形态属性</th>
                  <th className={tableThClass}>七球总分 / 形态</th>
                  <th className={tableThClass}>来源</th>
                  <th className={`${tableThClass} text-center`}>操作</th>
                </tr>
              </thead>
              <tbody>
                {draws.map((d) => {
                  const { ballsDetail, temaDetail, summary } = ensureDrawDetails(d);
                  const isExpanded = expandedPeriod === d.period;
                  const all7 = [...ballsDetail, temaDetail];

                  return (
                    <Fragment key={d.period}>
                      <tr className={`${tableRowClass} ${isExpanded ? "bg-primary/5 dark:bg-primary/10" : ""}`}>
                        <td className={tableTdClass}>
                          <span className="font-mono font-bold text-slate-900 dark:text-white">
                            第 {d.period} 期
                          </span>
                        </td>
                        <td className={tableTdClass}>
                          <span className="text-xs text-slate-500 dark:text-slate-400 font-mono">
                            {d.draw_date ?? "—"}
                          </span>
                        </td>
                        <td className={tableTdClass}>
                          <div className="flex items-center gap-2 flex-wrap">
                            {ballsDetail.map((b, i) => (
                              <DrawBallItem
                                key={i}
                                num={b.num}
                                xiao={b.xiao}
                                wuxing={b.wuxing}
                                bose={b.bose}
                                isLianxiao={b.is_lianxiao}
                                lianxiaoCount={b.lianxiao_count}
                                isAdjacent={b.is_adjacent_lianxiao}
                              />
                            ))}
                          </div>
                        </td>
                        <td className={tableTdClass}>
                          <DrawBallItem
                            num={temaDetail.num}
                            xiao={temaDetail.xiao}
                            wuxing={temaDetail.wuxing}
                            bose={temaDetail.bose}
                            isTema={true}
                            isLianxiao={temaDetail.is_lianxiao}
                            lianxiaoCount={temaDetail.lianxiao_count}
                            isAdjacent={temaDetail.is_adjacent_lianxiao}
                          />
                        </td>
                        <td className={tableTdClass}>
                          {summary.has_lianxiao ? (
                            <div className="flex flex-col gap-1 items-start">
                              <span className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-purple-500/10 text-purple-600 dark:text-purple-400 border border-purple-500/20">
                                <span>🔗 连肖:</span>
                                <span>{summary.lianxiao_text}</span>
                              </span>
                              {summary.has_adjacent_lianxiao && (
                                <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-2xs font-semibold bg-pink-500/10 text-pink-600 dark:text-pink-400 border border-pink-500/20">
                                  ⚡ 顺位紧邻
                                </span>
                              )}
                            </div>
                          ) : (
                            <span className="text-xs text-slate-400 px-2 py-0.5 rounded-md bg-slate-100 dark:bg-slate-800">
                              7肖各异
                            </span>
                          )}
                        </td>
                        <td className={tableTdClass}>
                          <div className="flex items-center gap-1.5 flex-wrap max-w-xs">
                            <span className="text-xs font-semibold px-2 py-0.5 rounded-md bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300">
                              {temaDetail.xiao} · {temaDetail.jiaye}
                            </span>
                            <span
                              className="text-xs font-bold px-2 py-0.5 rounded-md text-white shadow-2xs"
                              style={{ backgroundColor: BOSE_COLORS[temaDetail.bose]?.bg || "#ef4444" }}
                            >
                              {temaDetail.bose}波
                            </span>
                            {temaDetail.wuxing && (
                              <span
                                className="text-xs font-semibold px-2 py-0.5 rounded-md bg-slate-100 dark:bg-slate-800"
                                style={{ color: WUXING_COLORS[temaDetail.wuxing] }}
                              >
                                {temaDetail.wuxing}
                              </span>
                            )}
                            <span className="text-xs px-2 py-0.5 rounded-md bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400">
                              {temaDetail.size} · {temaDetail.odd}
                            </span>
                            <span className="text-xs px-2 py-0.5 rounded-md bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400">
                              合{temaDetail.sum}
                            </span>
                          </div>
                        </td>
                        <td className={tableTdClass}>
                          <div>
                            <div className="text-xs font-bold text-slate-900 dark:text-white">
                              总数: {summary.sum7}
                            </div>
                            <div className="flex items-center gap-1 mt-0.5 text-2xs text-slate-400">
                              <span>{summary.sum7_size}</span>
                              <span>•</span>
                              <span>{summary.sum7_odd}</span>
                            </div>
                          </div>
                        </td>
                        <td className={`${tableTdClass} text-xs text-slate-400 font-mono`}>
                          {d.source || "—"}
                        </td>
                        <td className={`${tableTdClass} text-center`}>
                          <button
                            type="button"
                            onClick={() => setExpandedPeriod(isExpanded ? null : d.period)}
                            className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-medium text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors cursor-pointer"
                          >
                            <span>{isExpanded ? "收起" : "属性明细"}</span>
                            <ChevronDownIcon size={13} className={`transition-transform duration-200 ${isExpanded ? "rotate-180" : ""}`} />
                          </button>
                        </td>
                      </tr>

                      {/* 展开的当期号码完整属性全景卡片 */}
                      {isExpanded && (
                        <tr className="bg-slate-50/70 dark:bg-slate-900/40">
                          <td colSpan={9} className="p-4 sm:p-6 border-b border-slate-200/80 dark:border-slate-800/80">
                            <div className="space-y-4">
                              <div className="flex justify-between items-center flex-wrap gap-2">
                                <h4 className="text-xs font-bold text-slate-900 dark:text-white flex items-center gap-2">
                                  <span>📊 第 {d.period} 期 开奖号码全量属性矩阵分析 ({d.draw_date || "—"})</span>
                                </h4>
                                <div className="flex gap-2 flex-wrap">
                                  {summary.has_lianxiao ? (
                                    <span className="px-2.5 py-0.5 rounded-full text-xs font-bold bg-purple-500/10 text-purple-600 dark:text-purple-400 border border-purple-500/20">
                                      🔗 连肖形态: {summary.lianxiao_text}
                                    </span>
                                  ) : (
                                    <span className="px-2.5 py-0.5 rounded-full text-xs text-slate-500 bg-slate-200/60 dark:bg-slate-800">
                                      7肖各异
                                    </span>
                                  )}
                                  <span className="px-2.5 py-0.5 rounded-full text-xs font-medium bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300">
                                    特码: {temaDetail.num} ({temaDetail.bose}波 · {temaDetail.xiao} · {temaDetail.wuxing || "无五行"})
                                  </span>
                                  <span className="px-2.5 py-0.5 rounded-full text-xs font-medium bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300">
                                    七球总数: {summary.sum7} ({summary.sum7_size} · {summary.sum7_odd})
                                  </span>
                                </div>
                              </div>

                              {/* 7球详细属性对照表 */}
                              <div className="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-800 bg-white dark:bg-[#0c1220] shadow-xs">
                                <table className="w-full text-left text-xs border-collapse">
                                  <thead>
                                    <tr className="bg-slate-50/80 dark:bg-slate-900/60 text-slate-500 dark:text-slate-400 border-b border-slate-200/80 dark:border-slate-800/80 font-semibold">
                                      <th className="py-2.5 px-3">落球位置</th>
                                      <th className="py-2.5 px-3">开奖号码</th>
                                      <th className="py-2.5 px-3">波色</th>
                                      <th className="py-2.5 px-3">生肖</th>
                                      <th className="py-2.5 px-3">连肖标记</th>
                                      <th className="py-2.5 px-3">五行</th>
                                      <th className="py-2.5 px-3">家野</th>
                                      <th className="py-2.5 px-3">大小</th>
                                      <th className="py-2.5 px-3">单双</th>
                                      <th className="py-2.5 px-3">合数</th>
                                      <th className="py-2.5 px-3">合单双</th>
                                      <th className="py-2.5 px-3">头数/尾数</th>
                                      <th className="py-2.5 px-3">半波</th>
                                    </tr>
                                  </thead>
                                  <tbody>
                                    {all7.map((b, idx) => {
                                      const isSpecial = idx === 6;
                                      const nInt = parseInt(b.num, 10);
                                      const heshuVal = Math.floor(nInt / 10) + (nInt % 10);
                                      return (
                                        <tr
                                          key={idx}
                                          className={`border-b border-slate-100 dark:border-slate-800/60 ${isSpecial ? "bg-amber-500/5 dark:bg-amber-500/10 font-medium" : ""}`}
                                        >
                                          <td className="py-2 px-3">
                                            {isSpecial ? (
                                              <span className="px-2 py-0.5 rounded bg-amber-500/20 text-amber-700 dark:text-amber-400 font-bold">特码</span>
                                            ) : (
                                              <span className="text-slate-400">正码 {idx + 1}</span>
                                            )}
                                          </td>
                                          <td className="py-2 px-3 font-mono font-bold">
                                            <span
                                              className="px-2 py-0.5 rounded text-white shadow-2xs"
                                              style={{ backgroundColor: BOSE_COLORS[b.bose]?.bg }}
                                            >
                                              {b.num}
                                            </span>
                                          </td>
                                          <td className="py-2 px-3 font-semibold" style={{ color: BOSE_COLORS[b.bose]?.bg }}>
                                            {b.bose}波
                                          </td>
                                          <td className={`py-2 px-3 font-semibold ${b.is_lianxiao ? "text-purple-500" : ""}`}>
                                            {b.xiao}
                                          </td>
                                          <td className="py-2 px-3">
                                            {b.is_lianxiao ? (
                                              <span className="px-1.5 py-0.5 rounded text-2xs bg-purple-500/10 text-purple-600 dark:text-purple-400 border border-purple-500/20 font-bold">
                                                🔗 {b.lianxiao_count}码同肖
                                              </span>
                                            ) : (
                                              <span className="text-slate-400 text-2xs">独肖</span>
                                            )}
                                          </td>
                                          <td className="py-2 px-3 font-bold" style={{ color: WUXING_COLORS[b.wuxing || ""] || "inherit" }}>
                                            {b.wuxing || "—"}
                                          </td>
                                          <td className="py-2 px-3">
                                            <span className={`px-1.5 py-0.5 rounded text-2xs ${b.jiaye === "家" ? "bg-emerald-500/10 text-emerald-600" : "bg-slate-100 dark:bg-slate-800 text-slate-500"}`}>
                                              {b.jiaye === "家" ? "家禽" : "野兽"}
                                            </span>
                                          </td>
                                          <td className="py-2 px-3">{b.size}</td>
                                          <td className="py-2 px-3">{b.odd}</td>
                                          <td className="py-2 px-3">{heshuVal}</td>
                                          <td className="py-2 px-3">{b.sum}</td>
                                          <td className="py-2 px-3">{b.head}头 / {b.wei}尾</td>
                                          <td className="py-2 px-3">{b.halfwave}</td>
                                        </tr>
                                      );
                                    })}
                                  </tbody>
                                </table>
                              </div>

                              {/* 综合分布统计卡片 */}
                              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                                <div className="p-3 rounded-xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80">
                                  <span className="text-2xs font-semibold text-slate-400 uppercase block">波色分布 (7码)</span>
                                  <div className="flex gap-3 mt-1.5 text-xs font-bold">
                                    <span className="text-rose-500">红波: {all7.filter((x) => x.bose === "红").length}</span>
                                    <span className="text-blue-500">蓝波: {all7.filter((x) => x.bose === "蓝").length}</span>
                                    <span className="text-emerald-500">绿波: {all7.filter((x) => x.bose === "绿").length}</span>
                                  </div>
                                </div>

                                <div className="p-3 rounded-xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80">
                                  <span className="text-2xs font-semibold text-slate-400 uppercase block">家野分布 (7码)</span>
                                  <div className="flex gap-4 mt-1.5 text-xs font-bold text-slate-700 dark:text-slate-300">
                                    <span>家禽: {all7.filter((x) => x.jiaye === "家").length} 码</span>
                                    <span>野兽: {all7.filter((x) => x.jiaye === "野").length} 码</span>
                                  </div>
                                </div>

                                <div className="p-3 rounded-xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80">
                                  <span className="text-2xs font-semibold text-slate-400 uppercase block">大小与单双分布 (7码)</span>
                                  <div className="flex gap-3 mt-1.5 text-xs font-bold text-slate-700 dark:text-slate-300">
                                    <span>大 {all7.filter((x) => x.size === "大").length} / 小 {all7.filter((x) => x.size === "小").length}</span>
                                    <span>单 {all7.filter((x) => x.odd === "单").length} / 双 {all7.filter((x) => x.odd === "双").length}</span>
                                  </div>
                                </div>

                                <div className="p-3 rounded-xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80">
                                  <span className="text-2xs font-semibold text-slate-400 uppercase block">特码形态总结</span>
                                  <div className="mt-1.5 text-xs font-bold text-primary">
                                    {temaDetail.num} ({temaDetail.bose}波 · {temaDetail.xiao} · {temaDetail.size}{temaDetail.odd} · 合{temaDetail.sum})
                                  </div>
                                </div>
                              </div>
                            </div>
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  );
                })}
              </tbody>
            </TableContainer>

            {total > 0 && (
              <div className="flex justify-between items-center mt-4 pt-3 border-t border-slate-100 dark:border-slate-800/80 flex-wrap gap-2">
                <span className="text-xs text-slate-500 dark:text-slate-400">
                  显示第 {offset + 1} - {Math.min(offset + limit, total)} 期，共 {total} 期历史开奖
                </span>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setOffset(Math.max(0, offset - limit))}
                    disabled={offset === 0}
                    className="px-3.5 py-1.5 rounded-xl text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 disabled:opacity-40 transition-colors cursor-pointer"
                  >
                    上一页
                  </button>
                  <button
                    type="button"
                    onClick={() => setOffset(offset + limit)}
                    disabled={offset + limit >= total}
                    className="px-3.5 py-1.5 rounded-xl text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 disabled:opacity-40 transition-colors cursor-pointer"
                  >
                    下一页
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </SectionCard>
    </div>
  );
}

function DrawBallItem({
  num,
  xiao,
  wuxing,
  bose,
  isTema = false,
  isLianxiao = false,
  lianxiaoCount,
  isAdjacent = false,
}: {
  num: string;
  xiao?: string;
  wuxing?: string | null;
  bose?: string;
  isTema?: boolean;
  isLianxiao?: boolean;
  lianxiaoCount?: number;
  isAdjacent?: boolean;
}) {
  const b = bose || getBose(num);
  const colorCfg = BOSE_COLORS[b] || BOSE_COLORS["红"];

  let ringStyle = "";
  if (isTema) {
    ringStyle = isLianxiao
      ? "ring-2 ring-amber-400 ring-offset-1 ring-offset-purple-500 shadow-md shadow-amber-500/20"
      : "ring-2 ring-amber-400 ring-offset-1 shadow-md shadow-amber-500/20";
  } else if (isLianxiao) {
    ringStyle = isAdjacent
      ? "ring-2 ring-pink-500 shadow-sm shadow-pink-500/30"
      : "ring-2 ring-purple-500 shadow-sm shadow-purple-500/30";
  }

  const ballTitle = [
    `${num}号 (${b}波 · ${xiao || getXiao(num)}${wuxing ? " · " + wuxing : ""})`,
    isAdjacent ? `[⚡ 顺位紧邻连肖 - 共${lianxiaoCount || 2}码]` : isLianxiao ? `[🔗 连肖 - 共${lianxiaoCount}码]` : "",
  ].filter(Boolean).join(" ");

  return (
    <div className="inline-flex flex-col items-center gap-1">
      <div
        className={`relative flex items-center justify-center font-bold font-mono text-white select-none transition-transform hover:scale-110 cursor-default ${ringStyle} ${
          isTema ? "w-8 h-8 rounded-full text-xs font-extrabold" : "w-7 h-7 rounded-full text-[11px]"
        }`}
        style={{ backgroundColor: colorCfg.bg }}
        title={ballTitle}
      >
        {num}

        {/* 连肖/紧邻角标 (左上方) */}
        {isLianxiao && (
          <span
            className={`absolute -top-1.5 -left-1.5 text-[8px] font-extrabold px-1 py-0 rounded text-white shadow-xs ${
              isAdjacent ? "bg-pink-600" : "bg-purple-600"
            }`}
            title={isAdjacent ? `⚡ 顺位紧邻连肖(${xiao}·共${lianxiaoCount}码)` : `🔗 连肖(${xiao}·共${lianxiaoCount}码)`}
          >
            {isAdjacent ? "⚡" : "🔗"}
          </span>
        )}
      </div>

      {/* 球号下方生肖与五行标记 */}
      <div className="flex items-center gap-0.5 text-[10px] leading-tight">
        <span className={`font-semibold ${isLianxiao ? "text-purple-600 dark:text-purple-400 font-bold" : "text-slate-600 dark:text-slate-300"}`}>
          {xiao || getXiao(num)}
        </span>
        {wuxing && (
          <span className="font-medium text-[9px]" style={{ color: WUXING_COLORS[wuxing] || "#94a3b8" }}>
            {wuxing}
          </span>
        )}
      </div>
    </div>
  );
}
