import { useState, type InputHTMLAttributes, type ReactNode } from "react";
import { cx } from "./utils";

type InputSize = "sm" | "md" | "lg";

const sizeMap: Record<InputSize, string> = {
  sm: "h-8 text-xs",
  md: "h-9.5 text-sm",
  lg: "h-10.5 text-sm",
};

export function Input({
  className,
  startSlot,
  endSlot,
  clearable,
  onClear,
  inputSize = "md",
  value,
  onChange,
  onFocus,
  onBlur,
  inputProps,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & {
  startSlot?: ReactNode;
  endSlot?: ReactNode;
  clearable?: boolean;
  onClear?: () => void;
  inputSize?: InputSize;
  inputProps?: InputHTMLAttributes<HTMLInputElement>;
}) {
  const [focused, setFocused] = useState(false);
  const showClear = clearable && String(value ?? "").length > 0;

  return (
    <div
      className={cx(
        "bento-input flex items-center gap-2 px-3",
        sizeMap[inputSize],
        focused && "border-indigo-500 ring-3 ring-indigo-500/15",
        className,
      )}
    >
      {startSlot ? <span className="shrink-0 text-slate-400 dark:text-slate-500">{startSlot}</span> : null}
      <input
        className="min-w-0 flex-1 bg-transparent outline-none placeholder:text-slate-400 dark:placeholder:text-slate-500 text-slate-900 dark:text-slate-100 disabled:cursor-not-allowed"
        value={value}
        onChange={onChange}
        {...props}
        {...inputProps}
        onFocus={(e) => {
          setFocused(true);
          onFocus?.(e);
          inputProps?.onFocus?.(e);
        }}
        onBlur={(e) => {
          setFocused(false);
          onBlur?.(e);
          inputProps?.onBlur?.(e);
        }}
      />
      {showClear ? (
        <button
          type="button"
          className="shrink-0 text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 text-xs cursor-pointer"
          onClick={onClear}
          tabIndex={-1}
        >
          清除
        </button>
      ) : null}
      {endSlot ? <span className="shrink-0">{endSlot}</span> : null}
    </div>
  );
}
