import type { HTMLAttributes, ReactNode } from "react";
import { cx } from "./utils";

type Variant = "default" | "error" | "success" | "warning" | "info";

const styles: Record<Variant, string> = {
  default: "border-white/20 bg-white/10 text-slate-700 dark:text-slate-200",
  error: "border-rose-400/40 bg-rose-500/10 text-rose-700 dark:text-rose-300",
  success: "border-emerald-400/40 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
  warning: "border-amber-400/40 bg-amber-500/10 text-amber-800 dark:text-amber-300",
  info: "border-sky-400/40 bg-sky-500/10 text-sky-800 dark:text-sky-300",
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
        "rounded-xl border px-3 py-2.5 text-sm backdrop-blur-md",
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
