import type { ReactNode } from "react";
import { ShieldIcon } from "./icons";

const POINTS = [
  { title: "端到端信封加密", desc: "RSA 握手 + AES-256-GCM" },
  { title: "请求签名防重放", desc: "HMAC · 时间戳 · nonce" },
  { title: "多设备可吊销", desc: "会话随时踢除" },
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
    <div className="min-h-screen w-full relative overflow-hidden font-sans text-slate-100">
      <div className="app-aurora" />
      <div className="app-aurora-grid" />
      <div
        className="auth-glow-orb w-[36rem] h-[36rem] -top-32 -left-24"
        style={{ background: "radial-gradient(circle, oklch(0.62 0.26 283 / 55%), transparent 70%)" }}
      />
      <div
        className="auth-glow-orb w-[30rem] h-[30rem] top-[15%] -right-20"
        style={{ background: "radial-gradient(circle, oklch(0.58 0.28 320 / 45%), transparent 70%)" }}
      />
      <div
        className="auth-glow-orb w-[28rem] h-[28rem] bottom-[-10%] left-[35%]"
        style={{ background: "radial-gradient(circle, oklch(0.55 0.22 250 / 40%), transparent 70%)" }}
      />

      <div className="relative z-10 min-h-screen flex items-center justify-center p-4 sm:p-8">
        <div className="w-full max-w-5xl grid lg:grid-cols-[1.05fr_0.95fr] gap-4 lg:gap-5 items-stretch">
          <aside className="hidden lg:flex flex-col justify-between glass-panel rounded-[28px] p-8 xl:p-10 relative overflow-hidden">
            <div className="pointer-events-none absolute -right-10 -top-10 w-56 h-56 rounded-full bg-fuchsia-500/20 blur-3xl" />
            <div>
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-2xl brand-gradient flex items-center justify-center text-white font-bold text-xl shadow-[0_12px_30px_-10px_rgba(139,92,246,0.85)]">
                  对
                </div>
                <div>
                  <div className="text-xl font-bold text-gradient tracking-[0.2em]">对料</div>
                  <div className="text-[11px] text-slate-400">Aurora Command Console</div>
                </div>
              </div>
              <div className="display-kicker mt-10">Glass Mission Control</div>
              <h2 className="display-title mt-3 max-w-md">
                采集 · 对照 · 研判
                <span className="text-gradient"> 一张玻璃台完成</span>
              </h2>
              <p className="mt-4 text-sm text-slate-300/80 leading-relaxed max-w-md">
                登录后使用顶部 Command Bar 跳转模块。数据链路全程信封加密，不在页面留下明文密钥。
              </p>
            </div>
            <ul className="space-y-2.5 mt-8">
              {POINTS.map((point) => (
                <li key={point.title} className="flex items-center gap-3 p-3 rounded-2xl glass-subtle">
                  <span className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center text-white shrink-0">
                    <ShieldIcon size={14} />
                  </span>
                  <div>
                    <div className="text-sm font-semibold">{point.title}</div>
                    <div className="text-[11px] text-slate-400">{point.desc}</div>
                  </div>
                </li>
              ))}
            </ul>
            <div className="flex gap-2 mt-8 text-[10px] text-slate-400">
              <span className="px-2 py-1 rounded-lg glass-subtle">RSA-4096</span>
              <span className="px-2 py-1 rounded-lg glass-subtle">AES-256-GCM</span>
              <span className="px-2 py-1 rounded-lg glass-subtle">HMAC</span>
            </div>
          </aside>

          <section className="glass-panel rounded-[28px] p-6 sm:p-8 animate-glassPop relative overflow-hidden flex flex-col justify-center">
            <div
              className="pointer-events-none absolute -top-20 -right-12 w-48 h-48 rounded-full opacity-50"
              style={{ background: "radial-gradient(circle, oklch(0.7 0.22 296 / 55%), transparent 70%)" }}
            />
            <div className="relative">
              <div className="lg:hidden flex items-center gap-2.5 mb-5">
                <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center text-white font-bold">对</div>
                <span className="font-bold text-gradient tracking-[0.18em]">对料</span>
              </div>
              <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-medium bg-emerald-500/15 text-emerald-200 border border-emerald-400/30 mb-4">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
                E2EE 端到端加密
              </div>
              <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight">{title}</h1>
              {description ? <p className="mt-2 text-xs sm:text-sm text-slate-400 leading-relaxed">{description}</p> : null}
              <div className="mt-6">{children}</div>
              {footer ? (
                <div className="mt-6 pt-4 border-t border-white/8 text-center text-xs text-slate-500">{footer}</div>
              ) : null}
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}
