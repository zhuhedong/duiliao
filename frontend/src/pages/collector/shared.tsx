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

/** 统一卡片容器 */
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
    <div className={`admin-card ${compact ? "p-4" : "p-4 sm:p-5"} ${className}`}>
      {(title || action) && (
        <div className="flex items-center justify-between gap-3 mb-3 pb-3 border-b border-slate-100 dark:border-slate-800">
          <div className="min-w-0">
            {title && (
              <h2 className="text-sm font-semibold text-slate-900 dark:text-white tracking-tight flex items-center gap-2">
                {title}
              </h2>
            )}
            {subtitle && (
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5 leading-relaxed">{subtitle}</p>
            )}
          </div>
          {action && <div className="shrink-0 flex items-center gap-2">{action}</div>}
        </div>
      )}
      {children}
    </div>
  );
}

/** 分段切换选项卡 */
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
      className={`inline-flex items-center gap-0.5 p-1 rounded-lg bg-slate-100 dark:bg-slate-800/80 border border-slate-200 dark:border-slate-700 max-w-full overflow-x-auto ${className}`}
    >
      {tabs.map((tab) => {
        const active = activeTab === tab.id;
        return (
          <button
            key={tab.id}
            type="button"
            onClick={() => onChange(tab.id)}
            className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs sm:text-sm font-medium transition-colors cursor-pointer whitespace-nowrap ${
              active
                ? "bg-white text-brand-700 shadow-sm border border-slate-200 dark:bg-slate-900 dark:text-brand-300 dark:border-slate-600"
                : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white border border-transparent"
            }`}
          >
            {tab.icon && <span className={active ? "text-brand-600 dark:text-brand-300" : "text-slate-400"}>{tab.icon}</span>}
            <span>{tab.label}</span>
            {tab.count !== undefined && (
              <span
                className={`ml-0.5 px-1.5 py-0.5 rounded text-2xs font-bold ${
                  active
                    ? "bg-brand-50 text-brand-700 dark:bg-brand-500/15 dark:text-brand-300"
                    : "bg-slate-200/70 text-slate-500 dark:bg-slate-700 dark:text-slate-400"
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

/** 状态胶囊 */
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
    success: "bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-300 dark:border-emerald-500/30",
    warning: "bg-amber-50 text-amber-800 border-amber-200 dark:bg-amber-500/10 dark:text-amber-300 dark:border-amber-500/30",
    danger: "bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-500/10 dark:text-rose-300 dark:border-rose-500/30",
    info: "bg-brand-50 text-brand-700 border-brand-200 dark:bg-brand-500/10 dark:text-brand-300 dark:border-brand-500/30",
    neutral: "bg-slate-50 text-slate-600 border-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:border-slate-700",
  };

  const dots = {
    success: "bg-emerald-500",
    warning: "bg-amber-500",
    danger: "bg-rose-500",
    info: "bg-brand-500",
    neutral: "bg-slate-400",
  };

  return (
    <span className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-md text-xs font-medium border ${styles[variant]} ${className}`}>
      {dot && <span className={`w-1.5 h-1.5 rounded-full ${dots[variant]}`} />}
      <span>{children}</span>
    </span>
  );
}

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
      className={`h-9 px-3 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 text-sm font-medium text-slate-800 dark:text-slate-200 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed ${className || ""}`}
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

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
      className={`h-9 px-3 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 text-sm text-slate-800 dark:text-slate-200 placeholder:text-slate-400 disabled:opacity-50 disabled:cursor-not-allowed ${className || ""}`}
    />
  );
}

/** 页面工作区：左侧说明与操作，右侧内容 */
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
    <div className="workspace-fill w-full grid grid-cols-1 xl:grid-cols-[220px_minmax(0,1fr)] gap-3 items-start">
      <aside className="xl:sticky xl:top-[4.5rem] xl:self-start flex flex-col gap-3">
        <div className="admin-card p-4">
          <div className="text-[10px] font-semibold uppercase tracking-[0.14em] text-brand-600 dark:text-brand-300">本页</div>
          <p className="mt-2 text-xs leading-relaxed text-slate-500 dark:text-slate-400">{summary}</p>
          {actions ? <div className="mt-4 flex flex-col gap-2">{actions}</div> : null}
        </div>
        {nav}
      </aside>
      <div className="min-w-0 w-full h-full flex flex-col gap-3">{children}</div>
    </div>
  );
}

export function Toolbar({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`flex items-center gap-2.5 flex-wrap p-3 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 ${className}`}>
      {children}
    </div>
  );
}

export function TableContainer({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`w-full overflow-x-auto admin-card ${className}`}>
      <table className="w-full text-left text-sm border-collapse">{children}</table>
    </div>
  );
}

export const tableThClass =
  "py-2.5 px-3 text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider bg-slate-50 dark:bg-slate-800/60 border-b border-slate-200 dark:border-slate-700 select-none";
export const tableTdClass =
  "py-2.5 px-3 text-sm text-slate-800 dark:text-slate-200 border-b border-slate-100 dark:border-slate-800 align-middle";
export const tableRowClass = "hover:bg-slate-50 dark:hover:bg-white/[0.03] transition-colors";

export function ResultJson({ data }: { data: unknown }) {
  if (data == null) return null;
  return (
    <pre className="m-0 p-3 rounded-lg bg-slate-950 text-emerald-300 border border-slate-800 text-xs font-mono leading-relaxed overflow-x-auto max-h-96">
      {JSON.stringify(data, null, 2)}
    </pre>
  );
}

export function Stats({ items }: { items: { label: string; value: ReactNode }[] }) {
  return (
    <div className="flex gap-2 flex-wrap">
      {items.map((s) => (
        <span
          key={s.label}
          className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-medium border border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-800/60 text-slate-700 dark:text-slate-300"
        >
          <span className="text-slate-400">{s.label}：</span>
          <span className="font-semibold text-slate-900 dark:text-white">{s.value}</span>
        </span>
      ))}
    </div>
  );
}

export function useCanWrite(): boolean {
  const { user } = useAuth();
  return user?.role === "admin" || user?.role === "staff";
}

export function ReadOnlyNote() {
  return (
    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-medium bg-amber-50 text-amber-800 border border-amber-200 dark:bg-amber-500/10 dark:text-amber-300 dark:border-amber-500/30">
      只读模式：需要员工 / 管理员角色方可执行采集操作
    </span>
  );
}

export function EmptyState({ title, description, action }: { title: string; description?: string; action?: ReactNode }) {
  return (
    <div className="admin-empty">
      <div className="admin-empty-title">{title}</div>
      {description ? <p className="text-xs max-w-sm">{description}</p> : null}
      {action}
    </div>
  );
}
