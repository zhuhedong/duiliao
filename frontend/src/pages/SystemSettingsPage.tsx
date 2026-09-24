import { useState, useEffect } from "react";
import { PageHeader } from "./collector/shared";
import {
  SparklesIcon,
  EyeIcon,
  EyeOffIcon,
  CheckBadgeIcon,
  ActivityIcon,
  ShieldIcon,
  DatabaseIcon,
  UploadIcon,
  RefreshIcon,
} from "../components/icons";
import {
  settingsApi,
  databaseApi,
  type AISettings,
  type AITestResult,
  type DatabaseStatus,
  type DBTestResult,
  type SqliteInspectResult,
  type SqliteImportResult,
  type SchemaVerifyResult,
  type SchemaRepairResult,
} from "../lib/api";

interface PresetConfig {
  name: string;
  base_url: string;
  model: string;
  badge: string;
}

const OPENAI_PRESETS: PresetConfig[] = [
  {
    name: "DeepSeek 官方 (推荐)",
    base_url: "https://api.deepseek.com/v1",
    model: "deepseek-chat",
    badge: "超高性价比/精准",
  },
  {
    name: "OpenAI 官方",
    base_url: "https://api.openai.com/v1",
    model: "gpt-4o",
    badge: "全球通用",
  },
  {
    name: "Kimi / 月之暗面",
    base_url: "https://api.moonshot.cn/v1",
    model: "moonshot-v1-8k",
    badge: "超长文本",
  },
  {
    name: "阿里通义千问 (Qwen)",
    base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
    model: "qwen-plus",
    badge: "阿里百炼兼容",
  },
  {
    name: "本地 Ollama",
    base_url: "http://localhost:11434/v1",
    model: "qwen2.5:7b",
    badge: "私有化/无费用",
  },
];

export function SystemSettingsPage() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saveSuccess, setSaveSuccess] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // Active tab
  const [activeTab, setActiveTab] = useState<"ai" | "database" | "system">("ai");

  // Database Management State
  const [dbStatus, setDbStatus] = useState<DatabaseStatus | null>(null);
  const [loadingDb, setLoadingDb] = useState(false);
  const [dbError, setDbError] = useState<string | null>(null);
  const [pgUrl, setPgUrl] = useState("");
  const [collectorPgUrl, setCollectorPgUrl] = useState("");
  const [testingPg, setTestingPg] = useState(false);
  const [pgTestResult, setPgTestResult] = useState<DBTestResult | null>(null);
  const [savingDb, setSavingDb] = useState(false);
  const [dbSaveSuccess, setDbSaveSuccess] = useState(false);

  // Schema Verification & Repair State
  const [schemaReport, setSchemaReport] = useState<SchemaVerifyResult | null>(null);
  const [checkingSchema, setCheckingSchema] = useState(false);
  const [repairingSchema, setRepairingSchema] = useState(false);
  const [repairResult, setRepairResult] = useState<SchemaRepairResult | null>(null);
  const [schemaError, setSchemaError] = useState<string | null>(null);

  // SQLite Import State
  const [sqliteFile, setSqliteFile] = useState<File | null>(null);
  const [fileBase64, setFileBase64] = useState<string>("");
  const [inspecting, setInspecting] = useState(false);
  const [inspectResult, setInspectResult] = useState<SqliteInspectResult | null>(null);
  const [selectedTables, setSelectedTables] = useState<string[]>([]);
  const [importMode, setImportMode] = useState<"skip" | "overwrite">("skip");
  const [importing, setImporting] = useState(false);
  const [importResult, setImportResult] = useState<SqliteImportResult | null>(null);
  const [importError, setImportError] = useState<string | null>(null);
  const [isDragOver, setIsDragOver] = useState(false);

  // AI Settings State
  const [defaultProvider, setDefaultProvider] = useState("openai");

  const [openaiBaseUrl, setOpenaiBaseUrl] = useState("https://api.openai.com/v1");
  const [openaiKey, setOpenaiKey] = useState("");
  const [openaiModel, setOpenaiModel] = useState("deepseek-chat");
  const [openaiConfigured, setOpenaiConfigured] = useState(false);

  const [geminiBaseUrl, setGeminiBaseUrl] = useState("https://generativelanguage.googleapis.com");
  const [geminiKey, setGeminiKey] = useState("");
  const [geminiModel, setGeminiModel] = useState("gemini-2.5-flash");
  const [geminiConfigured, setGeminiConfigured] = useState(false);

  const [anthropicBaseUrl, setAnthropicBaseUrl] = useState("https://api.anthropic.com");
  const [anthropicKey, setAnthropicKey] = useState("");
  const [anthropicModel, setAnthropicModel] = useState("claude-3-5-sonnet-20241022");
  const [anthropicConfigured, setAnthropicConfigured] = useState(false);

  // Key visibility
  const [showKey, setShowKey] = useState<Record<string, boolean>>({
    openai: false,
    gemini: false,
    anthropic: false,
  });

  // Connectivity test state
  const [testing, setTesting] = useState<Record<string, boolean>>({});
  const [testResult, setTestResult] = useState<Record<string, AITestResult | null>>({});

  useEffect(() => {
    loadSettings();
    loadDbStatus();
    loadSchemaReport();
  }, []);

  const loadSettings = async () => {
    setLoading(true);
    try {
      const res: AISettings = await settingsApi.getAISettings();
      setDefaultProvider(res.default_provider || "openai");

      if (res.openai) {
        setOpenaiBaseUrl(res.openai.base_url || "https://api.openai.com/v1");
        setOpenaiKey(res.openai.api_key || "");
        setOpenaiModel(res.openai.model || "deepseek-chat");
        setOpenaiConfigured(res.openai.is_configured);
      }

      if (res.gemini) {
        setGeminiBaseUrl(res.gemini.base_url || "https://generativelanguage.googleapis.com");
        setGeminiKey(res.gemini.api_key || "");
        setGeminiModel(res.gemini.model || "gemini-2.5-flash");
        setGeminiConfigured(res.gemini.is_configured);
      }

      if (res.anthropic) {
        setAnthropicBaseUrl(res.anthropic.base_url || "https://api.anthropic.com");
        setAnthropicKey(res.anthropic.api_key || "");
        setAnthropicModel(res.anthropic.model || "claude-3-5-sonnet-20241022");
        setAnthropicConfigured(res.anthropic.is_configured);
      }
    } catch (err: any) {
      setSaveError(err?.message || "加载系统配置失败");
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async () => {
    setSaving(true);
    setSaveSuccess(false);
    setSaveError(null);

    try {
      const payload = {
        default_provider: defaultProvider,
        openai: {
          base_url: openaiBaseUrl.trim(),
          api_key: openaiKey.trim(),
          model: openaiModel.trim(),
        },
        gemini: {
          base_url: geminiBaseUrl.trim(),
          api_key: geminiKey.trim(),
          model: geminiModel.trim(),
        },
        anthropic: {
          base_url: anthropicBaseUrl.trim(),
          api_key: anthropicKey.trim(),
          model: anthropicModel.trim(),
        },
      };

      const updated = await settingsApi.updateAISettings(payload);
      setOpenaiConfigured(updated.openai.is_configured);
      setGeminiConfigured(updated.gemini.is_configured);
      setAnthropicConfigured(updated.anthropic.is_configured);

      // Re-populate masked keys
      setOpenaiKey(updated.openai.api_key || "");
      setGeminiKey(updated.gemini.api_key || "");
      setAnthropicKey(updated.anthropic.api_key || "");

      setSaveSuccess(true);
      setTimeout(() => setSaveSuccess(false), 3500);
    } catch (err: any) {
      setSaveError(err?.message || "保存配置失败，请检查网络");
    } finally {
      setSaving(false);
    }
  };

  const handleTestConnection = async (provider: string) => {
    setTesting((prev) => ({ ...prev, [provider]: true }));
    setTestResult((prev) => ({ ...prev, [provider]: null }));

    try {
      let url = "";
      let key = "";
      let m = "";

      if (provider === "openai") {
        url = openaiBaseUrl;
        key = openaiKey;
        m = openaiModel;
      } else if (provider === "gemini") {
        url = geminiBaseUrl;
        key = geminiKey;
        m = geminiModel;
      } else if (provider === "anthropic") {
        url = anthropicBaseUrl;
        key = anthropicKey;
        m = anthropicModel;
      }

      const res = await settingsApi.testAIConnection({
        provider,
        base_url: url,
        api_key: key,
        model: m,
      });

      setTestResult((prev) => ({ ...prev, [provider]: res }));
    } catch (err: any) {
      setTestResult((prev) => ({
        ...prev,
        [provider]: {
          ok: false,
          message: err?.message || "网络请求异常",
          elapsed_ms: 0,
          error: String(err),
        },
      }));
    } finally {
      setTesting((prev) => ({ ...prev, [provider]: false }));
    }
  };

  const loadDbStatus = async () => {
    setLoadingDb(true);
    setDbError(null);
    try {
      const res = await databaseApi.getStatus();
      setDbStatus(res);
      if (!pgUrl) {
        if (res.app_db.engine === "postgresql" && res.app_db.url) {
          setPgUrl(res.app_db.url);
        }
      }
    } catch (err: any) {
      setDbError(err?.message || "获取数据库状态失败");
    } finally {
      setLoadingDb(false);
    }
  };

  const loadSchemaReport = async () => {
    setCheckingSchema(true);
    setSchemaError(null);
    try {
      const res = await databaseApi.verifySchema();
      setSchemaReport(res);
    } catch (err: any) {
      setSchemaError(err?.message || "表结构检测失败");
    } finally {
      setCheckingSchema(false);
    }
  };

  const handleRepairSchema = async () => {
    setRepairingSchema(true);
    setSchemaError(null);
    setRepairResult(null);
    try {
      const res = await databaseApi.repairSchema({ scope: "all", seed: true });
      setRepairResult(res);
      setSchemaReport(res.after);
      // Row counts change once reference data is reseeded.
      loadDbStatus();
    } catch (err: any) {
      setSchemaError(err?.message || "补齐缺失表失败");
    } finally {
      setRepairingSchema(false);
    }
  };

  const handleTestPg = async () => {
    if (!pgUrl.trim()) return;
    setTestingPg(true);
    setPgTestResult(null);
    try {
      const res = await databaseApi.testConnection(pgUrl.trim());
      setPgTestResult(res);
    } catch (err: any) {
      setPgTestResult({ ok: false, error: err?.message || "网络请求异常" });
    } finally {
      setTestingPg(false);
    }
  };

  const handleSaveDbConfig = async () => {
    if (!pgUrl.trim()) return;
    setSavingDb(true);
    setDbError(null);
    try {
      const res = await databaseApi.saveConfig({
        database_url: pgUrl.trim(),
        collector_database_url: collectorPgUrl.trim() || undefined,
      });
      setDbStatus(res);
      setDbSaveSuccess(true);
      setTimeout(() => setDbSaveSuccess(false), 4000);
    } catch (err: any) {
      setDbError(err?.message || "保存数据库配置失败");
    } finally {
      setSavingDb(false);
    }
  };

  const handleFileSelected = (file: File) => {
    if (!file.name.match(/\.(db|sqlite|sqlite3)$/i)) {
      setImportError("请选择有效的 SQLite 文件 (.db, .sqlite, .sqlite3)");
      return;
    }
    setSqliteFile(file);
    setImportResult(null);
    setImportError(null);
    setInspecting(true);

    const reader = new FileReader();
    reader.onload = async () => {
      try {
        const full = reader.result as string;
        const b64 = full.includes(",") ? full.split(",")[1] : full;
        setFileBase64(b64);
        const insp = await databaseApi.inspectSqlite(file.name, b64);
        setInspectResult(insp);
        setSelectedTables(insp.tables.map((t) => t.name));
      } catch (err: any) {
        setImportError(err?.message || "解析 SQLite 文件失败");
      } finally {
        setInspecting(false);
      }
    };
    reader.onerror = () => {
      setImportError("读取文件失败");
      setInspecting(false);
    };
    reader.readAsDataURL(file);
  };

  const handleStartImport = async () => {
    if (!sqliteFile || !fileBase64) return;
    setImporting(true);
    setImportError(null);
    try {
      const res = await databaseApi.importSqlite({
        filename: sqliteFile.name,
        content_base64: fileBase64,
        mode: importMode,
        tables: selectedTables.length > 0 ? selectedTables : undefined,
      });
      setImportResult(res);
      loadDbStatus();
    } catch (err: any) {
      setImportError(err?.message || "数据导入发生异常");
    } finally {
      setImporting(false);
    }
  };

  const applyPreset = (preset: PresetConfig) => {
    setOpenaiBaseUrl(preset.base_url);
    setOpenaiModel(preset.model);
  };

  return (
    <div className="space-y-6 max-w-5xl">
      {/* Top Header */}
      <PageHeader
        title="系统设置"
        desc="配置大语言模型（LLM）调用地址、API 鉴权密钥、PostgreSQL 数据库及数据导入。"
        right={
          activeTab === "ai" ? (
            <div className="flex items-center gap-2">
              <button
                onClick={handleSave}
                disabled={saving || loading}
                className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-semibold glow-button border-0 transition-all disabled:opacity-50 cursor-pointer"
              >
                <CheckBadgeIcon size={18} />
                {saving ? "正在保存..." : "保存 AI 配置"}
              </button>
            </div>
          ) : activeTab === "database" ? (
            <div className="flex items-center gap-2">
              <button
                onClick={() => {
                  loadDbStatus();
                  loadSchemaReport();
                }}
                disabled={loadingDb || checkingSchema}
                className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium glass-subtle hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 transition-all cursor-pointer"
              >
                <RefreshIcon size={16} className={loadingDb || checkingSchema ? "animate-spin" : ""} />
                刷新数据库状态
              </button>
            </div>
          ) : undefined
        }
      />

      {/* Status Alerts */}
      {saveSuccess && (
        <div className="p-4 rounded-xl bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 text-emerald-700 dark:text-emerald-300 text-sm flex items-center gap-2 animate-fadeIn backdrop-blur-md">
          <CheckBadgeIcon size={18} />
          <span>系统 AI 配置已成功保存并立即全局生效！</span>
        </div>
      )}

      {dbSaveSuccess && (
        <div className="p-4 rounded-xl bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 text-emerald-700 dark:text-emerald-300 text-sm flex items-center gap-2 animate-fadeIn backdrop-blur-md">
          <CheckBadgeIcon size={18} />
          <span>数据库配置已成功应用并重新建立连接池！</span>
        </div>
      )}

      {saveError && (
        <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-400/40 dark:border-rose-400/25 text-rose-700 dark:text-rose-300 text-sm flex items-center justify-between backdrop-blur-md">
          <span>{saveError}</span>
          <button
            onClick={() => setSaveError(null)}
            className="text-xs font-semibold hover:underline"
          >
            关闭
          </button>
        </div>
      )}

      {dbError && (
        <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-400/40 dark:border-rose-400/25 text-rose-700 dark:text-rose-300 text-sm flex items-center justify-between backdrop-blur-md">
          <span>{dbError}</span>
          <button
            onClick={() => setDbError(null)}
            className="text-xs font-semibold hover:underline"
          >
            关闭
          </button>
        </div>
      )}

      {schemaError && (
        <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-400/40 dark:border-rose-400/25 text-rose-700 dark:text-rose-300 text-sm flex items-center justify-between backdrop-blur-md">
          <span>{schemaError}</span>
          <button
            onClick={() => setSchemaError(null)}
            className="text-xs font-semibold hover:underline"
          >
            关闭
          </button>
        </div>
      )}

      {/* Tabs */}
      <div className="inline-flex items-center gap-1 p-1 rounded-2xl glass-subtle max-w-full overflow-x-auto">
        <button
          onClick={() => setActiveTab("ai")}
          className={`inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-sm font-medium transition-all cursor-pointer whitespace-nowrap ${
            activeTab === "ai"
              ? "text-violet-700 dark:text-violet-200 bg-gradient-to-r from-violet-500/15 via-fuchsia-500/10 to-transparent border border-violet-400/30 dark:border-violet-400/25 shadow-[0_4px_16px_-6px_rgba(139,92,246,0.35)] font-semibold"
              : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white border border-transparent"
          }`}
        >
          <SparklesIcon size={16} />
          AI 模型与密钥设置
        </button>
        <button
          onClick={() => {
            setActiveTab("database");
            loadDbStatus();
            loadSchemaReport();
          }}
          className={`inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-sm font-medium transition-all cursor-pointer whitespace-nowrap ${
            activeTab === "database"
              ? "text-violet-700 dark:text-violet-200 bg-gradient-to-r from-violet-500/15 via-fuchsia-500/10 to-transparent border border-violet-400/30 dark:border-violet-400/25 shadow-[0_4px_16px_-6px_rgba(139,92,246,0.35)] font-semibold"
              : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white border border-transparent"
          }`}
        >
          <DatabaseIcon size={16} />
          数据库与数据迁移
        </button>
        <button
          onClick={() => setActiveTab("system")}
          className={`inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-sm font-medium transition-all cursor-pointer whitespace-nowrap ${
            activeTab === "system"
              ? "text-violet-700 dark:text-violet-200 bg-gradient-to-r from-violet-500/15 via-fuchsia-500/10 to-transparent border border-violet-400/30 dark:border-violet-400/25 shadow-[0_4px_16px_-6px_rgba(139,92,246,0.35)] font-semibold"
              : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white border border-transparent"
          }`}
        >
          <ActivityIcon size={16} />
          系统环境与安全
        </button>
      </div>

      {loading ? (
        <div className="py-24 flex flex-col items-center justify-center space-y-3 text-slate-400 dark:text-slate-500">
          <div className="w-10 h-10 border-4 border-violet-500/20 border-t-violet-500 rounded-full animate-spin" />
          <p className="text-sm">正在加载系统配置...</p>
        </div>
      ) : (
        <>
          {/* TAB 1: AI Settings */}
          {activeTab === "ai" && (
            <div className="space-y-6">
              {/* Default Provider Card */}
              <div className="p-6 rounded-3xl glass-card space-y-4">
                <div>
                  <h3 className="text-base font-bold text-slate-900 dark:text-white flex items-center gap-2">
                    <SparklesIcon size={18} className="text-violet-600 dark:text-violet-300" />
                    系统默认 AI 研判服务商
                  </h3>
                  <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">
                    在【AI研判】和后台批量对料任务中，未特别指定时将默认调用此服务商。
                  </p>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  {[
                    {
                      id: "openai",
                      label: "OpenAI / DeepSeek 兼容",
                      desc: "支持 DeepSeek、Qwen、Kimi 及本地 Ollama",
                      configured: openaiConfigured,
                    },
                    {
                      id: "gemini",
                      label: "Google Gemini",
                      desc: "官方 Gemini 2.5 Flash / Pro",
                      configured: geminiConfigured,
                    },
                    {
                      id: "anthropic",
                      label: "Anthropic Claude",
                      desc: "官方 Claude 3.5 Sonnet",
                      configured: anthropicConfigured,
                    },
                  ].map((item) => (
                    <div
                      key={item.id}
                      onClick={() => setDefaultProvider(item.id)}
                      className={`p-4 rounded-2xl glass-subtle transition-all cursor-pointer flex flex-col justify-between ${
                        defaultProvider === item.id
                          ? "border-violet-400/50 dark:border-violet-400/35 shadow-[0_8px_24px_-8px_rgba(139,92,246,0.35)] ring-1 ring-violet-400/30"
                          : "hover:border-violet-400/40 dark:hover:border-violet-400/30"
                      }`}
                    >
                      <div>
                        <div className="flex items-center justify-between">
                          <span className="font-semibold text-sm text-slate-900 dark:text-white">
                            {item.label}
                          </span>
                          <input
                            type="radio"
                            name="default_provider"
                            checked={defaultProvider === item.id}
                            onChange={() => setDefaultProvider(item.id)}
                            className="accent-violet-600 dark:accent-violet-400 h-4 w-4"
                          />
                        </div>
                        <p className="text-xs text-slate-500 dark:text-slate-400 mt-1.5 leading-relaxed">
                          {item.desc}
                        </p>
                      </div>
                      <div className="mt-3 pt-2 border-t border-slate-200/50 dark:border-white/8 flex items-center justify-between text-2xs">
                        <span className="text-slate-400 dark:text-slate-500">密钥状态</span>
                        {item.configured ? (
                          <span className="text-emerald-600 dark:text-emerald-400 font-medium flex items-center gap-1">
                            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
                            已配置
                          </span>
                        ) : (
                          <span className="text-amber-600 dark:text-amber-300 font-medium flex items-center gap-1">
                            <span className="w-1.5 h-1.5 rounded-full bg-amber-500" />
                            未配置
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* CARD 1: OpenAI / DeepSeek / 兼容 */}
              <div className="p-6 rounded-3xl glass-card space-y-5">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="text-base font-bold text-slate-900 dark:text-white">
                        OpenAI / DeepSeek / 兼容协议配置
                      </h3>
                      {openaiConfigured ? (
                        <span className="px-2 py-0.5 rounded-full text-2xs font-semibold bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md">
                          已配置密钥
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 rounded-full text-2xs font-semibold bg-amber-500/10 text-amber-700 dark:text-amber-300 border border-amber-400/40 dark:border-amber-400/25 backdrop-blur-md">
                          待配置
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                      标准 OpenAI Chat Completions 协议，广泛兼容各大国产大模型与私有化部署。
                    </p>
                  </div>

                  <button
                    onClick={() => handleTestConnection("openai")}
                    disabled={testing["openai"]}
                    className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-semibold glass-subtle hover:bg-violet-500/10 dark:hover:bg-violet-400/10 text-slate-700 dark:text-slate-200 transition-colors disabled:opacity-50 cursor-pointer"
                  >
                    <ActivityIcon size={14} />
                    {testing["openai"] ? "正在测试连通性..." : "测试连接"}
                  </button>
                </div>

                {/* Quick Presets */}
                <div className="space-y-1.5">
                  <div className="text-xs font-semibold text-slate-500 dark:text-slate-400">
                    一键填入主流厂商地址与推荐模型：
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {OPENAI_PRESETS.map((preset) => (
                      <button
                        key={preset.name}
                        onClick={() => applyPreset(preset)}
                        className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-medium glass-subtle hover:bg-violet-500/10 hover:text-violet-700 dark:hover:bg-violet-400/10 dark:hover:text-violet-300 text-slate-700 dark:text-slate-300 transition-all cursor-pointer"
                      >
                        <span>{preset.name}</span>
                        <span className="text-2xs text-slate-400 dark:text-slate-500 font-mono">({preset.badge})</span>
                      </button>
                    ))}
                  </div>
                </div>

                {/* Form Fields */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-1.5 md:col-span-2">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300">
                      API 基础地址 (Base URL)
                    </label>
                    <input
                      type="text"
                      value={openaiBaseUrl}
                      onChange={(e) => setOpenaiBaseUrl(e.target.value)}
                      placeholder="例如：https://api.deepseek.com/v1 或 https://api.openai.com/v1"
                      className="w-full h-10 px-3.5 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                    />
                  </div>

                  <div className="space-y-1.5">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300 flex items-center justify-between">
                      <span>API 密钥 (API Key)</span>
                      <span className="text-2xs font-normal text-slate-400 dark:text-slate-500">
                        留空或保留••••掩码即表示不修改原密钥
                      </span>
                    </label>
                    <div className="relative">
                      <input
                        type={showKey["openai"] ? "text" : "password"}
                        value={openaiKey}
                        onChange={(e) => setOpenaiKey(e.target.value)}
                        placeholder="sk-..."
                        className="w-full h-10 pl-3.5 pr-10 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                      />
                      <button
                        type="button"
                        onClick={() =>
                          setShowKey((prev) => ({ ...prev, openai: !prev.openai }))
                        }
                        className="absolute right-3 top-2.5 text-slate-400 dark:text-slate-500 hover:text-slate-600 dark:hover:text-slate-200"
                      >
                        {showKey["openai"] ? <EyeOffIcon size={16} /> : <EyeIcon size={16} />}
                      </button>
                    </div>
                  </div>

                  <div className="space-y-1.5">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300">
                      默认模型名称 (Default Model)
                    </label>
                    <input
                      type="text"
                      value={openaiModel}
                      onChange={(e) => setOpenaiModel(e.target.value)}
                      placeholder="deepseek-chat, gpt-4o, qwen-plus..."
                      className="w-full h-10 px-3.5 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                    />
                  </div>
                </div>

                {/* Test Result Message */}
                {testResult["openai"] && (
                  <div
                    className={`p-3 rounded-xl text-xs flex items-center justify-between ${
                      testResult["openai"].ok
                        ? "bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 text-emerald-700 dark:text-emerald-300 backdrop-blur-md"
                        : "bg-rose-500/10 border border-rose-400/40 dark:border-rose-400/25 text-rose-700 dark:text-rose-300 backdrop-blur-md"
                    }`}
                  >
                    <span>{testResult["openai"].message}</span>
                    <span className="font-mono text-2xs opacity-80">
                      {testResult["openai"].elapsed_ms > 0 && `${testResult["openai"].elapsed_ms}ms`}
                    </span>
                  </div>
                )}
              </div>

              {/* CARD 2: Google Gemini */}
              <div className="p-6 rounded-3xl glass-card space-y-5">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="text-base font-bold text-slate-900 dark:text-white">
                        Google Gemini 配置
                      </h3>
                      {geminiConfigured ? (
                        <span className="px-2 py-0.5 rounded-full text-2xs font-semibold bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md">
                          已配置密钥
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 rounded-full text-2xs font-semibold bg-amber-500/10 text-amber-700 dark:text-amber-300 border border-amber-400/40 dark:border-amber-400/25 backdrop-blur-md">
                          待配置
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                      使用 Google AI Studio 提供的 Gemini API 密钥。
                    </p>
                  </div>

                  <button
                    onClick={() => handleTestConnection("gemini")}
                    disabled={testing["gemini"]}
                    className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-semibold glass-subtle hover:bg-violet-500/10 dark:hover:bg-violet-400/10 text-slate-700 dark:text-slate-200 transition-colors disabled:opacity-50 cursor-pointer"
                  >
                    <ActivityIcon size={14} />
                    {testing["gemini"] ? "正在测试连通性..." : "测试连接"}
                  </button>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-1.5 md:col-span-2">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300">
                      API 基础地址 (Base URL)
                    </label>
                    <input
                      type="text"
                      value={geminiBaseUrl}
                      onChange={(e) => setGeminiBaseUrl(e.target.value)}
                      placeholder="https://generativelanguage.googleapis.com"
                      className="w-full h-10 px-3.5 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                    />
                  </div>

                  <div className="space-y-1.5">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300 flex items-center justify-between">
                      <span>API 密钥 (API Key)</span>
                      <span className="text-2xs font-normal text-slate-400 dark:text-slate-500">
                        留空或保留••••掩码即不修改
                      </span>
                    </label>
                    <div className="relative">
                      <input
                        type={showKey["gemini"] ? "text" : "password"}
                        value={geminiKey}
                        onChange={(e) => setGeminiKey(e.target.value)}
                        placeholder="AIzaSy..."
                        className="w-full h-10 pl-3.5 pr-10 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                      />
                      <button
                        type="button"
                        onClick={() =>
                          setShowKey((prev) => ({ ...prev, gemini: !prev.gemini }))
                        }
                        className="absolute right-3 top-2.5 text-slate-400 dark:text-slate-500 hover:text-slate-600 dark:hover:text-slate-200"
                      >
                        {showKey["gemini"] ? <EyeOffIcon size={16} /> : <EyeIcon size={16} />}
                      </button>
                    </div>
                  </div>

                  <div className="space-y-1.5">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300">
                      默认模型名称 (Default Model)
                    </label>
                    <input
                      type="text"
                      value={geminiModel}
                      onChange={(e) => setGeminiModel(e.target.value)}
                      placeholder="gemini-2.5-flash, gemini-1.5-pro..."
                      className="w-full h-10 px-3.5 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                    />
                  </div>
                </div>

                {testResult["gemini"] && (
                  <div
                    className={`p-3 rounded-xl text-xs flex items-center justify-between ${
                      testResult["gemini"].ok
                        ? "bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 text-emerald-700 dark:text-emerald-300 backdrop-blur-md"
                        : "bg-rose-500/10 border border-rose-400/40 dark:border-rose-400/25 text-rose-700 dark:text-rose-300 backdrop-blur-md"
                    }`}
                  >
                    <span>{testResult["gemini"].message}</span>
                    <span className="font-mono text-2xs opacity-80">
                      {testResult["gemini"].elapsed_ms > 0 && `${testResult["gemini"].elapsed_ms}ms`}
                    </span>
                  </div>
                )}
              </div>

              {/* CARD 3: Anthropic Claude */}
              <div className="p-6 rounded-3xl glass-card space-y-5">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <div>
                    <div className="flex items-center gap-2">
                      <h3 className="text-base font-bold text-slate-900 dark:text-white">
                        Anthropic Claude 配置
                      </h3>
                      {anthropicConfigured ? (
                        <span className="px-2 py-0.5 rounded-full text-2xs font-semibold bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md">
                          已配置密钥
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 rounded-full text-2xs font-semibold bg-amber-500/10 text-amber-700 dark:text-amber-300 border border-amber-400/40 dark:border-amber-400/25 backdrop-blur-md">
                          待配置
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                      官方 Anthropic API，支持 Claude 3.5 Sonnet 及 Haiku 系列模型。
                    </p>
                  </div>

                  <button
                    onClick={() => handleTestConnection("anthropic")}
                    disabled={testing["anthropic"]}
                    className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-semibold glass-subtle hover:bg-violet-500/10 dark:hover:bg-violet-400/10 text-slate-700 dark:text-slate-200 transition-colors disabled:opacity-50 cursor-pointer"
                  >
                    <ActivityIcon size={14} />
                    {testing["anthropic"] ? "正在测试连通性..." : "测试连接"}
                  </button>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="space-y-1.5 md:col-span-2">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300">
                      API 基础地址 (Base URL)
                    </label>
                    <input
                      type="text"
                      value={anthropicBaseUrl}
                      onChange={(e) => setAnthropicBaseUrl(e.target.value)}
                      placeholder="https://api.anthropic.com"
                      className="w-full h-10 px-3.5 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                    />
                  </div>

                  <div className="space-y-1.5">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300 flex items-center justify-between">
                      <span>API 密钥 (API Key)</span>
                      <span className="text-2xs font-normal text-slate-400 dark:text-slate-500">
                        留空或保留••••掩码即不修改
                      </span>
                    </label>
                    <div className="relative">
                      <input
                        type={showKey["anthropic"] ? "text" : "password"}
                        value={anthropicKey}
                        onChange={(e) => setAnthropicKey(e.target.value)}
                        placeholder="sk-ant-..."
                        className="w-full h-10 pl-3.5 pr-10 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                      />
                      <button
                        type="button"
                        onClick={() =>
                          setShowKey((prev) => ({ ...prev, anthropic: !prev.anthropic }))
                        }
                        className="absolute right-3 top-2.5 text-slate-400 dark:text-slate-500 hover:text-slate-600 dark:hover:text-slate-200"
                      >
                        {showKey["anthropic"] ? (
                          <EyeOffIcon size={16} />
                        ) : (
                          <EyeIcon size={16} />
                        )}
                      </button>
                    </div>
                  </div>

                  <div className="space-y-1.5">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300">
                      默认模型名称 (Default Model)
                    </label>
                    <input
                      type="text"
                      value={anthropicModel}
                      onChange={(e) => setAnthropicModel(e.target.value)}
                      placeholder="claude-3-5-sonnet-20241022..."
                      className="w-full h-10 px-3.5 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                    />
                  </div>
                </div>

                {testResult["anthropic"] && (
                  <div
                    className={`p-3 rounded-xl text-xs flex items-center justify-between ${
                      testResult["anthropic"].ok
                        ? "bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 text-emerald-700 dark:text-emerald-300 backdrop-blur-md"
                        : "bg-rose-500/10 border border-rose-400/40 dark:border-rose-400/25 text-rose-700 dark:text-rose-300 backdrop-blur-md"
                    }`}
                  >
                    <span>{testResult["anthropic"].message}</span>
                    <span className="font-mono text-2xs opacity-80">
                      {testResult["anthropic"].elapsed_ms > 0 &&
                        `${testResult["anthropic"].elapsed_ms}ms`}
                    </span>
                  </div>
                )}
              </div>

              {/* Bottom Action Bar */}
              <div className="p-4 rounded-2xl glass-bar flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div className="text-xs text-slate-500 dark:text-slate-400">
                  <span>💡 提示：配置保存后将通过<strong>数据库 + .env 双重持久化</strong>，无论重启后端、重启前端或切换运行目录均永久有效。</span>
                </div>
                <div className="flex items-center gap-3 shrink-0">
                  {saveSuccess && (
                    <span className="text-xs font-semibold text-emerald-600 dark:text-emerald-400 flex items-center gap-1">
                      <CheckBadgeIcon size={16} />
                      配置已永久保存成功！
                    </span>
                  )}
                  <button
                    onClick={handleSave}
                    disabled={saving || loading}
                    className="inline-flex items-center gap-2 px-6 py-2.5 rounded-xl text-sm font-semibold glow-button border-0 transition-all disabled:opacity-50 cursor-pointer"
                  >
                    <CheckBadgeIcon size={18} />
                    {saving ? "正在保存中..." : "保存所有配置"}
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: Database Management & Migration */}
          {activeTab === "database" && (
            <div className="space-y-6">
              {/* Card 1: Database Status & Stats */}
              <div className="p-6 rounded-3xl glass-card space-y-5">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                  <div className="flex items-center gap-2">
                    <DatabaseIcon size={20} className="text-violet-600 dark:text-violet-300" />
                    <div>
                      <h3 className="text-base font-bold text-slate-900 dark:text-white">
                        当前数据库状态与统计
                      </h3>
                      <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                        系统支持 SQLite 轻量存储与 PostgreSQL 企业级数据库实时切换与混合部署。
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {dbStatus?.mode === "postgresql" ? (
                      <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md">
                        <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
                        PostgreSQL 企业级模式
                      </span>
                    ) : (
                      <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-amber-500/10 text-amber-700 dark:text-amber-300 border border-amber-400/40 dark:border-amber-400/25 backdrop-blur-md">
                        <span className="w-2 h-2 rounded-full bg-amber-500" />
                        SQLite 本地存储模式
                      </span>
                    )}
                  </div>
                </div>

                {/* DB Connection Indicators */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {/* App DB */}
                  <div className="p-4 rounded-2xl glass-subtle space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-slate-700 dark:text-slate-300">
                        主数据库 (App Database)
                      </span>
                      <span
                        className={`text-2xs font-semibold px-2 py-0.5 rounded-md ${
                          dbStatus?.app_db.is_connected
                            ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                            : "bg-rose-500/10 text-rose-600 dark:text-rose-400"
                        }`}
                      >
                        {dbStatus?.app_db.is_connected
                          ? `连接正常 (${dbStatus.app_db.ping_ms}ms)`
                          : "连接断开"}
                      </span>
                    </div>
                    <div className="text-xs font-mono text-slate-600 dark:text-slate-400 truncate" title={dbStatus?.app_db.url}>
                      {dbStatus?.app_db.url || "未连接"}
                    </div>
                    <div className="flex items-center gap-2 pt-1 border-t border-slate-200/50 dark:border-white/8 text-2xs text-slate-500 dark:text-slate-400">
                      <span>驱动方言: <strong className="uppercase font-mono">{dbStatus?.app_db.engine || "-"}</strong></span>
                    </div>
                  </div>

                  {/* Collector DB */}
                  <div className="p-4 rounded-2xl glass-subtle space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-slate-700 dark:text-slate-300">
                        采集业务库 (Collector Database)
                      </span>
                      <span
                        className={`text-2xs font-semibold px-2 py-0.5 rounded-md ${
                          dbStatus?.collector_db.is_connected
                            ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                            : "bg-rose-500/10 text-rose-600 dark:text-rose-400"
                        }`}
                      >
                        {dbStatus?.collector_db.is_connected
                          ? `连接正常 (${dbStatus.collector_db.ping_ms}ms)`
                          : "连接断开"}
                      </span>
                    </div>
                    <div className="text-xs font-mono text-slate-600 dark:text-slate-400 truncate" title={dbStatus?.collector_db.url}>
                      {dbStatus?.collector_db.url || "未连接"}
                    </div>
                    <div className="flex items-center gap-2 pt-1 border-t border-slate-200/50 dark:border-white/8 text-2xs text-slate-500 dark:text-slate-400">
                      <span>驱动方言: <strong className="uppercase font-mono">{dbStatus?.collector_db.engine || "-"}</strong></span>
                    </div>
                  </div>
                </div>

                {/* Table Row Statistics */}
                <div className="space-y-2">
                  <div className="text-xs font-bold text-slate-700 dark:text-slate-300 flex items-center justify-between">
                    <span>核心数据表记录行数</span>
                    <span className="text-2xs font-normal text-slate-400 dark:text-slate-500">
                      合计 {dbStatus?.total_tables ?? 0} 个数据表，{dbStatus?.total_records?.toLocaleString() ?? 0} 条数据
                    </span>
                  </div>

                  <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-2.5">
                    {[
                      { label: "用户账号 (users)", val: dbStatus?.app_db.tables.users ?? 0 },
                      { label: "开奖期数 (draw)", val: dbStatus?.collector_db.tables.draw ?? 0 },
                      { label: "预测记录 (prediction)", val: dbStatus?.collector_db.tables.prediction ?? 0 },
                      { label: "数据源 (source)", val: dbStatus?.collector_db.tables.source ?? 0 },
                      { label: "研判结果 (judge_result)", val: dbStatus?.collector_db.tables.judge_result ?? 0 },
                      { label: "抓取任务 (crawl_run)", val: dbStatus?.collector_db.tables.crawl_run ?? 0 },
                      { label: "审计事件 (audit_event)", val: dbStatus?.collector_db.tables.audit_event ?? 0 },
                      { label: "会话设备 (refresh_tokens)", val: dbStatus?.app_db.tables.refresh_tokens ?? 0 },
                      { label: "系统配置 (system_settings)", val: dbStatus?.app_db.tables.system_settings ?? 0 },
                      { label: "号码属性 (number_info)", val: dbStatus?.collector_db.tables.number_info ?? 0 },
                      { label: "问题记录 (issue)", val: dbStatus?.collector_db.tables.issue ?? 0 },
                      { label: "定时计划 (schedule)", val: dbStatus?.collector_db.tables.schedule ?? 0 },
                    ].map((item, idx) => (
                      <div
                        key={idx}
                        className="p-3 rounded-xl glass-subtle flex flex-col justify-between"
                      >
                        <span className="text-2xs text-slate-500 dark:text-slate-400 truncate" title={item.label}>
                          {item.label}
                        </span>
                        <span className="text-base font-bold font-mono text-slate-900 dark:text-white mt-1">
                          {item.val.toLocaleString()}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>

              {/* Card 1.5: Schema Verification & Repair */}
              <div className="p-6 rounded-3xl glass-card space-y-5">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                  <div className="flex items-center gap-2">
                    <ShieldIcon size={20} className="text-violet-600 dark:text-violet-300" />
                    <div>
                      <h3 className="text-base font-bold text-slate-900 dark:text-white">
                        表结构自检与修复
                      </h3>
                      <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                        比对代码中声明的数据表与数据库中实际存在的表，缺哪张补哪张。只新建缺失表，不修改也不删除已有表。
                      </p>
                    </div>
                  </div>
                  {schemaReport && (
                    <span
                      className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold border ${
                        schemaReport.ok
                          ? "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md"
                          : "bg-rose-500/10 text-rose-700 dark:text-rose-300 border-rose-400/40 dark:border-rose-400/25 backdrop-blur-md"
                      }`}
                    >
                      <span
                        className={`w-2 h-2 rounded-full ${
                          schemaReport.ok ? "bg-emerald-500" : "bg-rose-500 animate-pulse"
                        }`}
                      />
                      {schemaReport.ok
                        ? "全部就绪"
                        : `缺少 ${schemaReport.missing_total} 张表`}
                    </span>
                  )}
                </div>

                {/* Per-database schema diff */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {([
                    { label: "主数据库 (App)", rep: schemaReport?.app_db },
                    { label: "采集业务库 (Collector)", rep: schemaReport?.collector_db },
                  ] as const).map((item, idx) => (
                    <div
                      key={idx}
                      className="p-4 rounded-2xl glass-subtle space-y-2"
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-bold text-slate-700 dark:text-slate-300">
                          {item.label}
                        </span>
                        <span
                          className={`text-2xs font-semibold px-2 py-0.5 rounded-md ${
                            item.rep && item.rep.missing.length === 0 && item.rep.is_connected
                              ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                              : "bg-rose-500/10 text-rose-600 dark:text-rose-400"
                          }`}
                        >
                          {item.rep
                            ? `${item.rep.existing.length} / ${item.rep.declared.length} 张已建`
                            : "检测中..."}
                        </span>
                      </div>

                      {item.rep?.error && (
                        <div className="text-2xs text-rose-600 dark:text-rose-400 font-mono break-all">
                          {item.rep.error}
                        </div>
                      )}

                      {item.rep && item.rep.missing.length > 0 ? (
                        <div className="space-y-1.5">
                          <span className="text-2xs text-slate-500 dark:text-slate-400">
                            缺失表（按外键依赖顺序建立）：
                          </span>
                          <div className="flex flex-wrap gap-1.5">
                            {item.rep.missing.map((name) => (
                              <span
                                key={name}
                                className="px-2 py-0.5 rounded-md text-2xs font-mono bg-rose-500/10 text-rose-700 dark:text-rose-300 border border-rose-400/40 dark:border-rose-400/25 backdrop-blur-md"
                              >
                                {name}
                              </span>
                            ))}
                          </div>
                        </div>
                      ) : (
                        item.rep && (
                          <div className="text-2xs text-slate-500 dark:text-slate-400">
                            声明的表均已存在
                          </div>
                        )
                      )}

                      {item.rep && item.rep.unmanaged.length > 0 && (
                        <div className="text-2xs text-slate-400 dark:text-slate-500 pt-1 border-t border-slate-200/50 dark:border-white/8">
                          库中另有 {item.rep.unmanaged.length} 张非本项目声明的表（不会被改动）
                        </div>
                      )}
                    </div>
                  ))}
                </div>

                {schemaReport?.shared_database && (
                  <div className="text-2xs text-slate-500 dark:text-slate-400 px-3 py-2 rounded-lg glass-subtle">
                    当前主库与采集库指向同一个数据库，两套表共存于其中。
                  </div>
                )}

                {/* Repair result */}
                {repairResult && (
                  <div
                    className={`p-3.5 rounded-xl text-xs space-y-2 animate-fadeIn ${
                      repairResult.ok
                        ? "bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 text-emerald-700 dark:text-emerald-300 backdrop-blur-md"
                        : "bg-amber-500/10 border border-amber-400/40 dark:border-amber-400/25 text-amber-700 dark:text-amber-300 backdrop-blur-md"
                    }`}
                  >
                    <div className="font-semibold">
                      {repairResult.ok
                        ? `修复完成，新建 ${repairResult.created_total} 张表`
                        : `修复未完全成功，新建 ${repairResult.created_total} 张表，${repairResult.failed.length} 张失败`}
                    </div>

                    {repairResult.created_total > 0 && (
                      <div className="flex flex-wrap gap-1.5">
                        {[...repairResult.created.app, ...repairResult.created.collector].map((name) => (
                          <span
                            key={name}
                            className="px-2 py-0.5 rounded-md text-2xs font-mono glass-subtle"
                          >
                            {name}
                          </span>
                        ))}
                      </div>
                    )}

                    {repairResult.failed.length > 0 && (
                      <div className="space-y-1 pt-1 border-t border-current/20">
                        {repairResult.failed.map((f, i) => (
                          <div key={i} className="font-mono text-2xs break-all">
                            <strong>{f.db}.{f.table}</strong>: {f.error}
                          </div>
                        ))}
                      </div>
                    )}

                    {repairResult.notes.length > 0 && (
                      <div className="space-y-0.5 pt-1 border-t border-current/20">
                        {repairResult.notes.map((n, i) => (
                          <div key={i} className="text-2xs">{n}</div>
                        ))}
                      </div>
                    )}
                  </div>
                )}

                {/* Actions */}
                <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3 pt-1">
                  <span className="text-2xs text-slate-400 dark:text-slate-500">
                    后端启动时会自动执行同样的检测与补齐，此处用于手动复查。
                  </span>
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={loadSchemaReport}
                      disabled={checkingSchema || repairingSchema}
                      className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-semibold glass-subtle hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 transition-all disabled:opacity-50 cursor-pointer"
                    >
                      <RefreshIcon size={16} className={checkingSchema ? "animate-spin" : ""} />
                      {checkingSchema ? "正在检测..." : "重新检测"}
                    </button>
                    <button
                      type="button"
                      onClick={handleRepairSchema}
                      disabled={
                        repairingSchema ||
                        checkingSchema ||
                        !schemaReport ||
                        schemaReport.missing_total === 0
                      }
                      className="inline-flex items-center gap-2 px-5 py-2 rounded-xl text-xs font-semibold glow-button border-0 transition-all disabled:opacity-50 cursor-pointer"
                      title={
                        schemaReport && schemaReport.missing_total === 0
                          ? "当前没有缺失表"
                          : undefined
                      }
                    >
                      <CheckBadgeIcon size={16} />
                      {repairingSchema
                        ? "正在建表..."
                        : schemaReport && schemaReport.missing_total > 0
                          ? `补齐 ${schemaReport.missing_total} 张缺失表`
                          : "补齐缺失表"}
                    </button>
                  </div>
                </div>
              </div>

              {/* Card 2: PostgreSQL Configuration & Switching */}
              <div className="p-6 rounded-3xl glass-card space-y-4">
                <div className="flex items-center gap-2">
                  <DatabaseIcon size={20} className="text-violet-600 dark:text-violet-300" />
                  <div>
                    <h3 className="text-base font-bold text-slate-900 dark:text-white">
                      PostgreSQL 数据库配置与切换
                    </h3>
                    <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                      配置 PostgreSQL 数据库连接串。保存后系统将自动更新环境变量、重载连接池并创建所有表结构。
                    </p>
                  </div>
                </div>

                <div className="space-y-4 pt-2">
                  <div className="space-y-1.5">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300 flex items-center justify-between">
                      <span>主数据库连接地址 (DATABASE_URL)</span>
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => setPgUrl("postgresql://postgres:postgres@localhost:5432/duiliao")}
                          className="text-2xs text-violet-600 dark:text-violet-300 hover:underline cursor-pointer"
                        >
                          填入本地 PG 默认
                        </button>
                        <span className="text-slate-300 dark:text-white/25">|</span>
                        <button
                          type="button"
                          onClick={() => setPgUrl("sqlite:///./duiliao.db")}
                          className="text-2xs text-slate-500 dark:text-slate-400 hover:underline cursor-pointer"
                        >
                          恢复默认 SQLite
                        </button>
                      </div>
                    </label>
                    <input
                      type="text"
                      value={pgUrl}
                      onChange={(e) => setPgUrl(e.target.value)}
                      placeholder="postgresql://user:password@localhost:5432/duiliao 或 sqlite:///./duiliao.db"
                      className="w-full h-10 px-3.5 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                    />
                  </div>

                  <div className="space-y-1.5">
                    <label className="text-xs font-semibold text-slate-700 dark:text-slate-300 flex items-center justify-between">
                      <span>独立采集库地址 (COLLECTOR_DATABASE_URL，可选)</span>
                      <span className="text-2xs font-normal text-slate-400 dark:text-slate-500">留空则自动复用主数据库</span>
                    </label>
                    <input
                      type="text"
                      value={collectorPgUrl}
                      onChange={(e) => setCollectorPgUrl(e.target.value)}
                      placeholder="可选：若采集表存放在独立数据库则填写，否则留空"
                      className="w-full h-10 px-3.5 rounded-xl glass-input text-sm font-mono text-slate-800 dark:text-slate-200"
                    />
                  </div>

                  {/* Test Feedback */}
                  {pgTestResult && (
                    <div
                      className={`p-3.5 rounded-xl text-xs flex items-center justify-between animate-fadeIn ${
                        pgTestResult.ok
                          ? "bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 text-emerald-700 dark:text-emerald-300 backdrop-blur-md"
                          : "bg-rose-500/10 border border-rose-400/40 dark:border-rose-400/25 text-rose-700 dark:text-rose-300 backdrop-blur-md"
                      }`}
                    >
                      <div className="space-y-0.5">
                        <div className="font-semibold">{pgTestResult.message || pgTestResult.error}</div>
                        {pgTestResult.version && (
                          <div className="text-2xs opacity-80 truncate">{pgTestResult.version}</div>
                        )}
                      </div>
                      {pgTestResult.elapsed_ms !== undefined && (
                        <span className="font-mono text-2xs font-semibold shrink-0">
                          {pgTestResult.elapsed_ms}ms
                        </span>
                      )}
                    </div>
                  )}

                  {/* Actions */}
                  <div className="flex items-center gap-3 pt-2">
                    <button
                      type="button"
                      onClick={handleTestPg}
                      disabled={testingPg || !pgUrl.trim()}
                      className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-semibold glass-subtle hover:bg-violet-500/5 dark:hover:bg-violet-400/5 text-slate-700 dark:text-slate-300 transition-all disabled:opacity-50 cursor-pointer"
                    >
                      {testingPg ? "正在测试连通性..." : "测试数据库连接"}
                    </button>
                    <button
                      type="button"
                      onClick={handleSaveDbConfig}
                      disabled={savingDb || !pgUrl.trim()}
                      className="inline-flex items-center gap-2 px-5 py-2 rounded-xl text-xs font-semibold glow-button border-0 transition-all disabled:opacity-50 cursor-pointer"
                    >
                      <CheckBadgeIcon size={16} />
                      {savingDb ? "正在保存并初始化表..." : "保存并切换数据库"}
                    </button>
                  </div>
                </div>
              </div>

              {/* Card 3: SQLite File Upload & Data Import */}
              <div className="p-6 rounded-3xl glass-card space-y-4">
                <div className="flex items-center gap-2">
                  <UploadIcon size={20} className="text-violet-600 dark:text-violet-300" />
                  <div>
                    <h3 className="text-base font-bold text-slate-900 dark:text-white">
                      上传 SQLite 文件并导入数据
                    </h3>
                    <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                      支持上传已有 SQLite 数据库文件（如 pred.db、duiliao.db 或备份文件），自动解析表结构并以拓扑顺序安全导入到当前数据库中。
                    </p>
                  </div>
                </div>

                {/* Upload Drag & Drop Box */}
                {!inspectResult && (
                  <div
                    onDragOver={(e) => {
                      e.preventDefault();
                      setIsDragOver(true);
                    }}
                    onDragLeave={() => setIsDragOver(false)}
                    onDrop={(e) => {
                      e.preventDefault();
                      setIsDragOver(false);
                      const file = e.dataTransfer.files?.[0];
                      if (file) handleFileSelected(file);
                    }}
                    className={`p-8 rounded-2xl glass-subtle border-dashed! flex flex-col items-center justify-center text-center transition-all cursor-pointer ${
                      isDragOver
                        ? "border-violet-400/70 dark:border-violet-400/50"
                        : "hover:border-violet-400/50 dark:hover:border-violet-400/35"
                    }`}
                    onClick={() => {
                      const input = document.getElementById("sqlite-file-input") as HTMLInputElement;
                      if (input) input.click();
                    }}
                  >
                    <input
                      id="sqlite-file-input"
                      type="file"
                      accept=".db,.sqlite,.sqlite3"
                      className="hidden"
                      onChange={(e) => {
                        const file = e.target.files?.[0];
                        if (file) handleFileSelected(file);
                      }}
                    />
                    <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-violet-500/15 to-fuchsia-500/10 text-violet-600 dark:text-violet-300 border border-violet-400/30 flex items-center justify-center mb-3 backdrop-blur-sm">
                      <UploadIcon size={24} />
                    </div>
                    <div className="text-sm font-semibold text-slate-800 dark:text-slate-200">
                      {inspecting ? "正在解析 SQLite 文件..." : "点击或拖拽 SQLite 文件至此处"}
                    </div>
                    <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">
                      支持格式：.db、.sqlite、.sqlite3（文件经由安全加密信道传输）
                    </p>
                  </div>
                )}

                {/* File Inspection Result */}
                {inspectResult && (
                  <div className="space-y-4 p-4 rounded-2xl glass-subtle">
                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 pb-3 border-b border-slate-200/50 dark:border-white/8">
                      <div>
                        <div className="text-sm font-bold text-slate-900 dark:text-white flex items-center gap-2">
                          <span className="w-2 h-2 rounded-full bg-violet-500 shadow-[0_0_6px_rgba(139,92,246,0.8)]" />
                          已解析文件: {inspectResult.filename}
                        </div>
                        <div className="text-2xs text-slate-500 dark:text-slate-400 mt-0.5">
                          文件大小: {(inspectResult.file_size / 1024).toFixed(1)} KB | 数据表: {inspectResult.total_tables} 个 | 总记录: {inspectResult.total_rows.toLocaleString()} 条
                        </div>
                      </div>
                      <button
                        type="button"
                        onClick={() => {
                          setInspectResult(null);
                          setSqliteFile(null);
                          setFileBase64("");
                          setImportResult(null);
                        }}
                        className="text-xs text-rose-600 dark:text-rose-300 hover:underline self-start sm:self-auto cursor-pointer"
                      >
                        重新选择文件
                      </button>
                    </div>

                    {/* Import Mode Selection */}
                    <div className="space-y-2">
                      <label className="text-xs font-bold text-slate-700 dark:text-slate-300">
                        冲突处理策略 (Import Mode)
                      </label>
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <label
                          className={`p-3 rounded-2xl glass-subtle transition-all cursor-pointer flex items-center justify-between ${
                            importMode === "skip"
                              ? "border-violet-400/50 dark:border-violet-400/35 shadow-[0_8px_24px_-8px_rgba(139,92,246,0.35)] ring-1 ring-violet-400/30"
                              : "hover:border-violet-400/40 dark:hover:border-violet-400/30"
                          }`}
                        >
                          <div>
                            <div className="text-xs font-bold text-slate-900 dark:text-white">
                              增量合并 (跳过冲突，推荐)
                            </div>
                            <div className="text-2xs text-slate-500 dark:text-slate-400 mt-0.5">
                              若主键已存在则跳过，保留现有数据，仅插入新增数据。
                            </div>
                          </div>
                          <input
                            type="radio"
                            name="import_mode"
                            value="skip"
                            checked={importMode === "skip"}
                            onChange={() => setImportMode("skip")}
                            className="accent-violet-600 dark:accent-violet-400 h-4 w-4"
                          />
                        </label>

                        <label
                          className={`p-3 rounded-2xl glass-subtle transition-all cursor-pointer flex items-center justify-between ${
                            importMode === "overwrite"
                              ? "border-violet-400/50 dark:border-violet-400/35 shadow-[0_8px_24px_-8px_rgba(139,92,246,0.35)] ring-1 ring-violet-400/30"
                              : "hover:border-violet-400/40 dark:hover:border-violet-400/30"
                          }`}
                        >
                          <div>
                            <div className="text-xs font-bold text-slate-900 dark:text-white">
                              覆盖更新 (冲突更新)
                            </div>
                            <div className="text-2xs text-slate-500 dark:text-slate-400 mt-0.5">
                              若主键已存在则更新替换现有记录，同步最新数据。
                            </div>
                          </div>
                          <input
                            type="radio"
                            name="import_mode"
                            value="overwrite"
                            checked={importMode === "overwrite"}
                            onChange={() => setImportMode("overwrite")}
                            className="accent-violet-600 dark:accent-violet-400 h-4 w-4"
                          />
                        </label>
                      </div>
                    </div>

                    {/* Table Selection Checklist */}
                    <div className="space-y-2">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-bold text-slate-700 dark:text-slate-300">
                          选择要导入的数据表 ({selectedTables.length} / {inspectResult.tables.length})
                        </span>
                        <div className="flex items-center gap-2 text-2xs">
                          <button
                            type="button"
                            onClick={() => setSelectedTables(inspectResult.tables.map((t) => t.name))}
                            className="text-violet-600 dark:text-violet-300 hover:underline cursor-pointer"
                          >
                            全选
                          </button>
                          <span className="text-slate-300 dark:text-white/25">|</span>
                          <button
                            type="button"
                            onClick={() => setSelectedTables([])}
                            className="text-slate-500 dark:text-slate-400 hover:underline cursor-pointer"
                          >
                            全不选
                          </button>
                        </div>
                      </div>

                      <div className="max-h-56 overflow-y-auto grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2 p-2 rounded-xl glass-subtle">
                        {inspectResult.tables.map((tbl) => {
                          const isSelected = selectedTables.includes(tbl.name);
                          return (
                            <label
                              key={tbl.name}
                              className={`p-2.5 rounded-lg border text-xs flex items-center justify-between transition-all cursor-pointer ${
                                isSelected
                                  ? "border-violet-400/40 bg-violet-500/10 dark:bg-violet-400/10 text-slate-900 dark:text-white font-semibold"
                                  : "border-slate-200/50 dark:border-white/8 text-slate-600 dark:text-slate-400"
                              }`}
                            >
                              <div className="flex items-center gap-2 truncate">
                                <input
                                  type="checkbox"
                                  checked={isSelected}
                                  onChange={(e) => {
                                    if (e.target.checked) {
                                      setSelectedTables((prev) => [...prev, tbl.name]);
                                    } else {
                                      setSelectedTables((prev) => prev.filter((n) => n !== tbl.name));
                                    }
                                  }}
                                  className="accent-violet-600 dark:accent-violet-400 rounded-sm h-3.5 w-3.5"
                                />
                                <span className="truncate">{tbl.name}</span>
                              </div>
                              <span className="font-mono text-2xs text-slate-400 dark:text-slate-500 shrink-0 ml-1">
                                {tbl.rows} 行
                              </span>
                            </label>
                          );
                        })}
                      </div>
                    </div>

                    {/* Import Execution Button */}
                    <div className="pt-2 flex items-center justify-between">
                      <div className="text-2xs text-slate-400 dark:text-slate-500">
                        目标数据库模式: <strong className="uppercase font-mono">{dbStatus?.mode || "SQLITE"}</strong>
                      </div>
                      <button
                        type="button"
                        onClick={handleStartImport}
                        disabled={importing || selectedTables.length === 0}
                        className="inline-flex items-center gap-2 px-6 py-2.5 rounded-xl text-sm font-semibold glow-button border-0 transition-all disabled:opacity-50 cursor-pointer"
                      >
                        <UploadIcon size={16} />
                        {importing ? "正在导入数据中，请稍候..." : `开始导入 (${selectedTables.length} 个表)`}
                      </button>
                    </div>
                  </div>
                )}

                {/* Import Result Feedback */}
                {importResult && (
                  <div className="p-4 rounded-xl bg-emerald-500/10 border border-emerald-400/40 dark:border-emerald-400/25 text-emerald-700 dark:text-emerald-300 text-xs space-y-2 animate-fadeIn backdrop-blur-md">
                    <div className="font-bold flex items-center gap-2 text-sm">
                      <CheckBadgeIcon size={18} />
                      <span>数据导入成功！</span>
                    </div>
                    <div className="text-xs">
                      耗时 <strong>{importResult.elapsed_ms}ms</strong>，成功写入 <strong>{importResult.total_inserted.toLocaleString()}</strong> 条数据，跳过 <strong>{importResult.total_skipped.toLocaleString()}</strong> 条重复记录。
                    </div>
                    <div className="pt-2 border-t border-emerald-400/30 dark:border-emerald-400/20 max-h-40 overflow-y-auto space-y-1 text-2xs font-mono">
                      {Object.entries(importResult.summary).map(([tname, sinfo]) => (
                        <div key={tname} className="flex items-center justify-between">
                          <span>{tname}</span>
                          <span>
                            写入: {sinfo.inserted} | 跳过: {sinfo.skipped}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {importError && (
                  <div className="p-3.5 rounded-xl bg-rose-500/10 border border-rose-400/40 dark:border-rose-400/25 text-rose-700 dark:text-rose-300 text-xs animate-fadeIn backdrop-blur-md">
                    {importError}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* TAB 3: System Environment & Security */}
          {activeTab === "system" && (
            <div className="space-y-6">
              <div className="p-6 rounded-3xl glass-card space-y-4">
                <div className="flex items-center gap-2">
                  <ShieldIcon size={20} className="text-violet-600 dark:text-violet-300" />
                  <h3 className="text-base font-bold text-slate-900 dark:text-white">
                    安全传输与环境架构
                  </h3>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div className="p-4 rounded-2xl glass-subtle space-y-1">
                    <div className="text-xs text-slate-400 dark:text-slate-500">应用层加密通道</div>
                    <div className="text-sm font-semibold text-slate-800 dark:text-slate-200 flex items-center gap-2">
                      <span className="w-2 h-2 rounded-full bg-emerald-500" />
                      RSA 2048 + AES-256-GCM 会话密钥协商
                    </div>
                  </div>

                  <div className="p-4 rounded-2xl glass-subtle space-y-1">
                    <div className="text-xs text-slate-400 dark:text-slate-500">防重放与请求验签</div>
                    <div className="text-sm font-semibold text-slate-800 dark:text-slate-200 flex items-center gap-2">
                      <span className="w-2 h-2 rounded-full bg-emerald-500" />
                      HMAC-SHA256 签名校验
                    </div>
                  </div>

                  <div className="p-4 rounded-2xl glass-subtle space-y-1">
                    <div className="text-xs text-slate-400 dark:text-slate-500">动态配置存储</div>
                    <div className="text-sm font-semibold text-slate-800 dark:text-slate-200">
                      SQLite / PostgreSQL 数据库（system_settings）
                    </div>
                  </div>

                  <div className="p-4 rounded-2xl glass-subtle space-y-1">
                    <div className="text-xs text-slate-400 dark:text-slate-500">API 服务网关</div>
                    <div className="text-sm font-semibold text-slate-800 dark:text-slate-200">
                      FastAPI v1 (/api/v1)
                    </div>
                  </div>
                </div>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
