/**
 * API client with a transparent security layer:
 *   - performs the RSA/AES crypto handshake lazily and caches the session
 *   - encrypts request bodies, decrypts encrypted responses
 *   - signs every request (HMAC) with timestamp + nonce for anti-replay
 *   - attaches the JWT access token and auto-refreshes it on 401
 *
 * Callers just do `api.post("/auth/login", {...})` and never see encryption.
 */
import {
  aesDecrypt,
  aesEncrypt,
  generateAesSession,
  hmacSha256Hex,
  importRsaPublicKey,
  randomNonceHex,
  sha256Hex,
  wrapAesKey,
  type AesSession,
  type Envelope,
} from "./crypto";

const API_BASE = import.meta.env.VITE_API_BASE_URL?.trim() || "/api/v1";
const SIGNING_SECRET = import.meta.env.VITE_APP_SIGNING_SECRET || "";
const APP_ID = import.meta.env.VITE_APP_ID || "web";
const REFRESH_STORAGE_KEY = "duiliao.refresh_token";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export class ApiError extends Error {
  status: number;
  code?: string;
  constructor(message: string, status: number, code?: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

type Method = "GET" | "POST" | "PATCH" | "PUT" | "DELETE";

interface RequestOptions {
  auth?: boolean; // attach bearer token (default true)
  retry?: boolean; // internal: whether a retry already happened
}

export type SessionStatus = "connected" | "connecting" | "disconnected";

class ApiClient {
  private session: { id: string; aes: AesSession } | null = null;
  private sessionPromise: Promise<void> | null = null;
  private accessToken: string | null = null;
  private refreshToken: string | null = localStorage.getItem(REFRESH_STORAGE_KEY);

  private _sessionStatus: SessionStatus = "disconnected";
  private statusListeners: Array<(s: SessionStatus) => void> = [];

  getSessionStatus(): SessionStatus {
    return this._sessionStatus;
  }

  subscribeStatus(fn: (s: SessionStatus) => void) {
    this.statusListeners.push(fn);
    return () => {
      this.statusListeners = this.statusListeners.filter((l) => l !== fn);
    };
  }

  private setSessionStatus(status: SessionStatus) {
    this._sessionStatus = status;
    this.statusListeners.forEach((fn) => fn(status));
  }

  // --- Token management -----------------------------------------------------

  setTokens(access: string | null, refresh?: string | null) {
    this.accessToken = access;
    if (refresh !== undefined) {
      this.refreshToken = refresh;
      if (refresh) localStorage.setItem(REFRESH_STORAGE_KEY, refresh);
      else localStorage.removeItem(REFRESH_STORAGE_KEY);
    }
  }

  clearTokens() {
    this.accessToken = null;
    this.refreshToken = null;
    localStorage.removeItem(REFRESH_STORAGE_KEY);
  }

  hasRefreshToken(): boolean {
    return !!this.refreshToken;
  }

  // --- Crypto session -------------------------------------------------------

  private async establishSession(): Promise<void> {
    this.setSessionStatus("connecting");
    try {
      const pkRes = await fetch(`${API_BASE}/crypto/public-key`);
      if (!pkRes.ok) throw new ApiError("Failed to fetch public key", pkRes.status);
      const { publicKey } = (await pkRes.json()) as { publicKey: string };

      const rsaPub = await importRsaPublicKey(publicKey);
      const aes = await generateAesSession();
      const encryptedKey = await wrapAesKey(rsaPub, aes.rawKey);

      const hsRes = await fetch(`${API_BASE}/crypto/handshake`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ encryptedKey }),
      });
      if (!hsRes.ok) throw new ApiError("Crypto handshake failed", hsRes.status);
      const { sessionId } = (await hsRes.json()) as { sessionId: string };
      this.session = { id: sessionId, aes };
      this.setSessionStatus("connected");
    } catch (e) {
      this.setSessionStatus("disconnected");
      throw e;
    }
  }

  private async ensureSession(): Promise<void> {
    if (this.session) return;
    if (!this.sessionPromise) {
      this.sessionPromise = this.establishSession().finally(() => {
        this.sessionPromise = null;
      });
    }
    await this.sessionPromise;
  }

  private resetSession() {
    this.session = null;
    this.setSessionStatus("disconnected");
  }

  // --- Core request ---------------------------------------------------------

  private async signHeaders(rawBody: Uint8Array): Promise<Record<string, string>> {
    const sessionId = this.session!.id;
    const ts = Math.floor(Date.now() / 1000).toString();
    const nonce = randomNonceHex(16);
    const bodyHash = await sha256Hex(rawBody);
    const signature = await hmacSha256Hex(
      SIGNING_SECRET,
      [sessionId, ts, nonce, bodyHash].join("\n"),
    );
    return {
      "X-Session-Id": sessionId,
      "X-Timestamp": ts,
      "X-Nonce": nonce,
      "X-Signature": signature,
      "X-App-Id": APP_ID,
    };
  }

  async request<T = unknown>(
    method: Method,
    path: string,
    body?: unknown,
    opts: RequestOptions = {},
  ): Promise<T> {
    const { auth = true, retry = false } = opts;
    await this.ensureSession();

    // Encrypt the body (if any) into an envelope, then to raw bytes.
    let rawBody = new Uint8Array(0);
    const headers: Record<string, string> = {};
    if (body !== undefined) {
      const plaintext = encoder.encode(JSON.stringify(body));
      const env = await aesEncrypt(this.session!.aes.key, plaintext);
      rawBody = encoder.encode(JSON.stringify(env));
      headers["Content-Type"] = "application/json";
    }

    Object.assign(headers, await this.signHeaders(rawBody));
    if (auth && this.accessToken) headers["Authorization"] = `Bearer ${this.accessToken}`;

    const res = await fetch(`${API_BASE}${path}`, {
      method,
      headers,
      body: body !== undefined ? rawBody : undefined,
    });

    // Decode response (encrypted or plain).
    const payload = await this.decodeResponse(res);

    if (res.ok) return payload as T;

    const code = extractCode(payload);

    // Session expired/rotated on the server -> re-handshake once.
    if (res.status === 401 && code === "no_session" && !retry) {
      this.resetSession();
      return this.request<T>(method, path, body, { ...opts, retry: true });
    }

    // Access token expired -> try to refresh once, then retry.
    if (res.status === 401 && auth && this.refreshToken && !retry && !path.startsWith("/auth/")) {
      const refreshed = await this.tryRefresh();
      if (refreshed) return this.request<T>(method, path, body, { ...opts, retry: true });
    }

    throw new ApiError(extractMessage(payload, res.statusText), res.status, code);
  }

  private async decodeResponse(res: Response): Promise<unknown> {
    const text = await res.text();
    if (!text) return null;
    if (res.headers.get("x-encrypted") === "1" && this.session) {
      const env = JSON.parse(text) as Envelope;
      const plain = await aesDecrypt(this.session.aes.key, env);
      const decoded = decoder.decode(plain);
      try {
        return JSON.parse(decoded);
      } catch {
        return decoded;
      }
    }
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  }

  private async tryRefresh(): Promise<boolean> {
    try {
      const data = await this.request<{ access_token: string; refresh_token: string }>(
        "POST",
        "/auth/refresh",
        { refresh_token: this.refreshToken },
        { auth: false, retry: true },
      );
      this.setTokens(data.access_token, data.refresh_token);
      return true;
    } catch {
      this.clearTokens();
      return false;
    }
  }

  // --- Convenience verbs ----------------------------------------------------

  get<T>(path: string, opts?: RequestOptions) {
    return this.request<T>("GET", path, undefined, opts);
  }
  post<T>(path: string, body?: unknown, opts?: RequestOptions) {
    return this.request<T>("POST", path, body, opts);
  }
  patch<T>(path: string, body?: unknown, opts?: RequestOptions) {
    return this.request<T>("PATCH", path, body, opts);
  }
  put<T>(path: string, body?: unknown, opts?: RequestOptions) {
    return this.request<T>("PUT", path, body, opts);
  }
  del<T>(path: string, opts?: RequestOptions) {
    return this.request<T>("DELETE", path, undefined, opts);
  }

  async stream(
    path: string,
    body: unknown,
    callbacks: {
      onChunk?: (delta: string) => void;
      onStatus?: (status: { stage?: string; message?: string; target_period?: string; scraped_summary?: any }) => void;
      onDone?: (info: { elapsed_sec?: number; provider?: string; model?: string; period?: string; usage?: any }) => void;
      onError?: (err: Error) => void;
    },
  ): Promise<void> {
    const url = `${API_BASE}${path}`;
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (this.accessToken) {
      headers["Authorization"] = `Bearer ${this.accessToken}`;
    }

    const resp = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });

    if (!resp.ok) {
      let errText = await resp.text();
      try {
        const errJson = JSON.parse(errText);
        errText = errJson.detail || errText;
      } catch {}
      const err = new ApiError(errText || `请求失败 (HTTP ${resp.status})`, resp.status);
      callbacks.onError?.(err);
      throw err;
    }

    const reader = resp.body?.getReader();
    if (!reader) {
      const err = new ApiError("浏览器无法获取流式数据通道", 500);
      callbacks.onError?.(err);
      throw err;
    }

    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed) continue;
          if (trimmed.startsWith("data:")) {
            const dataStr = trimmed.slice(5).trim();
            if (dataStr === "[DONE]") {
              return;
            }
            try {
              const data = JSON.parse(dataStr);
              if (data.stage === "error") {
                const err = new Error(data.error || "大模型分析异常");
                callbacks.onError?.(err);
                throw err;
              }
              if (data.stage === "delta" && data.delta) {
                callbacks.onChunk?.(data.delta);
              } else if (data.stage === "done") {
                callbacks.onDone?.(data);
              } else if (data.stage) {
                callbacks.onStatus?.(data);
              }
            } catch (e: any) {
              if (e.message && !e.message.includes("JSON")) {
                throw e;
              }
            }
          }
        }
      }
    } catch (e: any) {
      callbacks.onError?.(e);
      throw e;
    }
  }
}

function extractCode(payload: unknown): string | undefined {
  if (payload && typeof payload === "object" && "detail" in payload) {
    const detail = (payload as { detail: unknown }).detail;
    if (detail && typeof detail === "object" && "code" in detail) {
      return String((detail as { code: unknown }).code);
    }
  }
  return undefined;
}

function extractMessage(payload: unknown, fallback: string): string {
  if (payload && typeof payload === "object" && "detail" in payload) {
    const detail = (payload as { detail: unknown }).detail;
    if (typeof detail === "string") return detail;
    if (detail && typeof detail === "object" && "message" in detail) {
      return String((detail as { message: unknown }).message);
    }
  }
  if (typeof payload === "string" && payload) return payload;
  return fallback;
}

export const api = new ApiClient();

// --- Typed domain models + endpoint wrappers --------------------------------

export interface User {
  id: string;
  username: string | null;
  email: string | null;
  email_verified: boolean;
  phone: string | null;
  phone_verified: boolean;
  display_name: string | null;
  avatar_url: string | null;
  locale: string;
  timezone: string;
  status: string;
  role: string;
  registration_source: string;
  mfa_enabled: boolean;
  last_login_at: string | null;
  created_at: string;
}

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
  expires_in: number;
  user: User;
}

export interface DeviceInfo {
  deviceId?: string;
  deviceName?: string;
  platform?: string;
  appVersion?: string;
}

export interface SessionInfo {
  id: string;
  device_name: string | null;
  platform: string | null;
  app_version: string | null;
  ip_address: string | null;
  created_at: string;
  last_used_at: string | null;
  current: boolean;
}

const device: DeviceInfo = { platform: "web", deviceName: navigator.userAgent.slice(0, 80) };

export interface BootstrapStatus {
  available: boolean;
  reason: string | null;
}

export const authApi = {
  register(input: {
    email?: string;
    phone?: string;
    username?: string;
    password: string;
    display_name?: string;
  }) {
    return api.post<TokenResponse>("/auth/register", { ...input, source: "web", device }, { auth: false });
  },
  login(identifier: string, password: string) {
    return api.post<TokenResponse>("/auth/login", { identifier, password, device }, { auth: false });
  },
  bootstrapStatus() {
    return api.get<BootstrapStatus>("/auth/bootstrap", { auth: false });
  },
  bootstrap(input: {
    email?: string;
    phone?: string;
    username?: string;
    password: string;
    display_name?: string;
  }) {
    return api.post<TokenResponse>("/auth/bootstrap", { ...input, device }, { auth: false });
  },
  me() {
    return api.get<User>("/auth/me");
  },
  logout(allDevices = false) {
    return api.post<void>("/auth/logout", { all_devices: allDevices });
  },
};

export const userApi = {
  me() {
    return api.get<User>("/users/me");
  },
  update(input: Partial<Pick<User, "display_name" | "avatar_url" | "locale" | "timezone">>) {
    return api.patch<User>("/users/me", input);
  },
  sessions() {
    return api.get<SessionInfo[]>("/users/me/sessions");
  },
  revokeSession(id: string) {
    return api.del<void>(`/users/me/sessions/${id}`);
  },
  changePassword(currentPassword: string, newPassword: string) {
    return api.post<void>("/users/me/password", {
      current_password: currentPassword,
      new_password: newPassword,
    });
  },
};

export interface AIProviderConfig {
  base_url: string;
  api_key: string;
  model: string;
  is_configured: boolean;
}

export interface AISettings {
  default_provider: string;
  openai: AIProviderConfig;
  gemini: AIProviderConfig;
  anthropic: AIProviderConfig;
}

export interface AITestResult {
  ok: boolean;
  message: string;
  elapsed_ms: number;
  error?: string | null;
}

export const settingsApi = {
  getAISettings() {
    return api.get<AISettings>("/settings/ai");
  },
  updateAISettings(data: {
    default_provider?: string;
    openai?: Partial<AIProviderConfig>;
    gemini?: Partial<AIProviderConfig>;
    anthropic?: Partial<AIProviderConfig>;
  }) {
    return api.put<AISettings>("/settings/ai", data);
  },
  testAIConnection(data: {
    provider: string;
    base_url?: string;
    api_key?: string;
    model?: string;
  }) {
    return api.post<AITestResult>("/settings/ai/test", data);
  },
};

export interface DatabaseInfo {
  engine: string;
  url: string;
  is_connected: boolean;
  ping_ms: number;
  tables: Record<string, number>;
  error?: string;
}

export interface DatabaseStatus {
  mode: "sqlite" | "postgresql";
  app_db: DatabaseInfo;
  collector_db: DatabaseInfo;
  total_records: number;
  total_tables: number;
}

export interface DBTestResult {
  ok: boolean;
  message?: string;
  version?: string;
  elapsed_ms?: number;
  error?: string;
}

export interface SqliteTableInfo {
  name: string;
  rows: number;
  columns: string[];
  category: "app" | "collector" | "other";
}

export interface SqliteInspectResult {
  filename: string;
  file_size: number;
  total_tables: number;
  total_rows: number;
  tables: SqliteTableInfo[];
}

export interface SqliteImportResult {
  ok: boolean;
  filename: string;
  total_inserted: number;
  total_skipped: number;
  elapsed_ms: number;
  summary: Record<string, { status: string; inserted: number; skipped: number; reason?: string }>;
  error?: string;
}

export interface SchemaDbReport {
  engine: string;
  url: string;
  is_connected: boolean;
  declared: string[];
  existing: string[];
  missing: string[];
  unmanaged: string[];
  error?: string;
}

export interface SchemaVerifyResult {
  ok: boolean;
  missing_total: number;
  shared_database: boolean;
  app_db: SchemaDbReport;
  collector_db: SchemaDbReport;
}

export interface SchemaRepairResult {
  ok: boolean;
  scope: string;
  created: { app: string[]; collector: string[] };
  created_total: number;
  failed: { db: string; table: string; error: string }[];
  notes: string[];
  before_missing: { total: number; app: string[]; collector: string[] };
  after: SchemaVerifyResult;
}

export const databaseApi = {
  getStatus() {
    return api.get<DatabaseStatus>("/settings/database");
  },
  verifySchema() {
    return api.get<SchemaVerifyResult>("/settings/database/schema");
  },
  repairSchema(data?: { scope?: "all" | "app" | "collector"; seed?: boolean }) {
    return api.post<SchemaRepairResult>("/settings/database/schema/repair", data ?? {});
  },
  testConnection(url: string) {
    return api.post<DBTestResult>("/settings/database/test", { url });
  },
  saveConfig(data: { database_url: string; collector_database_url?: string }) {
    return api.post<DatabaseStatus>("/settings/database/config", data);
  },
  inspectSqlite(filename: string, content_base64: string) {
    return api.post<SqliteInspectResult>("/settings/database/inspect-sqlite", {
      filename,
      content_base64,
    });
  },
  importSqlite(data: {
    filename: string;
    content_base64: string;
    mode?: "skip" | "overwrite";
    tables?: string[];
  }) {
    return api.post<SqliteImportResult>("/settings/database/import-sqlite", data);
  },
};
