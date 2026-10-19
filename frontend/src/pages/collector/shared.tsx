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

/** 统一 Bento 卡片容器 */
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
      className={`bento-card rounded-2xl ${
        compact ? "p-4 sm:p-5" : "p-5 sm:p-6"
      } ${className}`}
    >
      {(title || action) && (
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-4 pb-3 border-b border-slate-100 dark:border-white/[0.06]">
          <div className="min-w-0">
            {title && (
              <h2 className="text-[15px] font-semibold text-slate-900 dark:text-slate-100 tracking-tight flex items-center gap-2">
                {title}
              </h2>
            )}
            {subtitle && (
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-1 leading-relaxed">
                {subtitle}
              </p>
            )}
          </div>
          {action && <div className="shrink-0 flex items-center gap-2 flex-wrap">{action}</div>}
        </div>
      )}
      {children}
    </div>
  );
}

/** 统一 Apple / Notion 风格分段切换选项卡 */
export function SegmentedTabs<T extends string>({
  tabs,
  options,
  activeTab,
  value,
  onChange,
  size = "md",
  className = "",
}: {
  tabs?: { id: T; label: string; icon?: ReactNode; count?: ReactNode }[];
  options?: { value: T; label: string; icon?: ReactNode; count?: ReactNode }[];
  activeTab?: T;
  value?: T;
  onChange: (id: T) => void;
  size?: "sm" | "md";
  className?: string;
}) {
  const current = (activeTab ?? value) as T;
  const items: { id: T; label: string; icon?: ReactNode; count?: ReactNode }[] =
    tabs ??
    (options ?? []).map((opt) => ({
      id: opt.value,
      label: opt.label,
      icon: opt.icon,
      count: opt.count,
    }));

  const btnPadding =
    size === "sm"
      ? "px-2.5 py-1 text-xs rounded-lg"
      : "px-3 py-1.5 text-xs sm:text-[13px] rounded-lg";

  return (
    <div
      className={`inline-flex items-center gap-1 p-1 rounded-xl bg-slate-100/90 dark:bg-white/[0.05] border border-slate-200/70 dark:border-white/[0.07] max-w-full overflow-x-auto no-scrollbar ${className}`}
    >
      {items.map((tab) => {
        const active = current === tab.id;
        return (
          <button
            key={tab.id}
            type="button"
            onClick={() => onChange(tab.id)}
            className={`inline-flex items-center gap-1.5 font-medium transition-all cursor-pointer whitespace-nowrap ${btnPadding} ${
              active
                ? "text-slate-900 dark:text-white bg-white dark:bg-[#1e232e] shadow-xs border border-slate-200/60 dark:border-white/10 font-semibold"
                : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200 border border-transparent"
            }`}
          >
            {tab.icon && (
              <span className={active ? "text-indigo-600 dark:text-indigo-400" : "text-slate-400 dark:text-slate-500"}>
                {tab.icon}
              </span>
            )}
            <span>{tab.label}</span>
            {tab.count !== undefined && (
              <span
                className={`ml-0.5 px-1.5 py-0.5 rounded-md text-[10px] font-semibold tabular-nums ${
                  active
                    ? "bg-indigo-50 text-indigo-700 dark:bg-indigo-500/20 dark:text-indigo-300"
                    : "bg-slate-200/70 text-slate-600 dark:bg-white/10 dark:text-slate-400"
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
      "bg-emerald-50 text-emerald-700 border-emerald-200/80 dark:bg-emerald-500/12 dark:text-emerald-300 dark:border-emerald-500/25",
    warning:
      "bg-amber-50 text-amber-700 border-amber-200/80 dark:bg-amber-500/12 dark:text-amber-300 dark:border-amber-500/25",
    danger:
      "bg-rose-50 text-rose-700 border-rose-200/80 dark:bg-rose-500/12 dark:text-rose-300 dark:border-rose-500/25",
    info:
      "bg-indigo-50 text-indigo-700 border-indigo-200/80 dark:bg-indigo-500/12 dark:text-indigo-300 dark:border-indigo-500/25",
    neutral:
      "bg-slate-100 text-slate-600 border-slate-200/80 dark:bg-white/[0.06] dark:text-slate-300 dark:border-white/10",
  };

  const dots = {
    success: "bg-emerald-500",
    warning: "bg-amber-500",
    danger: "bg-rose-500",
    info: "bg-indigo-500",
    neutral: "bg-slate-400",
  };

  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium border ${styles[variant]} ${className}`}
    >
      {dot && <span className={`w-1.5 h-1.5 rounded-full shrink-0 ${dots[variant]}`} />}
      <span>{children}</span>
    </span>
  );
}

/** 统一 Bento 下拉选择框 */
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
      className={`h-9.5 px-3 rounded-xl bento-input text-xs sm:text-sm font-medium text-slate-800 dark:text-slate-100 cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed ${className || ""}`}
    >
      {options.map((o) => (
        <option
          key={o.value}
          value={o.value}
          className="bg-white dark:bg-[#181c25] text-slate-800 dark:text-slate-100"
        >
          {o.label}
        </option>
      ))}
    </select>
  );
}

/** 统一 Bento 文本输入框 */
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
      className={`h-9.5 px-3.5 rounded-xl bento-input text-xs sm:text-sm text-slate-800 dark:text-slate-100 placeholder:text-slate-400 dark:placeholder:text-slate-500 disabled:opacity-50 disabled:cursor-not-allowed ${className || ""}`}
    />
  );
}

/** 页面工作区：紧凑精致的 Bento 页头横幅 + 全宽内容容器 */
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
    <div className="workspace-fill w-full flex flex-col gap-4">
      <div className="bento-card rounded-2xl px-4 sm:px-5 py-3.5">
        <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-3">
          <div className="min-w-0 flex-1 flex items-center gap-2.5">
            <span className="w-1.5 h-4 rounded-full bg-indigo-500 shrink-0" />
            <p className="text-xs sm:text-[13px] text-slate-600 dark:text-slate-400 leading-relaxed">
              {summary}
            </p>
          </div>
          {actions ? (
            <div className="flex flex-wrap items-center gap-2 shrink-0">{actions}</div>
          ) : null}
        </div>
        {nav ? (
          <div className="mt-3 pt-3 border-t border-slate-100 dark:border-white/[0.06]">{nav}</div>
        ) : null}
      </div>
      <div className="min-w-0 w-full flex flex-col gap-4">{children}</div>
    </div>
  );
}

/** 统一操作工具栏 */
export function Toolbar({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`flex items-center gap-3 flex-wrap p-3.5 sm:p-4 rounded-2xl bento-card ${className}`}
    >
      {children}
    </div>
  );
}

/** 统一 Bento 表格容器 */
export function TableContainer({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={`w-full overflow-x-auto rounded-2xl bento-card ${className}`}>
      <table className="w-full text-left text-sm border-collapse [&_tbody_tr]:transition-colors [&_tbody_tr:hover]:bg-slate-50/80 dark:[&_tbody_tr:hover]:bg-white/[0.03]">
        {children}
      </table>
    </div>
  );
}

export const tableThClass =
  "py-3 px-4 text-[11px] font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider bg-slate-50/90 dark:bg-white/[0.025] border-b border-slate-200/80 dark:border-white/[0.07] select-none whitespace-nowrap";
export const tableTdClass =
  "py-3 px-4 text-sm text-slate-700 dark:text-slate-200 border-b border-slate-100 dark:border-white/[0.05] align-middle";
export const tableRowClass =
  "hover:bg-slate-50/80 dark:hover:bg-white/[0.03] transition-colors";

/** JSON 预览面板 */
export function ResultJson({ data }: { data: unknown }) {
  if (data == null) return null;
  return (
    <pre className="m-0 p-4 rounded-2xl bg-slate-900 dark:bg-[#0d1017] text-emerald-400 border border-slate-800 dark:border-white/10 text-xs font-mono leading-relaxed overflow-x-auto max-h-96">
      {JSON.stringify(data, null, 2)}
    </pre>
  );
}

/** 统计数值胶囊排 */
export function Stats({ items }: { items: { label: string; value: ReactNode }[] }) {
  return (
    <div className="flex gap-2 flex-wrap">
      {items.map((s) => (
        <span
          key={s.label}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium bg-slate-100/80 dark:bg-white/[0.05] border border-slate-200/60 dark:border-white/[0.07] text-slate-700 dark:text-slate-300"
        >
          <span className="text-slate-500 dark:text-slate-400">{s.label}：</span>
          <span className="font-semibold tabular-nums text-slate-900 dark:text-white">{s.value}</span>
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
    <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-xl text-xs font-medium bg-amber-50 text-amber-700 border border-amber-200/80 dark:bg-amber-500/12 dark:text-amber-300 dark:border-amber-500/25">
      只读模式：需要员工 / 管理员角色方可执行采集操作
    </span>
  );
}

export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="bento-card rounded-2xl px-6 py-12 flex flex-col items-center text-center gap-2.5">
      <div className="w-12 h-12 rounded-2xl bg-slate-100 dark:bg-white/[0.06] border border-slate-200/70 dark:border-white/10 flex items-center justify-center text-slate-400 dark:text-slate-500 text-lg font-semibold">
        ∅
      </div>
      <div className="text-sm font-semibold text-slate-800 dark:text-slate-100 mt-1">{title}</div>
      {description ? (
        <p className="text-xs text-slate-500 dark:text-slate-400 max-w-sm leading-relaxed">
          {description}
        </p>
      ) : null}
      {action ? <div className="mt-2">{action}</div> : null}
    </div>
  );
}
