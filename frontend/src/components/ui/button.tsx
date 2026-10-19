import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cx } from "./utils";

type Variant = "default" | "primary" | "secondary" | "outline" | "ghost" | "danger";
type Size = "sm" | "md" | "lg" | "icon" | "icon-sm";

const variants: Record<Variant, string> = {
  default: "glow-button",
  primary: "glow-button",
  secondary:
    "bg-slate-100 text-slate-800 border border-slate-200/80 hover:bg-slate-200/75 dark:bg-white/[0.06] dark:text-slate-100 dark:border-white/10 dark:hover:bg-white/[0.11] shadow-2xs",
  outline:
    "bg-white text-slate-700 border border-slate-200/90 hover:bg-slate-50 hover:text-slate-900 dark:bg-transparent dark:text-slate-200 dark:border-white/12 dark:hover:bg-white/[0.06] shadow-2xs",
  ghost:
    "bg-transparent text-slate-600 hover:bg-slate-100/80 hover:text-slate-900 dark:text-slate-400 dark:hover:bg-white/[0.06] dark:hover:text-slate-100 border border-transparent",
  danger:
    "bg-rose-600 text-white hover:bg-rose-500 border border-rose-500/20 shadow-[0_1px_2px_rgba(225,29,72,0.25),0_4px_12px_-2px_rgba(225,29,72,0.2)]",
};

const sizes: Record<Size, string> = {
  sm: "h-8 px-3 text-xs rounded-xl gap-1.5",
  md: "h-9 px-3.5 text-xs sm:text-sm rounded-xl gap-1.5",
  lg: "h-10.5 px-4 text-sm rounded-xl gap-2",
  icon: "h-9 w-9 rounded-xl",
  "icon-sm": "h-8 w-8 rounded-xl",
};

export function Button({
  className,
  variant = "default",
  size = "md",
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant;
  size?: Size;
  children?: ReactNode;
}) {
  return (
    <button
      type="button"
      className={cx(
        "inline-flex items-center justify-center font-medium transition-all active:scale-[0.985] disabled:opacity-50 disabled:pointer-events-none cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500/30",
        variants[variant] || variants.default,
        sizes[size] || sizes.md,
        className,
      )}
      {...props}
    >
      {children}
    </button>
  );
}
