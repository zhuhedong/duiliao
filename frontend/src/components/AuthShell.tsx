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
    <div className="min-h-screen w-full bg-[var(--admin-bg)] text-[var(--admin-fg)]">
      <div className="min-h-screen grid lg:grid-cols-[1fr_440px]">
        <aside className="hidden lg:flex flex-col justify-between p-12 xl:p-16 bg-slate-950 text-slate-300">
          <div className="flex items-center gap-3">
            <div className="brand-mark !w-11 !h-11 !text-lg !rounded-xl">对</div>
            <div>
              <div className="text-xl font-bold text-white tracking-wide">对料</div>
              <div className="text-xs text-slate-500">加密数据采集控制台</div>
            </div>
          </div>

          <div className="max-w-lg">
            <h2 className="text-3xl xl:text-4xl font-bold leading-tight text-white">
              采集、对照与研判
              <span className="text-brand-300"> 统一管理</span>
            </h2>
            <p className="mt-4 text-sm text-slate-400 leading-relaxed">
              登录后进入管理后台。数据请求走 RSA 握手与 AES-256-GCM 信封，不在页面上留下明文密钥。
            </p>
            <ul className="mt-8 space-y-3">
              {POINTS.map((point) => (
                <li key={point} className="flex items-center gap-3 text-sm text-slate-200">
                  <span className="w-8 h-8 rounded-lg bg-white/5 border border-white/10 flex items-center justify-center text-brand-300">
                    <ShieldIcon size={14} />
                  </span>
                  {point}
                </li>
              ))}
            </ul>
          </div>

          <div className="text-[11px] text-slate-500">RSA-4096 / AES-256-GCM</div>
        </aside>

        <section className="flex items-center justify-center p-4 sm:p-8">
          <div className="w-full max-w-[420px] admin-card p-6 sm:p-8 animate-fadeIn">
            <div className="lg:hidden flex items-center gap-2.5 mb-5">
              <div className="brand-mark">对</div>
              <span className="font-bold tracking-wide">对料</span>
            </div>
            <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-medium bg-emerald-50 text-emerald-700 border border-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-300 dark:border-emerald-500/30 mb-4">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
              E2EE 端到端加密保护
            </div>
            <h1 className="text-2xl font-bold tracking-tight">{title}</h1>
            {description ? <p className="mt-1.5 text-xs text-slate-500 dark:text-slate-400 leading-relaxed">{description}</p> : null}
            <div className="mt-6">{children}</div>
            {footer ? (
              <div className="mt-6 pt-4 border-t border-slate-200 dark:border-slate-700 text-center text-xs text-slate-500">
                {footer}
              </div>
            ) : null}
          </div>
        </section>
      </div>
    </div>
  );
}
