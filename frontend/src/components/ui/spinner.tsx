import type { HTMLAttributes } from "react";
import { cx } from "./utils";

export function Spinner({
  className,
  currentColor: _currentColor,
  ...props
}: HTMLAttributes<HTMLSpanElement> & { currentColor?: boolean }) {
  return (
    <span
      role="status"
      className={cx(
        "inline-block size-4 animate-spin rounded-full border-2 border-current border-r-transparent",
        className,
      )}
      {...props}
    />
  );
}
