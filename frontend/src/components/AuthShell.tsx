import type { ReactNode } from "react";
import { ShieldIcon, SparklesIcon, CompareIcon, DatabaseIcon } from "./icons";

const BENTO_FEATURES = [
  {
    icon: <ShieldIcon size={16} />,
    title: "端到端信封加密",
    desc: "RSA-4096 握手 + AES-256-GCM 载荷保护",
  },
  {
    icon: <DatabaseIcon size={16} />,
    title: "全自动多源采集",
    desc: "定时巡检、缺期监控与智能补采",
  },
  {
    icon: <CompareIcon size={16} />,
    title: "全站共识与评级",
    desc: "多窗口真实命中率核算与虚假报喜识别",
  },
  {
    icon: <SparklesIcon size={16} />,
    title: "AI 深度研判与复盘",
    desc: "智能文本速录、自动对奖与多模型研判",
  },
];

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
    <div className="min-h-screen w-full relative overflow-hidden font-sans text-slate-900 dark:text-slate-100 bg-[var(--background)]">
      <div className="app-aurora" />

      <div className="relative z-10 min-h-screen flex items-center justify-center p-4 sm:p-6 lg:p-10">
        <div className="w-full max-w-5xl grid lg:grid-cols-[1.08fr_0.92fr] gap-5 items-stretch">
          {/* Left Bento Brand & Capabilities Showcase */}
          <aside className="hidden lg:flex flex-col justify-between bento-card rounded-3xl p-8 xl:p-10 relative overflow-hidden">
            <div>
              <div className="flex items-center gap-3">
                <div className="w-11 h-11 rounded-2xl brand-mark text-lg">对</div>
                <div>
                  <div className="text-lg font-bold text-slate-900 dark:text-white tracking-tight">
                    对料工作台
                  </div>
                  <div className="text-xs text-slate-400 dark:text-slate-500">
                    Bento Intelligence Studio
                  </div>
                </div>
              </div>

              <div className="display-kicker mt-10">Data & Consensus Workspace</div>
              <h2 className="text-2xl xl:text-3xl font-bold tracking-tight text-slate-900 dark:text-white mt-2.5 leading-snug">
                采集、对照、记账与 AI 研判，
                <br />
                <span className="text-indigo-600 dark:text-indigo-400">尽在清爽有序的卡片工作台。</span>
              </h2>
              <p className="mt-3.5 text-sm text-slate-500 dark:text-slate-400 leading-relaxed max-w-md">
                全链路零明文信封加密传输，自动同步官方开奖并核算各数据源真实命中率。
              </p>
            </div>

            <div className="grid grid-cols-2 gap-3 my-8">
              {BENTO_FEATURES.map((feat) => (
                <div
                  key={feat.title}
                  className="p-4 rounded-2xl bg-slate-50/90 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06] flex flex-col gap-2"
                >
                  <span className="w-8 h-8 rounded-xl bg-indigo-50 text-indigo-600 dark:bg-indigo-500/15 dark:text-indigo-300 flex items-center justify-center">
                    {feat.icon}
                  </span>
                  <div>
                    <div className="text-xs font-semibold text-slate-900 dark:text-slate-100">
                      {feat.title}
                    </div>
                    <div className="text-[11px] text-slate-500 dark:text-slate-400 mt-0.5 leading-relaxed">
                      {feat.desc}
                    </div>
                  </div>
                </div>
              ))}
            </div>

            <div className="flex items-center gap-2 text-[11px] text-slate-400 dark:text-slate-500 font-mono">
              <span className="px-2.5 py-1 rounded-lg bg-slate-100 dark:bg-white/[0.05] text-slate-600 dark:text-slate-400">
                RSA-4096
              </span>
              <span className="px-2.5 py-1 rounded-lg bg-slate-100 dark:bg-white/[0.05] text-slate-600 dark:text-slate-400">
                AES-256-GCM
              </span>
              <span className="px-2.5 py-1 rounded-lg bg-slate-100 dark:bg-white/[0.05] text-slate-600 dark:text-slate-400">
                HMAC-SHA256
              </span>
            </div>
          </aside>

          {/* Right Login / Bootstrap Card */}
          <section className="bento-card rounded-3xl p-6 sm:p-9 animate-glassPop flex flex-col justify-center">
            <div>
              <div className="lg:hidden flex items-center gap-2.5 mb-6">
                <div className="w-9 h-9 rounded-xl brand-mark text-sm">对</div>
                <span className="font-bold text-base text-slate-900 dark:text-white tracking-tight">
                  对料工作台
                </span>
              </div>

              <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-medium bg-emerald-50 text-emerald-700 border border-emerald-200/80 dark:bg-emerald-500/12 dark:text-emerald-300 dark:border-emerald-500/25 mb-4">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
                E2EE 端到端加密通道
              </div>

              <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-white">
                {title}
              </h1>
              {description ? (
                <p className="mt-1.5 text-xs sm:text-sm text-slate-500 dark:text-slate-400 leading-relaxed">
                  {description}
                </p>
              ) : null}

              <div className="mt-6">{children}</div>

              {footer ? (
                <div className="mt-6 pt-4 border-t border-slate-100 dark:border-white/[0.06] text-center text-xs text-slate-500 dark:text-slate-400">
                  {footer}
                </div>
              ) : null}
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}
