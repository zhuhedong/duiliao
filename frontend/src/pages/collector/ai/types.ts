/** AI 研判指挥台共享类型 */

export type AnalysisMode = "post" | "streak";

export interface PromptInfo {
  id: string;
  name: string;
  description: string;
  is_default: boolean;
  user_template?: string;
  system_prompt?: string;
}

export interface ScrapedModule {
  id: number;
  name: string;
  type: string;
  content: string | null;
  sort?: number;
  classId?: number;
}

export interface ScrapedSummary {
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
  raw_html?: string;
  raw_html_error?: string | null;
  modules?: ScrapedModule[];
}

export interface AIResult {
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

export interface StreakRow {
  xiao?: string;
  xiaos?: string[];
  length: number;
  kind?: string;
  start_period: string;
  end_period: string;
  is_active?: boolean;
}

/** 会话内沉淀的一份研判报告（含流式完成后的最终稿） */
export interface ReportEntry {
  id: string;
  ts: number;
  mode: AnalysisMode;
  /** 报告标签：帖文模式为期号，连肖模式为参数摘要 */
  label: string;
  provider: string;
  model: string;
  elapsed_sec: number;
  usage: AIResult["usage"];
  analysis: string;
}

export const REPORT_HISTORY_KEY = "duiliao_report_history_v1";
export const REPORT_HISTORY_LIMIT = 8;

export function loadReportHistory(): ReportEntry[] {
  try {
    const raw = localStorage.getItem(REPORT_HISTORY_KEY);
    if (!raw) return [];
    const arr = JSON.parse(raw);
    if (!Array.isArray(arr)) return [];
    return arr.filter((r) => r && typeof r.analysis === "string").slice(0, REPORT_HISTORY_LIMIT);
  } catch {
    return [];
  }
}

export function saveReportHistory(entries: ReportEntry[]) {
  try {
    localStorage.setItem(
      REPORT_HISTORY_KEY,
      JSON.stringify(entries.slice(0, REPORT_HISTORY_LIMIT))
    );
  } catch {
    /* 存储超限时静默降级为仅内存历史 */
  }
}

export function formatReportTime(ts: number): string {
  const d = new Date(ts);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
