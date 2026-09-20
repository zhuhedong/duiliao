import { useState, useEffect, useCallback, useMemo } from "react";
import { Card } from "@appica/ui-react/card";
import { Button } from "@appica/ui-react/button";
import { Badge } from "@appica/ui-react/badge";
import { Spinner } from "@appica/ui-react/spinner";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { ApiError } from "../../lib/api";
import {
  collectorApi,
  type CollectionSchedule,
  type CollectionScheduleCreate,
  type CollectorSource,
  type Lottery,
  type SourceSchedulerStatus,
} from "../../lib/collector";
import {
  LOTTERIES,
  Select,
  TextInput,
  useCanWrite,
} from "./shared";
import {
  ClockIcon,
  PlayIcon,
  RefreshIcon,
  TrashIcon,
  EditIcon,
  ActivityIcon,
  CheckBadgeIcon,
  CloseIcon,
  CalendarIcon,
  SparklesIcon,
} from "../../components/icons";

interface PresetCron {
  label: string;
  cron: string;
  desc: string;
}

const CRON_PRESETS: PresetCron[] = [
  { label: "每 10 分钟", cron: "*/10 * * * *", desc: "高频抓取，适合临近封盘时段" },
  { label: "每 15 分钟", cron: "*/15 * * * *", desc: "推荐频率，适合晚间集中开奖前" },
  { label: "每 30 分钟", cron: "*/30 * * * *", desc: "日常周期采集" },
  { label: "每小时一次", cron: "0 * * * *", desc: "每整点采集一次" },
  { label: "每晚 20:30", cron: "30 20 * * *", desc: "每日开奖前 1 小时预采集" },
  { label: "开奖前连采", cron: "0,15,30 21 * * *", desc: "每日 21:00、21:15、21:30 连采" },
];

export type ScheduleMode = "time_window" | "cron" | "once";

export function calculateTimelinePreview(
  startTime: string,
  endTime: string,
  intervalMinutes: number
): string[] {
  if (!startTime || !endTime || intervalMinutes <= 0) return [];
  const sParts = startTime.split(":").map(Number);
  const eParts = endTime.split(":").map(Number);
  if (sParts.length < 2 || eParts.length < 2) return [];
  const [sh, sm] = sParts;
  const [eh, em] = eParts;
  if (isNaN(sh) || isNaN(sm) || isNaN(eh) || isNaN(em)) return [];
  const sTotal = sh * 60 + sm;
  const eTotal = eh * 60 + em;
  if (sTotal > eTotal) return [];

  const points: string[] = [];
  for (let m = sTotal; m <= eTotal; m += intervalMinutes) {
    const hh = Math.floor(m / 60)
      .toString()
      .padStart(2, "0");
    const mm = (m % 60).toString().padStart(2, "0");
    points.push(`${hh}:${mm}`);
    if (points.length >= 100) break;
  }
  return points;
}

interface ScheduleManagerProps {
  currentLottery?: Lottery;
  allSources?: CollectorSource[];
}

export function ScheduleManager({ currentLottery = "macau", allSources = [] }: ScheduleManagerProps) {
  const canWrite = useCanWrite();
  const [schedules, setSchedules] = useState<CollectionSchedule[]>([]);
  const [schedulerStatus, setSchedulerStatus] = useState<SourceSchedulerStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [filterLottery, setFilterLottery] = useState<string>("all");

  // Triggering state: schedule_id -> boolean
  const [triggering, setTriggering] = useState<Record<number, boolean>>({});

  // Create / Edit modal state
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // Form fields
  const [scheduleMode, setScheduleMode] = useState<ScheduleMode>("time_window");
  const [formName, setFormName] = useState("");
  const [formLottery, setFormLottery] = useState<Lottery>(currentLottery);
  const [formPeriod, setFormPeriod] = useState("");

  // Specific Time Window fields
  const [twStart, setTwStart] = useState("21:00");
  const [twEnd, setTwEnd] = useState("21:30");
  const [twInterval, setTwInterval] = useState(5);
  const [twScope, setTwScope] = useState<"today" | "daily">("today");

  // Cron & Once fields
  const [formCron, setFormCron] = useState("0-30/5 21 * * *");
  const [formStartAt, setFormStartAt] = useState("");
  const [formEndAt, setFormEndAt] = useState("");

  // Concurrency field
  const [formConcurrency, setFormConcurrency] = useState(8);

  const [formEnabled, setFormEnabled] = useState(true);
  const [formDoIngest, setFormDoIngest] = useState(true);
  const [formAutoJudge, setFormAutoJudge] = useState(true);
  const [sourceMode, setSourceMode] = useState<"all" | "custom">("all");
  const [selectedSourceIds, setSelectedSourceIds] = useState<Set<string>>(new Set());

  // Log drawer state
  const [activeLogSchedule, setActiveLogSchedule] = useState<CollectionSchedule | null>(null);

  // Timeline preview for time window mode
  const timelinePreview = useMemo(() => {
    if (scheduleMode !== "time_window") return [];
    return calculateTimelinePreview(twStart, twEnd, twInterval);
  }, [scheduleMode, twStart, twEnd, twInterval]);

  const loadData = useCallback(async () => {
    setError(null);
    try {
      const res = await collectorApi.listSchedules();
      setSchedules(res.schedules || []);
      setSchedulerStatus(res.scheduler || null);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "加载定时任务失败");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadData();
    const interval = setInterval(() => {
      void loadData();
    }, 10000);
    return () => clearInterval(interval);
  }, [loadData]);

  // Available sources filtered by selected lottery in form
  const lotterySources = useMemo(() => {
    return allSources.filter((s) => s.lottery === formLottery);
  }, [allSources, formLottery]);

  const openCreateModal = () => {
    setEditingId(null);
    setScheduleMode("time_window");
    setFormName(`澳门晚间21:00-21:30高频采集 (线程池加速)`);
    setFormLottery(currentLottery);
    setFormPeriod("");
    setTwStart("21:00");
    setTwEnd("21:30");
    setTwInterval(5);
    setTwScope("today");
    setFormConcurrency(8);
    setFormCron("0-30/5 21 * * *");
    setFormStartAt("");
    setFormEndAt("");
    setFormEnabled(true);
    setFormDoIngest(true);
    setFormAutoJudge(true);
    setSourceMode("all");
    setSelectedSourceIds(new Set());
    setShowModal(true);
  };

  const openEditModal = (sched: CollectionSchedule) => {
    setEditingId(sched.id);
    setFormName(sched.name);
    setFormLottery(sched.lottery);
    setFormPeriod(sched.period || "");
    setFormStartAt(sched.start_at || "");
    setFormEndAt(sched.end_at || "");
    setFormEnabled(sched.enabled);
    setFormDoIngest(sched.do_ingest);
    setFormAutoJudge(sched.auto_judge);
    setFormConcurrency(sched.spec?.concurrency ?? 8);

    if (sched.spec?.time_window_start && sched.spec?.time_window_end) {
      setScheduleMode("time_window");
      setTwStart(sched.spec.time_window_start);
      setTwEnd(sched.spec.time_window_end);
      setTwInterval(sched.spec.interval_minutes || 5);
      setTwScope(sched.spec.window_date === "daily" ? "daily" : "today");
      setFormCron(sched.cron || "");
    } else if (sched.cron) {
      setScheduleMode("cron");
      setFormCron(sched.cron);
    } else {
      setScheduleMode("once");
    }

    if (sched.source_ids && sched.source_ids.length > 0) {
      setSourceMode("custom");
      setSelectedSourceIds(new Set(sched.source_ids));
    } else {
      setSourceMode("all");
      setSelectedSourceIds(new Set());
    }
    setShowModal(true);
  };

  const handleSave = async () => {
    if (!formName.trim()) {
      setError("请输入任务名称");
      return;
    }

    if (scheduleMode === "time_window") {
      if (!twStart || !twEnd || twInterval <= 0) {
        setError("请完整配置时间段（开始时间、结束时间及执行间隔）");
        return;
      }
    } else if (scheduleMode === "cron") {
      if (!formCron.trim()) {
        setError("请输入 Cron 表达式");
        return;
      }
    } else if (scheduleMode === "once") {
      if (!formStartAt.trim()) {
        setError("请输入单次特定开始时间");
        return;
      }
    }

    setSubmitting(true);
    setError(null);
    setSuccessMsg(null);

    const source_ids = sourceMode === "custom" && selectedSourceIds.size > 0
      ? Array.from(selectedSourceIds)
      : null;

    try {
      const isWindow = scheduleMode === "time_window";
      const payload: CollectionScheduleCreate = {
        name: formName.trim(),
        lottery: formLottery,
        period: formPeriod.trim() || null,
        enabled: formEnabled,
        do_ingest: formDoIngest,
        auto_judge: formAutoJudge,
        source_ids: source_ids,
        concurrency: formConcurrency,
      };

      if (isWindow) {
        payload.time_window_start = twStart;
        payload.time_window_end = twEnd;
        payload.interval_minutes = twInterval;
        payload.window_date = twScope;
      } else if (scheduleMode === "cron") {
        payload.cron = formCron.trim() || null;
        payload.start_at = formStartAt.trim() || null;
        payload.end_at = formEndAt.trim() || null;
      } else if (scheduleMode === "once") {
        payload.cron = null;
        payload.start_at = formStartAt.trim() || null;
        payload.end_at = null;
      }

      if (editingId !== null) {
        await collectorApi.updateSchedule(editingId, payload);
        setSuccessMsg(`定时任务 #${editingId} (${formName}) 已成功更新！`);
      } else {
        const res = await collectorApi.createSchedule(payload);
        setSuccessMsg(`定时任务 #${res.schedule.id} (${res.schedule.name}) 已成功创建并启动！`);
      }
      setShowModal(false);
      await loadData();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "保存定时任务失败");
    } finally {
      setSubmitting(false);
    }
  };

  const handleToggleEnabled = async (sched: CollectionSchedule) => {
    try {
      await collectorApi.updateSchedule(sched.id, { enabled: !sched.enabled });
      setSuccessMsg(`任务 #${sched.id} 已${sched.enabled ? "暂停" : "重新启用"}。`);
      await loadData();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "切换任务状态失败");
    }
  };

  const handleTriggerNow = async (sched: CollectionSchedule) => {
    setTriggering((prev) => ({ ...prev, [sched.id]: true }));
    setError(null);
    setSuccessMsg(null);
    try {
      const res = await collectorApi.triggerSchedule(sched.id);
      const summary = res.result;
      setSuccessMsg(
        `任务 #${sched.id} 立即执行完成！期数: ${summary?.period || "auto"}，成功 ${summary?.source_ok ?? 0}/${summary?.source_total ?? 0} 源`
      );
      await loadData();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : `执行任务 #${sched.id} 失败`);
    } finally {
      setTriggering((prev) => ({ ...prev, [sched.id]: false }));
    }
  };

  const handleDelete = async (sched: CollectionSchedule) => {
    if (!window.confirm(`确定要永久删除定时任务 #${sched.id} (${sched.name}) 吗？`)) {
      return;
    }
    try {
      await collectorApi.deleteSchedule(sched.id);
      setSuccessMsg(`任务 #${sched.id} 已成功删除。`);
      await loadData();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "删除任务失败");
    }
  };

  const filteredSchedules = useMemo(() => {
    if (filterLottery === "all") return schedules;
    return schedules.filter((s) => s.lottery === filterLottery);
  }, [schedules, filterLottery]);

  return (
    <div className="space-y-6">
      {/* Alerts */}
      {error && (
        <Alert variant="error" className="flex items-center justify-between">
          <AlertDescription>{error}</AlertDescription>
          <button onClick={() => setError(null)} className="text-xs hover:underline cursor-pointer">
            关闭
          </button>
        </Alert>
      )}

      {successMsg && (
        <div className="p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-600 dark:text-emerald-400 text-sm flex items-center justify-between">
          <div className="flex items-center gap-2">
            <CheckBadgeIcon size={18} />
            <span>{successMsg}</span>
          </div>
          <button onClick={() => setSuccessMsg(null)} className="text-xs hover:underline cursor-pointer">
            关闭
          </button>
        </div>
      )}

      {/* Scheduler Status Header Card */}
      <Card className="p-5 bg-gradient-to-r from-slate-50 to-indigo-50/30 dark:from-[#0d1527] dark:to-[#0f172a] border border-slate-200 dark:border-slate-800">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div className="flex items-start md:items-center gap-3">
            <div className="p-3 rounded-2xl bg-primary/10 text-primary">
              <ClockIcon size={24} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-base font-semibold text-slate-900 dark:text-white">
                  数据源自动采集调度器
                </h3>
                {schedulerStatus?.running ? (
                  <Badge variant="success" className="gap-1.5 py-0.5 px-2">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                    服务运行中
                  </Badge>
                ) : (
                  <Badge variant="outline" className="text-slate-500">
                    等待初始化
                  </Badge>
                )}
                <span className="text-xs text-slate-500 dark:text-slate-400">
                  (轮询检测: 每 {schedulerStatus?.check_interval_seconds || 5} 秒)
                </span>
              </div>
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">
                支持 Linux 标准 5 段 Cron 表达式、指定日期时间开始（延迟启动）、特定期数采集以及自动入库评奖。
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2.5 flex-wrap">
            <Button
              variant="outline"
              size="sm"
              onClick={() => void loadData()}
              className="gap-1.5 text-xs rounded-xl"
            >
              <RefreshIcon size={14} />
              刷新
            </Button>
            {canWrite && (
              <Button
                size="sm"
                onClick={openCreateModal}
                className="gap-1.5 text-xs rounded-xl bg-primary hover:bg-primary/90 text-white font-medium shadow-xs"
              >
                <PlayIcon size={14} />
                新建定时任务
              </Button>
            )}
          </div>
        </div>

        {/* Quick Stats bar */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mt-4 pt-4 border-t border-slate-200/60 dark:border-slate-800/60 text-xs">
          <div>
            <span className="text-slate-400 block">已注册任务</span>
            <span className="text-base font-bold text-slate-800 dark:text-slate-100">
              {schedules.length} 个
            </span>
          </div>
          <div>
            <span className="text-slate-400 block">启用中任务</span>
            <span className="text-base font-bold text-emerald-600 dark:text-emerald-400">
              {schedules.filter((s) => s.enabled).length} 个
            </span>
          </div>
          <div>
            <span className="text-slate-400 block">正在执行</span>
            <span className="text-base font-bold text-amber-600 dark:text-amber-400">
              {schedulerStatus?.active_tasks_count || 0} 个
            </span>
          </div>
          <div>
            <span className="text-slate-400 block">最近执行日志</span>
            <span className="text-base font-bold text-slate-800 dark:text-slate-100">
              {schedulerStatus?.recent_logs?.length || 0} 条
            </span>
          </div>
        </div>
      </Card>

      {/* Filter Toolbar */}
      <div className="flex items-center justify-between gap-4 flex-wrap">
        <div className="flex items-center gap-2">
          <span className="text-xs text-slate-500 font-medium">筛选彩种：</span>
          <Select
            value={filterLottery}
            onChange={setFilterLottery}
            options={[
              { value: "all", label: "全部彩种" },
              ...LOTTERIES.map((l) => ({ value: l.value, label: l.label })),
            ]}
          />
        </div>

        <span className="text-xs text-slate-500">
          共 {filteredSchedules.length} 个定时任务
        </span>
      </div>

      {/* Schedules Table / Empty State */}
      {loading ? (
        <Card className="p-12 flex flex-col items-center justify-center text-slate-400">
          <Spinner className="w-8 h-8 text-primary mb-3" />
          <p className="text-sm">正在加载定时采集任务...</p>
        </Card>
      ) : filteredSchedules.length === 0 ? (
        <Card className="p-12 text-center text-slate-400 border-dashed border-2 border-slate-200 dark:border-slate-800">
          <div className="w-12 h-12 mx-auto mb-3 rounded-2xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center text-slate-400">
            <ClockIcon size={24} />
          </div>
          <h4 className="text-sm font-semibold text-slate-700 dark:text-slate-300 mb-1">
            暂无定时采集任务
          </h4>
          <p className="text-xs text-slate-400 max-w-md mx-auto mb-4">
            您可以添加周期性 Cron 采集任务（如每 15 分钟执行），或指定在未来特定时间启动采集。
          </p>
          {canWrite && (
            <Button size="sm" onClick={openCreateModal} className="rounded-xl">
              立即创建第一个定时任务
            </Button>
          )}
        </Card>
      ) : (
        <div className="grid grid-cols-1 gap-4">
          {filteredSchedules.map((sched) => {
            const isRunning = triggering[sched.id] || schedulerStatus?.running_task_ids?.includes(sched.id);
            const sourceCount = sched.source_ids?.length || 0;
            const targetScope = sourceCount === 0 ? "全部有效数据源" : `${sourceCount} 个指定源`;

            return (
              <Card
                key={sched.id}
                className="p-5 border border-slate-200 dark:border-slate-800 hover:border-primary/40 transition-colors shadow-xs"
              >
                <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
                  {/* Left: Task info */}
                  <div className="space-y-2 flex-1">
                    <div className="flex items-center gap-2.5 flex-wrap">
                      <span className="text-xs font-mono font-bold text-slate-400">
                        #{sched.id}
                      </span>
                      <h4 className="text-base font-bold text-slate-900 dark:text-white">
                        {sched.name}
                      </h4>
                      <Badge variant="outline" className="uppercase font-mono text-[11px]">
                        {sched.lottery}
                      </Badge>
                      {sched.period ? (
                        <Badge variant="secondary" className="text-[11px]">
                          指定期数: {sched.period}
                        </Badge>
                      ) : (
                        <Badge variant="outline" className="text-[11px] text-slate-500">
                          最新期 (自动识别)
                        </Badge>
                      )}
                      {sched.spec?.time_window_start && (
                        <Badge variant="secondary" className="text-[11px] bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20">
                          {sched.spec.window_date === "daily" ? "每日" : "当天"} {sched.spec.time_window_start}-{sched.spec.time_window_end} (每{sched.spec.interval_minutes}分)
                        </Badge>
                      )}
                      <Badge variant="outline" className="text-[11px] text-indigo-600 dark:text-indigo-400 bg-indigo-50/50 dark:bg-indigo-950/30 border-indigo-200 dark:border-indigo-800 flex items-center gap-1">
                        <span>⚡</span>
                        <span>{sched.spec?.concurrency || 8} 线程</span>
                      </Badge>
                      {sched.enabled ? (
                        <Badge variant="success" className="text-[11px]">
                          已启用
                        </Badge>
                      ) : (
                        <Badge variant="outline" className="text-[11px] text-slate-400">
                          已暂停
                        </Badge>
                      )}
                    </div>

                    {/* Schedule rules display */}
                    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3 text-xs text-slate-600 dark:text-slate-300 pt-1">
                      <div>
                        <span className="text-slate-400 block text-[11px]">调度规则 (Cron)</span>
                        <code className="font-mono bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 rounded text-[11px] text-primary font-bold" title={sched.cron || ""}>
                          {sched.cron || "单次执行"}
                        </code>
                      </div>
                      <div>
                        <span className="text-slate-400 block text-[11px]">有效窗口 (Start ~ End)</span>
                        <span className="font-mono text-[11px]">
                          {sched.start_at ? sched.start_at.slice(5, 16) : "即刻"} ~ {sched.end_at ? sched.end_at.slice(5, 16) : "长期"}
                        </span>
                      </div>
                      <div>
                        <span className="text-slate-400 block text-[11px]">下次执行</span>
                        <span className="font-mono text-[11px] text-emerald-600 dark:text-emerald-400 font-semibold">
                          {sched.enabled ? (sched.next_run_at || "已完成/无") : "已暂停"}
                        </span>
                      </div>
                      <div>
                        <span className="text-slate-400 block text-[11px]">数据源范围</span>
                        <span className="text-[11px] font-medium text-slate-700 dark:text-slate-200">
                          {targetScope}
                        </span>
                      </div>
                    </div>

                    {/* Last run status info */}
                    {sched.last_run_at && (
                      <div className="flex items-center gap-3 text-xs text-slate-500 pt-1 border-t border-slate-100 dark:border-slate-800/60 mt-2">
                        <span>上次运行：{sched.last_run_at}</span>
                        {sched.last_status === "success" ? (
                          <Badge variant="success" className="py-0 text-[10px]">
                            成功
                          </Badge>
                        ) : (
                          <Badge variant="error" className="py-0 text-[10px]">
                            失败
                          </Badge>
                        )}
                        {sched.last_result && (
                          <span className="text-[11px] text-slate-400">
                            (抓取 {sched.last_result.source_ok ?? 0}/{sched.last_result.source_total ?? 0} 源
                            {sched.last_result.period ? `，期数 ${sched.last_result.period}` : ""})
                          </span>
                        )}
                      </div>
                    )}
                  </div>

                  {/* Right: Actions */}
                  <div className="flex items-center gap-2 self-end lg:self-center flex-wrap pt-2 lg:pt-0">
                    {canWrite && (
                      <>
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={isRunning}
                          onClick={() => void handleTriggerNow(sched)}
                          className="gap-1 text-xs rounded-xl hover:bg-primary/10 hover:text-primary hover:border-primary/30"
                        >
                          {isRunning ? (
                            <>
                              <Spinner className="w-3.5 h-3.5" />
                              执行中...
                            </>
                          ) : (
                            <>
                              <PlayIcon size={14} />
                              立即执行
                            </>
                          )}
                        </Button>

                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => void handleToggleEnabled(sched)}
                          className={`text-xs rounded-xl ${
                            sched.enabled ? "text-amber-600 hover:text-amber-700" : "text-emerald-600 hover:text-emerald-700"
                          }`}
                        >
                          {sched.enabled ? "暂停" : "启用"}
                        </Button>

                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => openEditModal(sched)}
                          className="text-xs rounded-xl text-slate-600 dark:text-slate-300"
                        >
                          <EditIcon size={14} />
                        </Button>

                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => setActiveLogSchedule(sched)}
                          className="text-xs rounded-xl text-slate-600 dark:text-slate-300"
                          title="查看执行日志"
                        >
                          <ActivityIcon size={14} />
                        </Button>

                        <Button
                          size="sm"
                          variant="ghost"
                          onClick={() => void handleDelete(sched)}
                          className="text-xs rounded-xl text-rose-500 hover:text-rose-600"
                        >
                          <TrashIcon size={14} />
                        </Button>
                      </>
                    )}
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      {/* Create / Edit Schedule Modal */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-fadeIn">
          <Card className="w-full max-w-3xl max-h-[85vh] flex flex-col p-0 bg-white dark:bg-[#0c1220] border border-slate-200 dark:border-slate-800 shadow-2xl rounded-2xl overflow-hidden">
            <div className="flex items-center justify-between px-6 py-4 border-b border-slate-200 dark:border-slate-800 shrink-0">
              <div className="flex items-center gap-2">
                <ClockIcon size={20} className="text-primary" />
                <h3 className="text-base font-bold text-slate-900 dark:text-white">
                  {editingId !== null ? `编辑定时采集任务 #${editingId}` : "新建数据源定时采集任务"}
                </h3>
              </div>
              <button
                onClick={() => setShowModal(false)}
                className="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 cursor-pointer p-1 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
              >
                <CloseIcon size={20} />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto p-6 space-y-4">
              {/* Task Name */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                  任务名称 <span className="text-rose-500">*</span>
                </label>
                <TextInput
                  value={formName}
                  onChange={setFormName}
                  placeholder="例如：澳门晚间21:00-21:30高频采集 (线程池加速)"
                  className="w-full"
                />
              </div>

              {/* Lottery & Period */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                    目标彩种
                  </label>
                  <Select
                    value={formLottery}
                    onChange={(v) => setFormLottery(v as Lottery)}
                    options={LOTTERIES.map((l) => ({ value: l.value, label: l.label }))}
                    className="w-full"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                    指定期数 <span className="text-slate-400 font-normal">(可选，留空则自动抓取最新期)</span>
                  </label>
                  <TextInput
                    value={formPeriod}
                    onChange={setFormPeriod}
                    placeholder="如：2026263，留空为最新期"
                    className="w-full"
                  />
                </div>
              </div>

              {/* Schedule Mode Selector */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-2">
                  调度策略模式
                </label>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                  <button
                    type="button"
                    onClick={() => setScheduleMode("time_window")}
                    className={`p-3 rounded-xl border text-left transition-all cursor-pointer ${
                      scheduleMode === "time_window"
                        ? "bg-primary/10 border-primary text-primary font-semibold shadow-xs ring-1 ring-primary/30"
                        : "bg-white dark:bg-slate-800/60 border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:border-slate-300"
                    }`}
                  >
                    <div className="flex items-center gap-1.5 text-xs font-bold mb-1">
                      <ClockIcon size={14} />
                      特定时间段模式
                    </div>
                    <p className="text-[11px] text-slate-500 dark:text-slate-400 font-normal">
                      当天 21:00-21:30 每 N 分钟执行
                    </p>
                  </button>

                  <button
                    type="button"
                    onClick={() => setScheduleMode("cron")}
                    className={`p-3 rounded-xl border text-left transition-all cursor-pointer ${
                      scheduleMode === "cron"
                        ? "bg-primary/10 border-primary text-primary font-semibold shadow-xs ring-1 ring-primary/30"
                        : "bg-white dark:bg-slate-800/60 border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:border-slate-300"
                    }`}
                  >
                    <div className="flex items-center gap-1.5 text-xs font-bold mb-1">
                      <SparklesIcon size={14} />
                      Cron 表达式模式
                    </div>
                    <p className="text-[11px] text-slate-500 dark:text-slate-400 font-normal">
                      标准 5 段表达式，周期重复
                    </p>
                  </button>

                  <button
                    type="button"
                    onClick={() => setScheduleMode("once")}
                    className={`p-3 rounded-xl border text-left transition-all cursor-pointer ${
                      scheduleMode === "once"
                        ? "bg-primary/10 border-primary text-primary font-semibold shadow-xs ring-1 ring-primary/30"
                        : "bg-white dark:bg-slate-800/60 border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:border-slate-300"
                    }`}
                  >
                    <div className="flex items-center gap-1.5 text-xs font-bold mb-1">
                      <CalendarIcon size={14} />
                      单次定时预约
                    </div>
                    <p className="text-[11px] text-slate-500 dark:text-slate-400 font-normal">
                      指定未来某个时刻单次执行
                    </p>
                  </button>
                </div>
              </div>

              {/* Mode 1: Time Window Mode Settings */}
              {scheduleMode === "time_window" && (
                <div className="p-4 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-200 dark:border-slate-800 space-y-3.5 animate-fadeIn">
                  <div className="flex items-center justify-between pb-1 border-b border-slate-200/60 dark:border-slate-800/60">
                    <span className="text-xs font-bold text-slate-800 dark:text-slate-200 flex items-center gap-1.5">
                      <ClockIcon size={14} className="text-primary" />
                      时间段窗口配置 (如：当天 21:00-21:30 每 5 分钟)
                    </span>
                    <span className="text-[11px] text-slate-400">北京时间 (UTC+8)</span>
                  </div>

                  {/* Window Start & End */}
                  <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                    <div>
                      <label className="block text-[11px] font-semibold text-slate-600 dark:text-slate-400 mb-1">
                        起始时间 (HH:MM)
                      </label>
                      <TextInput
                        value={twStart}
                        onChange={setTwStart}
                        placeholder="21:00"
                        className="w-full font-mono text-xs"
                      />
                    </div>
                    <div>
                      <label className="block text-[11px] font-semibold text-slate-600 dark:text-slate-400 mb-1">
                        截止时间 (HH:MM)
                      </label>
                      <TextInput
                        value={twEnd}
                        onChange={setTwEnd}
                        placeholder="21:30"
                        className="w-full font-mono text-xs"
                      />
                    </div>
                    <div className="col-span-2 sm:col-span-1">
                      <label className="block text-[11px] font-semibold text-slate-600 dark:text-slate-400 mb-1">
                        间隔分钟数 (每 N 分钟)
                      </label>
                      <input
                        type="number"
                        min={1}
                        max={60}
                        value={twInterval}
                        onChange={(e) => setTwInterval(Math.max(1, parseInt(e.target.value) || 1))}
                        className="w-full px-3 py-1.5 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-xs font-mono"
                      />
                    </div>
                  </div>

                  {/* Interval quick buttons */}
                  <div className="flex items-center gap-2 flex-wrap text-xs">
                    <span className="text-[11px] text-slate-400">常用间隔：</span>
                    {[1, 2, 3, 5, 10, 15].map((mins) => (
                      <button
                        key={mins}
                        type="button"
                        onClick={() => setTwInterval(mins)}
                        className={`text-xs px-2.5 py-0.5 rounded-lg border transition-colors cursor-pointer ${
                          twInterval === mins
                            ? "bg-primary/10 border-primary text-primary font-semibold"
                            : "bg-white dark:bg-slate-800 border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:border-slate-300"
                        }`}
                      >
                        每 {mins} 分钟
                      </button>
                    ))}
                  </div>

                  {/* Scope: Today vs Daily */}
                  <div className="pt-2 border-t border-slate-200/60 dark:border-slate-800/60">
                    <label className="block text-[11px] font-semibold text-slate-600 dark:text-slate-400 mb-1.5">
                      重复周期
                    </label>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      <label className={`flex items-start gap-2 p-2.5 rounded-xl border cursor-pointer transition-all ${
                        twScope === "today"
                          ? "bg-primary/5 border-primary/40 text-primary shadow-2xs"
                          : "bg-white dark:bg-slate-800 border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300"
                      }`}>
                        <input
                          type="radio"
                          name="twScope"
                          checked={twScope === "today"}
                          onChange={() => setTwScope("today")}
                          className="mt-0.5 text-primary"
                        />
                        <div>
                          <span className="text-xs font-semibold block">仅在当天执行 (today)</span>
                          <span className="text-[10px] text-slate-400 font-normal leading-relaxed block mt-0.5">
                            自动绑定今日日期，到达 {twEnd} 执行完成后自动停止，不跨天
                          </span>
                        </div>
                      </label>

                      <label className={`flex items-start gap-2 p-2.5 rounded-xl border cursor-pointer transition-all ${
                        twScope === "daily"
                          ? "bg-primary/5 border-primary/40 text-primary shadow-2xs"
                          : "bg-white dark:bg-slate-800 border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300"
                      }`}>
                        <input
                          type="radio"
                          name="twScope"
                          checked={twScope === "daily"}
                          onChange={() => setTwScope("daily")}
                          className="mt-0.5 text-primary"
                        />
                        <div>
                          <span className="text-xs font-semibold block">每日循环执行 (daily)</span>
                          <span className="text-[10px] text-slate-400 font-normal leading-relaxed block mt-0.5">
                            每天到达 {twStart} 至 {twEnd} 期间准时每隔 {twInterval} 分钟采集一次
                          </span>
                        </div>
                      </label>
                    </div>
                  </div>

                  {/* Timeline Preview */}
                  {timelinePreview.length > 0 && (
                    <div className="pt-2 border-t border-slate-200/60 dark:border-slate-800/60">
                      <div className="flex items-center justify-between mb-1.5">
                        <span className="text-[11px] font-semibold text-slate-600 dark:text-slate-400">
                          执行时刻点预览 (共 {timelinePreview.length} 次采集)：
                        </span>
                        <span className="text-[10px] font-mono text-primary font-semibold">
                          {twStart} ~ {twEnd}
                        </span>
                      </div>
                      <div className="flex flex-wrap gap-1.5 max-h-24 overflow-y-auto p-2 rounded-lg bg-white dark:bg-slate-800 border border-slate-200 dark:border-slate-700">
                        {timelinePreview.map((pt, i) => (
                          <span
                            key={i}
                            className="px-2 py-0.5 rounded-md bg-slate-100 dark:bg-slate-700 font-mono text-[11px] text-slate-700 dark:text-slate-200 font-semibold"
                          >
                            {pt}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}

              {/* Mode 2: Cron Mode Settings */}
              {scheduleMode === "cron" && (
                <div className="p-4 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-200 dark:border-slate-800 space-y-3 animate-fadeIn">
                  <div className="flex items-center justify-between">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300 flex items-center gap-1.5">
                      <SparklesIcon size={14} className="text-primary" />
                      Cron 表达式 (标准 5 段：分 时 日 月 周)
                    </label>
                    <span className="text-[11px] text-slate-400">北京时间 (UTC+8)</span>
                  </div>

                  <TextInput
                    value={formCron}
                    onChange={setFormCron}
                    placeholder="*/15 * * * *"
                    className="w-full font-mono text-sm"
                  />

                  {/* Quick Cron Presets */}
                  <div>
                    <span className="text-[11px] text-slate-400 block mb-1.5">快捷预设模板：</span>
                    <div className="flex flex-wrap gap-1.5">
                      {CRON_PRESETS.map((p) => (
                        <button
                          key={p.cron}
                          type="button"
                          onClick={() => setFormCron(p.cron)}
                          className={`text-xs px-2.5 py-1 rounded-lg border transition-colors cursor-pointer ${
                            formCron === p.cron
                              ? "bg-primary/10 border-primary text-primary font-semibold"
                              : "bg-white dark:bg-slate-800 border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:border-slate-300"
                          }`}
                          title={p.desc}
                        >
                          {p.label}
                        </button>
                      ))}
                    </div>
                  </div>

                  {/* Optional start/end for cron */}
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-2 border-t border-slate-200/60 dark:border-slate-800/60">
                    <div>
                      <label className="block text-[11px] font-semibold text-slate-600 dark:text-slate-400 mb-1">
                        起效时间 (Start At，可选)
                      </label>
                      <TextInput
                        value={formStartAt}
                        onChange={setFormStartAt}
                        placeholder="YYYY-MM-DD HH:MM:SS"
                        className="w-full font-mono text-xs"
                      />
                    </div>
                    <div>
                      <label className="block text-[11px] font-semibold text-slate-600 dark:text-slate-400 mb-1">
                        失效时间 (End At，可选)
                      </label>
                      <TextInput
                        value={formEndAt}
                        onChange={setFormEndAt}
                        placeholder="YYYY-MM-DD HH:MM:SS"
                        className="w-full font-mono text-xs"
                      />
                    </div>
                  </div>
                </div>
              )}

              {/* Mode 3: Once Mode Settings */}
              {scheduleMode === "once" && (
                <div className="p-4 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-200 dark:border-slate-800 space-y-3 animate-fadeIn">
                  <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1 flex items-center gap-1">
                    <CalendarIcon size={14} className="text-primary" />
                    单次特定执行时间 (Start At) <span className="text-rose-500">*</span>
                  </label>
                  <TextInput
                    value={formStartAt}
                    onChange={setFormStartAt}
                    placeholder="格式：YYYY-MM-DD HH:MM:SS"
                    className="w-full font-mono text-xs"
                  />
                  <span className="text-[11px] text-slate-400 block">
                    到达该特定时间点将仅执行 1 次，执行完毕后自动归档完成。
                  </span>
                </div>
              )}

              {/* Thread Pool Concurrency Configuration */}
              <div className="p-4 rounded-xl bg-indigo-50/50 dark:bg-indigo-950/20 border border-indigo-200 dark:border-indigo-800/50 space-y-2.5">
                <div className="flex items-center justify-between">
                  <label className="text-xs font-bold text-indigo-950 dark:text-indigo-200 flex items-center gap-1.5">
                    <span>⚡</span>
                    线程池并发采集设置 (ThreadPoolExecutor)
                  </label>
                  <span className="text-xs font-mono font-bold text-indigo-600 dark:text-indigo-400">
                    {formConcurrency} 线程
                  </span>
                </div>

                <div className="flex items-center gap-4">
                  <input
                    type="range"
                    min={1}
                    max={20}
                    value={formConcurrency}
                    onChange={(e) => setFormConcurrency(parseInt(e.target.value) || 8)}
                    className="flex-1 accent-indigo-600 cursor-pointer"
                  />
                  <input
                    type="number"
                    min={1}
                    max={20}
                    value={formConcurrency}
                    onChange={(e) => setFormConcurrency(Math.min(20, Math.max(1, parseInt(e.target.value) || 8)))}
                    className="w-16 px-2.5 py-1 rounded-lg border border-indigo-200 dark:border-indigo-700 bg-white dark:bg-slate-800 text-xs font-mono text-center font-bold"
                  />
                </div>

                <div className="flex items-center justify-between flex-wrap gap-2 pt-1 text-xs">
                  <div className="flex items-center gap-1.5">
                    <span className="text-[11px] text-indigo-600/70 dark:text-indigo-400/70">快捷配置：</span>
                    {[4, 8, 12, 16].map((num) => (
                      <button
                        key={num}
                        type="button"
                        onClick={() => setFormConcurrency(num)}
                        className={`text-[11px] px-2 py-0.5 rounded-md border transition-colors cursor-pointer ${
                          formConcurrency === num
                            ? "bg-indigo-600 text-white border-indigo-600 font-bold"
                            : "bg-white dark:bg-slate-800 border-indigo-200 dark:border-indigo-800 text-indigo-700 dark:text-indigo-300"
                        }`}
                      >
                        {num} 线程{num === 8 ? " (推荐)" : ""}
                      </button>
                    ))}
                  </div>
                  <span className="text-[11px] text-slate-400">
                    35+ 数据源多线程并行采集仅需 1~2 秒 (提升 10x+)
                  </span>
                </div>
              </div>

              {/* Source Scope Selection */}
              <div>
                <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                  目标数据源范围
                </label>
                <div className="flex items-center gap-4 mb-2">
                  <label className="inline-flex items-center gap-2 text-xs text-slate-700 dark:text-slate-300 cursor-pointer">
                    <input
                      type="radio"
                      name="sourceMode"
                      checked={sourceMode === "all"}
                      onChange={() => setSourceMode("all")}
                      className="text-primary"
                    />
                    全部有效数据源 (自动包含所有 {lotterySources.length} 个可用源)
                  </label>
                  <label className="inline-flex items-center gap-2 text-xs text-slate-700 dark:text-slate-300 cursor-pointer">
                    <input
                      type="radio"
                      name="sourceMode"
                      checked={sourceMode === "custom"}
                      onChange={() => setSourceMode("custom")}
                      className="text-primary"
                    />
                    指定特定数据源 ({selectedSourceIds.size} 已选)
                  </label>
                </div>

                {sourceMode === "custom" && (
                  <div className="p-3 rounded-xl border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-900/50 space-y-2">
                    <div className="flex items-center justify-between pb-1 text-xs">
                      <span className="text-slate-500 font-medium">选择需要采集的对料源：</span>
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => {
                            const tongtianIds = lotterySources.filter(s => s.source_id.startsWith("tt_")).map(s => s.source_id);
                            setSelectedSourceIds(new Set(tongtianIds));
                          }}
                          className="text-[11px] text-primary hover:underline cursor-pointer"
                        >
                          全选通天源 (35)
                        </button>
                        <span className="text-slate-300">|</span>
                        <button
                          type="button"
                          onClick={() => setSelectedSourceIds(new Set(lotterySources.map(s => s.source_id)))}
                          className="text-[11px] text-primary hover:underline cursor-pointer"
                        >
                          全选
                        </button>
                        <span className="text-slate-300">|</span>
                        <button
                          type="button"
                          onClick={() => setSelectedSourceIds(new Set())}
                          className="text-[11px] text-slate-500 hover:underline cursor-pointer"
                        >
                          清空
                        </button>
                      </div>
                    </div>

                    <div className="max-h-48 overflow-y-auto grid grid-cols-2 sm:grid-cols-3 gap-1.5 pt-1">
                      {lotterySources.map((s) => {
                        const checked = selectedSourceIds.has(s.source_id);
                        return (
                          <label
                            key={s.source_id}
                            className={`flex items-center gap-1.5 p-1.5 rounded-lg text-xs cursor-pointer border transition-colors ${
                              checked
                                ? "bg-primary/10 border-primary/40 text-primary font-medium"
                                : "bg-white dark:bg-slate-800 border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300"
                            }`}
                          >
                            <input
                              type="checkbox"
                              checked={checked}
                              onChange={() => {
                                setSelectedSourceIds((prev) => {
                                  const next = new Set(prev);
                                  next.has(s.source_id) ? next.delete(s.source_id) : next.add(s.source_id);
                                  return next;
                                });
                              }}
                              className="text-primary rounded"
                            />
                            <span className="truncate" title={s.source_name || s.source_id}>
                              {s.source_name || s.source_id}
                            </span>
                          </label>
                        );
                      })}
                    </div>
                  </div>
                )}
              </div>

              {/* Execution Options */}
              <div className="flex items-center gap-6 pt-2 border-t border-slate-200 dark:border-slate-800 text-xs">
                <label className="inline-flex items-center gap-2 text-slate-700 dark:text-slate-300 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formDoIngest}
                    onChange={(e) => setFormDoIngest(e.target.checked)}
                    className="text-primary rounded"
                  />
                  <span>自动入库与去重 (do_ingest)</span>
                </label>
                <label className="inline-flex items-center gap-2 text-slate-700 dark:text-slate-300 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formAutoJudge}
                    onChange={(e) => setFormAutoJudge(e.target.checked)}
                    className="text-primary rounded"
                  />
                  <span>自动对奖比对 (auto_judge)</span>
                </label>
                <label className="inline-flex items-center gap-2 text-slate-700 dark:text-slate-300 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formEnabled}
                    onChange={(e) => setFormEnabled(e.target.checked)}
                    className="text-primary rounded"
                  />
                  <span>立即启用</span>
                </label>
              </div>
            </div>

            {/* Modal Footer - Pinned at Bottom */}
            <div className="flex items-center justify-between px-6 py-4 border-t border-slate-200 dark:border-slate-800 bg-slate-50/95 dark:bg-slate-900/90 backdrop-blur-xs shrink-0">
              <div className="text-xs text-slate-500 dark:text-slate-400 hidden sm:flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-emerald-500 shrink-0 animate-pulse" />
                <span className="truncate max-w-[320px]">
                  {scheduleMode === "time_window"
                    ? `${twScope === "today" ? "当天" : "每日"} ${twStart}-${twEnd} (每${twInterval}分) · ⚡${formConcurrency}线程`
                    : scheduleMode === "cron"
                    ? `Cron: ${formCron} · ⚡${formConcurrency}线程`
                    : `单次: ${formStartAt || "未指定时间"} · ⚡${formConcurrency}线程`}
                </span>
              </div>
              <div className="flex items-center gap-3 ml-auto">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowModal(false)}
                  disabled={submitting}
                  className="rounded-xl px-4"
                >
                  取消
                </Button>
                <Button
                  size="sm"
                  onClick={() => void handleSave()}
                  disabled={submitting}
                  className="rounded-xl bg-primary hover:bg-primary/90 text-white font-semibold px-5 shadow-sm hover:shadow transition-all"
                >
                  {submitting ? "正在保存..." : editingId !== null ? "保存修改" : "确认创建并启动"}
                </Button>
              </div>
            </div>
          </Card>
        </div>
      )}

      {/* Execution Logs Drawer / Modal */}
      {activeLogSchedule && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-fadeIn">
          <Card className="w-full max-w-3xl max-h-[85vh] flex flex-col p-6 bg-white dark:bg-[#0c1220] border border-slate-200 dark:border-slate-800 shadow-2xl rounded-2xl">
            <div className="flex items-center justify-between pb-3 border-b border-slate-200 dark:border-slate-800">
              <div className="flex items-center gap-2">
                <ActivityIcon size={20} className="text-primary" />
                <h3 className="text-base font-bold text-slate-900 dark:text-white">
                  任务执行日志 — #{activeLogSchedule.id} ({activeLogSchedule.name})
                </h3>
              </div>
              <button
                onClick={() => setActiveLogSchedule(null)}
                className="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 cursor-pointer"
              >
                <CloseIcon size={20} />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto py-4 space-y-3">
              {/* Task Details Summary */}
              <div className="p-3 rounded-xl bg-slate-50 dark:bg-slate-900 text-xs grid grid-cols-2 sm:grid-cols-4 gap-2">
                <div>
                  <span className="text-slate-400 block">Cron 规则:</span>
                  <span className="font-mono font-bold text-primary">{activeLogSchedule.cron || "无"}</span>
                </div>
                <div>
                  <span className="text-slate-400 block">特定开始时间:</span>
                  <span>{activeLogSchedule.start_at || "即刻"}</span>
                </div>
                <div>
                  <span className="text-slate-400 block">下次调度:</span>
                  <span className="text-emerald-600 dark:text-emerald-400 font-mono font-semibold">
                    {activeLogSchedule.next_run_at || "无"}
                  </span>
                </div>
                <div>
                  <span className="text-slate-400 block">上次运行:</span>
                  <span>{activeLogSchedule.last_run_at || "尚未运行"}</span>
                </div>
              </div>

              {/* Logs List from recent_logs */}
              <h5 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mt-2">
                最近执行记录
              </h5>
              {(() => {
                const logs = (schedulerStatus?.recent_logs || []).filter(
                  (l) => l.schedule_id === activeLogSchedule.id
                );
                if (logs.length === 0) {
                  return (
                    <p className="text-xs text-slate-400 py-6 text-center">
                      暂无针对该任务的内存近期日志记录（任务刚创建或尚未到达触发时刻）。
                    </p>
                  );
                }
                return (
                  <div className="space-y-2">
                    {logs.map((l, idx) => (
                      <div
                        key={idx}
                        className="p-3 rounded-xl border border-slate-200 dark:border-slate-800 text-xs space-y-1.5"
                      >
                        <div className="flex items-center justify-between">
                          <span className="font-mono text-slate-400">{l.timestamp}</span>
                          <div className="flex items-center gap-2">
                            {l.concurrency && (
                              <span className="text-[10px] text-indigo-500 font-mono font-semibold">
                                ⚡{l.concurrency}线程
                              </span>
                            )}
                            {l.duration_sec !== undefined && (
                              <span className="text-[10px] text-slate-400 font-mono">
                                {l.duration_sec}s
                              </span>
                            )}
                            {l.status === "success" ? (
                              <Badge variant="success" className="text-[10px] py-0">
                                成功
                              </Badge>
                            ) : (
                              <Badge variant="error" className="text-[10px] py-0">
                                失败
                              </Badge>
                            )}
                          </div>
                        </div>
                        <p className="font-medium text-slate-800 dark:text-slate-200">
                          {l.detail || (l as any).message}
                        </p>
                        {(l as any).result && (
                          <pre className="p-2 rounded-lg bg-slate-900 text-slate-200 text-[11px] overflow-x-auto">
                            {JSON.stringify((l as any).result, null, 2)}
                          </pre>
                        )}
                      </div>
                    ))}
                  </div>
                );
              })()}
            </div>

            <div className="pt-3 border-t border-slate-200 dark:border-slate-800 flex justify-end">
              <Button size="sm" variant="outline" onClick={() => setActiveLogSchedule(null)} className="rounded-xl">
                关闭
              </Button>
            </div>
          </Card>
        </div>
      )}
    </div>
  );
}
