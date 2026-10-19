import type { HTMLAttributes, ReactNode } from "react";
import { cx } from "./utils";

type Variant = "default" | "error" | "success" | "warning" | "info";

const styles: Record<Variant, string> = {
  default:
    "border-slate-200/80 bg-slate-50/90 text-slate-700 dark:border-white/10 dark:bg-white/[0.04] dark:text-slate-200",
  error:
    "border-rose-200 bg-rose-50/90 text-rose-700 dark:border-rose-500/25 dark:bg-rose-500/10 dark:text-rose-300",
  success:
    "border-emerald-200 bg-emerald-50/90 text-emerald-700 dark:border-emerald-500/25 dark:bg-emerald-500/10 dark:text-emerald-300",
  warning:
    "border-amber-200 bg-amber-50/90 text-amber-800 dark:border-amber-500/25 dark:bg-amber-500/10 dark:text-amber-300",
  info:
    "border-sky-200 bg-sky-50/90 text-sky-800 dark:border-sky-500/25 dark:bg-sky-500/10 dark:text-sky-300",
};

export function Alert({
  className,
  variant = "default",
  children,
  ...props
}: HTMLAttributes<HTMLDivElement> & { variant?: Variant; children?: ReactNode }) {
  return (
    <div
      role="alert"
      className={cx(
        "rounded-2xl border px-4 py-3 text-sm",
        styles[variant] || styles.default,
        className,
      )}
      {...props}
    >
      {children}
    </div>
  );
}

export function AlertDescription({
  className,
  children,
  ...props
}: HTMLAttributes<HTMLParagraphElement> & { children?: ReactNode }) {
  return (
    <p className={cx("leading-relaxed", className)} {...props}>
      {children}
    </p>
  );
}
