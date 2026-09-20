import { Fragment, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { Spinner } from "@appica/ui-react/spinner";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { ApiError } from "../../lib/api";
import {
  collectorApi,
  LOTTERY_LABEL,
  type CollectResult,
  type CollectorSource,
  type Lottery,
  type ScriptRunResult,
  type ScriptTemplate,
} from "../../lib/collector";
import {
  LOTTERIES,
  PageHeader,
  ReadOnlyNote,
  ResultJson,
  Select,
  Stats,
  TextInput,
  playLabel,
  useCanWrite,
  SectionCard,
  SegmentedTabs,
  StatusPill,
  TableContainer,
  tableThClass,
  tableTdClass,
  tableRowClass,
} from "./shared";
import { ScheduleManager } from "./ScheduleManager";
import {
  ClockIcon,
  DatabaseIcon,
  PlayIcon,
  EditIcon,
  TrashIcon,
  CheckBadgeIcon,
  SparklesIcon,
  RefreshIcon,
  ChevronDownIcon,
  CloseIcon,
} from "../../components/icons";

export function CollectorSourcesPage() {
  const canWrite = useCanWrite();
  const [searchParams, setSearchParams] = useSearchParams();
  const initialTab = searchParams.get("tab") === "schedules" ? "schedules" : "sources";
  const [activeTab, setActiveTab] = useState<"sources" | "schedules">(initialTab);

  const handleTabChange = (tab: "sources" | "schedules") => {
    setActiveTab(tab);
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      if (tab === "schedules") {
        next.set("tab", "schedules");
      } else {
        next.delete("tab");
      }
      return next;
    });
  };

  const [sources, setSources] = useState<CollectorSource[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  // Batch collection state
  const [lottery, setLottery] = useState<Lottery>("macau");
  const [period, setPeriod] = useState("");
  const [fixtureDir, setFixtureDir] = useState("");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<CollectResult | null>(null);

  // Templates & create form
  const [templates, setTemplates] = useState<ScriptTemplate[]>([]);
  const [showCreate, setShowCreate] = useState(false);
  const [creating, setCreating] = useState(false);
  const [createForm, setCreateForm] = useState({
    source_id: "",
    source_name: "",
    lottery: "macau" as Lottery,
    play_type: "pingte_xiao",
    site_family: "dingjian_dashi",
    script_path: "",
    hit_mode: "any",
    enabled: true,
    script: "",
  });

  // Source details
  const [expanded, setExpanded] = useState<string | null>(null);
  const [sourceDetail, setSourceDetail] = useState<any | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  // Script Code Editor Modal
  const [scriptModal, setScriptModal] = useState<{
    open: boolean;
    sourceId: string;
    scriptName: string;
    content: string;
    saving: boolean;
  } | null>(null);

  // Single Script Test Execution Modal
  const [testModal, setTestModal] = useState<{
    open: boolean;
    sourceId: string;
    sourceName: string;
    scriptPath: string;
    lottery: Lottery;
    period: string;
    running: boolean;
    ingest: boolean;
    result: ScriptRunResult | null;
  } | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const [srcs, tmpls] = await Promise.all([
        collectorApi.listSources(),
        collectorApi.getScriptTemplates().catch(() => []),
      ]);
      setSources(srcs);
      setTemplates(tmpls);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "加载来源列表失败");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const visible = useMemo(
    () => (sources ?? []).filter((s) => s.lottery === lottery),
    [sources, lottery],
  );

  const toggleSelect = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const handleApplyTemplate = (tmplId: string) => {
    const tmpl = templates.find((t) => t.id === tmplId);
    if (!tmpl) return;
    let code = tmpl.code;
    if (createForm.source_id) {
      code = code.replace(/SOURCE_ID = "[^"]*"/, `SOURCE_ID = "${createForm.source_id}"`);
    }
    if (createForm.source_name) {
      code = code.replace(/SOURCE_NAME = "[^"]*"/, `SOURCE_NAME = "${createForm.source_name}"`);
    }
    setCreateForm((prev) => ({ ...prev, script: code }));
  };

  const handleCreate = async () => {
    setCreating(true);
    setError(null);
    setSuccessMsg(null);
    try {
      await collectorApi.createSource({
        ...createForm,
        script_path: createForm.script_path || `sources/${createForm.source_id}.py`,
      });
      setShowCreate(false);
      setSuccessMsg(`数据源 ${createForm.source_id} 及其脚本已成功录入！`);
      setCreateForm({
        source_id: "",
        source_name: "",
        lottery: "macau",
        play_type: "pingte_xiao",
        site_family: "dingjian_dashi",
        script_path: "",
        hit_mode: "any",
        enabled: true,
        script: "",
      });
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "创建失败");
    } finally {
      setCreating(false);
    }
  };

  const openScriptEditor = async (s: CollectorSource) => {
    setError(null);
    setSuccessMsg(null);
    const scriptName = s.script_path.replace(/^sources\//, "");
    try {
      const fileData = await collectorApi.readScript(scriptName);
      setScriptModal({
        open: true,
        sourceId: s.source_id,
        scriptName: fileData.name,
        content: fileData.content,
        saving: false,
      });
    } catch {
      const defaultTmpl = templates[0]?.code || "# Custom script\n";
      setScriptModal({
        open: true,
        sourceId: s.source_id,
        scriptName,
        content: defaultTmpl,
        saving: false,
      });
    }
  };

  const saveScriptContent = async () => {
    if (!scriptModal) return;
    setScriptModal((prev) => (prev ? { ...prev, saving: true } : null));
    try {
      await collectorApi.writeScript(scriptModal.scriptName, scriptModal.content);
      setSuccessMsg(`脚本 sources/${scriptModal.scriptName} 保存成功！`);
      setScriptModal(null);
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "保存脚本失败");
      setScriptModal((prev) => (prev ? { ...prev, saving: false } : null));
    }
  };

  const openTestModal = (s: CollectorSource) => {
    setTestModal({
      open: true,
      sourceId: s.source_id,
      sourceName: s.source_name,
      scriptPath: s.script_path,
      lottery: (s.lottery as Lottery) || lottery,
      period: period.trim() || "",
      running: false,
      ingest: false,
      result: null,
    });
  };

  const executeTestRun = async () => {
    if (!testModal) return;
    setTestModal((prev) => (prev ? { ...prev, running: true, result: null } : null));
    setError(null);
    try {
      const res = await collectorApi.testSource(testModal.sourceId, {
        lottery: testModal.lottery,
        period: testModal.period.trim() || undefined,
        ingest: testModal.ingest,
      });
      setTestModal((prev) => (prev ? { ...prev, running: false, result: res } : null));
      if (testModal.ingest && res.ok) {
        setSuccessMsg(`脚本测试执行成功，预测数据已成功入库！`);
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "执行测试失败");
      setTestModal((prev) => (prev ? { ...prev, running: false } : null));
    }
  };

  const runCollect = async () => {
    setRunning(true);
    setError(null);
    setResult(null);
    setSuccessMsg(null);
    try {
      const res = await collectorApi.collect({
        lottery,
        period: period.trim() || undefined,
        source_ids: selected.size ? [...selected] : undefined,
        fixture_dir: fixtureDir.trim() || undefined,
        ingest: true,
      });
      setResult(res);
      setSuccessMsg(`批量采集完成：${res.source_ok}/${res.source_total} 个来源执行成功！已自动入库。`);
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "采集失败");
    } finally {
      setRunning(false);
    }
  };

  const toggleEnabled = async (s: CollectorSource) => {
    try {
      await collectorApi.updateSource(s.source_id, { enabled: !s.enabled });
      await load();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "更新失败");
    }
  };

  const handleDelete = async (sourceId: string) => {
    if (!window.confirm(`确认删除数据源 ${sourceId} 吗？此操作不可恢复。`)) return;
    try {
      await collectorApi.deleteSource(sourceId);
      setSuccessMsg(`数据源 ${sourceId} 已成功删除。`);
      await load();
      if (expanded === sourceId) {
        setExpanded(null);
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "删除失败");
    }
  };

  const toggleExpand = async (sourceId: string) => {
    if (expanded === sourceId) {
      setExpanded(null);
      setSourceDetail(null);
    } else {
      setExpanded(sourceId);
      setSourceDetail(null);
      setDetailLoading(true);
      try {
        const detail = await collectorApi.getSource(sourceId);
        setSourceDetail(detail);
      } catch (err) {
        setSourceDetail({ error: err instanceof ApiError ? err.message : "加载详情失败" });
      } finally {
        setDetailLoading(false);
      }
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title={activeTab === "sources" ? "数据源与脚本采集" : "数据源定时采集任务"}
        desc={
          activeTab === "sources"
            ? "支持录入自定义 Python 爬虫脚本、单脚本在线调试运行、批量采集与标准化入库。"
            : "自动化定时采集调度系统，支持 Linux 5 段 Cron 表达式、指定时间延迟启动及自动对奖评测。"
        }
        right={
          activeTab === "sources" ? (
            canWrite ? (
              <button
                type="button"
                onClick={() => setShowCreate(!showCreate)}
                className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold bg-primary hover:bg-primary/90 text-white shadow-xs transition-all cursor-pointer"
              >
                <SparklesIcon size={16} />
                {showCreate ? "取消录入" : "+ 录入新脚本与数据源"}
              </button>
            ) : (
              <ReadOnlyNote />
            )
          ) : null
        }
      />

      {/* 选项卡切换: 数据源管理 vs 定时采集任务 */}
      <div className="flex items-center justify-between gap-4 flex-wrap pb-1">
        <SegmentedTabs
          tabs={[
            {
              id: "sources",
              label: "数据源采集管理",
              icon: <DatabaseIcon size={16} />,
              count: sources ? sources.length : undefined,
            },
            {
              id: "schedules",
              label: "定时采集调度计划",
              icon: <ClockIcon size={16} />,
            },
          ]}
          activeTab={activeTab}
          onChange={handleTabChange}
        />

        {activeTab === "sources" && (
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={load}
              disabled={loading}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
            >
              <RefreshIcon size={14} className={loading ? "animate-spin" : ""} />
              <span>刷新列表</span>
            </button>
          </div>
        )}
      </div>

      {/* 状态提示信息 */}
      {error && (
        <Alert variant="error" className="rounded-2xl border border-rose-200 dark:border-rose-900/60 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200">
          <AlertDescription className="text-sm font-medium">{error}</AlertDescription>
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

      {/* TAB 2: 定时调度计划管理器 */}
      {activeTab === "schedules" ? (
        <ScheduleManager currentLottery={lottery} allSources={sources ?? []} />
      ) : (
        <>
          {/* 折叠的新建数据源与脚本录入面板 */}
          {showCreate && (
            <SectionCard
              title={
                <div className="flex items-center gap-2">
                  <SparklesIcon size={18} className="text-primary" />
                  <span>录入新脚本采集数据源 (Python Pred.v1)</span>
                </div>
              }
              subtitle="为系统注册一个新的数据抓取脚本，支持自定义爬虫逻辑与命中计算"
              action={
                templates.length > 0 && (
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-slate-500 dark:text-slate-400">代码模版:</span>
                    <select
                      onChange={(e) => handleApplyTemplate(e.target.value)}
                      defaultValue=""
                      className="h-8 px-2.5 rounded-lg border border-slate-200 dark:border-slate-800 bg-white dark:bg-[#0c1220] text-xs font-medium text-slate-800 dark:text-slate-200 cursor-pointer shadow-2xs"
                    >
                      <option value="" disabled>-- 选择代码模版快速填入 --</option>
                      {templates.map((t) => (
                        <option key={t.id} value={t.id}>{t.name}</option>
                      ))}
                    </select>
                  </div>
                )
              }
              className="border-primary/30"
            >
              <div className="space-y-4">
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                  <div>
                    <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                      Source ID * (小写字母下划线)
                    </label>
                    <TextInput
                      value={createForm.source_id}
                      onChange={(v) => {
                        const cleaned = v.toLowerCase().replace(/[^a-z0-9_]/g, "");
                        setCreateForm({
                          ...createForm,
                          source_id: cleaned,
                          script_path: `sources/${cleaned}.py`,
                        });
                      }}
                      placeholder="如 haige_xiao"
                      className="w-full"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                      显示名称 (Display Name) *
                    </label>
                    <TextInput
                      value={createForm.source_name}
                      onChange={(v) => setCreateForm({ ...createForm, source_name: v })}
                      placeholder="如 海哥平特一肖"
                      className="w-full"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                      彩种 (Lottery)
                    </label>
                    <Select
                      value={createForm.lottery}
                      onChange={(v) => setCreateForm({ ...createForm, lottery: v as Lottery })}
                      options={LOTTERIES}
                      className="w-full"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                      玩法类型 (Play Type)
                    </label>
                    <TextInput
                      value={createForm.play_type}
                      onChange={(v) => setCreateForm({ ...createForm, play_type: v })}
                      placeholder="如 pingte_xiao, tema_n, texiao"
                      className="w-full"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                      站群分类 (Site Family)
                    </label>
                    <TextInput
                      value={createForm.site_family}
                      onChange={(v) => setCreateForm({ ...createForm, site_family: v })}
                      placeholder="如 dingjian_dashi, custom_api"
                      className="w-full"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                      脚本文件路径 (Script Path)
                    </label>
                    <TextInput
                      value={createForm.script_path}
                      onChange={(v) => setCreateForm({ ...createForm, script_path: v })}
                      placeholder="如 sources/xxx.py"
                      className="w-full"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                      命中判断模式 (Hit Mode)
                    </label>
                    <Select
                      value={createForm.hit_mode}
                      onChange={(v) => setCreateForm({ ...createForm, hit_mode: v })}
                      options={[
                        { value: "any", label: "Any (命中任意一个即中)" },
                        { value: "all", label: "All (全部预测须全中)" },
                        { value: "none", label: "None (反选不中)" },
                      ]}
                      className="w-full"
                    />
                  </div>
                  <div className="flex items-center pt-6">
                    <label className="flex items-center gap-2 cursor-pointer text-sm font-medium text-slate-700 dark:text-slate-300 select-none">
                      <input
                        type="checkbox"
                        checked={createForm.enabled}
                        onChange={(e) => setCreateForm({ ...createForm, enabled: e.target.checked })}
                        className="w-4 h-4 rounded border-slate-300 text-primary focus:ring-primary/20"
                      />
                      启用该数据源
                    </label>
                  </div>
                </div>

                <div>
                  <div className="flex justify-between items-center mb-1.5">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300">
                      Python 采集脚本代码 (需遵守 pred.v1 输出规范，可从右上角模版载入):
                    </label>
                    <span className="text-xs text-primary font-medium">执行时将使用独立子进程运行</span>
                  </div>
                  <textarea
                    value={createForm.script}
                    onChange={(e) => setCreateForm({ ...createForm, script: e.target.value })}
                    placeholder="# 录入您的 Python 采集脚本代码，或直接留空按默认模版自动生成..."
                    rows={12}
                    spellCheck={false}
                    className="w-full font-mono text-xs sm:text-sm p-4 rounded-xl border border-slate-200 dark:border-slate-800 bg-slate-950 text-emerald-400 leading-relaxed focus:outline-none focus:ring-2 focus:ring-primary/20 shadow-inner"
                  />
                </div>

                <div className="flex justify-end gap-3 pt-2">
                  <button
                    type="button"
                    onClick={() => setShowCreate(false)}
                    className="px-4 py-2 rounded-xl text-sm font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
                  >
                    取消
                  </button>
                  <button
                    type="button"
                    onClick={handleCreate}
                    disabled={creating || !createForm.source_id || !createForm.source_name}
                    className="px-5 py-2 rounded-xl text-sm font-semibold bg-primary hover:bg-primary/90 text-white shadow-xs transition-all disabled:opacity-50 cursor-pointer"
                  >
                    {creating ? "保存录入中..." : "保存并注册脚本"}
                  </button>
                </div>
              </div>
            </SectionCard>
          )}

          {/* 发起批量采集控制卡片 */}
          <SectionCard
            title={
              <div className="flex items-center gap-2">
                <DatabaseIcon size={18} className="text-primary" />
                <span>执行批量采集</span>
              </div>
            }
            subtitle="一键触发当前彩种或已勾选来源的数据抓取与自动入库流程"
          >
            <div className="space-y-3.5">
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
                  placeholder="期号（留空则自动抓取网站当前最新数据）"
                  className="flex-1 min-w-[240px]"
                />
                <TextInput
                  value={fixtureDir}
                  onChange={setFixtureDir}
                  placeholder="离线样例目录（可选）如 fixtures/dingjian"
                  className="min-w-[200px]"
                />
                <button
                  type="button"
                  onClick={runCollect}
                  disabled={!canWrite || running}
                  className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-semibold bg-primary hover:bg-primary/90 text-white shadow-xs transition-all disabled:opacity-50 cursor-pointer whitespace-nowrap"
                >
                  <PlayIcon size={16} />
                  {running
                    ? "采集中…"
                    : selected.size
                    ? `执行选中 ${selected.size} 个来源`
                    : "执行当前彩种全部启用来源"}
                </button>
              </div>

              <div className="flex items-center gap-2 text-xs text-slate-500 dark:text-slate-400">
                <span className="text-primary">💡 提示：</span>
                <span>期号可留空，系统将自动抓取当前目标网站最新发布的所有期数预测入库并自动对奖；若填写期号（如 248），则精准抓取并过滤该指定期数。</span>
              </div>

              {result && (
                <div className="space-y-3 pt-2 border-t border-slate-100 dark:border-slate-800/80">
                  <Stats
                    items={[
                      { label: "运行标识", value: result.run_id },
                      { label: "采集成功", value: `${result.source_ok}/${result.source_total}` },
                      { label: "入库新增", value: result.ingest?.inserted ?? 0 },
                      { label: "更新记录", value: result.ingest?.updated ?? 0 },
                      { label: "补充缺期", value: result.ingest?.missing_added ?? 0 },
                    ]}
                  />
                  <ResultJson data={result} />
                </div>
              )}
            </div>
          </SectionCard>

          {/* 来源列表与操作表格 */}
          <SectionCard
            title={
              <div className="flex items-center gap-3">
                <span>{LOTTERY_LABEL[lottery]}数据源列表</span>
                <span className="text-xs px-2.5 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400 font-semibold border border-slate-200 dark:border-slate-700">
                  共 {visible.length} 个
                </span>
                {selected.size > 0 && (
                  <StatusPill variant="info" dot={false}>
                    已选 {selected.size} 项
                  </StatusPill>
                )}
              </div>
            }
            action={
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => {
                    if (selected.size === visible.length) setSelected(new Set());
                    else setSelected(new Set(visible.map((s) => s.source_id)));
                  }}
                  className="px-3 py-1.5 rounded-xl text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
                >
                  {selected.size === visible.length ? "取消全选" : "全选当前"}
                </button>
              </div>
            }
          >
            {loading ? (
              <div className="p-12 flex justify-center">
                <Spinner aria-label="加载中" />
              </div>
            ) : visible.length === 0 ? (
              <div className="py-12 text-center text-sm text-slate-400">
                该彩种暂无已配置来源。点击右上角录入新脚本与数据源。
              </div>
            ) : (
              <TableContainer>
                <thead>
                  <tr>
                    <th className={`${tableThClass} w-10 text-center`}>
                      <input
                        type="checkbox"
                        checked={visible.length > 0 && selected.size === visible.length}
                        onChange={() => {
                          if (selected.size === visible.length) setSelected(new Set());
                          else setSelected(new Set(visible.map((s) => s.source_id)));
                        }}
                        className="w-4 h-4 rounded border-slate-300 text-primary focus:ring-primary/20 cursor-pointer"
                      />
                    </th>
                    <th className={tableThClass}>数据源名称 / ID</th>
                    <th className={tableThClass}>玩法</th>
                    <th className={tableThClass}>站群</th>
                    <th className={tableThClass}>脚本状态</th>
                    <th className={tableThClass}>启用状态</th>
                    <th className={`${tableThClass} text-right`}>操作</th>
                  </tr>
                </thead>
                <tbody>
                  {visible.map((s) => {
                    const isExpanded = expanded === s.source_id;
                    const isSelected = selected.has(s.source_id);
                    return (
                      <Fragment key={s.source_id}>
                        <tr className={`${tableRowClass} ${isSelected ? "bg-primary/5 dark:bg-primary/10" : ""}`}>
                          <td className={`${tableTdClass} text-center`}>
                            <input
                              type="checkbox"
                              checked={isSelected}
                              onChange={() => toggleSelect(s.source_id)}
                              aria-label={`选择 ${s.source_id}`}
                              className="w-4 h-4 rounded border-slate-300 text-primary focus:ring-primary/20 cursor-pointer"
                            />
                          </td>
                          <td
                            className={`${tableTdClass} cursor-pointer group`}
                            onClick={() => toggleExpand(s.source_id)}
                          >
                            <div className="flex items-center gap-2">
                              <span className="font-semibold text-slate-900 dark:text-white group-hover:text-primary transition-colors">
                                {s.source_name}
                              </span>
                              <ChevronDownIcon
                                size={14}
                                className={`text-slate-400 transition-transform duration-200 ${isExpanded ? "rotate-180" : ""}`}
                              />
                            </div>
                            <div className="text-xs font-mono text-slate-400 mt-0.5">{s.source_id}</div>
                          </td>
                          <td className={tableTdClass}>
                            <span className="text-xs font-medium px-2 py-0.5 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300">
                              {playLabel(s.play_type)}
                            </span>
                          </td>
                          <td className={tableTdClass}>
                            <span className="text-xs font-mono text-slate-500 dark:text-slate-400">
                              {s.site_family}
                            </span>
                          </td>
                          <td className={tableTdClass}>
                            {s.script_exists ? (
                              <StatusPill variant="success">已就绪</StatusPill>
                            ) : (
                              <StatusPill variant="danger">缺失文件</StatusPill>
                            )}
                          </td>
                          <td className={tableTdClass}>
                            <button
                              type="button"
                              onClick={() => toggleEnabled(s)}
                              disabled={!canWrite}
                              className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium border cursor-pointer transition-all ${
                                s.enabled
                                  ? "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-400 border-emerald-200 dark:border-emerald-800"
                                  : "bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400 border-slate-200 dark:border-slate-700"
                              }`}
                            >
                              <span className={`w-1.5 h-1.5 rounded-full ${s.enabled ? "bg-emerald-500" : "bg-slate-400"}`} />
                              <span>{s.enabled ? "已启用" : "已暂停"}</span>
                            </button>
                          </td>
                          <td className={`${tableTdClass} text-right`}>
                            <div className="flex items-center justify-end gap-1.5">
                              <button
                                type="button"
                                onClick={() => openTestModal(s)}
                                className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-medium text-emerald-600 dark:text-emerald-400 hover:bg-emerald-50 dark:hover:bg-emerald-950/40 border border-emerald-200/80 dark:border-emerald-800/60 transition-colors cursor-pointer"
                                title="调试运行此脚本"
                              >
                                <PlayIcon size={13} />
                                <span>测试</span>
                              </button>
                              <button
                                type="button"
                                onClick={() => openScriptEditor(s)}
                                className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-medium text-slate-700 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 border border-slate-200 dark:border-slate-800 transition-colors cursor-pointer"
                                title="编辑 Python 脚本"
                              >
                                <EditIcon size={13} />
                                <span>代码</span>
                              </button>
                              {canWrite && (
                                <button
                                  type="button"
                                  onClick={() => handleDelete(s.source_id)}
                                  className="p-1 rounded-lg text-slate-400 hover:text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-950/40 transition-colors cursor-pointer"
                                  title="删除数据源"
                                >
                                  <TrashIcon size={15} />
                                </button>
                              )}
                            </div>
                          </td>
                        </tr>

                        {/* 展开的详情配置面板 */}
                        {isExpanded && (
                          <tr className="bg-slate-50/70 dark:bg-slate-900/40">
                            <td colSpan={7} className="p-4 sm:p-5 border-b border-slate-200/80 dark:border-slate-800/80">
                              {detailLoading ? (
                                <div className="py-4 flex justify-center">
                                  <Spinner aria-label="加载详情中" />
                                </div>
                              ) : (
                                <div className="space-y-3">
                                  <div className="flex justify-between items-center">
                                    <h4 className="text-xs font-bold text-slate-800 dark:text-slate-200 uppercase tracking-wider">
                                      {s.source_name} 详细配置与入库参数
                                    </h4>
                                    <button
                                      type="button"
                                      onClick={() => void openScriptEditor(s)}
                                      className="inline-flex items-center gap-1.5 px-3 py-1 rounded-lg text-xs font-medium border border-slate-200 dark:border-slate-800 hover:bg-white dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
                                    >
                                      <EditIcon size={13} />
                                      <span>查看/编辑源文件</span>
                                    </button>
                                  </div>
                                  <ResultJson data={sourceDetail} />
                                </div>
                              )}
                            </td>
                          </tr>
                        )}
                      </Fragment>
                    );
                  })}
                </tbody>
              </TableContainer>
            )}
          </SectionCard>
        </>
      )}

      {/* 脚本代码查看与在线编辑弹窗 */}
      {scriptModal?.open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 bg-black/60 backdrop-blur-sm animate-fadeIn">
          <div className="w-full max-w-4xl max-h-[90vh] bg-white dark:bg-[#0c1220] border border-slate-200 dark:border-slate-800 rounded-3xl shadow-2xl flex flex-col overflow-hidden p-6 gap-4">
            <div className="flex justify-between items-center border-b border-slate-100 dark:border-slate-800/80 pb-3">
              <div>
                <h3 className="text-base font-bold text-slate-900 dark:text-white flex items-center gap-2">
                  <EditIcon size={18} className="text-primary" />
                  <span>编辑采集脚本：sources/{scriptModal.scriptName}</span>
                </h3>
                <span className="text-xs text-slate-400 mt-0.5 block">
                  数据源关联: {scriptModal.sourceId}
                </span>
              </div>
              <button
                type="button"
                onClick={() => setScriptModal(null)}
                className="p-1 rounded-lg text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 cursor-pointer"
              >
                <CloseIcon size={20} />
              </button>
            </div>

            <div className="flex-1 flex flex-col gap-2 min-h-0">
              <div className="flex justify-between text-xs text-slate-400">
                <span>Python 脚本源文件内容：</span>
                <span className="font-mono">共 {scriptModal.content.split("\n").length} 行</span>
              </div>
              <textarea
                value={scriptModal.content}
                onChange={(e) => setScriptModal({ ...scriptModal, content: e.target.value })}
                spellCheck={false}
                className="flex-1 min-h-[380px] font-mono text-xs sm:text-sm p-4 rounded-2xl bg-slate-950 text-emerald-400 border border-slate-800 leading-relaxed focus:outline-none focus:ring-2 focus:ring-primary/20 resize-none shadow-inner"
              />
            </div>

            <div className="flex justify-between items-center border-t border-slate-100 dark:border-slate-800/80 pt-4">
              <span className="text-xs text-slate-400">
                保存后将立即写入服务器 sources/ 目录，下次采集或测试时生效。
              </span>
              <div className="flex gap-3">
                <button
                  type="button"
                  onClick={() => setScriptModal(null)}
                  className="px-4 py-2 rounded-xl text-sm font-medium border border-slate-200 dark:border-slate-800 hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 transition-colors cursor-pointer"
                >
                  取消
                </button>
                <button
                  type="button"
                  onClick={saveScriptContent}
                  disabled={scriptModal.saving}
                  className="px-5 py-2 rounded-xl text-sm font-semibold bg-primary hover:bg-primary/90 text-white shadow-xs transition-all disabled:opacity-50 cursor-pointer"
                >
                  {scriptModal.saving ? "保存中..." : "保存脚本代码"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* 单脚本调试执行弹窗 */}
      {testModal?.open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6 bg-black/60 backdrop-blur-sm animate-fadeIn">
          <div className="w-full max-w-4xl max-h-[90vh] bg-white dark:bg-[#0c1220] border border-slate-200 dark:border-slate-800 rounded-3xl shadow-2xl flex flex-col overflow-hidden p-6 gap-4">
            <div className="flex justify-between items-center border-b border-slate-100 dark:border-slate-800/80 pb-3">
              <div>
                <h3 className="text-base font-bold text-slate-900 dark:text-white flex items-center gap-2">
                  <PlayIcon size={18} className="text-emerald-500" />
                  <span>单脚本在线测试运行：{testModal.sourceName}</span>
                </h3>
                <span className="text-xs font-mono text-slate-400 mt-0.5 block">
                  {testModal.scriptPath} ({testModal.sourceId})
                </span>
              </div>
              <button
                type="button"
                onClick={() => setTestModal(null)}
                className="p-1 rounded-lg text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 cursor-pointer"
              >
                <CloseIcon size={20} />
              </button>
            </div>

            {/* 控制参数条 */}
            <div className="p-3.5 rounded-2xl bg-slate-50 dark:bg-slate-900/60 border border-slate-200/80 dark:border-slate-800/80 flex items-center gap-4 flex-wrap">
              <div className="flex items-center gap-2">
                <span className="text-xs font-semibold text-slate-700 dark:text-slate-300">彩种:</span>
                <Select
                  value={testModal.lottery}
                  onChange={(v) => setTestModal({ ...testModal, lottery: v as Lottery })}
                  options={LOTTERIES}
                  className="min-w-[110px]"
                />
              </div>
              <div className="flex items-center gap-2">
                <span className="text-xs font-semibold text-slate-700 dark:text-slate-300">期号:</span>
                <TextInput
                  value={testModal.period}
                  onChange={(v) => setTestModal({ ...testModal, period: v })}
                  placeholder="期号 (留空默认最新)"
                  className="w-36"
                />
              </div>
              <label className="flex items-center gap-2 text-xs font-medium text-slate-700 dark:text-slate-300 cursor-pointer select-none">
                <input
                  type="checkbox"
                  checked={testModal.ingest}
                  onChange={(e) => setTestModal({ ...testModal, ingest: e.target.checked })}
                  className="w-4 h-4 rounded border-slate-300 text-primary focus:ring-primary/20"
                />
                测试成功后自动入库
              </label>
              <button
                type="button"
                onClick={executeTestRun}
                disabled={testModal.running}
                className="ml-auto inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-semibold bg-emerald-600 hover:bg-emerald-500 text-white shadow-xs transition-all disabled:opacity-50 cursor-pointer"
              >
                <PlayIcon size={14} />
                {testModal.running ? "子进程运行中..." : "启动测试运行"}
              </button>
            </div>

            {/* 输出结果 */}
            {testModal.result && (
              <div className="flex-1 flex flex-col gap-3.5 overflow-y-auto min-h-0 pr-1">
                <div className="flex items-center gap-2.5 flex-wrap">
                  {testModal.result.ok ? (
                    <StatusPill variant="success">
                      执行成功 (Exit: {testModal.result.exit_code ?? 0})
                    </StatusPill>
                  ) : (
                    <StatusPill variant="danger">
                      执行失败 ({testModal.result.error_code || "exit " + testModal.result.exit_code})
                    </StatusPill>
                  )}
                  <span className="text-xs text-slate-400">
                    耗时: <strong className="text-slate-700 dark:text-slate-200">{testModal.result.elapsed_ms} ms</strong>
                  </span>
                  <span className="text-xs text-slate-400">
                    提取预测项: <strong className="text-slate-700 dark:text-slate-200">{testModal.result.item_count} 条</strong>
                  </span>
                  {testModal.result.ingest && (
                    <span className="text-xs px-2 py-0.5 rounded-full bg-cyan-500/10 text-cyan-600 dark:text-cyan-400 font-semibold border border-cyan-500/20">
                      入库: 新增 {testModal.result.ingest.inserted}, 更新 {testModal.result.ingest.updated}
                    </span>
                  )}
                </div>

                {testModal.result.error_msg && (
                  <Alert variant="error" className="rounded-xl border border-rose-200 dark:border-rose-900 bg-rose-50/80 dark:bg-rose-950/40 text-rose-800 dark:text-rose-200 py-2.5 px-3">
                    <AlertDescription className="text-xs">{testModal.result.error_msg}</AlertDescription>
                  </Alert>
                )}

                <div>
                  <div className="text-xs font-semibold text-slate-500 dark:text-slate-400 mb-1.5">
                    标准输出与错误日志 (Stdout & Stderr):
                  </div>
                  <pre className="m-0 p-3.5 rounded-2xl bg-slate-950 text-slate-300 border border-slate-800 text-xs font-mono max-h-48 overflow-y-auto leading-relaxed shadow-inner">
                    {testModal.result.stdout || "(无 stdout 输出)"}
                    {testModal.result.stderr ? `\n--- STDERR ---\n${testModal.result.stderr}` : ""}
                  </pre>
                </div>

                {!!testModal.result.data?.items && (
                  <div>
                    <div className="text-xs font-semibold text-slate-500 dark:text-slate-400 mb-1.5">
                      标准化预测数据项 (pred.v1 items):
                    </div>
                    <ResultJson data={testModal.result.data.items} />
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
