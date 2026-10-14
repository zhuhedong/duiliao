import type { InputHTMLAttributes } from "react";
import { cx } from "./utils";

export function Checkbox({
  className,
  checked,
  onCheckedChange,
  ...props
}: Omit<InputHTMLAttributes<HTMLInputElement>, "type" | "onChange"> & {
  onCheckedChange?: (checked: boolean) => void;
}) {
  return (
    <input
      type="checkbox"
      checked={!!checked}
      onChange={(e) => onCheckedChange?.(e.target.checked)}
      className={cx(
        "size-4 rounded border-slate-300 text-brand-600 focus:ring-brand-500/30 dark:border-slate-600 dark:bg-slate-900",
        className,
      )}
      {...props}
    />
  );
}
