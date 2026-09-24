import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api, settingsApi, type AISettings } from "../../lib/api";
import { PageWorkspace, SegmentedTabs } from "./shared";
import {
  SparklesIcon,
  DatabaseIcon,
  ActivityIcon,
  SettingsIcon,
  ChevronDownIcon,
} from "../../components/icons";
import {
  loadReportHistory,
  saveReportHistory,
  type AIResult,
  type AnalysisMode,
  type PromptInfo,
  type ReportEntry,
  type ScrapedSummary,
} from "./ai/types";
import { ReportCanvas } from "./ai/ReportCanvas";
import { PromptDock, DEFAULT_ANALYST_PROMPT } from "./ai/PromptDock";
import { DataPanel } from "./ai/DataPanel";
import { StreakConfigBar, StreakDataView } from "./ai/StreakPanel";
import { AdvancedDrawer } from "./ai/AdvancedDrawer";

const PROVIDERS = [
  { id: "openai" as const, label: "OpenAI" },
  { id: "gemini" as const, label: "Gemini" },
  { id: "anthropic" as const, label: "Claude" },
];

export function CollectorAIAnalysisPage() {
  const navigate = useNavigate();

  // ── 研判模式（帖文 / 连肖，共用同一报告画布）──
  const [mode, setMode] = useState<AnalysisMode>(() => {
    return (localStorage.getItem("duiliao_ai_mode") as AnalysisMode) || "post";
  });
  useEffect(() => {
    localStorage.setItem("duiliao_ai_mode", mode);
  }, [mode]);

  // ── 提示词与参数（跨刷新持久化）──
  const [prompts, setPrompts] = useState<PromptInfo[]>([]);
  const [selectedPromptId, setSelectedPromptId] = useState<string>(() => {
    const saved = localStorage.getItem("duiliao_prompt_id") || "macau_analyst_expert";
    // 连肖模板只吃按期开奖数据，放在帖文研判里会对空。
    return saved === "zodiac_streak_analysis" ? "macau_analyst_expert" : saved;
  });
  const [period, setPeriod] = useState<string>(() => localStorage.getItem("duiliao_period") || "262");
  const [customPrompt, setCustomPrompt] = useState<string>(() => localStorage.getItem("duiliao_custom_prompt") || "");
  const [provider, setProvider] = useState<"openai" | "gemini" | "anthropic">(() => {
    return (localStorage.getItem("duiliao_provider") as any) || "openai";
  });
  const [model, setModel] = useState<string>(() => localStorage.getItem("duiliao_model_override") || "");
  const [formatMode, setFormatMode] = useState<"modules_summary" | "raw_html">(() => {
    return (localStorage.getItem("duiliao_format_mode") as any) || "modules_summary";
  });
  const [temperature, setTemperature] = useState(0.7);
  const [aiSettings, setAiSettings] = useState<AISettings | null>(null);

  useEffect(() => { localStorage.setItem("duiliao_prompt_id", selectedPromptId); }, [selectedPromptId]);
  useEffect(() => { localStorage.setItem("duiliao_period", period); }, [period]);
  useEffect(() => { localStorage.setItem("duiliao_custom_prompt", customPrompt); }, [customPrompt]);
  useEffect(() => { localStorage.setItem("duiliao_provider", provider); }, [provider]);
  useEffect(() => { localStorage.setItem("duiliao_model_override", model); }, [model]);
  useEffect(() => { localStorage.setItem("duiliao_format_mode", formatMode); }, [formatMode]);

  // ── 帖文数据 ──
  const [scrapedData, setScrapedData] = useState<ScrapedSummary | null>(null);
  const [isScraping, setIsScraping] = useState(false);
  const [scrapeError, setScrapeError] = useState<string | null>(null);

  // ── 帖文研判执行 ──
  const [isAnalyzing, setIsAnalyzing] = useState(false);
  const [streamStatus, setStreamStatus] = useState("");
  const [aiError, setAiError] = useState<string | null>(null);
  const [aiResult, setAiResult] = useState<AIResult | null>(null);
  const analysisRef = useRef("");

  // ── 连肖研判 ──
  const [streakLottery, setStreakLottery] = useState<"macau" | "hk">("macau");
  const [streakNumPeriods, setStreakNumPeriods] = useState(30);
  const [streakMinStreak, setStreakMinStreak] = useState(3);
  const [streakData, setStreakData] = useState<any>(null);
  const [isLoadingStreakData, setIsLoadingStreakData] = useState(false);
  const [streakDataError, setStreakDataError] = useState<string | null>(null);
  const [isStreakAnalyzing, setIsStreakAnalyzing] = useState(false);
  const [streakStreamStatus, setStreakStreamStatus] = useState("");
  const [streakAiError, setStreakAiError] = useState<string | null>(null);
  const [streakAiResult, setStreakAiResult] = useState<AIResult | null>(null);
  const streakAnalysisRef = useRef("");

  // ── 报告历史与面板开关 ──
  const [history, setHistory] = useState<ReportEntry[]>(() => loadReportHistory());
  const [viewing, setViewing] = useState<ReportEntry | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [showContext, setShowContext] = useState(false);

  // ── 初始化：模板列表、最新期号、AI 设置 ──
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
      .catch((err) => console.warn("Failed to load prompts:", err));

    api
      .get<{ items?: { period?: string }[] }>("/collector/draws?lottery=macau&limit=1")
      .then((res) => {
        const full = res.items?.[0]?.period || "";
        const short = full.length >= 3 ? full.slice(-3) : "";
        const latest = Number(short);
        const saved = Number(localStorage.getItem("duiliao_period") || "");
        if (!short || !Number.isFinite(latest)) return;
        if (!Number.isFinite(saved) || latest - saved >= 2) {
          setPeriod(short);
        }
      })
      .catch(() => {});

    settingsApi
      .getAISettings()
      .then((cfg) => {
        setAiSettings(cfg);
        const savedProvider = localStorage.getItem("duiliao_provider");
        if (!savedProvider && cfg?.default_provider) {
          setProvider(cfg.default_provider as any);
        }
      })
      .catch((err) => console.warn("Failed to load AI settings:", err));
  }, []);

  const pushHistory = (entry: ReportEntry) => {
    setHistory((prev) => {
      const next = [entry, ...prev.filter((h) => h.id !== entry.id)].slice(0, 8);
      saveReportHistory(next);
      return next;
    });
  };

  // ── 抓取 588080 ──
  const handleScrape = async () => {
    setIsScraping(true);
    setScrapeError(null);
    try {
      const res = await api.post<ScrapedSummary>("/collector/site-dump/588080", {
        include_html: true,
        include_modules: true,
        timeout: 45.0,
      });
      setScrapedData(res);
      setShowContext(true);

      // 从抓取内容中自动识别期号
      const allText = (res.modules || []).map((m: any) => m.content || "").join(" ");
      const match = allText.match(/(?:第\s*)?(\d{3})\s*期/);
      if (match && match[1]) setPeriod(match[1]);
    } catch (err: any) {
      setScrapeError(err?.message || "抓取数据失败，请检查网络连接");
    } finally {
      setIsScraping(false);
    }
  };

  // ── 帖文研判（流式）──
  const handleRunAI = async () => {
    setMode("post");
    setViewing(null);
    setIsAnalyzing(true);
    setAiError(null);
    setStreamStatus("正在连接大模型并准备上下文...");
    analysisRef.current = "";
    setAiResult({
      ok: true,
      provider,
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
        provider,
        format_mode: formatMode,
        temperature,
        fetch_fresh: !scrapedData,
      };
      if (model.trim()) payload.model = model.trim();
      if (selectedPromptId === "custom" && customPrompt.trim()) {
        payload.custom_prompt = customPrompt.trim();
      }
      if (scrapedData) {
        payload.fetch_fresh = false;
        payload.custom_data = scrapedData;
      }

      await api.stream("/ai/analyze-stream", payload, {
        onStatus: (st) => {
          if (st.message) setStreamStatus(st.message);
        },
        onChunk: (delta) => {
          analysisRef.current += delta;
          setAiResult((prev) =>
            prev
              ? { ...prev, analysis: prev.analysis + delta }
              : {
                  ok: true, provider, model: model || "default",
                  prompt_id: selectedPromptId, analysis: delta, usage: {}, elapsed_sec: 0,
                }
          );
        },
        onDone: (doneInfo) => {
          setAiResult((prev) => (prev ? { ...prev, ...doneInfo } : null));
          setStreamStatus("");
          if (analysisRef.current.trim()) {
            pushHistory({
              id: `post-${Date.now()}`,
              ts: Date.now(),
              mode: "post",
              label: `第${period.trim() || "262"}期`,
              provider: doneInfo.provider || provider,
              model: doneInfo.model || model || "default",
              elapsed_sec: doneInfo.elapsed_sec || 0,
              usage: doneInfo.usage || {},
              analysis: analysisRef.current,
            });
          }
        },
        onError: (err) => setAiError(err.message || "AI 流式分析异常中断"),
      });
    } catch (err: any) {
      setAiError(err?.message || "AI 研判分析调用失败");
    } finally {
      setIsAnalyzing(false);
      setStreamStatus("");
    }
  };

  // ── 连肖数据查询 ──
  const handleLoadStreakData = async () => {
    setIsLoadingStreakData(true);
    setStreakDataError(null);
    try {
      const res = await api.get<any>(
        `/ai/zodiac-streak-data?lottery=${streakLottery}&num_periods=${streakNumPeriods}&min_streak=${streakMinStreak}`
      );
      setStreakData(res);
      setShowContext(true);
    } catch (err: any) {
      setStreakDataError(err?.message || "查询连肖数据失败");
    } finally {
      setIsLoadingStreakData(false);
    }
  };

  // ── 连肖研判（流式）──
  const handleRunStreakAI = async () => {
    setMode("streak");
    setViewing(null);
    setIsStreakAnalyzing(true);
    setStreakAiError(null);
    setStreakStreamStatus("正在查询开奖数据并计算连肖走势...");
    streakAnalysisRef.current = "";
    setStreakAiResult({
      ok: true,
      provider,
      model: model || "default",
      prompt_id: "zodiac_streak_analysis",
      analysis: "",
      usage: {},
      elapsed_sec: 0,
    });

    try {
      const payload: any = {
        lottery: streakLottery,
        num_periods: streakNumPeriods,
        min_streak: streakMinStreak,
        prompt_id: "zodiac_streak_analysis",
        provider,
        temperature,
      };
      if (model.trim()) payload.model = model.trim();

      await api.stream("/ai/zodiac-streak-stream", payload, {
        onStatus: (st) => {
          if (st.message) setStreakStreamStatus(st.message);
        },
        onChunk: (delta) => {
          streakAnalysisRef.current += delta;
          setStreakAiResult((prev) =>
            prev
              ? { ...prev, analysis: prev.analysis + delta }
              : {
                  ok: true, provider, model: model || "default",
                  prompt_id: "zodiac_streak_analysis", analysis: delta, usage: {}, elapsed_sec: 0,
                }
          );
        },
        onDone: (doneInfo) => {
          setStreakAiResult((prev) => (prev ? { ...prev, ...doneInfo } : null));
          setStreakStreamStatus("");
          if (streakAnalysisRef.current.trim()) {
            pushHistory({
              id: `streak-${Date.now()}`,
              ts: Date.now(),
              mode: "streak",
              label: `${streakLottery === "macau" ? "澳门" : "香港"}·近${streakNumPeriods}期`,
              provider: doneInfo.provider || provider,
              model: doneInfo.model || model || "default",
              elapsed_sec: doneInfo.elapsed_sec || 0,
              usage: doneInfo.usage || {},
              analysis: streakAnalysisRef.current,
            });
          }
        },
        onError: (err) => setStreakAiError(err.message || "AI 连肖分析异常中断"),
      });
    } catch (err: any) {
      setStreakAiError(err?.message || "AI 连肖分析调用失败");
    } finally {
      setIsStreakAnalyzing(false);
      setStreakStreamStatus("");
    }
  };

  // ── 载荷预览（抽屉用）──
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
        .replace(/---\s*\{context_data\}\s*---/g, "[... 此处自动嵌入抓取的数据内容 ...]");
    }
    return DEFAULT_ANALYST_PROMPT.replace(/{period}/g, targetPeriod);
  };

  const getScrapedDataPreview = () => {
    if (!scrapedData) {
      return "【提示】当前尚未抓取网页数据，启动研判时系统将自动抓取并注入此处。";
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

  // ── 当前模式下的画布状态 ──
  const isPost = mode === "post";
  const curAnalyzing = isPost ? isAnalyzing : isStreakAnalyzing;
  const effectiveModel = model.trim() || aiSettings?.[provider]?.model || "默认模型";
  const keyMissing = aiSettings ? !aiSettings[provider]?.is_configured : false;

  const dataStatus = isPost ? (
    isScraping ? (
      <span className="inline-flex items-center gap-1.5 text-2xs font-medium text-violet-600 dark:text-violet-300">
        <span className="h-1.5 w-1.5 animate-ping rounded-full bg-violet-500" />
        正在抓取...
      </span>
    ) : scrapedData ? (
      <span className="inline-flex items-center gap-1.5 text-2xs font-medium text-emerald-600 dark:text-emerald-400">
        <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
        数据就绪 · {scrapedData.loaded_content_count || scrapedData.total_modules} 模块
      </span>
    ) : (
      <span className="inline-flex items-center gap-1.5 text-2xs font-medium text-amber-500">
        <span className="h-1.5 w-1.5 rounded-full bg-amber-500" />
        未抓取 · 研判时自动抓取
      </span>
    )
  ) : streakData ? (
    <span className="inline-flex items-center gap-1.5 text-2xs font-medium text-emerald-600 dark:text-emerald-400">
      <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
      连肖数据已加载 · {streakData.num_periods} 期
    </span>
  ) : (
    <span className="inline-flex items-center gap-1.5 text-2xs font-medium text-amber-500">
      <span className="h-1.5 w-1.5 rounded-full bg-amber-500" />
      连肖数据未预览 · 研判时自动查询
    </span>
  );

  return (
    <PageWorkspace summary="选定模式与期号，一键启动大模型研判；报告流式呈现，历史自动沉淀。高级参数收在右侧抽屉。">
      {/* ═══ 指挥条 ═══ */}
      <div className="sticky top-[5rem] z-20 flex flex-wrap items-center gap-x-3 gap-y-2.5 rounded-2xl glass-bar p-3.5">
        <SegmentedTabs
          tabs={[
            { id: "post" as const, label: "帖文研判", icon: <SparklesIcon size={15} /> },
            { id: "streak" as const, label: "连肖研判", icon: <ActivityIcon size={15} /> },
          ]}
          activeTab={mode}
          onChange={(m) => {
            setMode(m);
            setViewing(null);
          }}
        />

        {isPost && (
          <div className="flex items-center gap-1 rounded-xl glass-subtle px-2.5 py-1.5">
            <span className="text-2xs font-medium text-slate-400">第</span>
            <input
              type="text"
              value={period}
              onChange={(e) => setPeriod(e.target.value)}
              placeholder="262"
              className="w-12 bg-transparent text-center text-sm font-bold text-primary outline-none"
            />
            <span className="text-2xs font-medium text-slate-400">期</span>
          </div>
        )}

        <div className="hidden sm:block">{dataStatus}</div>

        {keyMissing && (
          <button
            onClick={() => navigate("/settings")}
            title={`当前服务商未配置 API Key，点击前往系统设置`}
            className="inline-flex cursor-pointer items-center gap-1.5 rounded-lg bg-amber-500/10 px-2.5 py-1.5 text-2xs font-medium text-amber-600 transition-colors hover:bg-amber-500/15 dark:text-amber-400"
          >
            <span className="h-1.5 w-1.5 rounded-full bg-amber-500" />
            未配置密钥 · 去配置
          </button>
        )}

        <div className="ml-auto flex flex-wrap items-center gap-2">
          {/* 服务商快切 */}
          <div className="flex items-center gap-1 rounded-xl glass-subtle p-1">
            {PROVIDERS.map((p) => {
              const active = provider === p.id;
              const noKey = aiSettings ? !aiSettings[p.id]?.is_configured : false;
              return (
                <button
                  key={p.id}
                  onClick={() => {
                    setProvider(p.id);
                    setModel("");
                  }}
                  title={noKey ? `${p.label} · 未配置密钥` : p.label}
                  className={`relative cursor-pointer rounded-lg px-2.5 py-1.5 text-xs font-medium transition-all ${
                    active
                      ? "glow-button border-0 shadow-xs"
                      : "text-slate-600 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white"
                  }`}
                >
                  {p.label}
                  {noKey && !active && (
                    <span className="absolute -right-0.5 -top-0.5 h-2 w-2 rounded-full border border-white bg-amber-500 dark:border-slate-900" />
                  )}
                </button>
              );
            })}
          </div>

          {/* 当前模型 → 打开抽屉 */}
          <button
            onClick={() => setDrawerOpen(true)}
            title="高级参数：模型覆盖 / 上下文模式 / 温度 / 组合载荷"
            className="hidden max-w-40 cursor-pointer items-center gap-1 truncate rounded-xl glass-subtle px-2.5 py-1.5 font-mono text-2xs text-slate-500 transition-colors hover:text-slate-800 md:inline-flex dark:text-slate-400 dark:hover:text-slate-200"
          >
            {effectiveModel}
            <ChevronDownIcon size={12} />
          </button>

          <button
            onClick={() => setDrawerOpen(true)}
            className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl px-3 py-2 text-xs font-semibold text-slate-700 glass-subtle transition-all hover:bg-violet-500/5 dark:text-slate-300 dark:hover:bg-violet-400/5"
          >
            <SettingsIcon size={14} />
            高级
          </button>

          {isPost && (
            <button
              onClick={handleScrape}
              disabled={isScraping}
              className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl px-3 py-2 text-xs font-semibold text-slate-700 glass-subtle transition-all hover:bg-violet-500/5 disabled:opacity-50 dark:text-slate-300 dark:hover:bg-violet-400/5"
            >
              <DatabaseIcon size={14} />
              {isScraping ? "抓取中..." : "抓取数据"}
            </button>
          )}

          {/* 主 CTA */}
          <button
            onClick={isPost ? handleRunAI : handleRunStreakAI}
            disabled={curAnalyzing}
            className="glow-button inline-flex cursor-pointer items-center gap-2 rounded-xl border-0 px-5 py-2.5 text-sm font-bold transition-all disabled:opacity-50"
          >
            <SparklesIcon size={16} />
            {curAnalyzing ? "研判中..." : isPost ? "开始研判" : "AI 连肖研判"}
          </button>
        </div>
      </div>

      {/* ═══ 配置带 ═══ */}
      {isPost ? (
        <div className="rounded-3xl glass-card p-4">
          <PromptDock
            prompts={prompts}
            selectedId={selectedPromptId}
            onSelect={setSelectedPromptId}
            customPrompt={customPrompt}
            onCustomPromptChange={setCustomPrompt}
            period={period}
          />
        </div>
      ) : (
        <StreakConfigBar
          lottery={streakLottery}
          numPeriods={streakNumPeriods}
          minStreak={streakMinStreak}
          onLottery={setStreakLottery}
          onNumPeriods={setStreakNumPeriods}
          onMinStreak={setStreakMinStreak}
          onLoadData={handleLoadStreakData}
          isLoadingData={isLoadingStreakData}
        />
      )}

      {/* ═══ 报告画布（主角）═══ */}
      <ReportCanvas
        accent={isPost ? "violet" : "fuchsia"}
        title={isPost ? "AI 帖文研判报告" : "AI 连肖走势研判报告"}
        contextLabel={
          isPost
            ? `第 ${period.trim() || "262"} 期`
            : `${streakLottery === "macau" ? "澳门" : "香港"} · 近${streakNumPeriods}期 ≥${streakMinStreak}连`
        }
        result={isPost ? aiResult : streakAiResult}
        isAnalyzing={curAnalyzing}
        streamStatus={isPost ? streamStatus : streakStreamStatus}
        error={isPost ? aiError || scrapeError : streakAiError}
        emptyHint={
          isPost
            ? {
                title: "点击上方「开始研判」生成当期深度对料报告",
                subtitle: "系统将自动抓取预测栏目数据，与提示词打包后以流式输出实时呈现大模型分析全过程。",
              }
            : {
                title: "配置参数后点击「AI 连肖研判」",
                subtitle: "系统按期分组提取生肖，送入 AI 后按三连、四连、五连、复式、N 连五类输出报告。",
              }
        }
        loadingHint={
          isPost
            ? "正在对料提炼预测卡片共识、号码重合度与防守生肖"
            : `查询 ${streakNumPeriods} 期开奖数据，计算连肖统计并送入 AI 深度研判`
        }
        history={history.filter((h) => h.mode === mode)}
        viewing={viewing}
        onViewHistory={setViewing}
        onClearHistory={() => {
          const next = history.filter((h) => h.mode !== mode);
          setHistory(next);
          saveReportHistory(next);
          setViewing(null);
        }}
      />

      {/* ═══ 上下文数据（可折叠，画布之下）═══ */}
      <div className="rounded-3xl glass-card">
        <button
          onClick={() => setShowContext((v) => !v)}
          className="flex w-full cursor-pointer items-center justify-between px-5 py-3.5 text-left"
        >
          <span className="flex items-center gap-2 text-sm font-bold text-slate-900 dark:text-white">
            <DatabaseIcon size={16} className={isPost ? "text-violet-500" : "text-fuchsia-500"} />
            {isPost ? "注入上下文数据" : "连肖数据预览"}
            {isPost && scrapedData && (
              <span className="rounded-md bg-emerald-500/10 px-2 py-0.5 text-2xs font-semibold text-emerald-600 dark:text-emerald-400">
                {scrapedData.total_modules} 模块已就绪
              </span>
            )}
            {!isPost && streakData && (
              <span className="rounded-md bg-emerald-500/10 px-2 py-0.5 text-2xs font-semibold text-emerald-600 dark:text-emerald-400">
                已加载
              </span>
            )}
          </span>
          <ChevronDownIcon
            size={16}
            className={`text-slate-400 transition-transform ${showContext ? "rotate-180" : ""}`}
          />
        </button>
        {showContext && (
          <div className="border-t border-slate-200/40 p-4 dark:border-white/5">
            {isPost ? (
              <DataPanel
                data={scrapedData}
                isScraping={isScraping}
                error={scrapeError}
                onScrape={handleScrape}
              />
            ) : streakDataError ? (
              <div className="rounded-xl border border-rose-400/40 bg-rose-500/10 p-4 text-sm text-rose-700 dark:border-rose-400/25 dark:text-rose-300">
                {streakDataError}
              </div>
            ) : streakData ? (
              <StreakDataView data={streakData} />
            ) : (
              <div className="flex flex-col items-center gap-2 py-8 text-center">
                <ActivityIcon size={28} className="text-slate-300 dark:text-slate-600" />
                <p className="text-sm text-slate-500">尚未加载连肖数据</p>
                <p className="text-2xs text-slate-400">
                  点击参数条上的「查看连肖数据」预览送入口径，或直接启动 AI 连肖研判。
                </p>
              </div>
            )}
          </div>
        )}
      </div>

      {/* ═══ 高级参数抽屉 ═══ */}
      <AdvancedDrawer
        open={drawerOpen}
        onClose={() => setDrawerOpen(false)}
        provider={provider}
        aiSettings={aiSettings}
        model={model}
        onModelChange={setModel}
        formatMode={formatMode}
        onFormatModeChange={setFormatMode}
        temperature={temperature}
        onTemperatureChange={setTemperature}
        period={period}
        promptPreview={getCurrentPromptPreview()}
        dataPreview={getScrapedDataPreview()}
        dataReadyLabel={
          scrapedData
            ? `已载入 ${scrapedData.loaded_content_count || scrapedData.total_modules} 个模块 (${formatMode === "modules_summary" ? "智能去噪" : "原始 HTML"})`
            : "尚未抓取 (启动研判时自动抓取)"
        }
        onGoSettings={() => navigate("/settings")}
      />
    </PageWorkspace>
  );
}
