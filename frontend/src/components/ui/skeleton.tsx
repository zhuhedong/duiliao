import type { HTMLAttributes } from "react";
import { cx } from "./utils";

export function Skeleton({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div aria-hidden="true" className={cx("skeleton", className)} {...props} />;
}

export function KpiSkeleton({ count = 4 }: { count?: number }) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3.5">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="bento-card rounded-2xl p-4 sm:p-5 space-y-3">
          <div className="flex items-center justify-between">
            <Skeleton className="h-3.5 w-24 rounded-md" />
            <Skeleton className="h-7 w-7 rounded-xl" />
          </div>
          <Skeleton className="h-7 w-32 rounded-lg" />
          <div className="flex items-center justify-between pt-1">
            <Skeleton className="h-3 w-28 rounded-md" />
            <Skeleton className="h-5 w-16 rounded-md" />
          </div>
        </div>
      ))}
    </div>
  );
}

export function TableSkeleton({
  rows = 5,
  cols = 5,
}: {
  rows?: number;
  cols?: number;
}) {
  return (
    <div className="bento-card rounded-2xl overflow-hidden">
      <div className="px-4 py-3 border-b border-slate-200/70 dark:border-white/[0.06] bg-slate-50/70 dark:bg-white/[0.02] grid gap-4" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
        {Array.from({ length: cols }).map((_, i) => (
          <Skeleton key={i} className="h-3 w-20 rounded-md" />
        ))}
      </div>
      <div className="divide-y divide-slate-100 dark:divide-white/[0.05]">
        {Array.from({ length: rows }).map((_, r) => (
          <div
            key={r}
            className="px-4 py-3.5 grid gap-4 items-center"
            style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}
          >
            {Array.from({ length: cols }).map((_, c) => (
              <Skeleton
                key={c}
                className={cx(
                  "h-3.5 rounded-md",
                  c === 0 ? "w-24" : c === cols - 1 ? "w-16" : "w-full max-w-[120px]",
                )}
              />
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

export function CardSkeleton({ lines = 3 }: { lines?: number }) {
  return (
    <div className="bento-card rounded-2xl p-5 space-y-3">
      <div className="flex items-center justify-between">
        <Skeleton className="h-4 w-32 rounded-md" />
        <Skeleton className="h-5 w-14 rounded-full" />
      </div>
      <div className="space-y-2 pt-1">
        {Array.from({ length: lines }).map((_, idx) => (
          <Skeleton
            key={idx}
            className={cx("h-3.5 rounded-md", idx === lines - 1 ? "w-2/3" : "w-full")}
          />
        ))}
      </div>
    </div>
  );
}
