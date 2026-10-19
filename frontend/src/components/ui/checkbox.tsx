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
        "size-4 rounded-md border-slate-300 text-indigo-600 accent-indigo-600 focus:ring-indigo-500/30 dark:border-slate-600 dark:bg-slate-900 cursor-pointer",
        className,
      )}
      {...props}
    />
  );
}
