import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Link, Outlet, useLocation, useNavigate } from "react-router-dom";
import { api } from "../lib/api";
import { Button } from "./ui/button";
import { useTheme } from "../theme/ThemeProvider";
import { useAuth } from "../auth/AuthContext";
import { UserAvatar } from "./UserAvatar";
import {
  DashboardIcon,
  DatabaseIcon,
  TrophyIcon,
  CompareIcon,
  StarIcon,
  HashIcon,
  ActivityIcon,
  GlobeIcon,
  UserIcon,
  LogOutIcon,
  MoonIcon,
  SunIcon,
  MenuIcon,
  CloseIcon,
  SparklesIcon,
  SettingsIcon,
} from "./icons";

interface NavItem {
  to: string;
  label: string;
  short: string;
  icon: ReactNode;
  group: "core" | "ops" | "account";
}

const NAV: NavItem[] = [
  { to: "/", label: "工作台", short: "工作台", icon: <DashboardIcon size={16} />, group: "core" },
  { to: "/collector/ai-analysis", label: "AI 研判", short: "研判", icon: <SparklesIcon size={16} />, group: "core" },
  { to: "/collector/sources", label: "数据源", short: "采集", icon: <DatabaseIcon size={16} />, group: "core" },
  { to: "/collector/draws", label: "开奖", short: "开奖", icon: <TrophyIcon size={16} />, group: "core" },
  { to: "/collector/consensus", label: "多源对照", short: "对照", icon: <CompareIcon size={16} />, group: "core" },
  { to: "/collector/numbers", label: "号码", short: "号码", icon: <HashIcon size={16} />, group: "ops" },
  { to: "/collector/ratings", label: "评级", short: "评级", icon: <StarIcon size={16} />, group: "ops" },
  { to: "/collector/monitor", label: "监控", short: "监控", icon: <ActivityIcon size={16} />, group: "ops" },
  { to: "/collector/platform", label: "采集平台", short: "平台", icon: <GlobeIcon size={16} />, group: "ops" },
  { to: "/profile", label: "个人中心", short: "账户", icon: <UserIcon size={16} />, group: "account" },
  { to: "/settings", label: "系统设置", short: "设置", icon: <SettingsIcon size={16} />, group: "account" },
];

const PAGE_META: Record<string, { title: string; eyebrow: string }> = Object.fromEntries(
  NAV.map((n) => [
    n.to,
    {
      title: n.label,
      eyebrow: n.group === "core" ? "核心业务" : n.group === "ops" ? "质量与平台" : "账户",
    },
  ]),
);

export function AppLayout() {
  const { user, logout } = useAuth();
  const { resolvedTheme, setTheme } = useTheme();
  const navigate = useNavigate();
  const location = useLocation();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [jumpOpen, setJumpOpen] = useState(false);
  const [jumpQuery, setJumpQuery] = useState("");
  const [sessionStatus, setSessionStatus] = useState(api.getSessionStatus());

  useEffect(() => api.subscribeStatus(setSessionStatus), []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setJumpOpen(true);
      }
      if (e.key === "Escape") {
        setJumpOpen(false);
        setMobileOpen(false);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const page = PAGE_META[location.pathname] || { title: "工作台", eyebrow: "核心业务" };
  const core = NAV.filter((n) => n.group === "core");
  const filteredJump = useMemo(() => {
    const q = jumpQuery.trim().toLowerCase();
    if (!q) return NAV;
    return NAV.filter((n) => n.label.toLowerCase().includes(q) || n.short.includes(q) || n.to.includes(q));
  }, [jumpQuery]);

  const statusText =
    sessionStatus === "connected" ? "链路加密" : sessionStatus === "connecting" ? "握手中" : "已断开";
  const statusClass =
    sessionStatus === "connected"
      ? "text-emerald-300 bg-emerald-500/15 border-emerald-400/30"
      : sessionStatus === "connecting"
        ? "text-amber-200 bg-amber-500/15 border-amber-400/30"
        : "text-rose-200 bg-rose-500/15 border-rose-400/30";

  const handleLogout = async () => {
    await logout();
    navigate("/login", { replace: true });
  };

  return (
    <div className="min-h-screen relative text-slate-900 dark:text-slate-100">
      <div className="app-aurora" />
      <div className="app-aurora-grid" />

      {/* Floating command island — replaces left sidebar IA */}
      <div className="sticky top-0 z-40 px-3 sm:px-5 pt-3 pb-2">
        <div className="mx-auto max-w-[1440px] glass-panel rounded-[22px] px-2.5 sm:px-3 py-2 shadow-[0_20px_60px_-30px_rgba(124,58,237,0.55)]">
          <div className="flex items-center gap-2 sm:gap-3">
            <Link to="/" className="flex items-center gap-2 no-underline shrink-0 pl-1">
              <div className="w-9 h-9 rounded-2xl brand-gradient flex items-center justify-center text-white font-bold text-sm shadow-[0_10px_24px_-10px_rgba(139,92,246,0.85)]">
                对
              </div>
              <div className="hidden lg:block leading-tight">
                <div className="text-sm font-bold text-gradient tracking-[0.18em]">对料</div>
                <div className="text-[10px] text-slate-400">Aurora Command</div>
              </div>
            </Link>

            <div className="hidden md:flex items-center gap-1 flex-1 min-w-0 overflow-x-auto no-scrollbar px-1">
              {core.map((item) => {
                const active = location.pathname === item.to;
                return (
                  <Link
                    key={item.to}
                    to={item.to}
                    className={`shrink-0 inline-flex items-center gap-1.5 h-9 px-3 rounded-xl text-xs font-semibold no-underline transition-all ${
                      active
                        ? "bg-violet-500/20 text-violet-100 shadow-[inset_0_0_0_1px_rgba(167,139,250,0.45)]"
                        : "text-slate-400 hover:text-white hover:bg-white/5"
                    }`}
                  >
                    {item.icon}
                    {item.label}
                  </Link>
                );
              })}
            </div>

            <button
              type="button"
              onClick={() => setJumpOpen(true)}
              className="hidden sm:flex items-center gap-2 h-9 px-3 rounded-xl glass-subtle text-[11px] text-slate-400 hover:text-slate-100 cursor-pointer min-w-[140px]"
            >
              <span className="opacity-70">⌘K</span>
              <span>跳转页面…</span>
            </button>

            <div className={`hidden xl:inline-flex items-center gap-1.5 px-2.5 h-8 rounded-full text-[11px] font-medium border ${statusClass}`}>
              <span className="w-1.5 h-1.5 rounded-full bg-current" />
              {statusText}
            </div>

            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="切换主题"
              onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
            >
              {resolvedTheme === "dark" ? <SunIcon size={15} /> : <MoonIcon size={15} />}
            </Button>

            <Link to="/profile" className="no-underline hidden sm:block" title="个人中心">
              <UserAvatar name={user?.display_name || user?.email} url={user?.avatar_url} className="h-8 w-8 rounded-full text-xs" />
            </Link>

            <Button variant="ghost" size="icon-sm" aria-label="退出" onClick={handleLogout} className="hidden sm:inline-flex">
              <LogOutIcon size={15} />
            </Button>

            <button
              type="button"
              className="md:hidden p-2 rounded-xl glass-subtle"
              onClick={() => setMobileOpen(true)}
              aria-label="打开菜单"
            >
              <MenuIcon size={16} />
            </button>
          </div>

          {/* Contextual secondary strip */}
          <div className="hidden md:flex items-center gap-2 mt-2 pt-2 border-t border-white/5">
            <span className="text-[10px] uppercase tracking-[0.16em] text-violet-300/80 px-1">{page.eyebrow}</span>
            <span className="text-sm font-semibold text-white/90">{page.title}</span>
            <div className="flex-1" />
            {NAV.filter((n) => n.group !== "core").map((item) => {
              const active = location.pathname === item.to;
              return (
                <Link
                  key={item.to}
                  to={item.to}
                  className={`inline-flex items-center gap-1 h-7 px-2.5 rounded-lg text-[11px] no-underline ${
                    active ? "bg-white/10 text-white" : "text-slate-400 hover:text-slate-200 hover:bg-white/5"
                  }`}
                >
                  {item.icon}
                  {item.short}
                </Link>
              );
            })}
          </div>
        </div>
      </div>

      <main className="relative z-10 mx-auto max-w-[1440px] px-3 sm:px-5 pb-28 md:pb-8">
        <div className="workspace-fill animate-fadeIn">
          <Outlet />
        </div>
      </main>

      {/* Mobile floating dock */}
      <div className="md:hidden fixed inset-x-3 bottom-3 z-40">
        <div className="glass-panel rounded-2xl px-1.5 py-1.5 grid grid-cols-5 gap-1">
          {core.slice(0, 4).map((item) => {
            const active = location.pathname === item.to;
            return (
              <Link
                key={item.to}
                to={item.to}
                className={`flex flex-col items-center justify-center gap-1 h-12 rounded-xl no-underline text-[10px] ${
                  active ? "bg-violet-500/20 text-violet-100" : "text-slate-400"
                }`}
              >
                {item.icon}
                {item.short}
              </Link>
            );
          })}
          <button
            type="button"
            className="flex flex-col items-center justify-center gap-1 h-12 rounded-xl text-[10px] text-slate-400"
            onClick={() => setMobileOpen(true)}
          >
            <MenuIcon size={16} />
            全部
          </button>
        </div>
      </div>

      {mobileOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <div className="absolute inset-0 bg-slate-950/60 backdrop-blur-sm" onClick={() => setMobileOpen(false)} />
          <div className="absolute left-3 right-3 bottom-20 glass-panel rounded-3xl p-4 animate-glassPop">
            <div className="flex items-center justify-between mb-3">
              <span className="text-sm font-semibold">全部模块</span>
              <button type="button" className="p-1.5 rounded-lg glass-subtle" onClick={() => setMobileOpen(false)}>
                <CloseIcon size={14} />
              </button>
            </div>
            <div className="grid grid-cols-3 gap-2">
              {NAV.map((item) => {
                const active = location.pathname === item.to;
                return (
                  <Link
                    key={item.to}
                    to={item.to}
                    onClick={() => setMobileOpen(false)}
                    className={`flex flex-col items-center gap-1.5 py-3 rounded-2xl no-underline text-[11px] ${
                      active ? "bg-violet-500/20 text-violet-100" : "text-slate-300 glass-subtle"
                    }`}
                  >
                    {item.icon}
                    {item.short}
                  </Link>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {jumpOpen && (
        <div className="fixed inset-0 z-[60] flex items-start justify-center pt-[12vh] px-4">
          <div className="absolute inset-0 bg-slate-950/55 backdrop-blur-md" onClick={() => setJumpOpen(false)} />
          <div className="relative w-full max-w-lg glass-panel rounded-3xl p-3 animate-glassPop shadow-[0_30px_80px_-20px_rgba(124,58,237,0.55)]">
            <input
              autoFocus
              value={jumpQuery}
              onChange={(e) => setJumpQuery(e.target.value)}
              placeholder="搜索模块 / 路径…"
              className="w-full h-11 px-4 rounded-2xl glass-input text-sm outline-none"
            />
            <div className="mt-2 max-h-72 overflow-y-auto flex flex-col gap-1">
              {filteredJump.map((item) => (
                <button
                  key={item.to}
                  type="button"
                  className="flex items-center gap-3 px-3 py-2.5 rounded-xl text-left hover:bg-violet-500/15 cursor-pointer"
                  onClick={() => {
                    navigate(item.to);
                    setJumpOpen(false);
                    setJumpQuery("");
                  }}
                >
                  <span className="text-violet-300">{item.icon}</span>
                  <span className="flex-1 text-sm font-medium">{item.label}</span>
                  <span className="text-[10px] text-slate-500">{item.to}</span>
                </button>
              ))}
              {filteredJump.length === 0 && (
                <div className="px-3 py-8 text-center text-xs text-slate-500">没有匹配的页面</div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
