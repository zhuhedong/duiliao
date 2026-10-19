import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { Link, Outlet, useLocation, useNavigate } from "react-router-dom";
import { api } from "../lib/api";
import { Button, toast } from "./ui";
import { useTheme } from "../theme/ThemeProvider";
import { useAuth } from "../auth/AuthContext";
import { UserAvatar } from "./UserAvatar";
import { USER_ROLE_LABEL } from "../lib/userLabels";
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
  TrendIcon,
  TargetIcon,
  ClipboardListIcon,
  SearchIcon,
  SidebarIcon,
  PlusIcon,
} from "./icons";

type NavGroup = "overview" | "intel" | "ops" | "account";

interface NavItem {
  to: string;
  aliases?: string[];
  label: string;
  short: string;
  icon: ReactNode;
  group: NavGroup;
  keywords?: string;
}

const GROUP_LABELS: Record<NavGroup, string> = {
  overview: "概览与记账",
  intel: "开奖与情报",
  ops: "数据源与治理",
  account: "账户与系统",
};

const NAV: NavItem[] = [
  { to: "/", label: "工作台", short: "工作台", icon: <DashboardIcon size={16} />, group: "overview", keywords: "dashboard home 首页 概览" },
  { to: "/records", label: "投注记录", short: "记录", icon: <ClipboardListIcon size={16} />, group: "overview", keywords: "records bet 记账 账本 盈亏" },
  { to: "/collector/ai-analysis", label: "AI 研判", short: "AI 研判", icon: <SparklesIcon size={16} />, group: "overview", keywords: "ai llm 研判 预测 分析" },

  { to: "/collector/draws", label: "开奖管理", short: "开奖", icon: <TrophyIcon size={16} />, group: "intel", keywords: "draws lottery 开奖 期号 特码" },
  { to: "/collector/consensus", label: "多源对照", short: "对照", icon: <CompareIcon size={16} />, group: "intel", keywords: "consensus compare 对照 共识" },
  {
    to: "/collector/pingte-ranking",
    aliases: ["/pingte-ranking"],
    label: "平特排行",
    short: "排行",
    icon: <TargetIcon size={16} />,
    group: "intel",
    keywords: "pingte ranking 平特 连肖 命中率",
  },
  {
    to: "/collector/trend",
    aliases: ["/trend"],
    label: "走势分析",
    short: "走势",
    icon: <TrendIcon size={16} />,
    group: "intel",
    keywords: "trend chart 走势 冷热 遗漏",
  },
  { to: "/collector/numbers", label: "号码属性", short: "号码", icon: <HashIcon size={16} />, group: "intel", keywords: "numbers zodiac 波色 生肖 五行" },

  { to: "/collector/sources", label: "数据源与调度", short: "数据源", icon: <DatabaseIcon size={16} />, group: "ops", keywords: "sources cron schedule 数据源 定时" },
  { to: "/collector/ratings", label: "源可信评级", short: "评级", icon: <StarIcon size={16} />, group: "ops", keywords: "ratings trust 评级 权重" },
  { to: "/collector/monitor", label: "缺期与巡检", short: "监控", icon: <ActivityIcon size={16} />, group: "ops", keywords: "monitor health 缺期 巡检 监控" },
  { to: "/collector/platform", label: "采集平台", short: "平台", icon: <GlobeIcon size={16} />, group: "ops", keywords: "platform spider 爬虫 采集" },

  { to: "/profile", label: "个人中心", short: "账户", icon: <UserIcon size={16} />, group: "account", keywords: "profile user 账户 密码" },
  { to: "/settings", label: "系统设置", short: "设置", icon: <SettingsIcon size={16} />, group: "account", keywords: "settings config 设置 备份 数据库" },
];

function isNavActive(pathname: string, item: NavItem): boolean {
  if (pathname === item.to) return true;
  if (item.aliases?.includes(pathname)) return true;
  return false;
}

interface CommandEntry {
  id: string;
  section: "action" | "nav";
  label: string;
  hint: string;
  shortcut?: string;
  icon: ReactNode;
  active?: boolean;
  run: () => void;
}

export function AppLayout() {
  const { user, logout } = useAuth();
  const { resolvedTheme, setTheme } = useTheme();
  const navigate = useNavigate();
  const location = useLocation();

  const [collapsed, setCollapsed] = useState<boolean>(() => {
    try {
      return localStorage.getItem("duiliao_sidebar_collapsed") === "1";
    } catch {
      return false;
    }
  });
  const [mobileOpen, setMobileOpen] = useState(false);
  const [jumpOpen, setJumpOpen] = useState(false);
  const [jumpQuery, setJumpQuery] = useState("");
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [sessionStatus, setSessionStatus] = useState(api.getSessionStatus());

  useEffect(() => api.subscribeStatus(setSessionStatus), []);

  const toggleCollapsed = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      try {
        localStorage.setItem("duiliao_sidebar_collapsed", next ? "1" : "0");
      } catch {
        // ignore
      }
      return next;
    });
  }, []);

  const toggleThemeMode = useCallback(() => {
    const next = resolvedTheme === "dark" ? "light" : "dark";
    setTheme(next);
    toast.info(`已切换至${next === "dark" ? "暗色" : "亮色"}外观`);
  }, [resolvedTheme, setTheme]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setJumpOpen((prev) => {
          const next = !prev;
          if (next) {
            setJumpQuery("");
            setSelectedIndex(0);
          }
          return next;
        });
      } else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "b") {
        e.preventDefault();
        toggleCollapsed();
      } else if (e.key === "Escape") {
        setJumpOpen(false);
        setMobileOpen(false);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [toggleCollapsed]);

  const currentNav = useMemo(
    () => NAV.find((n) => isNavActive(location.pathname, n)) ?? NAV[0]!,
    [location.pathname],
  );

  const commandEntries = useMemo<CommandEntry[]>(() => {
    const q = jumpQuery.trim().toLowerCase();

    const quickActions: CommandEntry[] = [
      {
        id: "act-new-record",
        section: "action",
        label: "前往投注记录并记一笔",
        hint: "快捷操作",
        icon: <PlusIcon size={15} />,
        run: () => navigate("/records"),
      },
      {
        id: "act-ai",
        section: "action",
        label: "启动 AI 综合研判工作台",
        hint: "快捷操作",
        icon: <SparklesIcon size={15} />,
        run: () => navigate("/collector/ai-analysis"),
      },
      {
        id: "act-theme",
        section: "action",
        label: resolvedTheme === "dark" ? "切换为亮色模式 (Light)" : "切换为暗色模式 (Dark)",
        hint: "外观偏好",
        icon: resolvedTheme === "dark" ? <SunIcon size={15} /> : <MoonIcon size={15} />,
        run: toggleThemeMode,
      },
      {
        id: "act-sidebar",
        section: "action",
        label: collapsed ? "展开左侧导航栏" : "收起左侧导航栏",
        hint: "布局控制",
        shortcut: "⌘B",
        icon: <SidebarIcon size={15} />,
        run: toggleCollapsed,
      },
    ];

    const navEntries: CommandEntry[] = NAV.map((n) => ({
      id: `nav-${n.to}`,
      section: "nav" as const,
      label: n.label,
      hint: GROUP_LABELS[n.group],
      shortcut: n.to,
      icon: n.icon,
      active: isNavActive(location.pathname, n),
      run: () => navigate(n.to),
    }));

    const all = [...quickActions, ...navEntries];
    if (!q) return all;

    return all.filter((item) => {
      const navMatch = NAV.find((n) => `nav-${n.to}` === item.id);
      const kw = navMatch?.keywords ?? "";
      return (
        item.label.toLowerCase().includes(q) ||
        item.hint.toLowerCase().includes(q) ||
        (item.shortcut?.toLowerCase().includes(q) ?? false) ||
        kw.toLowerCase().includes(q)
      );
    });
  }, [jumpQuery, resolvedTheme, collapsed, location.pathname, navigate, toggleThemeMode, toggleCollapsed]);

  useEffect(() => {
    setSelectedIndex(0);
  }, [jumpQuery]);

  const statusText =
    sessionStatus === "connected" ? "链路加密" : sessionStatus === "connecting" ? "握手中" : "已断开";
  const statusClass =
    sessionStatus === "connected"
      ? "text-emerald-700 bg-emerald-50 border-emerald-200/80 dark:text-emerald-300 dark:bg-emerald-500/12 dark:border-emerald-500/25"
      : sessionStatus === "connecting"
        ? "text-amber-700 bg-amber-50 border-amber-200/80 dark:text-amber-300 dark:bg-amber-500/12 dark:border-amber-500/25"
        : "text-rose-700 bg-rose-50 border-rose-200/80 dark:text-rose-300 dark:bg-rose-500/12 dark:border-rose-500/25";

  const handleLogout = async () => {
    await logout();
    navigate("/login", { replace: true });
  };

  const groups: NavGroup[] = ["overview", "intel", "ops", "account"];
  const mobileDockItems = [NAV[0]!, NAV[1]!, NAV[2]!, NAV[4]!]; // 工作台, 记录, AI 研判, 多源对照

  const actionItems = commandEntries.filter((e) => e.section === "action");
  const navItems = commandEntries.filter((e) => e.section === "nav");

  return (
    <div className="min-h-screen relative text-slate-900 dark:text-slate-100">
      <a href="#main-workspace" className="skip-link">
        跳转到主工作区
      </a>
      <div className="app-aurora" />

      <div className="mx-auto max-w-[1600px] px-3 sm:px-4 lg:px-5 py-3 flex items-start gap-4">
        {/* —— Desktop Left Bento Sidebar —— */}
        <aside
          aria-label="主导航侧栏"
          className={`hidden lg:flex flex-col justify-between shrink-0 sticky top-3 h-[calc(100vh-1.5rem)] bento-card rounded-2xl transition-all duration-200 overflow-hidden ${
            collapsed ? "w-[68px] p-2.5" : "w-60 p-3.5"
          }`}
        >
          {/* Brand Header */}
          <div className="flex flex-col min-h-0 flex-1">
            <div
              className={`flex items-center ${
                collapsed ? "justify-center" : "justify-between px-1"
              } pb-3 mb-2 border-b border-slate-100 dark:border-white/[0.06]`}
            >
              <Link to="/" className="flex items-center gap-2.5 no-underline min-w-0">
                <div className="w-9 h-9 rounded-xl brand-mark text-sm shrink-0">对</div>
                {!collapsed && (
                  <div className="min-w-0 leading-tight">
                    <div className="text-[15px] font-bold text-slate-900 dark:text-white tracking-tight truncate">
                      对料工作台
                    </div>
                    <div className="text-[11px] text-slate-400 dark:text-slate-500 truncate">
                      Bento Studio
                    </div>
                  </div>
                )}
              </Link>
            </div>

            {/* Navigation Groups */}
            <nav className="flex-1 overflow-y-auto no-scrollbar space-y-4 py-1">
              {groups.map((grp) => {
                const items = NAV.filter((n) => n.group === grp);
                return (
                  <div key={grp} className="space-y-1">
                    {!collapsed && (
                      <div className="px-2.5 pb-1 text-[10px] font-semibold uppercase tracking-wider text-slate-400 dark:text-slate-500 select-none">
                        {GROUP_LABELS[grp]}
                      </div>
                    )}
                    {items.map((item) => {
                      const active = isNavActive(location.pathname, item);
                      return (
                        <Link
                          key={item.to}
                          to={item.to}
                          title={collapsed ? item.label : undefined}
                          aria-current={active ? "page" : undefined}
                          className={`group relative flex items-center ${
                            collapsed ? "justify-center px-0 h-10" : "gap-2.5 px-2.5 h-9"
                          } rounded-xl text-[13px] no-underline transition-all ${
                            active
                              ? "bg-indigo-50/90 text-indigo-700 dark:bg-indigo-500/15 dark:text-indigo-300 font-semibold shadow-2xs"
                              : "text-slate-600 dark:text-slate-400 hover:bg-slate-100/80 dark:hover:bg-white/[0.05] hover:text-slate-900 dark:hover:text-slate-100 font-medium"
                          }`}
                        >
                          {active && !collapsed && (
                            <span
                              aria-hidden="true"
                              className="w-1 h-4 rounded-full bg-indigo-600 dark:bg-indigo-400 -ml-1 mr-0.5"
                            />
                          )}
                          <span
                            className={`shrink-0 transition-transform duration-150 group-hover:scale-105 ${
                              active
                                ? "text-indigo-600 dark:text-indigo-400"
                                : "text-slate-400 dark:text-slate-500 group-hover:text-slate-700 dark:group-hover:text-slate-300"
                            }`}
                          >
                            {item.icon}
                          </span>
                          {!collapsed && <span className="truncate">{item.label}</span>}
                        </Link>
                      );
                    })}
                  </div>
                );
              })}
            </nav>
          </div>

          {/* Sidebar Footer: User Card */}
          <div className="pt-3 mt-2 border-t border-slate-100 dark:border-white/[0.06]">
            {collapsed ? (
              <div className="flex flex-col items-center gap-2">
                <Link to="/profile" title="个人中心" className="no-underline">
                  <UserAvatar
                    name={user?.display_name || user?.email}
                    url={user?.avatar_url}
                    className="h-8 w-8 rounded-xl text-xs"
                  />
                </Link>
                <button
                  type="button"
                  onClick={handleLogout}
                  title="退出登录"
                  aria-label="退出登录"
                  className="p-2 rounded-xl text-slate-400 hover:text-rose-600 hover:bg-rose-50 dark:hover:bg-rose-500/10 transition-colors cursor-pointer"
                >
                  <LogOutIcon size={15} />
                </button>
              </div>
            ) : (
              <div className="flex items-center justify-between gap-2 p-2 rounded-xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/50 dark:border-white/[0.05]">
                <Link to="/profile" className="flex items-center gap-2.5 min-w-0 no-underline flex-1">
                  <UserAvatar
                    name={user?.display_name || user?.email}
                    url={user?.avatar_url}
                    className="h-8 w-8 rounded-xl text-xs shrink-0"
                  />
                  <div className="min-w-0 flex-1">
                    <div className="text-xs font-semibold text-slate-800 dark:text-slate-100 truncate">
                      {user?.display_name || user?.email || "用户"}
                    </div>
                    <div className="text-[10px] text-slate-400 dark:text-slate-500 truncate">
                      {USER_ROLE_LABEL[user?.role ?? ""] ?? user?.role ?? "在线"}
                    </div>
                  </div>
                </Link>
                <button
                  type="button"
                  onClick={handleLogout}
                  title="退出登录"
                  aria-label="退出登录"
                  className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 dark:hover:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-500/10 transition-colors cursor-pointer shrink-0"
                >
                  <LogOutIcon size={14} />
                </button>
              </div>
            )}
          </div>
        </aside>

        {/* —— Right Main Workspace Column —— */}
        <div className="flex-1 min-w-0 flex flex-col gap-4">
          {/* Top Bento Header Bar */}
          <header className="sticky top-3 z-30 bento-panel rounded-2xl px-3.5 sm:px-4 py-2.5 flex items-center justify-between gap-3">
            <div className="flex items-center gap-2.5 min-w-0">
              {/* Desktop Sidebar Collapse Toggle */}
              <button
                type="button"
                onClick={toggleCollapsed}
                title={collapsed ? "展开侧边栏 (⌘B)" : "收起侧边栏 (⌘B)"}
                aria-label={collapsed ? "展开侧边栏" : "收起侧边栏"}
                className="hidden lg:inline-flex items-center justify-center w-8 h-8 rounded-xl text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100 hover:bg-slate-100 dark:hover:bg-white/[0.06] transition-colors cursor-pointer shrink-0"
              >
                <SidebarIcon size={16} />
              </button>

              {/* Mobile Brand */}
              <Link to="/" className="lg:hidden flex items-center gap-2 no-underline shrink-0">
                <div className="w-8 h-8 rounded-xl brand-mark text-xs">对</div>
              </Link>

              <span className="hidden lg:block w-px h-4 bg-slate-200 dark:bg-white/10" />

              {/* Breadcrumb */}
              <div className="flex items-center gap-2 min-w-0">
                <span className="hidden sm:inline text-xs font-medium text-slate-400 dark:text-slate-500 shrink-0">
                  {GROUP_LABELS[currentNav.group]}
                </span>
                <span className="hidden sm:inline text-slate-300 dark:text-slate-600 text-xs">/</span>
                <div className="flex items-center gap-1.5 text-sm font-semibold text-slate-900 dark:text-white truncate">
                  <span className="text-indigo-600 dark:text-indigo-400 shrink-0">{currentNav.icon}</span>
                  <span className="truncate">{currentNav.label}</span>
                </div>
              </div>
            </div>

            {/* Right Controls */}
            <div className="flex items-center gap-2 shrink-0">
              {/* Quick Search / Command Palette */}
              <button
                type="button"
                onClick={() => {
                  setJumpQuery("");
                  setSelectedIndex(0);
                  setJumpOpen(true);
                }}
                aria-label="打开命令面板 (⌘K)"
                className="inline-flex items-center gap-2 h-8.5 px-2.5 sm:px-3 rounded-xl bg-slate-100/90 hover:bg-slate-200/70 dark:bg-white/[0.05] dark:hover:bg-white/[0.09] border border-slate-200/70 dark:border-white/[0.07] text-xs text-slate-500 dark:text-slate-400 transition-colors cursor-pointer sm:min-w-[172px]"
              >
                <SearchIcon size={13} className="text-slate-400 shrink-0" />
                <span className="hidden sm:inline flex-1 text-left">搜索或执行命令…</span>
                <kbd className="kbd">⌘K</kbd>
              </button>

              {/* E2EE Status Pill */}
              <div
                className={`hidden md:inline-flex items-center gap-1.5 px-2.5 h-8 rounded-full text-[11px] font-medium border ${statusClass}`}
              >
                <span
                  className={`w-1.5 h-1.5 rounded-full bg-current ${
                    sessionStatus === "connected" ? "pulse-dot" : ""
                  }`}
                />
                {statusText}
              </div>

              {/* Theme Toggle */}
              <Button
                variant="ghost"
                size="icon-sm"
                aria-label="切换主题"
                title={resolvedTheme === "dark" ? "切换到亮色模式" : "切换到暗色模式"}
                onClick={toggleThemeMode}
              >
                {resolvedTheme === "dark" ? <SunIcon size={16} /> : <MoonIcon size={16} />}
              </Button>

              {/* Tablet/Mobile User & Menu */}
              <Link to="/profile" className="lg:hidden no-underline hidden sm:block" title="个人中心">
                <UserAvatar
                  name={user?.display_name || user?.email}
                  url={user?.avatar_url}
                  className="h-8 w-8 rounded-xl text-xs"
                />
              </Link>

              <button
                type="button"
                className="lg:hidden inline-flex items-center justify-center w-8 h-8 rounded-xl bg-slate-100 dark:bg-white/[0.06] text-slate-700 dark:text-slate-200 border border-slate-200/70 dark:border-white/10 cursor-pointer"
                onClick={() => setMobileOpen(true)}
                aria-label="打开菜单"
              >
                <MenuIcon size={16} />
              </button>
            </div>
          </header>

          {/* Main Content Outlet */}
          <main id="main-workspace" className="relative z-10 flex-1 min-w-0 pb-24 lg:pb-8">
            <div key={location.pathname} className="workspace-fill page-enter">
              <Outlet />
            </div>
          </main>
        </div>
      </div>

      {/* —— Mobile / Tablet Floating Bottom Dock —— */}
      <div className="lg:hidden fixed inset-x-3 bottom-3 z-40">
        <div className="bento-panel rounded-2xl p-1.5 grid grid-cols-5 gap-1 shadow-lg">
          {mobileDockItems.map((item) => {
            const active = isNavActive(location.pathname, item);
            return (
              <Link
                key={item.to}
                to={item.to}
                className={`flex flex-col items-center justify-center gap-1 h-12 rounded-xl no-underline text-[10px] font-medium transition-colors ${
                  active
                    ? "bg-indigo-50 text-indigo-700 dark:bg-indigo-500/20 dark:text-indigo-300 font-semibold"
                    : "text-slate-500 dark:text-slate-400"
                }`}
              >
                {item.icon}
                <span>{item.short}</span>
              </Link>
            );
          })}
          <button
            type="button"
            className="flex flex-col items-center justify-center gap-1 h-12 rounded-xl text-[10px] font-medium text-slate-500 dark:text-slate-400 cursor-pointer"
            onClick={() => setMobileOpen(true)}
          >
            <MenuIcon size={16} />
            <span>全部</span>
          </button>
        </div>
      </div>

      {/* —— Mobile Full Navigation Sheet —— */}
      {mobileOpen && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <div
            className="absolute inset-0 bg-slate-900/40 dark:bg-black/60 backdrop-blur-xs animate-overlay"
            onClick={() => setMobileOpen(false)}
          />
          <div className="absolute left-3 right-3 bottom-20 max-h-[75vh] overflow-y-auto bento-card rounded-3xl p-4 sm:p-5 animate-sheet shadow-2xl">
            <div className="flex items-center justify-between pb-3 mb-3 border-b border-slate-100 dark:border-white/[0.06]">
              <div className="flex items-center gap-2.5">
                <UserAvatar
                  name={user?.display_name || user?.email}
                  url={user?.avatar_url}
                  className="h-8 w-8 rounded-xl text-xs"
                />
                <div>
                  <div className="text-xs font-bold text-slate-900 dark:text-white">
                    {user?.display_name || user?.email || "用户"}
                  </div>
                  <div className="text-[10px] text-slate-400">{statusText}</div>
                </div>
              </div>
              <div className="flex items-center gap-1.5">
                <button
                  type="button"
                  onClick={handleLogout}
                  className="px-2.5 py-1.5 rounded-xl text-xs font-medium text-rose-600 dark:text-rose-400 bg-rose-50 dark:bg-rose-500/10"
                >
                  退出
                </button>
                <button
                  type="button"
                  className="p-1.5 rounded-xl bg-slate-100 dark:bg-white/[0.06] text-slate-600 dark:text-slate-300"
                  onClick={() => setMobileOpen(false)}
                >
                  <CloseIcon size={15} />
                </button>
              </div>
            </div>

            <div className="space-y-4">
              {groups.map((grp) => (
                <div key={grp}>
                  <div className="text-[10px] font-semibold uppercase tracking-wider text-slate-400 dark:text-slate-500 mb-2 px-1">
                    {GROUP_LABELS[grp]}
                  </div>
                  <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
                    {NAV.filter((n) => n.group === grp).map((item) => {
                      const active = isNavActive(location.pathname, item);
                      return (
                        <Link
                          key={item.to}
                          to={item.to}
                          onClick={() => setMobileOpen(false)}
                          className={`flex flex-col items-center justify-center gap-1.5 py-3 px-2 rounded-2xl no-underline text-xs font-medium border transition-all ${
                            active
                              ? "bg-indigo-50 text-indigo-700 border-indigo-200 dark:bg-indigo-500/15 dark:text-indigo-300 dark:border-indigo-500/30 font-semibold"
                              : "bg-slate-50/80 text-slate-700 border-slate-200/60 dark:bg-white/[0.03] dark:text-slate-300 dark:border-white/[0.06]"
                          }`}
                        >
                          <span className={active ? "text-indigo-600 dark:text-indigo-400" : "text-slate-400"}>
                            {item.icon}
                          </span>
                          <span className="truncate max-w-full">{item.short}</span>
                        </Link>
                      );
                    })}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* —— ⌘K Command Palette Modal —— */}
      {jumpOpen && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="全局命令与跳转面板"
          className="fixed inset-0 z-[60] flex items-start justify-center pt-[10vh] px-4"
        >
          <div
            className="absolute inset-0 bg-slate-900/45 dark:bg-black/65 backdrop-blur-xs animate-overlay"
            onClick={() => setJumpOpen(false)}
          />
          <div className="relative w-full max-w-xl bento-card rounded-2xl p-3 animate-scale-in shadow-2xl">
            <div className="flex items-center gap-2.5 px-3.5 h-11 rounded-xl bg-slate-100/80 dark:bg-white/[0.05] border border-slate-200/70 dark:border-white/10">
              <SearchIcon size={16} className="text-indigo-500 shrink-0" />
              <input
                autoFocus
                value={jumpQuery}
                onChange={(e) => setJumpQuery(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "ArrowDown") {
                    e.preventDefault();
                    setSelectedIndex((prev) =>
                      commandEntries.length ? (prev + 1) % commandEntries.length : 0,
                    );
                  } else if (e.key === "ArrowUp") {
                    e.preventDefault();
                    setSelectedIndex((prev) =>
                      commandEntries.length
                        ? (prev - 1 + commandEntries.length) % commandEntries.length
                        : 0,
                    );
                  } else if (e.key === "Enter" && commandEntries[selectedIndex]) {
                    e.preventDefault();
                    commandEntries[selectedIndex].run();
                    setJumpOpen(false);
                    setJumpQuery("");
                  }
                }}
                placeholder="输入模块名称、拼音关键字或快捷指令…"
                className="w-full bg-transparent text-sm text-slate-900 dark:text-slate-100 placeholder:text-slate-400 outline-none"
              />
              <kbd className="kbd">ESC</kbd>
            </div>

            <div className="mt-2.5 max-h-88 overflow-y-auto flex flex-col gap-3 pr-0.5">
              {actionItems.length > 0 && (
                <div>
                  <div className="px-2.5 pb-1 text-[10px] font-bold uppercase tracking-wider text-slate-400 dark:text-slate-500">
                    快捷指令 Actions
                  </div>
                  <div className="flex flex-col gap-0.5">
                    {actionItems.map((item) => {
                      const idx = commandEntries.indexOf(item);
                      const highlighted = idx === selectedIndex;
                      return (
                        <button
                          key={item.id}
                          type="button"
                          onMouseEnter={() => setSelectedIndex(idx)}
                          onClick={() => {
                            item.run();
                            setJumpOpen(false);
                            setJumpQuery("");
                          }}
                          className={`flex items-center gap-3 px-3 py-2 rounded-xl text-left transition-colors cursor-pointer ${
                            highlighted
                              ? "bg-indigo-50 text-indigo-700 dark:bg-indigo-500/18 dark:text-indigo-200"
                              : "text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-white/[0.04]"
                          }`}
                        >
                          <span
                            className={`w-7 h-7 rounded-lg flex items-center justify-center shrink-0 ${
                              highlighted
                                ? "bg-indigo-500/15 text-indigo-600 dark:text-indigo-300"
                                : "bg-slate-100 dark:bg-white/[0.05] text-slate-500 dark:text-slate-400"
                            }`}
                          >
                            {item.icon}
                          </span>
                          <span className="flex-1 text-xs sm:text-[13px] font-medium truncate">
                            {item.label}
                          </span>
                          <span className="text-[11px] text-slate-400 dark:text-slate-500">
                            {item.hint}
                          </span>
                          {item.shortcut && <kbd className="kbd">{item.shortcut}</kbd>}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              {navItems.length > 0 && (
                <div>
                  <div className="px-2.5 pb-1 text-[10px] font-bold uppercase tracking-wider text-slate-400 dark:text-slate-500">
                    模块导航 Pages
                  </div>
                  <div className="flex flex-col gap-0.5">
                    {navItems.map((item) => {
                      const idx = commandEntries.indexOf(item);
                      const highlighted = idx === selectedIndex;
                      return (
                        <button
                          key={item.id}
                          type="button"
                          onMouseEnter={() => setSelectedIndex(idx)}
                          onClick={() => {
                            item.run();
                            setJumpOpen(false);
                            setJumpQuery("");
                          }}
                          className={`flex items-center gap-3 px-3 py-2 rounded-xl text-left transition-colors cursor-pointer ${
                            highlighted
                              ? "bg-indigo-50 text-indigo-700 dark:bg-indigo-500/18 dark:text-indigo-200"
                              : "text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-white/[0.04]"
                          }`}
                        >
                          <span
                            className={`w-7 h-7 rounded-lg flex items-center justify-center shrink-0 ${
                              highlighted || item.active
                                ? "bg-indigo-500/15 text-indigo-600 dark:text-indigo-300"
                                : "bg-slate-100 dark:bg-white/[0.05] text-slate-500 dark:text-slate-400"
                            }`}
                          >
                            {item.icon}
                          </span>
                          <span className="flex-1 text-xs sm:text-[13px] font-medium truncate">
                            {item.label}
                            {item.active && (
                              <span className="ml-2 text-[10px] font-semibold px-1.5 py-0.5 rounded bg-indigo-500/15 text-indigo-600 dark:text-indigo-300">
                                当前页
                              </span>
                            )}
                          </span>
                          <span className="text-[11px] text-slate-400 dark:text-slate-500">
                            {item.hint}
                          </span>
                          {item.shortcut && (
                            <span className="text-[11px] font-mono text-slate-400 dark:text-slate-500 bg-slate-100 dark:bg-white/[0.05] px-1.5 py-0.5 rounded">
                              {item.shortcut}
                            </span>
                          )}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}

              {commandEntries.length === 0 && (
                <div className="px-3 py-10 text-center text-xs text-slate-400">
                  没有匹配的模块或命令
                </div>
              )}
            </div>

            <div className="mt-2.5 pt-2.5 border-t border-slate-100 dark:border-white/[0.06] px-2 flex items-center justify-between text-[11px] text-slate-400 dark:text-slate-500">
              <div className="flex items-center gap-3">
                <span className="inline-flex items-center gap-1">
                  <kbd className="kbd">↑</kbd>
                  <kbd className="kbd">↓</kbd> 选择
                </span>
                <span className="inline-flex items-center gap-1">
                  <kbd className="kbd">↵</kbd> 执行
                </span>
                <span className="inline-flex items-center gap-1">
                  <kbd className="kbd">⌘B</kbd> 侧栏
                </span>
              </div>
              <span>Bento Command Center</span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
