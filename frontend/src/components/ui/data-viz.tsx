import { useEffect, useId, useRef, useState } from "react";
import { cx } from "./utils";

// Standard Mark Six (六合彩) wave color mapping
const RED_NUMBERS = new Set([
  1, 2, 7, 8, 12, 13, 18, 19, 23, 24, 29, 30, 34, 35, 40, 45, 46,
]);
const BLUE_NUMBERS = new Set([
  3, 4, 9, 10, 14, 15, 20, 25, 26, 31, 36, 37, 41, 42, 47, 48,
]);
const GREEN_NUMBERS = new Set([
  5, 6, 11, 16, 17, 21, 22, 27, 28, 32, 33, 38, 39, 43, 44, 49,
]);

export type BallWave = "red" | "blue" | "green" | "neutral";

export function getBallWave(num: number | string, explicitColor?: string | null): BallWave {
  if (explicitColor) {
    const c = explicitColor.toLowerCase();
    if (c.includes("red") || c.includes("红")) return "red";
    if (c.includes("blue") || c.includes("蓝")) return "blue";
    if (c.includes("green") || c.includes("绿")) return "green";
  }
  const n = typeof num === "number" ? num : parseInt(String(num), 10);
  if (RED_NUMBERS.has(n)) return "red";
  if (BLUE_NUMBERS.has(n)) return "blue";
  if (GREEN_NUMBERS.has(n)) return "green";
  return "neutral";
}

export interface LotteryBallProps {
  number?: number | string;
  num?: number | string;
  wave?: BallWave;
  colorHint?: string | null;
  zodiac?: string | null;
  wuxing?: string | null;
  size?: "xs" | "sm" | "md" | "lg";
  isSpecial?: boolean;
  isHit?: boolean;
  badge?: string | null;
  className?: string;
}

/** 3D 高光质感开奖号码球组件 */
export function LotteryBall({
  number,
  num,
  wave,
  colorHint,
  zodiac,
  wuxing,
  size = "md",
  isSpecial = false,
  isHit = false,
  badge,
  className,
}: LotteryBallProps) {
  const rawVal = number ?? num ?? "";
  const numStr = String(rawVal).padStart(2, "0");
  const resolvedWave = wave ?? getBallWave(rawVal, colorHint);
  const waveClass =
    resolvedWave === "red"
      ? "ball-red"
      : resolvedWave === "blue"
        ? "ball-blue"
        : resolvedWave === "green"
          ? "ball-green"
          : "ball-neutral";

  const sizeClass =
    size === "xs"
      ? "w-6 h-6 text-[11px]"
      : size === "sm"
        ? "w-7 h-7 text-xs"
        : size === "lg"
          ? "w-10 h-10 text-sm"
          : "w-8 h-8 text-xs";

  return (
    <div className={cx("inline-flex flex-col items-center gap-1 select-none", className)}>
      <div className="relative inline-flex items-center justify-center">
        <span
          className={cx(
            "ball",
            waveClass,
            sizeClass,
            isSpecial && "is-special",
            isHit && "is-hit",
          )}
        >
          {numStr}
        </span>
        {badge && (
          <span className="absolute -top-1.5 -right-1.5 px-1 py-0.2 rounded-full text-[9px] font-bold leading-tight bg-amber-400 text-slate-950 shadow-xs">
            {badge}
          </span>
        )}
      </div>
      {(zodiac || wuxing) && (
        <span className="text-[10px] font-medium text-slate-500 dark:text-slate-400 leading-none whitespace-nowrap">
          {[zodiac, wuxing].filter(Boolean).join("·")}
        </span>
      )}
    </div>
  );
}

/** SVG 微型趋势面积折线图 (Sparkline) */
export function Sparkline({
  data,
  width = 112,
  height = 34,
  tone = "indigo",
  showPulse = true,
  className,
}: {
  data: number[];
  width?: number;
  height?: number;
  tone?: "indigo" | "emerald" | "rose" | "amber";
  showPulse?: boolean;
  className?: string;
}) {
  const uid = useId();
  if (!data || data.length === 0) return null;

  const series = data.length === 1 ? [data[0]!, data[0]!] : data;
  const min = Math.min(...series);
  const max = Math.max(...series);
  const span = max - min || 1;
  const padX = 4;
  const padY = 5;
  const innerW = width - padX * 2;
  const innerH = height - padY * 2;

  const pts = series.map((val, idx) => {
    const x = padX + (idx / (series.length - 1)) * innerW;
    const y = padY + innerH - ((val - min) / span) * innerH;
    return { x, y };
  });

  const linePath = pts
    .map((p, i) => `${i === 0 ? "M" : "L"}${p.x.toFixed(1)},${p.y.toFixed(1)}`)
    .join(" ");
  const first = pts[0]!;
  const last = pts[pts.length - 1]!;
  const areaPath = `${linePath} L${last.x.toFixed(1)},${height} L${first.x.toFixed(1)},${height} Z`;

  const palette = {
    indigo: { stroke: "#6366f1", fill: "#6366f1" },
    emerald: { stroke: "#10b981", fill: "#10b981" },
    rose: { stroke: "#f43f5e", fill: "#f43f5e" },
    amber: { stroke: "#f59e0b", fill: "#f59e0b" },
  }[tone];

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className={cx("overflow-visible shrink-0", className)}
      aria-hidden="true"
    >
      <defs>
        <linearGradient id={`spark-${uid}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={palette.fill} stopOpacity="0.28" />
          <stop offset="100%" stopColor={palette.fill} stopOpacity="0.0" />
        </linearGradient>
      </defs>
      <path d={areaPath} fill={`url(#spark-${uid})`} />
      <path
        d={linePath}
        fill="none"
        stroke={palette.stroke}
        strokeWidth={1.85}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {showPulse && (
        <circle
          cx={last.x}
          cy={last.y}
          r={2.6}
          fill={palette.stroke}
          className="transition-all duration-300"
        />
      )}
    </svg>
  );
}

/** SVG 环形进度 / 胜率指示器 */
export function DonutRing({
  value,
  size = 52,
  strokeWidth = 5.5,
  tone = "indigo",
  label,
  className,
}: {
  /** 0 - 100 percentage */
  value: number;
  size?: number;
  strokeWidth?: number;
  tone?: "indigo" | "emerald" | "rose" | "amber";
  label?: string;
  className?: string;
}) {
  const clamped = Math.max(0, Math.min(100, Number.isFinite(value) ? value : 0));
  const r = (size - strokeWidth) / 2;
  const c = 2 * Math.PI * r;
  const offset = c - (clamped / 100) * c;

  const strokeColor = {
    indigo: "stroke-indigo-500 dark:stroke-indigo-400",
    emerald: "stroke-emerald-500 dark:stroke-emerald-400",
    rose: "stroke-rose-500 dark:stroke-rose-400",
    amber: "stroke-amber-500 dark:stroke-amber-400",
  }[tone];

  return (
    <div
      className={cx("relative inline-flex items-center justify-center shrink-0", className)}
      style={{ width: size, height: size }}
    >
      <svg width={size} height={size} className="-rotate-90">
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          strokeWidth={strokeWidth}
          className="stroke-slate-200/80 dark:stroke-white/[0.08]"
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          strokeWidth={strokeWidth}
          strokeDasharray={c}
          strokeDashoffset={offset}
          strokeLinecap="round"
          className={cx("transition-all duration-500 ease-out", strokeColor)}
        />
      </svg>
      <span className="absolute inset-0 flex items-center justify-center text-[11px] font-bold tabular-nums text-slate-800 dark:text-slate-100">
        {label ?? `${Math.round(clamped)}%`}
      </span>
    </div>
  );
}

/** 数字平滑递增动画组件 */
export function AnimatedNumber({
  value,
  decimals = 0,
  prefix = "",
  suffix = "",
  duration = 520,
  className,
}: {
  value: number;
  decimals?: number;
  prefix?: string;
  suffix?: string;
  duration?: number;
  className?: string;
}) {
  const [display, setDisplay] = useState(value);
  const prevRef = useRef(value);

  useEffect(() => {
    const start = prevRef.current;
    const end = value;
    prevRef.current = value;

    if (start === end || typeof window === "undefined") {
      setDisplay(end);
      return;
    }

    const prefersReduced =
      window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches ?? false;
    if (prefersReduced) {
      setDisplay(end);
      return;
    }

    let raf = 0;
    const t0 = performance.now();
    const step = (now: number) => {
      const p = Math.min(1, (now - t0) / duration);
      // easeOutExpo
      const eased = p === 1 ? 1 : 1 - Math.pow(2, -10 * p);
      setDisplay(start + (end - start) * eased);
      if (p < 1) {
        raf = requestAnimationFrame(step);
      } else {
        setDisplay(end);
      }
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [value, duration]);

  const formatted = display.toLocaleString("zh-CN", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });

  return (
    <span className={cx("tabular", className)}>
      {prefix}
      {formatted}
      {suffix}
    </span>
  );
}
