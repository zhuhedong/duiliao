import type { CSSProperties, HTMLAttributes, ReactNode } from "react";
import { cx } from "./utils";

type Variant = "default" | "secondary" | "outline" | "success" | "error" | "warning" | "soft" | "primary" | "info";
type Size = "sm" | "md" | "lg" | string;

const styles: Record<string, string> = {
  default: "bg-brand-600 text-white border-transparent",
  primary: "bg-brand-600 text-white border-transparent",
  secondary: "bg-slate-100 text-slate-700 border-slate-200 dark:bg-slate-800 dark:text-slate-200 dark:border-slate-700",
  outline: "bg-transparent text-slate-600 border-slate-200 dark:text-slate-300 dark:border-slate-700",
  success: "bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-300 dark:border-emerald-500/30",
  error: "bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-500/10 dark:text-rose-300 dark:border-rose-500/30",
  warning: "bg-amber-50 text-amber-800 border-amber-200 dark:bg-amber-500/10 dark:text-amber-300 dark:border-amber-500/30",
  soft: "bg-brand-50 text-brand-700 border-brand-100 dark:bg-brand-500/10 dark:text-brand-300 dark:border-brand-500/20",
  info: "bg-sky-50 text-sky-800 border-sky-200 dark:bg-sky-500/10 dark:text-sky-300 dark:border-sky-500/30",
};

const sizes: Record<string, string> = {
  sm: "text-[10px] px-1.5 py-0",
  md: "text-xs px-1.5 py-0.5",
  lg: "text-sm px-2 py-0.5",
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
        "inline-flex items-center gap-1 rounded-md border font-medium",
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
