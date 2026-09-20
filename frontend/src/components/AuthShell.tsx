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
    <div className="min-h-screen w-full flex items-center justify-center bg-[#070b14] p-4 sm:p-6 relative overflow-hidden font-sans">
      {/* 细腻环境背景光与微网格 */}
      <div className="absolute inset-0 pointer-events-none overflow-hidden z-0">
        <div className="absolute top-1/3 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[520px] h-[520px] rounded-full bg-cyan-600/10 blur-[120px]" />
        <div className="absolute bottom-10 left-1/2 -translate-x-1/2 w-[420px] h-[420px] rounded-full bg-indigo-600/10 blur-[130px]" />
        <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:32px_32px] [mask-image:radial-gradient(ellipse_60%_60%_at_50%_50%,#000_20%,transparent_100%)]" />
      </div>

      {/* 紧凑轻巧的居中悬浮卡片 */}
      <div className="w-full max-w-[420px] bg-white rounded-2xl sm:rounded-3xl p-6 sm:p-8 relative z-10 shadow-[0_20px_50px_rgba(0,0,0,0.35)] border border-slate-100/90">
        {/* 顶部品牌与安全徽章 */}
        <div className="flex flex-col items-center text-center mb-6">
          <div className="flex items-center gap-2.5 mb-3">
            <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center text-white font-bold text-lg shadow-md shadow-cyan-500/20">
              对
            </div>
            <span className="font-bold text-xl text-slate-900 tracking-wider">对料</span>
          </div>

          <div className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] font-medium bg-emerald-50 text-emerald-700 border border-emerald-200/70 mb-3">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse shadow-[0_0_6px_rgba(16,185,129,0.7)]" />
            <span>E2EE 端到端加密保护</span>
          </div>

          <h1 className="text-xl sm:text-2xl font-bold text-slate-900 tracking-tight">
            {title}
          </h1>
          {description && (
            <p className="mt-1.5 text-xs text-slate-500 max-w-[320px] leading-relaxed">
              {description}
            </p>
          )}
        </div>

        {/* 表单内容 */}
        <div>{children}</div>

        {/* 底部跳转链接 */}
        {footer && (
          <div className="mt-6 pt-4 border-t border-slate-100 text-center text-xs text-slate-500">
            {footer}
          </div>
        )}

        {/* 极简安全背书页脚 */}
        <div className="mt-5 flex items-center justify-center gap-1.5 text-[11px] text-slate-400">
          <ShieldIcon size={12} className="text-slate-400" />
          <span>RSA-4096 / AES-256-GCM 全链路信封加密</span>
        </div>
      </div>
    </div>
  );
}


