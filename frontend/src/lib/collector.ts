/**
 * Typed wrappers for the collector API (`/api/v1/collector/*`).
 *
 * Read calls work for any logged-in user; mutating calls (collect, ingest,
 * draw sync, judge, source writes, catalog scan) require the staff/admin role
 * server-side and will 403 otherwise.
 */
import { api } from "./api";

export type Lottery = "hk" | "macau" | "taiwan" | "new";

export const LOTTERY_LABEL: Record<string, string> = {
  hk: "香港",
  macau: "澳门",
  taiwan: "台湾",
  new: "新彩",
};

export interface PredAtom {
  kind: string;
  value: string;
  text?: string | null;
}

export interface CollectorSource {
  source_id: string;
  source_name: string;
  site_family: string;
  lottery: string;
  play_type: string;
  hit_mode: string;
  script_path: string;
  timeout_sec: number;
  enabled: boolean;
  remark?: string | null;
  extra?: Record<string, unknown>;
  script_exists?: boolean;
  script_path_valid?: boolean;
}

export interface IngestStats {
  ok: boolean;
  run_id: string;
  inserted: number;
  updated: number;
  unchanged: number;
  source_ok: number;
  source_fail: number;
  items: number;
  missing_added: number;
}

export interface CollectResult {
  ok: boolean;
  run_id: string;
  lottery: string;
  period?: string | null;
  source_total: number;
  source_ok: number;
  ingest?: IngestStats;
}

export interface DrawSyncResult {
  ok: boolean;
  inserted: number;
  updated: number;
  count: number;
  judged_periods: number;
  judged: number;
  hits: number;
  dirty_claimed: number;
  deadletter: string[];
}

export interface JudgeResult {
  ok: boolean;
  lottery: string;
  period: string;
  judged: number;
  hits: number;
  dirty_claimed: number;
  deadletter: string[];
}

export interface ConsensusTallyItem {
  preds: PredAtom[];
  votes: number;
  sources: string[];
  hit?: boolean | null;
  hit_detail?: Record<string, unknown> | null;
}

export interface ConsensusGroup {
  play_type: string;
  n_sources: number;
  n_votes: number;
  leader: PredAtom[] | null;
  leader_votes: number;
  leader_hit?: boolean | null;
  leader_hit_detail?: Record<string, unknown> | null;
  tally: ConsensusTallyItem[];
}

export interface AtomTallyItem {
  value: string;
  kind: "num" | "xiao";
  votes: number;
  percentage: number;
  sources: string[];
  hit?: boolean | null;
}

export interface ConsensusResult {
  ok: boolean;
  lottery: string;
  period: string;
  draw?: DrawRow | null;
  groups: ConsensusGroup[];
  atom_tallies?: {
    tema_n?: AtomTallyItem[];
    texiao?: AtomTallyItem[];
  };
}

export interface RatingRow {
  source_id: string;
  source_name: string;
  dirty_flags: number;
  missing: number;
  pending: number;
  uncovered: number;
  before_n: number;
  before_rate: number | null;
  after_n: number;
  after_rate: number | null;
  after_edits: number;
  longest_hit: number;
  longest_miss: number;
  current_streak: number;
  current_result: number | null;
  [key: string]: unknown; // n_30 / hit_30 / n_50 / ...
}

export interface RatingsResult {
  ok: boolean;
  lottery: string;
  play_type: string;
  windows: number[];
  periods: string[];
  period_from: string | null;
  period_to: string | null;
  sources: RatingRow[];
}

export interface MonitorRow {
  source_id: string;
  source_name: string;
  lottery: string;
  play_type: string;
  enabled: boolean;
  latest_period: string | null;
  latest_draw: string | null;
  lag: number | null;
  pending: string[];
  pending_total: number;
  confirmed: string[];
  confirmed_total: number;
  never_collected: boolean;
  last_seen: string | null;
}

export interface MonitorResult {
  items: MonitorRow[];
}

export interface CatalogStatus {
  ok: boolean;
  enabled: boolean;
  interval_minutes: number;
  active_host?: string;
  last_success_at?: string;
  last_attempt_at?: string;
  last_error?: string | null;
  content_total: number;
  open_issue_count?: number;
  items: Record<string, unknown>[];
  pending: Record<string, unknown>[];
  missing: Record<string, unknown>[];
  renamed: Record<string, unknown>[];
}

export interface LianxiaoGroup {
  xiao: string;
  count: number;
  nums: string[];
  positions: string[];
}

export interface AdjacentLianxiao {
  xiao: string;
  pos1: string;
  pos2: string;
  num1: string;
  num2: string;
}

export interface DrawSummary {
  sum7: number;
  sum7_size: "大" | "小";
  sum7_odd: "单" | "双";
  tema_xiao: string;
  tema_bose: string;
  tema_wuxing: string | null;
  tema_size: string;
  tema_odd: string;
  tema_sum_odd: string;
  tema_jiaye: string;
  tema_halfwave: string;
  has_lianxiao?: boolean;
  has_adjacent_lianxiao?: boolean;
  lianxiao_groups?: LianxiaoGroup[];
  adjacent_lianxiao?: AdjacentLianxiao[];
  lianxiao_text?: string;
}

export interface DrawRow {
  lottery: string;
  period: string;
  period_raw: string;
  draw_date: string | null;
  opened_at: string | null;
  balls: string[]; // z1..z6 (落球顺序)
  tema: string; // 特码
  source: string;
  tag: Record<string, unknown>;
  balls_detail?: NumberAttr[];
  tema_detail?: NumberAttr;
  summary?: DrawSummary;
}

export interface DrawListResult {
  ok: boolean;
  total: number;
  count: number;
  items: DrawRow[];
}

export interface SourceHistoryItem {
  id: number;
  source_id: string;
  source_name: string;
  lottery: string;
  play_type: string;
  hit_mode: string;
  period: string;
  period_raw: string;
  group_key: string;
  preds: PredAtom[];
  claimed_status: string;
  raw_text: string;
  final_url?: string | null;
  fetched_at?: string | null;
  official_hit?: number | null;
  claimed_hit?: number | null;
  hit_detail?: Record<string, unknown> | null;
  judged_at?: string | null;
  status: "hit" | "miss" | "pending" | "conflict";
  is_missing: boolean;
  is_conflict: boolean;
  draw?: DrawRow | null;
}

export interface SourceHistoryStats {
  total: number;
  judged: number;
  hits: number;
  misses: number;
  pending: number;
  conflicts: number;
  missing: number;
  hit_rate: number;
  longest_hit: number;
  longest_miss: number;
  current_streak: number;
  current_status: "hit" | "miss" | null;
}

export interface SourceHistoryResult {
  ok: boolean;
  source: CollectorSource;
  stats: SourceHistoryStats;
  total: number;
  limit: number;
  offset: number;
  items: SourceHistoryItem[];
}

export interface PredictionItem {
  id: number;
  source_id: string;
  source_name?: string;
  lottery: string;
  play_type: string;
  hit_mode?: string;
  period: string;
  period_raw?: string;
  group_key?: string;
  preds: PredAtom[];
  claimed_status: string;
  raw_text: string;
  final_url?: string | null;
  fetched_at?: string | null;
  official_hit?: number | null;
  claimed_hit?: number | null;
  hit_detail?: Record<string, unknown> | null;
  judged_at?: string | null;
  status?: "hit" | "miss" | "pending" | "conflict";
}

export interface PredictionListResult {
  ok: boolean;
  total: number;
  count: number;
  limit: number;
  offset: number;
  items: PredictionItem[];
}

export interface RuleRow {
  play_type: string;
  name: string;
  scope: string;
  condition: string;
  version: string;
  modes: string;
}

export interface NumberAttr {
  num: string;
  xiao: string; // 生肖
  jiaye: string; // 家 / 野
  bose: string; // 红 / 蓝 / 绿
  size: string; // 大 / 小
  odd: string; // 单 / 双
  head: string; // 头
  wei: string; // 尾
  sum: string; // 合数单双
  wuxing: string | null; // 金 / 木 / 水 / 火 / 土（按农历年，缺表为 null）
  halfwave?: string; // 半波
  is_lianxiao?: boolean; // 连肖标记 (本期出现2次及以上同生肖)
  lianxiao_count?: number; // 连肖总球数
  is_adjacent_lianxiao?: boolean; // 是否与顺位紧邻落球同肖
  role?: string | null; flower?: string | null; hour?: string | null; dizhi?: string | null; xiao_color?: string | null; stroke?: string | null; tian_di?: string | null; yin_yang?: string | null; gender?: string | null; luck?: string | null; season?: string | null; direction?: string | null;
}

export interface NumbersResult {
  ok: boolean;
  date: string;
  items: NumberAttr[];
  wuxing_available: boolean;
  wuxing_years: number[];
}

export interface ScriptRunResult {
  ok: boolean;
  source_id?: string;
  name?: string;
  lottery: string;
  period: string | null;
  exit_code: number | null;
  elapsed_ms: number;
  item_count: number;
  stdout: string;
  stderr: string;
  error_code?: string | null;
  error_msg?: string | null;
  data?: Record<string, unknown> | null;
  ingest?: IngestStats;
}

export interface ScriptTemplate {
  id: string;
  name: string;
  description: string;
  code: string;
}

export interface ComparisonItem {
  id: number;
  source_id: string;
  source_name: string;
  lottery: string;
  play_type: string;
  hit_mode: string;
  period: string;
  period_raw: string;
  group_key: string;
  preds: PredAtom[];
  claimed_status: string;
  raw_text: string;
  fetched_at: string | null;
  official_hit: number | null;
  claimed_hit: number | null;
  hit_detail: Record<string, unknown> | null;
  judged_at: string | null;
  status: "hit" | "miss" | "pending" | "conflict";
}

export interface PeriodComparisonResult {
  ok: boolean;
  lottery: string;
  period: string;
  draw: DrawRow | null;
  summary: {
    total: number;
    judged: number;
    hits: number;
    misses: number;
    pending: number;
    conflicts: number;
    hit_rate: number;
  };
  items: ComparisonItem[];
}

export interface DrawSchedulerLog {
  timestamp: string;
  lottery: string;
  status: "success" | "error";
  message: string;
  result?: Record<string, unknown> | null;
}

export interface DrawSchedulerStatus {
  enabled: boolean;
  running: boolean;
  start_time: string;
  end_time: string;
  interval_seconds: number;
  in_window: boolean;
  current_time: string;
  next_run_at: string | null;
  lotteries: string[];
  last_run_at: string | null;
  last_success_at: string | null;
  last_error: string | null;
  last_result: Record<string, unknown> | null;
  sync_count: number;
  recent_logs: DrawSchedulerLog[];
}

export interface CollectionSchedule {
  id: number;
  name: string;
  lottery: Lottery;
  period: string | null;
  source_ids: string[] | null;
  cron: string | null;
  start_at: string | null;
  end_at: string | null;
  interval_minutes: number;
  enabled: boolean;
  do_ingest: boolean;
  auto_judge: boolean;
  next_run_at: string | null;
  last_run_at: string | null;
  last_status: "success" | "error" | null;
  last_result: Record<string, any> | null;
  spec?: Record<string, any> | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface CollectionScheduleCreate {
  name: string;
  lottery?: Lottery;
  period?: string | null;
  source_ids?: string[] | null;
  cron?: string | null;
  start_at?: string | null;
  end_at?: string | null;
  enabled?: boolean;
  do_ingest?: boolean;
  auto_judge?: boolean;
  time_window_start?: string | null;
  time_window_end?: string | null;
  interval_minutes?: number | null;
  window_date?: string | null;
  concurrency?: number;
  spec?: Record<string, any>;
}

export interface CollectionScheduleUpdate {
  name?: string;
  lottery?: string;
  period?: string | null;
  source_ids?: string[] | null;
  cron?: string | null;
  start_at?: string | null;
  end_at?: string | null;
  enabled?: boolean;
  do_ingest?: boolean;
  auto_judge?: boolean;
  time_window_start?: string | null;
  time_window_end?: string | null;
  interval_minutes?: number | null;
  window_date?: string | null;
  concurrency?: number;
  spec?: Record<string, any>;
}

export interface SourceSchedulerStatus {
  running: boolean;
  check_interval_seconds: number;
  active_tasks_count: number;
  running_task_ids: number[];
  recent_logs: Array<{
    timestamp: string;
    schedule_id: number;
    schedule_name: string;
    action: string;
    status: "success" | "error";
    detail: string;
    concurrency?: number;
    duration_sec?: number;
  }>;
}

export interface SchedulesResponse {
  ok: boolean;
  scheduler: SourceSchedulerStatus;
  schedules: CollectionSchedule[];
}

export const collectorApi = {
  // --- pipeline ---
  collect(input: {
    lottery: Lottery;
    period?: string;
    source_ids?: string[];
    fixture_dir?: string;
    ingest?: boolean;
    concurrency?: number;
  }) {
    return api.post<CollectResult>("/collector/collect", input);
  },
  ingest(payload: unknown) {
    return api.post<IngestStats>("/collector/ingest", payload);
  },
  syncDraws(input: { lottery: Lottery; period?: string; draws?: unknown[] }) {
    return api.post<DrawSyncResult>("/collector/draws/sync", input);
  },
  judge(input: { lottery: Lottery; period: string }) {
    return api.post<JudgeResult>("/collector/judge", input);
  },

  // --- read models ---
  consensus(lottery: Lottery, period: string, playType?: string) {
    const q = new URLSearchParams({ lottery, period });
    if (playType) q.set("play_type", playType);
    return api.get<ConsensusResult>(`/collector/consensus?${q}`);
  },
  ratings(lottery: Lottery, playType: string, windows = "30,50,100") {
    const q = new URLSearchParams({ lottery, play_type: playType, windows });
    return api.get<RatingsResult>(`/collector/ratings?${q}`);
  },
  monitor(lottery?: Lottery) {
    const q = lottery ? `?lottery=${lottery}` : "";
    return api.get<MonitorResult>(`/collector/monitor${q}`);
  },
  listDraws(lottery?: Lottery, limit = 50, offset = 0) {
    const q = new URLSearchParams({ limit: String(limit), offset: String(offset) });
    if (lottery) q.set("lottery", lottery);
    return api.get<DrawListResult>(`/collector/draws?${q}`);
  },
  confirmMissing(source_id: string, periods: string[]) {
    return api.post("/collector/missing/confirm", { source_id, periods });
  },
  rules() {
    return api.get<RuleRow[]>("/collector/rules");
  },
  numbers(date?: string) {
    const q = date ? `?date=${date}` : "";
    return api.get<NumbersResult>(`/collector/numbers${q}`);
  },
  listPredictions(params?: {
    lottery?: Lottery;
    period?: string;
    source_id?: string;
    status?: string;
    limit?: number;
    offset?: number;
  }) {
    const q = new URLSearchParams();
    if (params?.lottery) q.set("lottery", params.lottery);
    if (params?.period) q.set("period", params.period);
    if (params?.source_id) q.set("source_id", params.source_id);
    if (params?.status) q.set("status", params.status);
    if (params?.limit !== undefined) q.set("limit", String(params.limit));
    if (params?.offset !== undefined) q.set("offset", String(params.offset));
    const qs = q.toString() ? `?${q.toString()}` : "";
    return api.get<PredictionListResult>(`/collector/predictions${qs}`);
  },
  getSourceHistory(
    sourceId: string,
    params?: {
      lottery?: Lottery;
      status?: string;
      period_from?: string;
      period_to?: string;
      limit?: number;
      offset?: number;
    }
  ) {
    const q = new URLSearchParams();
    if (params?.lottery) q.set("lottery", params.lottery);
    if (params?.status) q.set("status", params.status);
    if (params?.period_from) q.set("period_from", params.period_from);
    if (params?.period_to) q.set("period_to", params.period_to);
    if (params?.limit !== undefined) q.set("limit", String(params.limit));
    if (params?.offset !== undefined) q.set("offset", String(params.offset));
    const qs = q.toString() ? `?${q.toString()}` : "";
    return api.get<SourceHistoryResult>(`/collector/sources/${sourceId}/history${qs}`);
  },

  // --- source & script management ---
  listSources() {
    return api.get<CollectorSource[]>("/collector/sources");
  },
  getSource(id: string) {
    return api.get<CollectorSource & { script?: string | null }>(`/collector/sources/${id}`);
  },
  createSource(body: Record<string, unknown>) {
    return api.post<CollectorSource>("/collector/sources", body);
  },
  updateSource(id: string, body: Record<string, unknown>) {
    return api.patch<CollectorSource>(`/collector/sources/${id}`, body);
  },
  deleteSource(id: string, deleteFile = false) {
    return api.del<{ ok: boolean; deleted: string }>(
      `/collector/sources/${id}?delete_file=${deleteFile}`,
    );
  },
  testSource(
    sourceId: string,
    input?: { lottery?: Lottery; period?: string; fixture_dir?: string; ingest?: boolean },
  ) {
    return api.post<ScriptRunResult>(`/collector/sources/${sourceId}/test`, input || {});
  },
  runScript(
    name: string,
    input?: { lottery?: Lottery; period?: string; fixture?: string },
  ) {
    return api.post<ScriptRunResult>(`/collector/scripts/${name}/run`, input || {});
  },
  getScriptTemplates() {
    return api.get<ScriptTemplate[]>("/collector/scripts/templates");
  },
  readScript(name: string) {
    return api.get<{ ok: boolean; name: string; path: string; content: string }>(`/collector/scripts/${name}`);
  },
  writeScript(name: string, content: string) {
    return api.put<{ ok: boolean; name: string; path: string; bytes: number }>(`/collector/scripts/${name}`, { content });
  },

  // --- Comparison & Verification (开奖与预测明细比对) ---
  getComparison(lottery: Lottery, period: string) {
    const q = new URLSearchParams({ lottery, period });
    return api.get<PeriodComparisonResult>(`/collector/comparison?${q}`);
  },
  rejudgeComparison(lottery: Lottery, period: string) {
    return api.post<PeriodComparisonResult>("/collector/comparison/judge", { lottery, period });
  },

  // --- Draw Auto-Updater / Scheduler ---
  getDrawSchedulerStatus() {
    return api.get<DrawSchedulerStatus>("/collector/draw-scheduler");
  },
  updateDrawScheduler(
    config: {
      enabled?: boolean;
      start_time?: string;
      end_time?: string;
      interval_seconds?: number;
      lotteries?: string[];
    },
    trigger = false,
  ) {
    const q = trigger ? "?trigger=true" : "";
    return api.post<DrawSchedulerStatus>(`/collector/draw-scheduler${q}`, config);
  },

  // --- Source Collection Schedules (数据源采集定时任务) ---
  listSchedules(lottery?: Lottery) {
    const q = lottery ? `?lottery=${lottery}` : "";
    return api.get<SchedulesResponse>(`/collector/schedules${q}`);
  },
  createSchedule(data: CollectionScheduleCreate) {
    return api.post<{ ok: boolean; schedule: CollectionSchedule }>("/collector/schedules", data);
  },
  getSchedule(id: number) {
    return api.get<{ ok: boolean; schedule: CollectionSchedule }>(`/collector/schedules/${id}`);
  },
  updateSchedule(id: number, data: CollectionScheduleUpdate) {
    return api.put<{ ok: boolean; schedule: CollectionSchedule }>(`/collector/schedules/${id}`, data);
  },
  deleteSchedule(id: number) {
    return api.del<{ ok: boolean; message: string }>(`/collector/schedules/${id}`);
  },
  triggerSchedule(id: number) {
    return api.post<{ ok: boolean; result: any }>(`/collector/schedules/${id}/trigger`);
  },
  getScheduleLogs(id: number) {
    return api.get<{ ok: boolean; schedule: CollectionSchedule; logs: any[] }>(`/collector/schedules/${id}/logs`);
  },

  // --- catalog ---
  catalogStatus() {
    return api.get<CatalogStatus>("/collector/catalog/status");
  },
  catalogScan(record = true) {
    return api.post<CatalogStatus>(`/collector/catalog/scan?record=${record}`);
  },
};
