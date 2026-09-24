import { useState, useEffect, type ReactNode } from "react";
import { Link, Outlet, useLocation, useNavigate } from "react-router-dom";
import { api } from "../lib/api";
import { Button } from "@appica/ui-react/button";
import { useTheme } from "@appica/ui-react/hooks/use-theme";
import { useAuth } from "../auth/AuthContext";
import {
  DashboardIcon,
  DatabaseIcon,
  TrophyIcon,
  CompareIcon,
  StarIcon,
  HashIcon,
  ActivityIcon,
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
}

interface NavGroup {
  title: string;
  items: NavItem[];
}

const NAV_GROUPS: NavGroup[] = [
  {
    title: "概览",
    items: [{ to: "/", label: "工作台", short: "工作台", icon: <DashboardIcon size={18} /> }],
  },
  {
    title: "业务",
    items: [
      { to: "/collector/ai-analysis", label: "AI研判", short: "研判", icon: <SparklesIcon size={18} /> },
      { to: "/collector/sources", label: "数据源采集", short: "采集", icon: <DatabaseIcon size={18} /> },
      { to: "/collector/draws", label: "开奖管理", short: "开奖", icon: <TrophyIcon size={18} /> },
      { to: "/collector/consensus", label: "多源对照", short: "对照", icon: <CompareIcon size={18} /> },
      { to: "/collector/numbers", label: "号码分析", short: "号码", icon: <HashIcon size={18} /> },
    ],
  },
  {
    title: "质量",
    items: [
      { to: "/collector/ratings", label: "源可信评级", short: "评级", icon: <StarIcon size={18} /> },
      { to: "/collector/monitor", label: "服务监控", short: "监控", icon: <ActivityIcon size={18} /> },
    ],
  },
  {
    title: "账户",
    items: [
      { to: "/profile", label: "个人中心", short: "账户", icon: <UserIcon size={18} /> },
      { to: "/settings", label: "系统设置", short: "设置", icon: <SettingsIcon size={18} /> },
    ],
  },
];

const PAGE_TITLES: Record<string, { title: string; group: string }> = {
  "/": { title: "系统工作台", group: "概览" },
  "/collector/ai-analysis": { title: "AI研判", group: "采集与对照" },
  "/collector/sources": { title: "数据源采集", group: "采集与对照" },
  "/collector/draws": { title: "开奖管理", group: "采集与对照" },
  "/collector/consensus": { title: "多源数据对照", group: "采集与对照" },
  "/collector/numbers": { title: "号码指标分析", group: "采集与对照" },
  "/collector/ratings": { title: "源可信评级", group: "质量与度量" },
  "/collector/monitor": { title: "节点服务监控", group: "质量与度量" },
  "/profile": { title: "个人中心与设备安全", group: "账户与系统" },
  "/settings": { title: "系统设置", group: "账户与系统" },
};

export function AppLayout() {
  const { user, logout } = useAuth();
  const { resolvedTheme, setTheme } = useTheme();
  const navigate = useNavigate();
  const location = useLocation();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [sessionStatus, setSessionStatus] = useState(api.getSessionStatus());

  useEffect(() => {
    return api.subscribeStatus(setSessionStatus);
  }, []);

  const handleLogout = async () => {
    await logout();
    navigate("/login", { replace: true });
  };

  const page = PAGE_TITLES[location.pathname] || { title: "工作台", group: "概览" };
  const initial = (user?.display_name || user?.email || "用")?.charAt(0).toUpperCase();

  const statusClass =
    sessionStatus === "connected"
      ? "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-400/40 dark:border-emerald-400/25"
      : sessionStatus === "connecting"
        ? "bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-400/40 dark:border-amber-400/25"
        : "bg-rose-500/10 text-rose-700 dark:text-rose-300 border-rose-400/40 dark:border-rose-400/25";
  const dotClass =
    sessionStatus === "connected"
      ? "bg-emerald-500 animate-pulse"
      : sessionStatus === "connecting"
        ? "bg-amber-500 animate-pulse"
        : "bg-rose-500";
  const statusText =
    sessionStatus === "connected" ? "加密链路正常" : sessionStatus === "connecting" ? "连接中" : "链路断开";

  const rail = (
    <nav className="flex flex-col gap-1">
      {NAV_GROUPS.map((group, gi) => (
        <div key={group.title}>
          {gi > 0 && <div className="my-2 mx-3 h-px bg-slate-200/70 dark:bg-white/10" />}
          {group.items.map((item) => {
            const active = location.pathname === item.to;
            return (
              <Link
                key={item.to}
                to={item.to}
                title={item.label}
                className={`flex flex-col items-center justify-center gap-1 h-[68px] rounded-2xl no-underline transition-all ${
                  active
                    ? "bg-violet-500/15 text-violet-700 dark:text-violet-200 shadow-[inset_0_0_0_1px_rgba(139,92,246,0.35)]"
                    : "text-slate-500 dark:text-slate-400 hover:bg-white/50 dark:hover:bg-white/5 hover:text-slate-900 dark:hover:text-white"
                }`}
              >
                <span className={active ? "text-violet-600 dark:text-violet-300" : ""}>{item.icon}</span>
                <span className="text-[10px] font-medium leading-none">{item.short}</span>
              </Link>
            );
          })}
        </div>
      ))}
    </nav>
  );

  return (
    <div className="min-h-screen text-slate-900 dark:text-slate-100">
      <div className="app-aurora" />
      <div className="app-aurora-grid" />

      <header className="sticky top-0 z-30 px-3 sm:px-4 pt-3">
        <div className="h-14 glass-panel rounded-2xl px-3 sm:px-4 flex items-center gap-3">
          <Link to="/" className="flex items-center gap-2.5 no-underline shrink-0">
            <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center text-white font-bold shadow-[0_8px_20px_-8px_rgba(139,92,246,0.7)]">
              对
            </div>
            <span className="font-bold text-gradient tracking-wider hidden sm:inline">对料</span>
          </Link>
          <div className="h-6 w-px bg-slate-200/80 dark:bg-white/10 hidden sm:block" />
          <div className="min-w-0 flex-1">
            <div className="text-[10px] uppercase tracking-[0.16em] text-slate-400 dark:text-slate-500">{page.group}</div>
            <div className="text-sm font-semibold text-slate-900 dark:text-white truncate">{page.title}</div>
          </div>
          <div className={`hidden sm:inline-flex items-center gap-2 px-2.5 py-1 rounded-full text-[11px] font-medium border ${statusClass}`}>
            <span className={`w-1.5 h-1.5 rounded-full ${dotClass}`} />
            {statusText}
          </div>
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label="切换主题"
            className="text-slate-500 hover:text-violet-600 dark:text-slate-400 dark:hover:text-violet-300"
            onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
          >
            {resolvedTheme === "dark" ? <SunIcon size={16} /> : <MoonIcon size={16} />}
          </Button>
          <Link
            to="/profile"
            className="w-8 h-8 rounded-full brand-gradient flex items-center justify-center text-white text-xs font-bold no-underline"
            title={user?.display_name || user?.email || "个人中心"}
          >
            {initial}
          </Link>
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label="退出登录"
            className="text-slate-500 hover:text-rose-500 dark:text-slate-400"
            onClick={handleLogout}
          >
            <LogOutIcon size={16} />
          </Button>
        </div>
      </header>

      <div className="flex">
        <aside className="hidden md:block w-[92px] shrink-0 sticky top-[4.75rem] h-[calc(100vh-5.75rem)] px-2 py-3">
          <div className="h-full glass-panel rounded-3xl p-2 overflow-y-auto">{rail}</div>
        </aside>

        <main className="flex-1 min-w-0 px-3 sm:px-5 lg:px-6 pb-24 md:pb-8 pt-4">
          <div className="max-w-[1400px] animate-fadeIn">
            <Outlet />
          </div>
        </main>
      </div>

      <div className="md:hidden fixed inset-x-0 bottom-0 z-30 p-3">
        <div className="glass-panel rounded-2xl px-1.5 py-1.5 grid grid-cols-5 gap-1">
          {NAV_GROUPS.flatMap((g) => g.items)
            .slice(0, 4)
            .map((item) => {
              const active = location.pathname === item.to;
              return (
                <Link
                  key={item.to}
                  to={item.to}
                  className={`flex flex-col items-center justify-center gap-1 h-14 rounded-xl no-underline text-[10px] ${
                    active ? "bg-violet-500/15 text-violet-700 dark:text-violet-200" : "text-slate-500 dark:text-slate-400"
                  }`}
                >
                  {item.icon}
                  {item.short}
                </Link>
              );
            })}
          <button
            type="button"
            className="flex flex-col items-center justify-center gap-1 h-14 rounded-xl text-[10px] text-slate-500 dark:text-slate-400"
            onClick={() => setMobileMenuOpen(true)}
          >
            <MenuIcon size={18} />
            更多
          </button>
        </div>
      </div>

      {mobileMenuOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <div className="absolute inset-0 bg-slate-900/40 backdrop-blur-sm" onClick={() => setMobileMenuOpen(false)} />
          <div className="absolute left-3 right-3 bottom-24 glass-panel rounded-3xl p-4 animate-glassPop">
            <div className="flex items-center justify-between mb-3">
              <span className="text-sm font-semibold">全部导航</span>
              <button type="button" className="p-1.5 rounded-lg glass-subtle" onClick={() => setMobileMenuOpen(false)} aria-label="关闭菜单">
                <CloseIcon size={16} />
              </button>
            </div>
            <div className="grid grid-cols-4 gap-2">
              {NAV_GROUPS.flatMap((g) => g.items).map((item) => {
                const active = location.pathname === item.to;
                return (
                  <Link
                    key={item.to}
                    to={item.to}
                    onClick={() => setMobileMenuOpen(false)}
                    className={`flex flex-col items-center gap-1 py-3 rounded-2xl no-underline text-[11px] ${
                      active ? "bg-violet-500/15 text-violet-700 dark:text-violet-200" : "text-slate-600 dark:text-slate-300"
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
    </div>
  );
}
