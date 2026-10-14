import type { ButtonHTMLAttributes, ReactNode } from "react";
import { cx } from "./utils";

type Variant = "default" | "primary" | "secondary" | "outline" | "ghost" | "danger";
type Size = "sm" | "md" | "lg" | "icon" | "icon-sm";

const variants: Record<Variant, string> = {
  default: "glow-button",
  primary: "glow-button",
  secondary:
    "glass-subtle text-slate-800 dark:text-slate-100 hover:bg-white/70 dark:hover:bg-white/10",
  outline:
    "bg-transparent text-slate-700 dark:text-slate-200 border border-slate-200/70 dark:border-white/15 hover:bg-violet-500/5",
  ghost:
    "bg-transparent text-slate-500 hover:bg-white/50 dark:text-slate-400 dark:hover:bg-white/5 hover:text-violet-600 dark:hover:text-violet-300 border border-transparent",
  danger:
    "bg-rose-600 text-white hover:bg-rose-500 border border-transparent shadow-[0_8px_20px_-10px_rgba(244,63,94,0.65)]",
};

const sizes: Record<Size, string> = {
  sm: "h-8 px-3 text-xs rounded-xl gap-1.5",
  md: "h-9 px-3.5 text-sm rounded-xl gap-2",
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
        "inline-flex items-center justify-center font-medium transition-all disabled:opacity-50 disabled:pointer-events-none cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-500/35",
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
