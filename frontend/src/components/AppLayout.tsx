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
    <div className="h-full flex flex-col justify-between p-4 sm:p-5 bg-[#0b1220] text-slate-200 select-none">
      {/* 顶部品牌 */}
      <div>
        <div className="flex items-center justify-between px-2 py-2 mb-6">
          <Link to="/" className="flex items-center gap-3 no-underline">
            <div className="w-9 h-9 rounded-xl brand-gradient flex items-center justify-center text-white font-bold text-lg shadow-md shadow-cyan-500/20">
              对
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-lg text-white tracking-wider">对料</span>
                <span className="text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-cyan-300 font-mono border border-slate-700">
                  v2.0
                </span>
              </div>
              <span className="text-[11px] text-slate-400 block -mt-0.5">端到端加密控制台</span>
            </div>
          </Link>

          {/* 移动端关闭按钮 */}
          <button
            type="button"
            className="md:hidden text-slate-400 hover:text-white p-1 rounded-lg hover:bg-slate-800/80 cursor-pointer"
            onClick={() => setMobileMenuOpen(false)}
          >
            <CloseIcon size={20} />
          </button>
        </div>

        {/* 分类菜单 */}
        <div className="space-y-6 overflow-y-auto max-h-[calc(100vh-230px)] pr-1">
          {NAV_GROUPS.map((group) => (
            <div key={group.title}>
              <div className="px-3 mb-2 text-[11px] font-semibold text-slate-400 uppercase tracking-wider">
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
                      className={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all duration-150 ${
                        active
                          ? "bg-cyan-500/15 text-cyan-300 border border-cyan-500/30 shadow-sm"
                          : "text-slate-400 hover:text-slate-100 hover:bg-slate-800/60"
                      }`}
                    >
                      <span className={active ? "text-cyan-400" : "text-slate-400"}>
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
      <div className="pt-4 border-t border-slate-800/80">
        <div className="flex items-center justify-between p-2 rounded-xl bg-slate-900/60 border border-slate-800/80">
          <Link to="/profile" className="flex items-center gap-2.5 min-w-0 no-underline text-inherit group">
            <div className="w-8 h-8 rounded-lg brand-gradient flex items-center justify-center text-white font-bold text-xs shrink-0 shadow-sm">
              {initial}
            </div>
            <div className="min-w-0">
              <div className="text-xs font-semibold text-slate-200 truncate group-hover:text-cyan-300 transition-colors">
                {user?.display_name || user?.email || "用户"}
              </div>
              <div className="text-[10px] text-slate-400 truncate">
                {user?.role === "admin" ? "系统管理员" : "标准用户"}
              </div>
            </div>
          </Link>

          <div className="flex items-center gap-1 shrink-0">
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="切换主题"
              className="text-slate-400 hover:text-white hover:bg-slate-800"
              onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
            >
              {resolvedTheme === "dark" ? <SunIcon size={16} /> : <MoonIcon size={16} />}
            </Button>
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="退出登录"
              className="text-slate-400 hover:text-red-400 hover:bg-red-950/30"
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
    <div className="min-h-screen bg-slate-50/70 dark:bg-[#070b14] text-slate-900 dark:text-slate-100 flex">
      {/* 桌面端常驻侧边栏 */}
      <aside className="hidden md:block w-64 fixed inset-y-0 left-0 z-30 border-r border-slate-800/60 shadow-xl">
        {renderSidebarContent()}
      </aside>

      {/* 移动端侧边抽屉 */}
      {mobileMenuOpen && (
        <div className="fixed inset-0 z-50 md:hidden flex">
          <div
            className="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity"
            onClick={() => setMobileMenuOpen(false)}
          />
          <div className="relative w-72 max-w-[80vw] h-full shadow-2xl z-10 animate-in slide-in-from-left duration-200">
            {renderSidebarContent()}
          </div>
        </div>
      )}

      {/* 右侧主工作区 */}
      <div className="flex-1 md:pl-64 flex flex-col min-h-screen min-w-0">
        {/* 顶部状态栏 */}
        <header className="sticky top-0 z-20 h-16 bg-white/80 dark:bg-[#0b1220]/80 backdrop-blur-md border-b border-slate-200/80 dark:border-slate-800/80 px-4 sm:px-8 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0">
            <button
              type="button"
              className="md:hidden p-2 rounded-xl text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800 cursor-pointer"
              onClick={() => setMobileMenuOpen(true)}
              aria-label="打开菜单"
            >
              <MenuIcon size={20} />
            </button>
            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400 hidden sm:inline">工作台 /</span>
              <h1 className="text-base sm:text-lg font-bold text-slate-900 dark:text-white tracking-tight truncate">
                {currentTitle}
              </h1>
            </div>
          </div>

          <div className="flex items-center gap-3">
            {/* 安全状态指示胶囊 */}
            <div className={`inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-medium border shadow-xs ${
              sessionStatus === 'connected' ? 'bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-400 border-emerald-200/70 dark:border-emerald-800/60' :
              sessionStatus === 'connecting' ? 'bg-yellow-50 text-yellow-700 dark:bg-yellow-950/40 dark:text-yellow-400 border-yellow-200/70 dark:border-yellow-800/60' :
              'bg-red-50 text-red-700 dark:bg-red-950/40 dark:text-red-400 border-red-200/70 dark:border-red-800/60'
            }`}>
              <span className={`w-1.5 h-1.5 rounded-full ${
                sessionStatus === 'connected' ? 'bg-emerald-500 animate-pulse shadow-[0_0_6px_rgba(16,185,129,0.8)]' :
                sessionStatus === 'connecting' ? 'bg-yellow-500 animate-pulse shadow-[0_0_6px_rgba(234,179,8,0.8)]' :
                'bg-red-500 shadow-[0_0_6px_rgba(239,68,68,0.8)]'
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
              className="w-8 h-8 rounded-full brand-gradient flex items-center justify-center text-white font-bold text-xs shadow-sm hover:scale-105 transition-transform"
              title={user?.display_name || user?.email || "个人中心"}
            >
              {initial}
            </Link>
          </div>
        </header>

        {/* 页面内容 */}
        <main className="flex-1 p-4 sm:p-6 lg:p-8 max-w-7xl w-full mx-auto">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

