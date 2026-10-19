import type { CSSProperties, HTMLAttributes, ReactNode } from "react";
import { cx } from "./utils";

type Variant =
  | "default"
  | "secondary"
  | "outline"
  | "success"
  | "error"
  | "warning"
  | "soft"
  | "primary"
  | "info";
type Size = "sm" | "md" | "lg" | string;

const styles: Record<string, string> = {
  default: "bg-indigo-600 text-white border-transparent",
  primary: "bg-indigo-600 text-white border-transparent",
  secondary:
    "bg-slate-100 text-slate-700 border-slate-200/80 dark:bg-white/[0.06] dark:text-slate-200 dark:border-white/10",
  outline:
    "bg-transparent text-slate-600 border-slate-200 dark:text-slate-300 dark:border-white/12",
  success:
    "bg-emerald-50 text-emerald-700 border-emerald-200/80 dark:bg-emerald-500/12 dark:text-emerald-300 dark:border-emerald-500/25",
  error:
    "bg-rose-50 text-rose-700 border-rose-200/80 dark:bg-rose-500/12 dark:text-rose-300 dark:border-rose-500/25",
  warning:
    "bg-amber-50 text-amber-800 border-amber-200/80 dark:bg-amber-500/12 dark:text-amber-300 dark:border-amber-500/25",
  soft:
    "bg-indigo-50 text-indigo-700 border-indigo-200/70 dark:bg-indigo-500/12 dark:text-indigo-300 dark:border-indigo-500/25",
  info:
    "bg-sky-50 text-sky-700 border-sky-200/80 dark:bg-sky-500/12 dark:text-sky-300 dark:border-sky-500/25",
};

const sizes: Record<string, string> = {
  sm: "text-[11px] px-2 py-0.5 rounded-md",
  md: "text-xs px-2.5 py-0.5 rounded-lg",
  lg: "text-sm px-3 py-1 rounded-lg",
};

export function Badge({
  className,
  variant = "default",
  size = "md",
  children,
  style,
  ...props
}: HTMLAttributes<HTMLSpanElement> & {
  variant?: Variant;
  size?: Size;
  children?: ReactNode;
  style?: CSSProperties;
}) {
  return (
    <span
      className={cx(
        "inline-flex items-center gap-1 border font-medium leading-tight",
        styles[variant] || styles.default,
        sizes[size] || sizes.md,
        className,
      )}
      style={style}
      {...props}
    >
      {children}
    </span>
  );
}
