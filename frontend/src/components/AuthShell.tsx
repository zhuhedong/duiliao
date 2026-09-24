import type { ReactNode } from "react";
import { ShieldIcon } from "./icons";

const POINTS = ["端到端信封加密", "请求签名与防重放", "多设备会话可吊销"];

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
    <div className="min-h-screen w-full relative overflow-hidden font-sans">
      <div className="app-aurora" />
      <div className="app-aurora-grid" />

      <div className="relative z-10 min-h-screen grid lg:grid-cols-[1.05fr_0.95fr]">
        <aside className="hidden lg:flex flex-col justify-between p-12 xl:p-16">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-2xl brand-gradient flex items-center justify-center text-white font-bold text-xl shadow-[0_12px_30px_-10px_rgba(139,92,246,0.7)]">
              对
            </div>
            <div>
              <div className="text-2xl font-bold text-gradient tracking-wider">对料</div>
              <div className="text-xs text-slate-500 dark:text-slate-400">加密数据采集控制台</div>
            </div>
          </div>

          <div className="max-w-md">
            <h2 className="text-4xl font-bold leading-tight text-slate-900 dark:text-white">
              把采集、对照和研判
              <span className="text-gradient"> 放在同一张工作台</span>
            </h2>
            <p className="mt-4 text-sm text-slate-500 dark:text-slate-400 leading-relaxed">
              登录后进入图标轨工作区。数据请求走 RSA 握手和 AES-256-GCM 信封，不在页面上留下明文密钥。
            </p>
            <ul className="mt-8 space-y-3">
              {POINTS.map((point) => (
                <li key={point} className="flex items-center gap-3 text-sm text-slate-700 dark:text-slate-200">
                  <span className="w-8 h-8 rounded-xl glass-subtle flex items-center justify-center text-violet-600 dark:text-violet-300">
                    <ShieldIcon size={14} />
                  </span>
                  {point}
                </li>
              ))}
            </ul>
          </div>

          <div className="text-[11px] text-slate-400">RSA-4096 / AES-256-GCM</div>
        </aside>

        <section className="flex items-center justify-center p-4 sm:p-8">
          <div className="w-full max-w-[440px] rounded-[28px] glass-panel p-7 sm:p-9 animate-glassPop">
            <div className="lg:hidden flex items-center gap-2.5 mb-5">
              <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center text-white font-bold">对</div>
              <span className="font-bold text-gradient tracking-wider">对料</span>
            </div>
            <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-medium bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border border-emerald-400/40 dark:border-emerald-400/25 mb-4">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
              E2EE 端到端加密保护
            </div>
            <h1 className="text-2xl font-bold text-slate-900 dark:text-white tracking-tight">{title}</h1>
            {description && (
              <p className="mt-1.5 text-xs text-slate-500 dark:text-slate-400 leading-relaxed">{description}</p>
            )}
            <div className="mt-6">{children}</div>
            {footer && (
              <div className="mt-6 pt-4 border-t border-slate-200/60 dark:border-white/8 text-center text-xs text-slate-500 dark:text-slate-400">
                {footer}
              </div>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}
