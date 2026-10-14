import type { HTMLAttributes, ReactNode } from "react";
import { cx } from "./utils";

export function Card({
  className,
  children,
  ...props
}: HTMLAttributes<HTMLDivElement> & { children?: ReactNode }) {
  return (
    <div className={cx("glass-card", className)} {...props}>
      {children}
    </div>
  );
}
