import type { HTMLAttributes, LabelHTMLAttributes, ReactNode } from "react";
import { cx } from "./utils";

export function Field({
  className,
  children,
  ...props
}: HTMLAttributes<HTMLDivElement> & { children?: ReactNode }) {
  return (
    <div className={cx("flex flex-col gap-1.5", className)} {...props}>
      {children}
    </div>
  );
}

export function FieldLabel({
  className,
  children,
  ...props
}: LabelHTMLAttributes<HTMLLabelElement> & { children?: ReactNode }) {
  return (
    <label className={cx("text-xs font-medium text-slate-600 dark:text-slate-300", className)} {...props}>
      {children}
    </label>
  );
}

export function FieldDescription({
  className,
  children,
  ...props
}: HTMLAttributes<HTMLParagraphElement> & { children?: ReactNode }) {
  return (
    <p className={cx("text-[11px] text-slate-500 dark:text-slate-400 leading-relaxed", className)} {...props}>
      {children}
    </p>
  );
}
