import { useEffect, useState, type ReactNode } from "react";
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
}

interface NavGroup {
  title: string;
  items: NavItem[];
}

const NAV_GROUPS: NavGroup[] = [
  {
    title: "概览",
    items: [{ to: "/", label: "工作台", short: "工作台", icon: <DashboardIcon size={16} /> }],
  },
  {
    title: "业务",
    items: [
      { to: "/collector/ai-analysis", label: "AI 研判", short: "研判", icon: <SparklesIcon size={16} /> },
      { to: "/collector/sources", label: "数据源采集", short: "采集", icon: <DatabaseIcon size={16} /> },
      { to: "/collector/draws", label: "开奖管理", short: "开奖", icon: <TrophyIcon size={16} /> },
      { to: "/collector/consensus", label: "多源对照", short: "对照", icon: <CompareIcon size={16} /> },
      { to: "/collector/numbers", label: "号码分析", short: "号码", icon: <HashIcon size={16} /> },
    ],
  },
  {
    title: "质量与平台",
    items: [
      { to: "/collector/ratings", label: "源可信评级", short: "评级", icon: <StarIcon size={16} /> },
      { to: "/collector/monitor", label: "服务监控", short: "监控", icon: <ActivityIcon size={16} /> },
      { to: "/collector/platform", label: "采集平台", short: "平台", icon: <GlobeIcon size={16} /> },
    ],
  },
  {
    title: "账户",
    items: [
      { to: "/profile", label: "个人中心", short: "账户", icon: <UserIcon size={16} /> },
      { to: "/settings", label: "系统设置", short: "设置", icon: <SettingsIcon size={16} /> },
    ],
  },
];

const PAGE_TITLES: Record<string, { title: string; group: string }> = {
  "/": { title: "工作台", group: "概览" },
  "/collector/ai-analysis": { title: "AI 研判", group: "业务" },
  "/collector/sources": { title: "数据源采集", group: "业务" },
  "/collector/draws": { title: "开奖管理", group: "业务" },
  "/collector/consensus": { title: "多源对照", group: "业务" },
  "/collector/numbers": { title: "号码分析", group: "业务" },
  "/collector/ratings": { title: "源可信评级", group: "质量与平台" },
  "/collector/monitor": { title: "服务监控", group: "质量与平台" },
  "/collector/platform": { title: "采集平台", group: "质量与平台" },
  "/profile": { title: "个人中心", group: "账户" },
  "/settings": { title: "系统设置", group: "账户" },
};

const MOBILE_PRIMARY_COUNT = 4;

export function AppLayout() {
  const { user, logout } = useAuth();
  const { resolvedTheme, setTheme } = useTheme();
  const navigate = useNavigate();
  const location = useLocation();
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [sessionStatus, setSessionStatus] = useState(api.getSessionStatus());

  useEffect(() => api.subscribeStatus(setSessionStatus), []);

  useEffect(() => {
    if (!mobileMenuOpen) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMobileMenuOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [mobileMenuOpen]);

  const handleLogout = async () => {
    await logout();
    navigate("/login", { replace: true });
  };

  const page = PAGE_TITLES[location.pathname] || { title: "工作台", group: "概览" };
  const mobileItems = NAV_GROUPS.flatMap((group) => group.items);
  const mobilePrimary = mobileItems.slice(0, MOBILE_PRIMARY_COUNT);
  const moreActive = !mobilePrimary.some((item) => item.to === location.pathname);

  const statusText =
    sessionStatus === "connected" ? "加密链路正常" : sessionStatus === "connecting" ? "连接中" : "链路断开";
  const statusTone =
    sessionStatus === "connected"
      ? "text-emerald-600 bg-emerald-50 border-emerald-200 dark:text-emerald-300 dark:bg-emerald-500/10 dark:border-emerald-500/30"
      : sessionStatus === "connecting"
        ? "text-amber-700 bg-amber-50 border-amber-200 dark:text-amber-300 dark:bg-amber-500/10 dark:border-amber-500/30"
        : "text-rose-700 bg-rose-50 border-rose-200 dark:text-rose-300 dark:bg-rose-500/10 dark:border-rose-500/30";

  return (
    <div className="admin-shell">
      <aside className="admin-sidebar hidden md:flex">
        <div className="admin-sidebar-brand">
          <div className="brand-mark">对</div>
          <div className="min-w-0">
            <div className="text-sm font-semibold text-white tracking-wide">对料</div>
            <div className="text-[10px] text-slate-500 truncate">采集控制台</div>
          </div>
        </div>
        <nav className="admin-sidebar-nav">
          {NAV_GROUPS.map((group) => (
            <div key={group.title} className="admin-nav-group">
              <div className="admin-nav-group-title">{group.title}</div>
              {group.items.map((item) => {
                const active = location.pathname === item.to;
                return (
                  <Link key={item.to} to={item.to} className={`admin-nav-link${active ? " active" : ""}`}>
                    <span className="opacity-90">{item.icon}</span>
                    <span className="truncate">{item.label}</span>
                  </Link>
                );
              })}
            </div>
          ))}
        </nav>
        <div className="p-3 border-t border-white/10">
          <div className="flex items-center gap-2 px-2 py-2 rounded-lg bg-white/5">
            <UserAvatar
              name={user?.display_name || user?.email}
              url={user?.avatar_url}
              className="h-8 w-8 rounded-full text-xs"
            />
            <div className="min-w-0 flex-1">
              <div className="text-xs font-medium text-slate-100 truncate">
                {user?.display_name || user?.email || "用户"}
              </div>
              <div className="text-[10px] text-slate-500 truncate">{user?.role || "member"}</div>
            </div>
            <button
              type="button"
              className="p-1.5 rounded-md text-slate-400 hover:text-white hover:bg-white/10"
              title="退出登录"
              onClick={handleLogout}
            >
              <LogOutIcon size={14} />
            </button>
          </div>
        </div>
      </aside>

      <div className="admin-main">
        <header className="admin-topbar">
          <button
            type="button"
            className="md:hidden p-2 rounded-lg border border-slate-200 dark:border-slate-700"
            onClick={() => setMobileMenuOpen(true)}
            aria-label="打开导航"
          >
            <MenuIcon size={16} />
          </button>
          <div className="min-w-0 flex-1">
            <div className="text-[10px] uppercase tracking-[0.14em] text-slate-400">{page.group}</div>
            <div className="admin-page-title truncate text-[15px] sm:text-base">{page.title}</div>
          </div>
          <div className={`hidden sm:inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-medium border ${statusTone}`}>
            <span
              className={`w-1.5 h-1.5 rounded-full ${
                sessionStatus === "connected"
                  ? "bg-emerald-500"
                  : sessionStatus === "connecting"
                    ? "bg-amber-500"
                    : "bg-rose-500"
              }`}
            />
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
          <Link to="/profile" className="hidden sm:block no-underline" title="个人中心">
            <UserAvatar
              name={user?.display_name || user?.email}
              url={user?.avatar_url}
              className="h-8 w-8 rounded-full text-xs"
            />
          </Link>
        </header>

        <main className="admin-content">
          <div className="workspace-fill animate-fadeIn">
            <Outlet />
          </div>
        </main>
      </div>

      <div className="admin-mobile-nav md:hidden grid grid-cols-5 gap-1">
        {mobilePrimary.map((item) => {
          const active = location.pathname === item.to;
          return (
            <Link
              key={item.to}
              to={item.to}
              className={`flex flex-col items-center justify-center gap-1 h-12 rounded-lg no-underline text-[10px] ${
                active ? "bg-brand-50 text-brand-700 dark:bg-brand-500/15 dark:text-brand-200" : "text-slate-500"
              }`}
            >
              {item.icon}
              {item.short}
            </Link>
          );
        })}
        <button
          type="button"
          className={`flex flex-col items-center justify-center gap-1 h-12 rounded-lg text-[10px] ${
            moreActive || mobileMenuOpen
              ? "bg-brand-50 text-brand-700 dark:bg-brand-500/15 dark:text-brand-200"
              : "text-slate-500"
          }`}
          onClick={() => setMobileMenuOpen(true)}
        >
          <MenuIcon size={16} />
          更多
        </button>
      </div>

      {mobileMenuOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <div className="absolute inset-0 bg-slate-900/45" onClick={() => setMobileMenuOpen(false)} />
          <div className="absolute left-3 right-3 bottom-20 admin-card p-4 animate-fadeIn">
            <div className="flex items-center justify-between mb-3">
              <span className="text-sm font-semibold">全部导航</span>
              <button type="button" className="p-1.5 rounded-lg border border-slate-200 dark:border-slate-700" onClick={() => setMobileMenuOpen(false)}>
                <CloseIcon size={14} />
              </button>
            </div>
            <div className="grid grid-cols-3 gap-2">
              {mobileItems.map((item) => {
                const active = location.pathname === item.to;
                return (
                  <Link
                    key={item.to}
                    to={item.to}
                    onClick={() => setMobileMenuOpen(false)}
                    className={`flex flex-col items-center gap-1.5 py-3 rounded-xl no-underline text-[11px] border ${
                      active
                        ? "bg-brand-50 text-brand-700 border-brand-200 dark:bg-brand-500/15 dark:text-brand-200 dark:border-brand-500/30"
                        : "text-slate-600 dark:text-slate-300 border-slate-200 dark:border-slate-700"
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
