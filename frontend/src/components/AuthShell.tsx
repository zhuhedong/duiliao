import type { ReactNode } from "react";
import { ShieldIcon } from "./icons";

export function AuthShell({
  title,
  description,
  children,
  footer,
}: {
  title: string;
  description?: string;
  children: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <div className="min-h-screen w-full flex items-center justify-center p-4 sm:p-6 relative overflow-hidden font-sans">
      {/* 极光背景层 */}
      <div className="app-aurora" />
      <div className="app-aurora-grid" />

      {/* 漂浮装饰光斑 */}
      <div className="absolute inset-0 pointer-events-none overflow-hidden z-0">
        <div
          className="absolute top-[12%] left-[16%] w-40 h-40 rounded-3xl glass-card opacity-60 hidden lg:block"
          style={{ animation: "glassFloat 7s ease-in-out infinite" }}
        />
        <div
          className="absolute bottom-[16%] right-[14%] w-28 h-28 rounded-full glass-card opacity-50 hidden lg:block"
          style={{ animation: "glassFloat 9s ease-in-out infinite 1.2s" }}
        />
        <div
          className="absolute top-[58%] left-[8%] w-20 h-20 rounded-full glass-card opacity-40 hidden lg:block"
          style={{ animation: "glassFloat 8s ease-in-out infinite 0.6s" }}
        />
      </div>

      {/* 玻璃悬浮卡片 */}
      <div className="w-full max-w-[430px] rounded-[28px] glass-panel p-7 sm:p-9 relative z-10 animate-glassPop">
        {/* 顶部品牌与安全徽章 */}
        <div className="flex flex-col items-center text-center mb-7">
          <div className="flex items-center gap-2.5 mb-4">
            <div className="w-11 h-11 rounded-2xl brand-gradient flex items-center justify-center text-white font-bold text-xl shadow-[0_10px_28px_-8px_rgba(139,92,246,0.6)] ring-1 ring-white/30">
              对
            </div>
            <span className="font-bold text-2xl text-gradient tracking-wider">对料</span>
          </div>

          <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-medium bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md mb-4">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse shadow-[0_0_6px_rgba(16,185,129,0.7)]" />
            <span>E2EE 端到端加密保护</span>
          </div>

          <h1 className="text-xl sm:text-2xl font-bold text-slate-900 dark:text-white tracking-tight">
            {title}
          </h1>
          {description && (
            <p className="mt-1.5 text-xs text-slate-500 dark:text-slate-400 max-w-[320px] leading-relaxed">
              {description}
            </p>
          )}
        </div>

        {/* 表单内容 */}
        <div>{children}</div>

        {/* 底部跳转链接 */}
        {footer && (
          <div className="mt-6 pt-4 border-t border-slate-200/60 dark:border-white/8 text-center text-xs text-slate-500 dark:text-slate-400">
            {footer}
          </div>
        )}

        {/* 极简安全背书页脚 */}
        <div className="mt-5 flex items-center justify-center gap-1.5 text-[11px] text-slate-400 dark:text-slate-500">
          <ShieldIcon size={12} className="text-slate-400 dark:text-slate-500" />
          <span>RSA-4096 / AES-256-GCM 全链路信封加密</span>
        </div>
      </div>
    </div>
  );
}
