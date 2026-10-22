import { api } from "./api";

export interface BettingRecord {
  id: string;
  lottery: string;
  period: string;
  mode: string;
  play_type: string;
  numbers: string[];
  xiaos: string[];
  stake_per_note: number;
  multiplier: number;
  notes_count: number;
  total_amount: number;
  odds: number;
  status: "pending" | "won" | "lost";
  hit_numbers: string[];
  hit_notes: number;
  payout: number;
  net_profit: number;
  win_pill_label?: string;
  raw_input?: string;
  note?: string;
  source_badge?: string;
  created_at?: string;
  time_label?: string;
  draw_numbers?: string[];
  special_number?: string;
  draw_time?: string;
  draw?: {
    lottery: string;
    period: string;
    balls: string[];
    tema: string;
    opened_at?: string;
  } | null;
}

export interface RecordStats {
  total_records: number;
  settled_orders: number;
  pending_count: number;
  won_count: number;
  lost_count: number;
  pending_stake: number;
  pending_notes: number;
  total_stake: number;
  total_payout: number;
  net_profit: number;
  total_notes: number;
  hit_notes: number;
  win_rate: number;
  roi_pct: number;
  period_bars: Array<{ period: string; net_profit: number }>;
  play_breakdown: Array<{
    play_type: string;
    count: number;
    won_count: number;
    win_rate: number;
    net_profit: number;
    stake: number;
    share_pct: number;
  }>;
  frequent_hits: Array<{
    number: string;
    bose: string;
    count: number;
    profit: number;
  }>;
  hot_numbers?: Array<{
    number: string;
    bose: string;
    xiao: string;
    count: number;
    total_stake: number;
    hit_count: number;
  }>;
}

export interface RecordsResponse {
  ok: boolean;
  count: number;
  items: BettingRecord[];
  stats: RecordStats;
}

export interface CreateRecordPayload {
  lottery: string;
  period: string;
  mode?: string;
  play_type: string;
  numbers?: string[];
  xiaos?: string[];
  stake_per_note?: number;
  multiplier?: number;
  notes_count?: number;
  total_amount?: number;
  odds?: number;
  raw_input?: string;
  note?: string;
  source_badge?: string;
}

export interface UpdateRecordPayload {
  lottery?: string;
  period?: string;
  mode?: string;
  play_type?: string;
  numbers?: string[];
  xiaos?: string[];
  stake_per_note?: number;
  multiplier?: number;
  notes_count?: number;
  total_amount?: number;
  odds?: number;
  raw_input?: string;
  note?: string;
  source_badge?: string;
}

export interface CopyRecordsPayload {
  target_period: string;
  source_period?: string;
  record_ids?: string[];
  lottery?: string;
}

export const recordsApi = {
  list(params?: { lottery?: string; status?: string }) {
    const q = new URLSearchParams();
    if (params?.lottery) q.set("lottery", params.lottery);
    if (params?.status && params.status !== "all") q.set("status", params.status);
    const queryStr = q.toString() ? `?${q.toString()}` : "";
    return api.get<RecordsResponse>(`/app/records${queryStr}`);
  },

  create(payload: CreateRecordPayload) {
    return api.post<{ ok: boolean; record: BettingRecord }>("/app/records", payload);
  },

  update(id: string, payload: UpdateRecordPayload) {
    return api.put<{ ok: boolean; record: BettingRecord }>(`/app/records/${id}`, payload);
  },

  delete(id: string) {
    return api.delete<{ ok: boolean; deleted: boolean; id: string }>(`/app/records/${id}`);
  },

  clear(params?: { lottery?: string; status?: string }) {
    const q = new URLSearchParams();
    if (params?.lottery) q.set("lottery", params.lottery);
    if (params?.status && params.status !== "all") q.set("status", params.status);
    const queryStr = q.toString() ? `?${q.toString()}` : "";
    return api.delete<{ ok: boolean; deleted_count: number }>(`/app/records${queryStr}`);
  },

  settle(lottery?: string) {
    const q = lottery ? `?lottery=${lottery}` : "";
    return api.post<RecordsResponse>(`/app/records/settle${q}`);
  },

  copy(payload: CopyRecordsPayload) {
    return api.post<{ ok: boolean; copied_count: number; items: BettingRecord[] }>(
      "/app/records/copy",
      payload
    );
  },

  copySingle(recordId: string, targetPeriod: string) {
    return api.post<{ ok: boolean; record: BettingRecord }>(
      `/app/records/${recordId}/copy`,
      { target_period: targetPeriod }
    );
  },
};
