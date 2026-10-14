import type { CSSProperties, ReactNode } from "react";
import { useAuth } from "../../auth/AuthContext";
import type { Lottery } from "../../lib/collector";

export const LOTTERIES: { value: Lottery; label: string }[] = [
  { value: "macau", label: "澳门" },
  { value: "hk", label: "香港" },
  { value: "taiwan", label: "台湾" },
  { value: "new", label: "新彩" },
];

/** Fallback play-type labels; pages may also load the live rule catalog. */
export const PLAY_TYPE_LABEL: Record<string, string> = {
  pingte_xiao: "平特肖",
  pingte_wei: "平特尾",
  lianxiao_n: "连肖",
  lianwei_n: "连尾",
  tema_n: "特码",
  texiao: "特肖",
  tema_wei_n: "特尾",
  tema_head_n: "特头",
  tema_bose: "特波",
  tema_twoface: "两面",
  tema_halfwave: "半波",
  hexiao: "合肖",
  zhengma_n: "正码",
  zhengxiao: "正肖",
  lianma_2all: "二中二",
  lianma_3all: "三中三",
  lianma_3z2: "三中二",
  lianma_2zt: "二中特",
  buzhong_num: "不中码",
  buzhong_xiao: "杀肖",
  buzhong_wei: "杀尾",
};

export function playLabel(pt: string): string {
  return PLAY_TYPE_LABEL[pt] ?? pt;
}

/** 统一玻璃卡片容器 */
export function SectionCard({
  title,
  subtitle,
  action,
  children,
  className = "",
  compact = false,
}: {
  title?: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
  compact?: boolean;
}) {
  return (
    <div
      className={`rounded-3xl glass-card ${
        compact ? "p-4 sm:p-5" : "p-5 sm:p-6"
      } ${className}`}
    >
      {(title || action) && (
        <div className="flex items-center justify-between gap-4 mb-4 pb-1">
          <div>
            {title && (
              <h2 className="text-base font-bold text-slate-900 dark:text-white tracking-tight flex items-center gap-2">
                {title}
              </h2>
            )}
            {subtitle && (
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5 leading-relaxed">
                {subtitle}
              </p>
            )}
          </div>
          {action && <div className="shrink-0 flex items-center gap-2">{action}</div>}
        </div>
      )}
      {children}
    </div>
  );
}

/** 统一玻璃分段切换选项卡 */
export function SegmentedTabs<T extends string>({
  tabs,
  activeTab,
  onChange,
  className = "",
}: {
  tabs: { id: T; label: string; icon?: ReactNode; count?: ReactNode }[];
  activeTab: T;
  onChange: (id: T) => void;
  className?: string;
}) {
  return (
    <div
      className={`inline-flex items-center gap-1 p-1 rounded-2xl glass-subtle max-w-full overflow-x-auto ${className}`}
    >
      {tabs.map((tab) => {
        const active = activeTab === tab.id;
        return (
          <button
            key={tab.id}
            type="button"
            onClick={() => onChange(tab.id)}
            className={`inline-flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs sm:text-sm font-medium transition-all cursor-pointer whitespace-nowrap ${
              active
                ? "text-violet-700 dark:text-violet-200 bg-white/80 dark:bg-white/10 shadow-[0_2px_10px_-2px_rgba(139,92,246,0.3),inset_0_1px_0_rgba(255,255,255,0.5)] dark:shadow-[0_2px_10px_-2px_rgba(0,0,0,0.4),inset_0_1px_0_rgba(255,255,255,0.1)] border border-violet-300/50 dark:border-violet-400/25 font-semibold"
                : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white border border-transparent"
            }`}
          >
            {tab.icon && <span className={active ? "text-violet-600 dark:text-violet-300" : "text-slate-400"}>{tab.icon}</span>}
            <span>{tab.label}</span>
            {tab.count !== undefined && (
              <span
                className={`ml-1 px-1.5 py-0.5 rounded-full text-2xs font-bold ${
                  active
                    ? "bg-violet-500/15 text-violet-700 dark:text-violet-300"
                    : "bg-slate-500/10 text-slate-500 dark:text-slate-400"
                }`}
              >
                {tab.count}
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}

/** 统一状态胶囊 */
export function StatusPill({
  variant,
  children,
  dot = true,
  className = "",
}: {
  variant: "success" | "warning" | "danger" | "info" | "neutral";
  children: ReactNode;
  dot?: boolean;
  className?: string;
}) {
  const styles = {
    success:
      "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-400/40 dark:border-emerald-400/25",
    warning:
      "bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-400/40 dark:border-amber-400/25",
    danger:
      "bg-rose-500/10 text-rose-700 dark:text-rose-300 border-rose-400/40 dark:border-rose-400/25",
    info:
      "bg-violet-500/10 text-violet-700 dark:text-violet-300 border-violet-400/40 dark:border-violet-400/25",
    neutral:
      "bg-slate-500/10 text-slate-600 dark:text-slate-300 border-slate-400/30 dark:border-slate-400/20",
  };

  const dots = {
    success: "bg-emerald-500 shadow-[0_0_5px_rgba(16,185,129,0.7)]",
    warning: "bg-amber-500 shadow-[0_0_5px_rgba(245,158,11,0.7)]",
    danger: "bg-rose-500 shadow-[0_0_5px_rgba(244,63,94,0.7)]",
    info: "bg-violet-500 shadow-[0_0_5px_rgba(139,92,246,0.7)]",
    neutral: "bg-slate-400",
  };

  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium border backdrop-blur-md ${styles[variant]} ${className}`}
    >
      {dot && <span className={`w-1.5 h-1.5 rounded-full ${dots[variant]}`} />}
      <span>{children}</span>
    </span>
  );
}

/** 统一玻璃下拉选择框 */
export function Select({
  value,
  onChange,
  options,
  style,
  className,
  disabled,
}: {
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
  style?: CSSProperties;
  className?: string;
  disabled?: boolean;
}) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      disabled={disabled}
      style={style}
      className={`h-10 px-3.5 rounded-xl glass-input text-sm font-medium text-slate-800 dark:text-slate-200 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed ${className || ""}`}
    >
      {options.map((o) => (
        <option key={o.value} value={o.value} className="bg-white dark:bg-slate-900 text-slate-800 dark:text-slate-200">
          {o.label}
        </option>
      ))}
    </select>
  );
}

/** 统一玻璃文本输入框 */
export function TextInput({
  value,
  onChange,
  onKeyDown,
  placeholder,
  style,
  className,
  disabled,
}: {
  value: string;
  onChange: (v: string) => void;
  onKeyDown?: React.KeyboardEventHandler<HTMLInputElement>;
  placeholder?: string;
  style?: CSSProperties;
  className?: string;
  disabled?: boolean;
}) {
  return (
    <input
      value={value}
      onChange={(e) => onChange(e.target.value)}
      onKeyDown={onKeyDown}
      placeholder={placeholder}
      disabled={disabled}
      style={style}
      className={`h-10 px-3.5 rounded-xl glass-input text-sm text-slate-800 dark:text-slate-200 placeholder:text-slate-400 dark:placeholder:text-slate-500 disabled:opacity-50 disabled:cursor-not-allowed ${className || ""}`}
    />
  );
}

/** 页面工作区：顶部玻璃英雄条 + 全宽内容（不再使用左侧说明栏） */
export function PageWorkspace({
  summary,
  actions,
  nav,
  children,
}: {
  summary: string;
  actions?: ReactNode;
  nav?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="workspace-fill w-full flex flex-col gap-3">
      <div className="glass-panel rounded-[22px] p-4 sm:p-5 relative overflow-hidden">
        <div className="pointer-events-none absolute -right-8 -top-10 w-40 h-40 rounded-full bg-violet-500/20 blur-3xl" />
        <div className="pointer-events-none absolute right-16 -bottom-12 w-32 h-32 rounded-full bg-fuchsia-500/15 blur-3xl" />
        <div className="relative flex flex-col lg:flex-row lg:items-center gap-3">
          <div className="min-w-0 flex-1">
            <div className="text-[11px] font-semibold uppercase tracking-[0.2em] text-violet-600 dark:text-violet-200">上下文</div>
            <p className="mt-1.5 text-sm text-slate-200/90 leading-relaxed max-w-3xl">{summary}</p>
          </div>
          {actions ? <div className="flex flex-wrap items-center gap-2 shrink-0">{actions}</div> : null}
        </div>
        {nav ? <div className="relative mt-3 pt-3 border-t border-white/8">{nav}</div> : null}
      </div>
      <div className="min-w-0 w-full flex flex-col gap-3">{children}</div>
    </div>
  );
}

/** 统一玻璃操作工具栏 */
export function Toolbar({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`flex items-center gap-3 flex-wrap p-4 rounded-2xl glass-bar ${className}`}
    >
      {children}
    </div>
  );
}

/** 统一玻璃表格容器 — 卡片化表格（圆角面板 + 行悬浮） */
export function TableContainer({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={`w-full overflow-x-auto rounded-[22px] glass-card ${className}`}>
      <table className="w-full text-left text-sm border-collapse [&_tbody_tr]:transition-colors [&_tbody_tr:hover]:bg-violet-500/8">{children}</table>
    </div>
  );
}

export const tableThClass =
  "py-3 px-3.5 text-[11px] font-semibold text-slate-400 uppercase tracking-[0.12em] bg-white/5 border-b border-white/8 select-none";
export const tableTdClass =
  "py-3 px-3.5 text-sm text-slate-200 border-b border-white/5 align-middle";
export const tableRowClass =
  "hover:bg-violet-500/8 transition-colors";

/** JSON 预览面板 */
export function ResultJson({ data }: { data: unknown }) {
  if (data == null) return null;
  return (
    <pre className="m-0 p-4 rounded-2xl bg-slate-950/90 backdrop-blur-md text-emerald-300 border border-white/10 text-xs font-mono leading-relaxed overflow-x-auto max-h-96 shadow-inner">
      {JSON.stringify(data, null, 2)}
    </pre>
  );
}

/** 统计数值胶囊排 */
export function Stats({ items }: { items: { label: string; value: ReactNode }[] }) {
  return (
    <div className="flex gap-2.5 flex-wrap">
      {items.map((s) => (
        <span
          key={s.label}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium glass-subtle text-slate-700 dark:text-slate-300"
        >
          <span className="text-slate-400 dark:text-slate-500">{s.label}：</span>
          <span className="font-semibold text-slate-900 dark:text-white">{s.value}</span>
        </span>
      ))}
    </div>
  );
}

/** Returns whether the current user may run mutating collector operations. */
export function useCanWrite(): boolean {
  const { user } = useAuth();
  return user?.role === "admin" || user?.role === "staff";
}

export function ReadOnlyNote() {
  return (
    <span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium bg-amber-500/10 text-amber-700 dark:text-amber-300 border border-amber-400/40 dark:border-amber-400/25 backdrop-blur-md">
      只读模式：需要员工 / 管理员角色方可执行采集操作
    </span>
  );
}


export function EmptyState({ title, description, action }: { title: string; description?: string; action?: ReactNode }) {
  return (
    <div className="glass-card rounded-[22px] px-6 py-12 flex flex-col items-center text-center gap-3 relative overflow-hidden">
      <div className="pointer-events-none absolute inset-0 opacity-40" style={{ background: "radial-gradient(circle at 50% 0%, oklch(0.65 0.22 290 / 35%), transparent 55%)" }} />
      <div className="relative w-16 h-16 rounded-2xl brand-gradient flex items-center justify-center text-white text-2xl font-bold shadow-[0_16px_40px_-16px_rgba(124,58,237,0.9)]">
        ∅
      </div>
      <div className="relative admin-empty-title text-base">{title}</div>
      {description ? <p className="relative text-xs text-slate-400 max-w-sm leading-relaxed">{description}</p> : null}
      {action ? <div className="relative mt-1">{action}</div> : null}
    </div>
  );
}
