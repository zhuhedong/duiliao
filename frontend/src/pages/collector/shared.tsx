import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
} from "react";
import { useAuth } from "../../auth/AuthContext";
import type { Lottery } from "../../lib/collector";
import { CloseIcon } from "../../components/icons";

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

/** 统一 Apple / Linear 风格带滑动指示器的分段切换选项卡 */
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

  const rootRef = useRef<HTMLDivElement | null>(null);
  const btnRefs = useRef<Record<string, HTMLButtonElement | null>>({});
  const [indicator, setIndicator] = useState<{ left: number; width: number } | null>(null);

  const measure = () => {
    const root = rootRef.current;
    const activeBtn = btnRefs.current[String(current)];
    if (!root || !activeBtn) {
      setIndicator(null);
      return;
    }
    const left = activeBtn.offsetLeft;
    const width = activeBtn.offsetWidth;
    setIndicator({ left, width });
  };

  useLayoutEffect(() => {
    measure();
  }, [current, items.length, size]);

  useEffect(() => {
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, [current]);

  const btnPadding =
    size === "sm"
      ? "px-2.5 py-1 text-xs rounded-lg"
      : "px-3 py-1.5 text-xs sm:text-[13px] rounded-lg";

  return (
    <div
      ref={rootRef}
      role="tablist"
      className={`seg-root max-w-full overflow-x-auto no-scrollbar ${className}`}
    >
      {indicator && indicator.width > 0 && (
        <span
          aria-hidden="true"
          className="seg-indicator"
          style={{
            width: `${indicator.width}px`,
            transform: `translate3d(${indicator.left - 4}px, 0, 0)`,
          }}
        />
      )}
      {items.map((tab) => {
        const active = current === tab.id;
        return (
          <button
            key={tab.id}
            ref={(el) => {
              btnRefs.current[String(tab.id)] = el;
            }}
            role="tab"
            aria-selected={active}
            type="button"
            onClick={() => onChange(tab.id)}
            className={`relative z-10 inline-flex items-center gap-1.5 font-medium transition-colors cursor-pointer whitespace-nowrap ${btnPadding} ${
              active
                ? indicator
                  ? "text-slate-900 dark:text-white font-semibold"
                  : "text-slate-900 dark:text-white bg-white dark:bg-[#1e232e] shadow-xs border border-slate-200/60 dark:border-white/10 font-semibold"
                : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-200"
            }`}
          >
            {tab.icon && (
              <span
                className={
                  active
                    ? "text-indigo-600 dark:text-indigo-400"
                    : "text-slate-400 dark:text-slate-500"
                }
              >
                {tab.icon}
              </span>
            )}
            <span>{tab.label}</span>
            {tab.count !== undefined && (
              <span
                className={`ml-0.5 px-1.5 py-0.5 rounded-md text-[10px] font-semibold tabular-nums transition-colors ${
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

/** 活跃筛选条件胶囊条 (FilterChips) */
export function FilterChips({
  items,
  onClearAll,
  className = "",
}: {
  items: { key: string; label: string; value: string; onRemove: () => void }[];
  onClearAll?: () => void;
  className?: string;
}) {
  if (!items.length) return null;
  return (
    <div className={`flex items-center gap-2 flex-wrap ${className}`}>
      <span className="text-[11px] font-semibold uppercase tracking-wider text-slate-400 dark:text-slate-500">
        当前筛选
      </span>
      {items.map((item) => (
        <span
          key={item.key}
          className="inline-flex items-center gap-1.5 pl-2.5 pr-1.5 py-1 rounded-full text-xs font-medium bg-indigo-50/90 text-indigo-700 border border-indigo-200/80 dark:bg-indigo-500/12 dark:text-indigo-300 dark:border-indigo-500/25"
        >
          <span className="text-indigo-400 dark:text-indigo-400/80">{item.label}:</span>
          <span className="font-semibold">{item.value}</span>
          <button
            type="button"
            onClick={item.onRemove}
            aria-label={`移除 ${item.label} 筛选`}
            className="w-4 h-4 rounded-full inline-flex items-center justify-center hover:bg-indigo-200/70 dark:hover:bg-indigo-500/30 transition-colors cursor-pointer"
          >
            <CloseIcon size={10} />
          </button>
        </span>
      ))}
      {onClearAll && items.length > 1 && (
        <button
          type="button"
          onClick={onClearAll}
          className="text-xs font-medium text-slate-500 hover:text-rose-600 dark:text-slate-400 dark:hover:text-rose-400 px-2 py-0.5 transition-colors cursor-pointer"
        >
          清空全部
        </button>
      )}
    </div>
  );
}

/** 统一 Bento 表格容器（支持表头吸顶 + 移动端卡片化） */
export function TableContainer({
  children,
  className = "",
  stickyHeader = true,
  mobileStack = false,
}: {
  children: ReactNode;
  className?: string;
  stickyHeader?: boolean;
  mobileStack?: boolean;
}) {
  return (
    <div className={`w-full overflow-x-auto rounded-2xl bento-card ${className}`}>
      <table
        className={`w-full text-left text-sm border-collapse ${
          stickyHeader ? "table-sticky" : ""
        } ${
          mobileStack ? "table-stack" : ""
        } [&_tbody_tr]:transition-colors [&_tbody_tr:hover]:bg-slate-50/80 dark:[&_tbody_tr:hover]:bg-white/[0.03]`}
      >
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
  icon,
  variant = "default",
}: {
  title: string;
  description?: string;
  action?: ReactNode;
  icon?: ReactNode;
  variant?: "default" | "search" | "error";
}) {
  return (
    <div className="bento-card rounded-2xl px-6 py-12 flex flex-col items-center text-center gap-2.5">
      <div className="relative w-14 h-14 rounded-2xl bg-gradient-to-br from-indigo-500/10 via-slate-100 to-cyan-500/10 dark:from-indigo-500/15 dark:via-white/[0.04] dark:to-cyan-500/15 border border-slate-200/80 dark:border-white/10 flex items-center justify-center text-indigo-600 dark:text-indigo-400 shadow-2xs">
        {icon ??
          (variant === "search" ? (
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <circle cx="11" cy="11" r="7" />
              <path d="m20 20-3.5-3.5" />
              <path d="M8.5 11h5" />
            </svg>
          ) : (
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <rect x="3" y="4" width="18" height="16" rx="3" />
              <path d="M3 10h18" />
              <path d="M8 15h4" />
              <circle cx="16.5" cy="15" r="1.2" fill="currentColor" stroke="none" />
            </svg>
          ))}
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
