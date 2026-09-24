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
  icon: ReactNode;
}

interface NavGroup {
  title: string;
  items: NavItem[];
}

const NAV_GROUPS: NavGroup[] = [
  {
    title: "概览",
    items: [
      { to: "/", label: "工作台", icon: <DashboardIcon size={18} /> },
    ],
  },
  {
    title: "采集与对照",
    items: [
      { to: "/collector/ai-analysis", label: "AI研判", icon: <SparklesIcon size={18} /> },
      { to: "/collector/sources", label: "数据源采集", icon: <DatabaseIcon size={18} /> },
      { to: "/collector/draws", label: "开奖管理", icon: <TrophyIcon size={18} /> },
      { to: "/collector/consensus", label: "多源对照", icon: <CompareIcon size={18} /> },
      { to: "/collector/numbers", label: "号码分析", icon: <HashIcon size={18} /> },
    ],
  },
  {
    title: "质量与度量",
    items: [
      { to: "/collector/ratings", label: "源可信评级", icon: <StarIcon size={18} /> },
      { to: "/collector/monitor", label: "服务监控", icon: <ActivityIcon size={18} /> },
    ],
  },
  {
    title: "账户与系统",
    items: [
      { to: "/profile", label: "个人中心", icon: <UserIcon size={18} /> },
      { to: "/settings", label: "系统设置", icon: <SettingsIcon size={18} /> },
    ],
  },
];

const PAGE_TITLES: Record<string, string> = {
  "/": "系统工作台",
  "/collector/ai-analysis": "AI研判",
  "/collector/sources": "数据源采集",
  "/collector/draws": "开奖管理",
  "/collector/consensus": "多源数据对照",
  "/collector/numbers": "号码指标分析",
  "/collector/ratings": "源可信评级",
  "/collector/monitor": "节点服务监控",
  "/profile": "个人中心与设备安全",
  "/settings": "系统设置",
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

  const currentTitle = PAGE_TITLES[location.pathname] || "工作台";
  const initial = (user?.display_name || user?.email || "用")?.charAt(0).toUpperCase();

  const renderSidebarContent = () => (
    <div className="h-full flex flex-col justify-between p-4 sm:p-5 select-none">
      {/* 顶部品牌 */}
      <div className="min-h-0 flex flex-col">
        <div className="flex items-center justify-between px-2 py-2 mb-6">
          <Link to="/" className="flex items-center gap-3 no-underline">
            <div className="w-10 h-10 rounded-2xl brand-gradient flex items-center justify-center text-white font-bold text-lg shadow-[0_8px_24px_-6px_rgba(139,92,246,0.55)] ring-1 ring-white/30">
              对
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-lg text-gradient tracking-wider">对料</span>
                <span className="text-[10px] px-1.5 py-0.5 rounded-md glass-subtle text-violet-600 dark:text-violet-300 font-mono">
                  v2.0
                </span>
              </div>
              <span className="text-[11px] text-slate-500 dark:text-slate-400 block -mt-0.5">Aurora Glass 控制台</span>
            </div>
          </Link>

          {/* 移动端关闭按钮 */}
          <button
            type="button"
            className="md:hidden text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-white p-1.5 rounded-xl glass-subtle cursor-pointer"
            onClick={() => setMobileMenuOpen(false)}
          >
            <CloseIcon size={18} />
          </button>
        </div>

        {/* 分类菜单 */}
        <div className="space-y-6 overflow-y-auto max-h-[calc(100vh-240px)] pr-1 -mr-1">
          {NAV_GROUPS.map((group) => (
            <div key={group.title}>
              <div className="px-3 mb-2 text-[11px] font-semibold text-slate-400 dark:text-slate-500 uppercase tracking-widest">
                {group.title}
              </div>
              <div className="space-y-1">
                {group.items.map((item) => {
                  const active = location.pathname === item.to;
                  return (
                    <Link
                      key={item.to}
                      to={item.to}
                      onClick={() => setMobileMenuOpen(false)}
                      className={`relative flex items-center gap-3 px-3 py-2.5 rounded-2xl text-sm font-medium transition-all duration-200 no-underline ${
                        active
                          ? "text-violet-700 dark:text-violet-200 bg-gradient-to-r from-violet-500/15 via-fuchsia-500/10 to-transparent border border-violet-400/30 dark:border-violet-400/25 shadow-[0_4px_16px_-6px_rgba(139,92,246,0.35),inset_0_1px_0_rgba(255,255,255,0.35)] dark:shadow-[0_4px_16px_-6px_rgba(139,92,246,0.3),inset_0_1px_0_rgba(255,255,255,0.08)]"
                          : "text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white hover:bg-white/50 dark:hover:bg-white/5 border border-transparent"
                      }`}
                    >
                      {active && (
                        <span className="absolute left-0 top-1/2 -translate-y-1/2 w-1 h-5 rounded-full brand-gradient shadow-[0_0_8px_rgba(139,92,246,0.6)]" />
                      )}
                      <span className={active ? "text-violet-600 dark:text-violet-300" : "text-slate-400 dark:text-slate-500"}>
                        {item.icon}
                      </span>
                      <span>{item.label}</span>
                    </Link>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* 底部用户信息与操作 */}
      <div className="pt-4 mt-4 border-t border-slate-200/60 dark:border-white/8">
        <div className="flex items-center justify-between p-2 rounded-2xl glass-subtle">
          <Link to="/profile" className="flex items-center gap-2.5 min-w-0 no-underline text-inherit group">
            <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center text-white font-bold text-xs shrink-0 shadow-[0_4px_12px_-4px_rgba(139,92,246,0.5)] ring-1 ring-white/30">
              {initial}
            </div>
            <div className="min-w-0">
              <div className="text-xs font-semibold text-slate-800 dark:text-slate-200 truncate group-hover:text-violet-600 dark:group-hover:text-violet-300 transition-colors">
                {user?.display_name || user?.email || "用户"}
              </div>
              <div className="text-[10px] text-slate-500 dark:text-slate-400 truncate">
                {user?.role === "admin" ? "系统管理员" : "标准用户"}
              </div>
            </div>
          </Link>

          <div className="flex items-center gap-1 shrink-0">
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="切换主题"
              className="text-slate-500 hover:text-violet-600 dark:text-slate-400 dark:hover:text-violet-300 hover:bg-violet-500/10"
              onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
            >
              {resolvedTheme === "dark" ? <SunIcon size={16} /> : <MoonIcon size={16} />}
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="退出登录"
              className="text-slate-500 hover:text-rose-500 dark:text-slate-400 dark:hover:text-rose-400 hover:bg-rose-500/10"
              onClick={handleLogout}
            >
              <LogOutIcon size={16} />
            </Button>
          </div>
        </div>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen text-slate-900 dark:text-slate-100 flex">
      {/* 极光背景层 */}
      <div className="app-aurora" />
      <div className="app-aurora-grid" />

      {/* 桌面端常驻玻璃侧边栏（悬浮式） */}
      <aside className="hidden md:block w-72 fixed inset-y-0 left-0 z-30 p-4">
        <div className="h-full rounded-3xl glass-panel overflow-hidden">
          {renderSidebarContent()}
        </div>
      </aside>

      {/* 移动端侧边抽屉 */}
      {mobileMenuOpen && (
        <div className="fixed inset-0 z-50 md:hidden flex">
          <div
            className="fixed inset-0 bg-slate-900/40 dark:bg-black/60 backdrop-blur-sm transition-opacity"
            onClick={() => setMobileMenuOpen(false)}
          />
          <div className="relative w-80 max-w-[85vw] h-full p-3 z-10 animate-in slide-in-from-left duration-200">
            <div className="h-full rounded-3xl glass-panel overflow-hidden shadow-2xl">
              {renderSidebarContent()}
            </div>
          </div>
        </div>
      )}

      {/* 右侧主工作区 */}
      <div className="flex-1 md:pl-72 flex flex-col min-h-screen min-w-0">
        {/* 顶部玻璃状态栏（悬浮） */}
        <header className="sticky top-0 z-20 px-4 sm:px-6 lg:px-8 pt-4">
          <div className="h-16 glass-panel rounded-2xl px-4 sm:px-6 flex items-center justify-between gap-4 max-w-7xl mx-auto w-full">
            <div className="flex items-center gap-3 min-w-0">
              <button
                type="button"
                className="md:hidden p-2 rounded-xl text-slate-600 dark:text-slate-300 hover:bg-violet-500/10 cursor-pointer"
                onClick={() => setMobileMenuOpen(true)}
                aria-label="打开菜单"
              >
                <MenuIcon size={20} />
              </button>
              <div className="flex items-center gap-2 min-w-0">
                <span className="text-xs text-slate-400 dark:text-slate-500 hidden sm:inline shrink-0">工作台 /</span>
                <h1 className="text-base sm:text-lg font-bold text-slate-900 dark:text-white tracking-tight truncate">
                  {currentTitle}
                </h1>
              </div>
            </div>

            <div className="flex items-center gap-3">
              {/* 安全状态指示胶囊 */}
              <div className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-medium border backdrop-blur-md ${
                sessionStatus === 'connected' ? 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-400/40 dark:border-emerald-400/25' :
                sessionStatus === 'connecting' ? 'bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-400/40 dark:border-amber-400/25' :
                'bg-rose-500/10 text-rose-700 dark:text-rose-300 border-rose-400/40 dark:border-rose-400/25'
              }`}>
                <span className={`w-1.5 h-1.5 rounded-full ${
                  sessionStatus === 'connected' ? 'bg-emerald-500 animate-pulse shadow-[0_0_6px_rgba(16,185,129,0.8)]' :
                  sessionStatus === 'connecting' ? 'bg-amber-500 animate-pulse shadow-[0_0_6px_rgba(245,158,11,0.8)]' :
                  'bg-rose-500 shadow-[0_0_6px_rgba(244,63,94,0.8)]'
                }`} />
                <span className="hidden sm:inline">
                  {sessionStatus === 'connected' ? '加密链路正常' :
                   sessionStatus === 'connecting' ? '加密链路连接中' :
                   '加密链路断开'}
                </span>
                <span className="sm:hidden">
                  {sessionStatus === 'connected' ? '加密连接' :
                   sessionStatus === 'connecting' ? '连接中' :
                   '已断开'}
                </span>
              </div>

              {/* 顶栏右侧快捷头像 */}
              <Link
                to="/profile"
                className="w-9 h-9 rounded-full brand-gradient flex items-center justify-center text-white font-bold text-xs shadow-[0_4px_14px_-4px_rgba(139,92,246,0.55)] ring-2 ring-white/40 dark:ring-white/15 hover:scale-105 transition-transform"
                title={user?.display_name || user?.email || "个人中心"}
              >
                {initial}
              </Link>
            </div>
          </div>
        </header>

        {/* 页面内容 */}
        <main className="flex-1 px-4 sm:px-6 lg:px-8 pb-8 pt-6 w-full">
          <div className="max-w-7xl mx-auto animate-fadeIn">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
}
