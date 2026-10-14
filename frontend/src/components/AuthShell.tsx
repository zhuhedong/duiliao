import type { ReactNode } from "react";
import { ShieldIcon } from "./icons";

const POINTS = [
  { title: "端到端信封加密", desc: "RSA 握手 + AES-256-GCM，服务端不见明文" },
  { title: "请求签名与防重放", desc: "HMAC 时间戳与 nonce，链路可审计" },
  { title: "多设备会话可吊销", desc: "随时踢掉异常设备，会话可控" },
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
    <div className="min-h-screen w-full relative overflow-hidden font-sans text-slate-900 dark:text-slate-100">
      <div className="app-aurora" />
      <div className="app-aurora-grid" />
      <div
        className="auth-glow-orb w-[28rem] h-[28rem] -top-24 -left-20"
        style={{ background: "radial-gradient(circle, oklch(0.62 0.24 283 / 45%), transparent 70%)" }}
      />
      <div
        className="auth-glow-orb w-[24rem] h-[24rem] top-[20%] -right-16"
        style={{ background: "radial-gradient(circle, oklch(0.6 0.26 320 / 35%), transparent 70%)" }}
      />
      <div
        className="auth-glow-orb w-[22rem] h-[22rem] bottom-0 left-[30%]"
        style={{ background: "radial-gradient(circle, oklch(0.58 0.2 250 / 30%), transparent 70%)" }}
      />

      <div className="relative z-10 min-h-screen grid lg:grid-cols-[1.1fr_0.9fr]">
        <aside className="hidden lg:flex flex-col justify-between p-12 xl:p-16">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-2xl brand-gradient flex items-center justify-center text-white font-bold text-xl shadow-[0_12px_30px_-10px_rgba(139,92,246,0.7)]">
              对
            </div>
            <div>
              <div className="text-2xl font-bold text-gradient tracking-wider">对料</div>
              <div className="text-xs text-slate-500 dark:text-slate-400">Aurora Glass · 加密数据采集控制台</div>
            </div>
          </div>

          <div className="max-w-lg">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-[11px] font-medium glass-subtle text-violet-700 dark:text-violet-200 mb-5">
              <span className="w-1.5 h-1.5 rounded-full bg-violet-500 animate-pulse" />
              靛蓝 → 紫罗兰 → 品红
            </div>
            <h2 className="text-4xl xl:text-[2.75rem] font-bold leading-[1.15] text-slate-900 dark:text-white">
              把采集、对照和研判
              <span className="text-gradient"> 放在同一张玻璃工作台</span>
            </h2>
            <p className="mt-4 text-sm text-slate-500 dark:text-slate-400 leading-relaxed max-w-md">
              登录后进入图标轨工作区。数据请求走 RSA 握手与 AES-256-GCM 信封，不在页面上留下明文密钥。
            </p>
            <ul className="mt-8 space-y-3">
              {POINTS.map((point) => (
                <li
                  key={point.title}
                  className="flex items-start gap-3 p-3 rounded-2xl glass-subtle"
                >
                  <span className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center text-white shrink-0 shadow-[0_8px_18px_-10px_rgba(124,58,237,0.8)]">
                    <ShieldIcon size={15} />
                  </span>
                  <div className="min-w-0 pt-0.5">
                    <div className="text-sm font-semibold text-slate-800 dark:text-slate-100">{point.title}</div>
                    <div className="text-[11px] text-slate-500 dark:text-slate-400 mt-0.5 leading-relaxed">{point.desc}</div>
                  </div>
                </li>
              ))}
            </ul>
          </div>

          <div className="flex items-center gap-3 text-[11px] text-slate-400">
            <span className="px-2 py-1 rounded-lg glass-subtle">RSA-4096</span>
            <span className="px-2 py-1 rounded-lg glass-subtle">AES-256-GCM</span>
            <span className="px-2 py-1 rounded-lg glass-subtle">HMAC</span>
          </div>
        </aside>

        <section className="flex items-center justify-center p-4 sm:p-8">
          <div className="w-full max-w-[440px] rounded-[28px] glass-panel p-7 sm:p-9 animate-glassPop relative overflow-hidden">
            <div
              className="pointer-events-none absolute -top-16 -right-10 w-40 h-40 rounded-full opacity-40"
              style={{ background: "radial-gradient(circle, oklch(0.7 0.2 296 / 50%), transparent 70%)" }}
            />
            <div className="relative">
              <div className="lg:hidden flex items-center gap-2.5 mb-5">
                <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center text-white font-bold">对</div>
                <span className="font-bold text-gradient tracking-wider">对料</span>
              </div>
              <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-medium bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border border-emerald-400/40 dark:border-emerald-400/25 mb-4">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                E2EE 端到端加密保护
              </div>
              <h1 className="text-2xl font-bold text-slate-900 dark:text-white tracking-tight">{title}</h1>
              {description ? (
                <p className="mt-1.5 text-xs text-slate-500 dark:text-slate-400 leading-relaxed">{description}</p>
              ) : null}
              <div className="mt-6">{children}</div>
              {footer ? (
                <div className="mt-6 pt-4 border-t border-slate-200/60 dark:border-white/8 text-center text-xs text-slate-500 dark:text-slate-400">
                  {footer}
                </div>
              ) : null}
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
