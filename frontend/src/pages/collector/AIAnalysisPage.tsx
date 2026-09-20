import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { api, settingsApi, type AISettings } from "../../lib/api";
import { PageHeader, Toolbar } from "./shared";
import {
  SparklesIcon,
  DatabaseIcon,
  ActivityIcon,
  CheckBadgeIcon,
  SettingsIcon,
} from "../../components/icons";

interface PromptInfo {
  id: string;
  name: string;
  description: string;
  is_default: boolean;
  user_template?: string;
  system_prompt?: string;
}

interface ScrapedModule {
  id: number;
  name: string;
  type: string;
  content: string | null;
  sort?: number;
  classId?: number;
}

interface ScrapedSummary {
  ok: boolean;
  site_title: string;
  total_modules: number;
  content_modules_count: number;
  loaded_content_count: number;
  elapsed_sec: number;
  html_size_bytes: number;
  entry_url?: string;
  app_base?: string;
  html?: string;
  modules?: ScrapedModule[];
}

interface AIResult {
  ok: boolean;
  provider: string;
  model: string;
  prompt_id: string;
  analysis: string;
  usage: {
    prompt_tokens?: number;
    completion_tokens?: number;
    total_tokens?: number;
  };
  elapsed_sec: number;
  scraped_summary?: Partial<ScrapedSummary>;
}

export function CollectorAIAnalysisPage() {
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<"ai" | "data">("ai");

  // Prompts & Config (persisted to localStorage across page reloads)
  const [prompts, setPrompts] = useState<PromptInfo[]>([]);
  const [selectedPromptId, setSelectedPromptId] = useState<string>(() => {
    return localStorage.getItem("duiliao_prompt_id") || "macau_analyst_expert";
  });
  const [period, setPeriod] = useState<string>(() => {
    return localStorage.getItem("duiliao_period") || "262";
  });
  const [customPrompt, setCustomPrompt] = useState<string>(() => {
    return localStorage.getItem("duiliao_custom_prompt") || "";
  });
  const [provider, setProvider] = useState<"openai" | "gemini" | "anthropic">(() => {
    return (localStorage.getItem("duiliao_provider") as any) || "openai";
  });
  const [model, setModel] = useState<string>(() => {
    return localStorage.getItem("duiliao_model_override") || "";
  });
  const [formatMode, setFormatMode] = useState<"modules_summary" | "raw_html">(() => {
    return (localStorage.getItem("duiliao_format_mode") as any) || "modules_summary";
  });
  const [temperature, setTemperature] = useState(0.7);
  const [aiSettings, setAiSettings] = useState<AISettings | null>(null);

  // Sync state changes to localStorage
  useEffect(() => {
    localStorage.setItem("duiliao_prompt_id", selectedPromptId);
  }, [selectedPromptId]);

  useEffect(() => {
    localStorage.setItem("duiliao_period", period);
  }, [period]);

  useEffect(() => {
    localStorage.setItem("duiliao_custom_prompt", customPrompt);
  }, [customPrompt]);

  useEffect(() => {
    localStorage.setItem("duiliao_provider", provider);
  }, [provider]);

  useEffect(() => {
    localStorage.setItem("duiliao_model_override", model);
  }, [model]);

  useEffect(() => {
    localStorage.setItem("duiliao_format_mode", formatMode);
  }, [formatMode]);

  // Scraped Data State
  const [scrapedData, setScrapedData] = useState<ScrapedSummary | null>(null);
  const [isScraping, setIsScraping] = useState(false);
  const [scrapeError, setScrapeError] = useState<string | null>(null);
  const [filterType, setFilterType] = useState<string>("all");
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedModule, setSelectedModule] = useState<ScrapedModule | null>(null);

  // AI Execution State
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [streamStatus, setStreamStatus] = useState("");
  const [aiError, setAiError] = useState<string | null>(null);
  const [aiResult, setAiResult] = useState<AIResult | null>(null);
  const [copied, setCopied] = useState(false);
  const [showCombinedPreview, setShowCombinedPreview] = useState(false);

  // Load prompts & settings on mount
  useEffect(() => {
    api
      .get<PromptInfo[]>("/ai/prompts")
      .then((data) => {
        if (Array.isArray(data) && data.length > 0) {
          setPrompts(data);
          const savedPrompt = localStorage.getItem("duiliao_prompt_id");
          if (!savedPrompt) {
            const def = data.find((d) => d.is_default);
            if (def) setSelectedPromptId(def.id);
          }
        }
      })
      .catch((err) => {
        console.warn("Failed to load prompts:", err);
      });

    settingsApi
      .getAISettings()
      .then((cfg) => {
        setAiSettings(cfg);
        const savedProvider = localStorage.getItem("duiliao_provider");
        if (!savedProvider && cfg?.default_provider) {
          setProvider(cfg.default_provider as any);
        }
      })
      .catch((err) => {
        console.warn("Failed to load AI settings:", err);
      });
  }, []);

  // Fetch 588080 Scraped Data
  const handleScrape588080 = async () => {
    setIsScraping(true);
    setScrapeError(null);
    try {
      const res = await api.post<ScrapedSummary>("/collector/site-dump/588080", {
        include_html: true,
        include_modules: true,
        timeout: 15.0,
      });
      setScrapedData(res);

      // Auto-detect period from scraped content
      const allText = (res.modules || []).map((m: any) => m.content || "").join(" ");
      const match = allText.match(/(?:第\s*)?(\d{3})\s*期/);
      if (match && match[1]) {
        setPeriod(match[1]);
      }
    } catch (err: any) {
      setScrapeError(err?.message || "抓取数据失败，请检查网络连接");
    } finally {
      setIsScraping(false);
    }
  };

  // Run AI Analysis (Streaming with real-time markdown token rendering)
  const handleRunAI = async () => {
    setIsAnalyzing(true);
    setAiError(null);
    setStreamStatus("正在连接大模型并准备上下文...");

    // Initialize an empty result for typewriter output
    setAiResult({
      ok: true,
      provider: provider,
      model: model || "default",
      prompt_id: selectedPromptId,
      analysis: "",
      usage: {},
      elapsed_sec: 0,
    });

    try {
      const payload: any = {
        prompt_id: selectedPromptId,
        period: period.trim() || "262",
        provider: provider,
        format_mode: formatMode,
        temperature: temperature,
        fetch_fresh: !scrapedData,
      };

      if (model.trim()) {
        payload.model = model.trim();
      }
      if (selectedPromptId === "custom" && customPrompt.trim()) {
        payload.custom_prompt = customPrompt.trim();
      }
      if (scrapedData) {
        payload.fetch_fresh = false;
        payload.custom_data = scrapedData;
      }

      await api.stream("/ai/analyze-stream", payload, {
        onStatus: (st) => {
          if (st.message) {
            setStreamStatus(st.message);
          }
        },
        onChunk: (delta) => {
          setAiResult((prev) => {
            if (!prev) {
              return {
                ok: true,
                provider: provider,
                model: model || "default",
                prompt_id: selectedPromptId,
                analysis: delta,
                usage: {},
                elapsed_sec: 0,
              };
            }
            return {
              ...prev,
              analysis: prev.analysis + delta,
            };
          });
        },
        onDone: (doneInfo) => {
          setAiResult((prev) => (prev ? { ...prev, ...doneInfo } : null));
          setStreamStatus("");
        },
        onError: (err) => {
          setAiError(err.message || "AI 流式分析异常中断");
        },
      });
    } catch (err: any) {
      setAiError(err?.message || "AI 研判分析调用失败");
    } finally {
      setIsAnalyzing(false);
      setStreamStatus("");
    }
  };

  const copyAnalysis = () => {
    if (!aiResult?.analysis) return;
    navigator.clipboard.writeText(aiResult.analysis);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const downloadHtml = () => {
    if (!scrapedData?.html) return;
    const blob = new Blob([scrapedData.html], { type: "text/html;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "prediction_full_page.html";
    a.click();
    URL.revokeObjectURL(url);
  };

  const DEFAULT_ANALYST_PROMPT =
    "你现在是专业的澳门六合彩分析师，只分析帖文里的实码和生肖，严格过滤所有“發”“猫”“？”“0O”，给出{period}期热度最高的5个生肖以及重点6个号码10个号码";

  const getCurrentPromptPreview = () => {
    const targetPeriod = period.trim() || "262";
    if (selectedPromptId === "custom") {
      const pText = customPrompt.trim() || DEFAULT_ANALYST_PROMPT;
      return pText.replace(/{period}/g, targetPeriod);
    }
    const cur = prompts.find((p) => p.id === selectedPromptId);
    if (cur?.user_template) {
      return cur.user_template
        .replace(/{period}/g, targetPeriod)
        .replace(/---\s*\{context_data\}\s*---/g, "[... 此处自动嵌入下方抓取的数据内容 ...]");
    }
    return DEFAULT_ANALYST_PROMPT.replace(/{period}/g, targetPeriod);
  };

  const getScrapedDataPreview = () => {
    if (!scrapedData) {
      return "【提示】：当前尚未抓取网页数据。在您点击【启动大模型智能研判】或【执行 AI 研判】时，系统将自动抓取最新数据并直接注入此处。";
    }
    if (formatMode === "raw_html") {
      return (
        (scrapedData.html || "").slice(0, 800) +
        "\n\n[... 原始 HTML 共 " +
        ((scrapedData.html_size_bytes || 0) / 1024).toFixed(1) +
        " KB ...]"
      );
    }
    const modules = (scrapedData.modules || []).filter((m) => m.content && m.content.trim());
    if (modules.length === 0) {
      return `【站点标题: ${scrapedData.site_title || "顶尖大师"}】\n【暂无已解析模块文本，抓取时将自动提取】`;
    }
    const sample = modules
      .slice(0, 5)
      .map((m) => `【栏目 ${m.id}: ${m.name}】\n${(m.content || "").trim().slice(0, 150)}...`)
      .join("\n\n");
    return `【站点标题: ${scrapedData.site_title || "顶尖大师"}】\n【已提取 ${modules.length} 个核心预测栏目】：\n\n${sample}\n\n[... 以及其余 ${Math.max(0, modules.length - 5)} 个核心栏目均已打包注入 ...]`;
  };

  const filteredModules = (scrapedData?.modules || []).filter((m) => {
    if (filterType !== "all" && m.type !== filterType) return false;
    if (searchTerm && !m.name.toLowerCase().includes(searchTerm.toLowerCase())) return false;
    return true;
  });

  return (
    <div className="space-y-6">
      {/* Top Header */}
      <PageHeader
        title="AI研判"
        desc="全量抓取多源预测模块（含 21 个核心懒加载卡片），并配合 DeepSeek / Gemini / Claude 多模型进行深度对料共识研判。"
        right={
          <div className="flex items-center gap-2">
            <button
              onClick={() => navigate("/settings")}
              className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-xl text-sm font-semibold border border-slate-200 dark:border-slate-800 bg-white dark:bg-[#0c1220] hover:bg-slate-50 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-300 shadow-xs transition-all cursor-pointer"
              title="配置 AI 服务商地址与 API 密钥"
            >
              <SettingsIcon size={16} />
              AI配置
            </button>
            <button
              onClick={handleScrape588080}
              disabled={isScraping}
              className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold bg-emerald-600 hover:bg-emerald-500 text-white shadow-xs transition-all disabled:opacity-50"
            >
              <DatabaseIcon size={16} />
              {isScraping ? "正在抓取数据..." : "抓取最新数据"}
            </button>
            <button
              onClick={handleRunAI}
              disabled={isAnalyzing}
              className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-semibold bg-primary hover:bg-primary/90 text-white shadow-xs transition-all disabled:opacity-50"
            >
              <SparklesIcon size={16} />
              {isAnalyzing ? "正在进行 AI 研判..." : "执行 AI 研判"}
            </button>
          </div>
        }
      />

      {/* Tabs Navigation */}
      <Toolbar>
        <div className="flex items-center gap-2 w-full justify-between">
          <div className="flex items-center gap-1 bg-slate-100 dark:bg-slate-900/60 p-1 rounded-xl">
            <button
              onClick={() => setActiveTab("ai")}
              className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all ${
                activeTab === "ai"
                  ? "bg-white dark:bg-[#0c1220] text-primary shadow-xs font-semibold"
                  : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white"
              }`}
            >
              <SparklesIcon size={16} />
              AI 智能研判与提示词
            </button>
            <button
              onClick={() => setActiveTab("data")}
              className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all ${
                activeTab === "data"
                  ? "bg-white dark:bg-[#0c1220] text-primary shadow-xs font-semibold"
                  : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white"
              }`}
            >
              <DatabaseIcon size={16} />
              数据源抓取与预览
              {scrapedData && (
                <span className="ml-1 px-1.5 py-0.5 rounded-full text-2xs bg-emerald-500/10 text-emerald-600 dark:text-emerald-400">
                  {scrapedData.total_modules} 模块
                </span>
              )}
            </button>
          </div>

          {/* Quick Status Stats */}
          {scrapedData && (
            <div className="hidden lg:flex items-center gap-3 text-xs text-slate-500 dark:text-slate-400">
              <span>
                目标集群: <strong className="text-slate-800 dark:text-slate-200">{scrapedData.app_base}</strong>
              </span>
              <span>•</span>
              <span>
                核心卡片:{" "}
                <strong className="text-emerald-600 dark:text-emerald-400">
                  {scrapedData.loaded_content_count}/{scrapedData.content_modules_count}
                </strong>
              </span>
              <span>•</span>
              <span>
                页面体积:{" "}
                <strong className="text-slate-800 dark:text-slate-200">
                  {(scrapedData.html_size_bytes / 1024).toFixed(1)} KB
                </strong>
              </span>
            </div>
          )}
        </div>
      </Toolbar>

      {/* Scrape Error Message */}
      {scrapeError && (
        <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 text-sm">
          {scrapeError}
        </div>
      )}

      {/* TAB 1: AI 研判与提示词 */}
      {activeTab === "ai" && (
        <div className="grid grid-cols-1 xl:grid-cols-12 gap-6 items-start">
          {/* Left Column: Prompt Selector & Model Config */}
          <div className="xl:col-span-5 space-y-6">
            {/* Prompt Selector Card */}
            <div className="p-5 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 shadow-xs space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-base font-bold text-slate-900 dark:text-white flex items-center gap-2">
                  <SparklesIcon size={18} className="text-primary" />
                  提示词模板 (Prompt)
                </h3>
                <span className="text-xs text-slate-400">共 {prompts.length} 个内置模板</span>
              </div>

              {/* Dynamic Period Setting */}
              <div className="p-3.5 rounded-xl bg-slate-50/80 dark:bg-slate-900/60 border border-slate-200/80 dark:border-slate-800/80 flex items-center justify-between gap-3">
                <div>
                  <div className="text-xs font-bold text-slate-800 dark:text-slate-200 flex items-center gap-1.5">
                    <span>🎯 目标期号 (Period)</span>
                    <span className="text-2xs font-medium px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-600 dark:text-emerald-400">
                      动态注入
                    </span>
                  </div>
                  <div className="text-2xs text-slate-400 mt-0.5">
                    将自动替换提示词中的期号变量
                  </div>
                </div>
                <div className="flex items-center gap-1.5">
                  <span className="text-xs text-slate-400 font-medium">第</span>
                  <input
                    type="text"
                    value={period}
                    onChange={(e) => setPeriod(e.target.value)}
                    placeholder="262"
                    className="w-16 h-8 text-center rounded-lg border border-slate-200 dark:border-slate-800 bg-white dark:bg-[#0c1220] text-sm font-bold text-primary focus:outline-none focus:ring-2 focus:ring-primary/20 shadow-2xs"
                  />
                  <span className="text-xs text-slate-400 font-medium">期</span>
                </div>
              </div>

              {/* Dynamic Active Prompt Preview Box */}
              {selectedPromptId === "macau_analyst_expert" && (
                <div className="p-3 rounded-xl bg-amber-500/5 dark:bg-amber-500/10 border border-amber-500/30 text-xs text-amber-800 dark:text-amber-200 space-y-1">
                  <div className="font-bold flex items-center gap-1 text-amber-700 dark:text-amber-300">
                    <SparklesIcon size={14} /> 当前激活的预设提示词 (已注入第 {period} 期)：
                  </div>
                  <div className="font-mono text-2xs p-2 rounded-lg bg-white/80 dark:bg-slate-950/60 border border-amber-200/60 dark:border-amber-900/40 text-slate-700 dark:text-slate-300">
                    “你现在是专业的澳门六合彩分析师，只分析帖文里的实码和生肖，严格过滤所有“發”“猫”“？”“0O”，给出<strong className="text-primary font-bold mx-0.5">{period}</strong>期热度最高的5个生肖以及重点6个号码10个号码”
                  </div>
                </div>
              )}

              <div className="space-y-2">

                {prompts.map((p) => {
                  const isSelected = selectedPromptId === p.id;
                  return (
                    <div
                      key={p.id}
                      onClick={() => setSelectedPromptId(p.id)}
                      className={`p-3.5 rounded-xl border cursor-pointer transition-all ${
                        isSelected
                          ? "bg-primary/5 dark:bg-primary/10 border-primary shadow-xs"
                          : "bg-slate-50/50 dark:bg-slate-900/30 border-slate-200/60 dark:border-slate-800/60 hover:border-slate-300 dark:hover:border-slate-700"
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <div className="font-semibold text-sm text-slate-800 dark:text-slate-100 flex items-center gap-1.5">
                          {isSelected && <span className="w-1.5 h-1.5 rounded-full bg-primary" />}
                          {p.name}
                        </div>
                        {p.is_default && (
                          <span className="text-2xs px-2 py-0.5 rounded-md bg-primary/10 text-primary font-medium">
                            推荐
                          </span>
                        )}
                      </div>
                      <p className="mt-1 text-xs text-slate-500 dark:text-slate-400 leading-relaxed">
                        {p.description}
                      </p>
                    </div>
                  );
                })}

                {/* Custom Prompt Card */}
                <div
                  onClick={() => {
                    setSelectedPromptId("custom");
                    if (!customPrompt.trim()) {
                      setCustomPrompt(
                        DEFAULT_ANALYST_PROMPT.replace(/{period}/g, period.trim() || "262")
                      );
                    }
                  }}
                  className={`p-3.5 rounded-xl border cursor-pointer transition-all ${
                    selectedPromptId === "custom"
                      ? "bg-primary/5 dark:bg-primary/10 border-primary shadow-xs"
                      : "bg-slate-50/50 dark:bg-slate-900/30 border-slate-200/60 dark:border-slate-800/60 hover:border-slate-300 dark:hover:border-slate-700"
                  }`}
                >
                  <div className="font-semibold text-sm text-slate-800 dark:text-slate-100 flex items-center gap-1.5">
                    {selectedPromptId === "custom" && <span className="w-1.5 h-1.5 rounded-full bg-primary" />}
                    ✏️ 自定义提示词 (Custom Prompt)
                  </div>
                  <p className="mt-1 text-xs text-slate-500 dark:text-slate-400">
                    自定义编写提示词对抓取到的当期数据进行特定问题解答
                  </p>
                </div>
              </div>

              {/* Custom Prompt Textarea if selected */}
              {selectedPromptId === "custom" && (
                <div className="mt-3 space-y-2">
                  <div className="flex items-center justify-between">
                    <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300">
                      编写自定义 Prompt：
                    </label>
                    <button
                      type="button"
                      onClick={() =>
                        setCustomPrompt(
                          DEFAULT_ANALYST_PROMPT.replace(/{period}/g, period.trim() || "262")
                        )
                      }
                      className="text-2xs text-primary hover:underline font-medium cursor-pointer"
                    >
                      填入预设专家提示词
                    </button>
                  </div>
                  <textarea
                    rows={4}
                    value={customPrompt}
                    onChange={(e) => setCustomPrompt(e.target.value)}
                    placeholder="例如：你现在是专业的澳门六合彩分析师，只分析帖文里的实码和生肖，严格过滤所有“發”“猫”“？”“0O”，给出262期热度最高的5个生肖以及重点6个号码10个号码"
                    className="w-full p-3 rounded-xl border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-900 text-sm text-slate-800 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-primary/20"
                  />
                  <div className="text-2xs text-slate-400">
                    💡 提示：您编写的提示词将自动与抓取到的 21 个预测模块内容拼接发送给大模型，支持使用 <code className="text-primary font-mono font-semibold">{"{period}"}</code> 作为期号。
                  </div>
                </div>
              )}
            </div>

            {/* Combined Payload Packaging Card */}
            <div className="p-4 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 shadow-xs space-y-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="text-base">📦</span>
                  <span className="text-xs font-bold text-slate-800 dark:text-slate-200">
                    组合发送机制 (提示词 + 抓取数据)
                  </span>
                  <span className="text-2xs px-1.5 py-0.5 rounded bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 font-medium">
                    已自动打包
                  </span>
                </div>
                <button
                  type="button"
                  onClick={() => setShowCombinedPreview(!showCombinedPreview)}
                  className="text-xs text-primary hover:text-primary/80 font-medium transition-colors cursor-pointer"
                >
                  {showCombinedPreview ? "收起预览 ▲" : "查看发送给 AI 的完整内容 ▼"}
                </button>
              </div>

              <p className="text-2xs text-slate-500 dark:text-slate-400 leading-relaxed">
                系统会自动将<strong>您的提示词指令</strong>与<strong>抓取到的 {scrapedData ? `${scrapedData.total_modules} 个核心预测模块数据` : "当期预测数据"}</strong>无缝打包在同一会话上下文中发给大模型，模型基于抓取事实逐项精算。
              </p>

              {showCombinedPreview && (
                <div className="mt-3 pt-3 border-t border-slate-100 dark:border-slate-800 space-y-3">
                  <div>
                    <div className="text-2xs font-semibold text-slate-600 dark:text-slate-400 mb-1 flex items-center justify-between">
                      <span>1. 提示词指令部分 (Prompt)：</span>
                      <span className="text-slate-400">目标期号：第 {period || "262"} 期</span>
                    </div>
                    <div className="p-2.5 rounded-xl bg-slate-50 dark:bg-slate-900 border border-slate-200/60 dark:border-slate-800/60 font-mono text-2xs text-slate-700 dark:text-slate-300 whitespace-pre-wrap max-h-36 overflow-y-auto">
                      {getCurrentPromptPreview()}
                    </div>
                  </div>

                  <div>
                    <div className="text-2xs font-semibold text-slate-600 dark:text-slate-400 mb-1 flex items-center justify-between">
                      <span>2. 注入的抓取预测数据 (Context Data)：</span>
                      <span className="text-slate-400">
                        {scrapedData
                          ? `已载入 ${scrapedData.loaded_content_count || scrapedData.total_modules} 个模块 (${formatMode === "modules_summary" ? "智能去噪文本" : "原始 HTML"})`
                          : "尚未抓取 (启动研判时自动抓取)"}
                      </span>
                    </div>
                    <div className="p-2.5 rounded-xl bg-slate-50 dark:bg-slate-900 border border-slate-200/60 dark:border-slate-800/60 font-mono text-2xs text-slate-700 dark:text-slate-300 whitespace-pre-wrap max-h-40 overflow-y-auto">
                      {getScrapedDataPreview()}
                    </div>
                  </div>

                  <div className="p-2 rounded-lg bg-emerald-500/5 dark:bg-emerald-500/10 border border-emerald-500/20 text-2xs text-emerald-700 dark:text-emerald-300 flex items-center gap-1.5">
                    <CheckBadgeIcon size={14} className="text-emerald-500 shrink-0" />
                    <span>提示词与数据已正确组合为同一请求载荷，AI 可 100% 深度参考各模块进行分析。</span>
                  </div>
                </div>
              )}
            </div>

            {/* Model & Config Card */}
            <div className="p-5 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 shadow-xs space-y-4">
              <h3 className="text-base font-bold text-slate-900 dark:text-white flex items-center gap-2">
                <ActivityIcon size={18} className="text-amber-500" />
                大模型服务商与参数
              </h3>

              <div className="space-y-3.5 text-xs sm:text-sm">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                    AI 服务商 (Provider):
                  </label>
                  <div className="grid grid-cols-3 gap-2">
                    {(["openai", "gemini", "anthropic"] as const).map((p) => (
                      <button
                        key={p}
                        onClick={() => {
                          setProvider(p);
                          setModel("");
                        }}
                        className={`py-2 px-3 rounded-xl border text-xs font-medium transition-all ${
                          provider === p
                            ? "bg-slate-900 text-white dark:bg-white dark:text-slate-900 border-transparent shadow-xs"
                            : "bg-white dark:bg-slate-900/60 border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-400"
                        }`}
                      >
                        {p === "openai" ? "OpenAI/DeepSeek" : p === "gemini" ? "Google Gemini" : "Anthropic Claude"}
                      </button>
                    ))}
                  </div>

                  {/* Provider Key Status Pill */}
                  {aiSettings && (
                    <div className="mt-2 flex items-center justify-between text-2xs px-3 py-1.5 rounded-xl bg-slate-50 dark:bg-slate-900/50 border border-slate-200/60 dark:border-slate-800/60">
                      <div className="flex items-center gap-1.5">
                        <span className="text-slate-400">密钥状态:</span>
                        {aiSettings[provider]?.is_configured ? (
                          <span className="text-emerald-600 dark:text-emerald-400 font-medium flex items-center gap-1">
                            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
                            已配置 ({aiSettings[provider]?.api_key})
                          </span>
                        ) : (
                          <span className="text-amber-500 font-medium flex items-center gap-1">
                            <span className="w-1.5 h-1.5 rounded-full bg-amber-500" />
                            未配置密钥
                          </span>
                        )}
                      </div>
                      <button
                        type="button"
                        onClick={() => navigate("/settings")}
                        className="text-primary hover:underline font-medium cursor-pointer"
                      >
                        去配置地址与Key &rarr;
                      </button>
                    </div>
                  )}
                </div>

                <div>
                  <div className="flex items-center justify-between mb-1.5">
                    <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300">
                      模型名称 (Model Override):
                    </label>
                    {aiSettings?.[provider]?.model && (
                      <span className="text-2xs text-slate-400">
                        系统配置: <strong className="text-primary font-mono">{aiSettings[provider].model}</strong>
                      </span>
                    )}
                  </div>
                  <input
                    type="text"
                    value={model}
                    onChange={(e) => setModel(e.target.value)}
                    placeholder={
                      aiSettings?.[provider]?.model
                        ? `留空则使用系统配置: ${aiSettings[provider].model}`
                        : provider === "openai"
                        ? "默认: deepseek-chat (或 qwen-plus, gpt-4o)"
                        : provider === "gemini"
                        ? "默认: gemini-2.5-flash"
                        : "默认: claude-3-5-sonnet"
                    }
                    className="w-full h-9 px-3 rounded-xl border border-slate-200 dark:border-slate-800 bg-white dark:bg-[#0c1220] text-xs text-slate-800 dark:text-slate-200 focus:outline-none focus:ring-2 focus:ring-primary/20"
                  />
                  <div className="flex items-center justify-between text-2xs text-slate-400 mt-1">
                    <span>
                      当前生效:{" "}
                      <strong className="text-emerald-600 dark:text-emerald-400 font-mono font-medium">
                        {model.trim() || aiSettings?.[provider]?.model || "默认模型"}
                      </strong>
                    </span>
                    {model.trim() && (
                      <button
                        type="button"
                        onClick={() => setModel("")}
                        className="text-primary hover:underline cursor-pointer"
                      >
                        清除覆盖，使用系统配置
                      </button>
                    )}
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1.5">
                    数据上下文模式 (Context Mode):
                  </label>
                  <div className="grid grid-cols-2 gap-2">
                    <button
                      onClick={() => setFormatMode("modules_summary")}
                      className={`p-2.5 rounded-xl border text-left text-xs transition-all ${
                        formatMode === "modules_summary"
                          ? "border-primary bg-primary/5 text-primary font-semibold"
                          : "border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-400"
                      }`}
                    >
                      <div>🚀 智能去噪 (推荐)</div>
                      <div className="text-2xs font-normal text-slate-400 mt-0.5">压缩至 12KB 核心预测</div>
                    </button>
                    <button
                      onClick={() => setFormatMode("raw_html")}
                      className={`p-2.5 rounded-xl border text-left text-xs transition-all ${
                        formatMode === "raw_html"
                          ? "border-primary bg-primary/5 text-primary font-semibold"
                          : "border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-400"
                      }`}
                    >
                      <div>🌐 原始全量 HTML</div>
                      <div className="text-2xs font-normal text-slate-400 mt-0.5">320KB 完整代码结构</div>
                    </button>
                  </div>
                </div>

                <div>
                  <div className="flex justify-between text-xs font-semibold text-slate-700 dark:text-slate-300 mb-1">
                    <span>生成发散度 (Temperature):</span>
                    <span>{temperature}</span>
                  </div>
                  <input
                    type="range"
                    min="0"
                    max="1.5"
                    step="0.1"
                    value={temperature}
                    onChange={(e) => setTemperature(parseFloat(e.target.value))}
                    className="w-full accent-primary"
                  />
                </div>
              </div>

              {/* Not Configured Notice Banner */}
              {aiSettings && !aiSettings[provider]?.is_configured && (
                <div className="p-3 rounded-xl bg-amber-500/10 border border-amber-500/20 text-amber-700 dark:text-amber-300 text-xs flex items-center justify-between">
                  <span>当前 {provider === "openai" ? "OpenAI/DeepSeek" : provider} 服务商尚未配置 API Key。</span>
                  <button
                    onClick={() => navigate("/settings")}
                    className="font-semibold underline shrink-0 cursor-pointer ml-2"
                  >
                    立即前往配置
                  </button>
                </div>
              )}

              <button
                onClick={handleRunAI}
                disabled={isAnalyzing}
                className="w-full py-3 rounded-xl text-sm font-semibold bg-primary hover:bg-primary/90 text-white shadow-sm transition-all disabled:opacity-50 flex items-center justify-center gap-2"
              >
                <SparklesIcon size={18} />
                {isAnalyzing ? "正在向大模型传输数据并研判中..." : "启动大模型智能研判"}
              </button>
            </div>
          </div>

          {/* Right Column: AI Analysis Result Output */}
          <div className="xl:col-span-7 space-y-6">
            <div className="p-6 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 shadow-xs min-h-[500px] flex flex-col">
              {/* Header Bar */}
              <div className="flex items-center justify-between pb-4 border-b border-slate-100 dark:border-slate-800/60">
                <div className="flex items-center gap-2">
                  <h3 className="font-bold text-base text-slate-900 dark:text-white flex items-center gap-2">
                    <span className="flex h-2.5 w-2.5 rounded-full bg-emerald-500 animate-pulse" />
                    AI 研判分析报告
                  </h3>
                  {aiResult && (
                    <span className="text-2xs px-2 py-0.5 rounded-md bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 font-mono">
                      {aiResult.provider} / {aiResult.model} • {aiResult.elapsed_sec}s
                    </span>
                  )}
                </div>

                {aiResult && (
                  <div className="flex items-center gap-2">
                    <button
                      onClick={copyAnalysis}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700 transition-colors"
                    >
                      {copied ? <CheckBadgeIcon size={14} className="text-emerald-500" /> : null}
                      {copied ? "已复制" : "复制报告"}
                    </button>
                  </div>
                )}
              </div>

              {/* Error Message */}
              {aiError && (
                <div className="mt-4 p-4 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-600 dark:text-rose-400 text-sm">
                  {aiError}
                </div>
              )}

              {/* Content Body */}
              <div className="flex-1 mt-4">
                {isAnalyzing && !aiResult?.analysis ? (
                  <div className="py-20 flex flex-col items-center justify-center text-center space-y-4">
                    <div className="relative">
                      <div className="w-12 h-12 rounded-full border-4 border-primary/20 border-t-primary animate-spin" />
                      <SparklesIcon size={20} className="text-primary absolute inset-0 m-auto" />
                    </div>
                    <div className="space-y-1">
                      <p className="text-sm font-semibold text-slate-800 dark:text-slate-200">
                        {streamStatus || "正在结合当期抓取数据进行 AI 精算研判..."}
                      </p>
                      <p className="text-xs text-slate-400">
                        正在对料提炼 21 个预测卡片共识、号码重合度与防守生肖
                      </p>
                    </div>
                  </div>
                ) : aiResult && aiResult.analysis ? (
                  <div className="space-y-4">
                    {/* Live streaming status bar */}
                    {isAnalyzing && (
                      <div className="flex items-center justify-between px-3.5 py-2 rounded-xl bg-primary/5 border border-primary/20 text-xs text-primary font-medium">
                        <span className="flex items-center gap-2">
                          <span className="w-2 h-2 rounded-full bg-primary animate-ping" />
                          {streamStatus || "大模型正在实时流式推理输出中..."}
                        </span>
                        <span className="font-mono text-2xs opacity-70">流式输出中</span>
                      </div>
                    )}

                    {/* Token Stats Bar */}
                    {!isAnalyzing && aiResult.usage && Object.keys(aiResult.usage).length > 0 && (
                      <div className="flex items-center gap-4 text-xs font-mono text-slate-400 px-3 py-2 rounded-xl bg-slate-50 dark:bg-slate-900/40 border border-slate-100 dark:border-slate-800/40">
                        <span>输入 Token: {aiResult.usage.prompt_tokens ?? "-"}</span>
                        <span>•</span>
                        <span>输出 Token: {aiResult.usage.completion_tokens ?? "-"}</span>
                        <span>•</span>
                        <span>总 Token: {aiResult.usage.total_tokens ?? "-"}</span>
                      </div>
                    )}

                    {/* Report Content with live cursor */}
                    <div className="prose prose-sm dark:prose-invert max-w-none leading-relaxed text-slate-800 dark:text-slate-200 font-sans whitespace-pre-wrap selection:bg-primary/20">
                      {aiResult.analysis}
                      {isAnalyzing && (
                        <span className="inline-block w-2 h-4 ml-0.5 bg-primary animate-pulse align-middle" />
                      )}
                    </div>
                  </div>
                ) : (
                  <div className="py-24 flex flex-col items-center justify-center text-center text-slate-400 space-y-3">
                    <SparklesIcon size={40} className="text-slate-300 dark:text-slate-700" />
                    <p className="text-sm">点击左侧或右上角 “执行 AI 研判” 即可生成当期深度对料报告</p>
                    <p className="text-xs text-slate-500">
                      系统将以流式输出实时呈现大模型对料分析全过程
                    </p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* TAB 2: 数据源抓取与预览 */}
      {activeTab === "data" && (
        <div className="space-y-6">
          {/* Stats Bar */}
          {scrapedData ? (
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
              <div className="p-4 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80">
                <div className="text-xs text-slate-400">页面模块总数</div>
                <div className="text-2xl font-bold text-slate-900 dark:text-white mt-1">
                  {scrapedData.total_modules} <span className="text-xs font-normal text-slate-400">个</span>
                </div>
              </div>
              <div className="p-4 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80">
                <div className="text-xs text-slate-400">核心预测懒加载卡片</div>
                <div className="text-2xl font-bold text-emerald-600 dark:text-emerald-400 mt-1">
                  {scrapedData.loaded_content_count} / {scrapedData.content_modules_count}
                </div>
              </div>
              <div className="p-4 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80">
                <div className="text-xs text-slate-400">拼装 HTML 体积</div>
                <div className="text-2xl font-bold text-slate-900 dark:text-white mt-1">
                  {(scrapedData.html_size_bytes / 1024).toFixed(1)}{" "}
                  <span className="text-xs font-normal text-slate-400">KB</span>
                </div>
              </div>
              <div className="p-4 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80">
                <div className="text-xs text-slate-400">抓取与组装耗时</div>
                <div className="text-2xl font-bold text-indigo-600 dark:text-indigo-400 mt-1">
                  {scrapedData.elapsed_sec} <span className="text-xs font-normal text-slate-400">秒</span>
                </div>
              </div>
            </div>
          ) : (
            <div className="p-8 rounded-2xl bg-white dark:bg-[#0c1220] border border-dashed border-slate-200 dark:border-slate-800 text-center space-y-3">
              <DatabaseIcon size={36} className="text-slate-400 mx-auto" />
              <p className="text-sm text-slate-600 dark:text-slate-300">尚未加载网页数据</p>
              <button
                onClick={handleScrape588080}
                disabled={isScraping}
                className="px-4 py-2 rounded-xl text-xs font-semibold bg-primary text-white"
              >
                {isScraping ? "正在获取中..." : "立即获取全量数据"}
              </button>
            </div>
          )}

          {/* Module List & Filter */}
          {scrapedData && (
            <div className="p-5 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 space-y-4">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div className="flex items-center gap-2">
                  <h3 className="font-bold text-base text-slate-900 dark:text-white">
                    抓取到的模块清单 ({filteredModules.length})
                  </h3>
                  <button
                    onClick={downloadHtml}
                    className="text-xs text-primary font-semibold hover:underline ml-2"
                  >
                    下载完整单文件 HTML
                  </button>
                </div>

                <div className="flex items-center gap-2">
                  <input
                    type="text"
                    placeholder="按栏目名称搜索..."
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    className="h-8 px-3 rounded-lg border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-900 text-xs text-slate-800 dark:text-slate-200"
                  />
                  <select
                    value={filterType}
                    onChange={(e) => setFilterType(e.target.value)}
                    className="h-8 px-2.5 rounded-lg border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-900 text-xs text-slate-800 dark:text-slate-200"
                  >
                    <option value="all">全部类型</option>
                    <option value="content">核心预测 (content)</option>
                    <option value="code">注入代码 (code)</option>
                    <option value="publicCode">广告/跑量 (publicCode)</option>
                    <option value="system">系统模块 (system)</option>
                    <option value="style">样式 (style)</option>
                  </select>
                </div>
              </div>

              {/* Modules Grid */}
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3 max-h-[450px] overflow-y-auto pr-1">
                {filteredModules.map((m) => {
                  const hasContent = !!(m.content && m.content.trim().length > 0);
                  const isContent = m.type === "content";
                  return (
                    <div
                      key={m.id}
                      onClick={() => setSelectedModule(m)}
                      className="p-3 rounded-xl border border-slate-200/70 dark:border-slate-800/70 hover:border-primary/50 bg-slate-50/50 dark:bg-slate-900/30 cursor-pointer transition-all flex flex-col justify-between"
                    >
                      <div className="flex items-start justify-between gap-2">
                        <div className="font-semibold text-xs text-slate-900 dark:text-white truncate">
                          {m.name}
                        </div>
                        <span
                          className={`text-2xs px-1.5 py-0.5 rounded font-mono ${
                            isContent
                              ? "bg-emerald-500/10 text-emerald-600 dark:text-emerald-400"
                              : "bg-slate-200/60 dark:bg-slate-800 text-slate-500"
                          }`}
                        >
                          {m.type}
                        </span>
                      </div>
                      <div className="mt-2 flex items-center justify-between text-2xs text-slate-400">
                        <span>ID: {m.id}</span>
                        <span>{hasContent ? `${(m.content || "").length} 字符` : "无独立文本"}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Module Detail Modal / Preview */}
          {selectedModule && (
            <div className="p-5 rounded-2xl bg-white dark:bg-[#0c1220] border border-primary/40 space-y-3">
              <div className="flex items-center justify-between border-b border-slate-100 dark:border-slate-800 pb-2">
                <div className="flex items-center gap-2">
                  <span className="font-bold text-sm text-slate-900 dark:text-white">
                    模块详情: 【{selectedModule.name}】
                  </span>
                  <span className="text-xs text-slate-400 font-mono">
                    (类型: {selectedModule.type}, ID: {selectedModule.id})
                  </span>
                </div>
                <button
                  onClick={() => setSelectedModule(null)}
                  className="text-xs text-slate-400 hover:text-slate-600 dark:hover:text-slate-200"
                >
                  关闭
                </button>
              </div>

              <div className="space-y-2">
                <div className="text-xs font-semibold text-slate-500">提取到的 HTML 片段预览：</div>
                <pre className="p-3 rounded-xl bg-slate-950 text-slate-300 text-xs font-mono overflow-x-auto max-h-60 leading-relaxed">
                  {selectedModule.content || "(空)"}
                </pre>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
