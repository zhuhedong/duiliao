import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../auth/AuthContext";
import {
  CheckBadgeIcon,
  GlobeIcon,
  MailIcon,
  ShieldIcon,
  UserIcon,
  DatabaseIcon,
  TrophyIcon,
  CompareIcon,
  ActivityIcon,
  LockIcon,
  ArrowRightIcon,
  StarIcon,
  HashIcon,
} from "../components/icons";

const STATUS_LABEL: Record<string, string> = {
  active: "正常运行",
  pending: "待验证",
  suspended: "已停用",
  banned: "已封禁",
  deleted: "已注销",
};

const ROLE_LABEL: Record<string, string> = {
  user: "普通用户",
  staff: "技术员工",
  admin: "超级管理员",
};

const SOURCE_LABEL: Record<string, string> = {
  web: "Web 网页端",
  ios: "iOS 客户端",
  android: "Android 客户端",
  api: "开放接口",
};

export function DashboardPage() {
  const { user } = useAuth();
  if (!user) return null;

  const stats: {
    icon: ReactNode;
    label: string;
    value: string;
    tone: string;
    desc: string;
  }[] = [
    {
      icon: <CheckBadgeIcon size={20} />,
      label: "账号状态",
      value: STATUS_LABEL[user.status] ?? user.status,
      tone: "from-emerald-500/15 to-teal-500/10 text-emerald-600 dark:text-emerald-300 border-emerald-400/30",
      desc: "鉴权正常 · 具备完整会话权限",
    },
    {
      icon: <UserIcon size={20} />,
      label: "账号角色",
      value: ROLE_LABEL[user.role] ?? user.role,
      tone: "from-violet-500/15 to-fuchsia-500/10 text-violet-600 dark:text-violet-300 border-violet-400/30",
      desc: user.role === "admin" ? "系统最高控制权限" : "标准业务查询权限",
    },
    {
      icon: <GlobeIcon size={20} />,
      label: "接入渠道",
      value: SOURCE_LABEL[user.registration_source] ?? user.registration_source,
      tone: "from-sky-500/15 to-blue-500/10 text-sky-600 dark:text-sky-300 border-sky-400/30",
      desc: "TLS 1.3 / WebSocket 接入",
    },
    {
      icon: <MailIcon size={20} />,
      label: "安全验证",
      value: user.email_verified ? "已双向验证" : "待邮箱验证",
      tone: user.email_verified
        ? "from-emerald-500/15 to-teal-500/10 text-emerald-600 dark:text-emerald-300 border-emerald-400/30"
        : "from-amber-500/15 to-orange-500/10 text-amber-600 dark:text-amber-300 border-amber-400/30",
      desc: user.email_verified ? "高安全级别账号" : "建议完成邮箱验证",
    },
  ];

  const quickActions = [
    {
      to: "/collector/sources",
      title: "数据源采集",
      desc: "配置与触发各数据源自动解析同步",
      icon: <DatabaseIcon size={22} />,
      tag: "CORE ETL",
      accent: "from-violet-500/15 to-purple-500/10 text-violet-600 dark:text-violet-300 border-violet-400/30",
    },
    {
      to: "/collector/draws",
      title: "开奖管理",
      desc: "全周期历史开奖数据检索与管理",
      icon: <TrophyIcon size={22} />,
      tag: "RECORDS",
      accent: "from-amber-500/15 to-orange-500/10 text-amber-600 dark:text-amber-300 border-amber-400/30",
    },
    {
      to: "/collector/consensus",
      title: "多源对照",
      desc: "智能交叉对比各来源一致性与异常差分",
      icon: <CompareIcon size={22} />,
      tag: "CONSENSUS",
      accent: "from-fuchsia-500/15 to-pink-500/10 text-fuchsia-600 dark:text-fuchsia-300 border-fuchsia-400/30",
    },
    {
      to: "/collector/monitor",
      title: "服务监控",
      desc: "节点吞吐率、抓取健康度与链路耗时",
      icon: <ActivityIcon size={22} />,
      tag: "HEALTH",
      accent: "from-emerald-500/15 to-teal-500/10 text-emerald-600 dark:text-emerald-300 border-emerald-400/30",
    },
    {
      to: "/collector/ratings",
      title: "源评级",
      desc: "多维度评估数据源稳定性及准确率",
      icon: <StarIcon size={22} />,
      tag: "RATING",
      accent: "from-sky-500/15 to-blue-500/10 text-sky-600 dark:text-sky-300 border-sky-400/30",
    },
    {
      to: "/collector/numbers",
      title: "号码资料",
      desc: "基础号码资料与属性分析检索",
      icon: <HashIcon size={22} />,
      tag: "DATA",
      accent: "from-fuchsia-500/15 to-violet-500/10 text-fuchsia-600 dark:text-fuchsia-300 border-fuchsia-400/30",
    },
  ];

  const lastLogin = user.last_login_at
    ? new Date(user.last_login_at).toLocaleString("zh-CN")
    : "首次建立会话";

  const securityFeatures = [
    { title: "1. 混合信封加密", desc: "RSA-4096 握手协商 + AES-256-GCM 动态信封，实现每次请求端侧加密。" },
    { title: "2. 防篡改与防重放", desc: "HMAC-SHA256 请求级签名校验，结合微秒级时间戳与一次性 Nonce 检查。" },
    { title: "3. Argon2id 凭证保护", desc: "抗 GPU / ASIC 硬件暴力破解的顶级口令哈希，绝不存储任何原始口令。" },
    { title: "4. 设备细粒度会话吊销", desc: "多端独立 Refresh Token，支持随时随地远程一键吊销指定客户端。" },
    { title: "5. 速率限制与暴力防御", desc: "基于令牌桶算法的接口级限流策略与异常 IP 临时静默阻断机制。" },
    { title: "6. 零知识架构原则", desc: "敏感业务与密钥仅掌握在终端节点手中，服务端不具备越权解密能力。" },
  ];

  return (
    <div className="grid grid-cols-1 xl:grid-cols-12 gap-4">
      <section className="xl:col-span-8 relative overflow-hidden rounded-[28px] glass-panel p-6 sm:p-8 min-h-[240px] flex flex-col justify-between">
        <div className="absolute -top-20 -right-16 w-72 h-72 bg-violet-500/20 rounded-full blur-3xl pointer-events-none" />
        <div className="relative">
          <div className="text-[11px] uppercase tracking-[0.18em] text-violet-600 dark:text-violet-300">今日工作台</div>
          <h2 className="mt-3 text-3xl sm:text-4xl font-bold tracking-tight text-slate-900 dark:text-white max-w-xl">
            {user.display_name ? (
              <>{user.display_name}，从这里进入采集流水线</>
            ) : (
              <>从这里进入采集流水线</>
            )}
          </h2>
          <p className="mt-3 max-w-lg text-sm text-slate-500 dark:text-slate-400">
            左侧图标轨切换业务。请求仍走端到端信封加密，页面只展示你有权限看到的结果。
          </p>
        </div>
        <div className="relative mt-8 flex flex-wrap gap-2">
          {quickActions.slice(0, 3).map((action) => (
            <Link
              key={action.to}
              to={action.to}
              className="inline-flex items-center gap-2 px-3 py-2 rounded-full glass-subtle no-underline text-sm text-slate-700 dark:text-slate-200 hover:border-violet-400/40"
            >
              {action.icon}
              {action.title}
            </Link>
          ))}
        </div>
      </section>

      <aside className="xl:col-span-4 flex flex-col gap-4">
        <div className="rounded-[28px] glass-card p-5 flex items-center gap-4">
          <div className="w-14 h-14 rounded-2xl brand-gradient text-white text-xl font-bold flex items-center justify-center shrink-0">
            {(user.display_name || user.email || "用").charAt(0).toUpperCase()}
          </div>
          <div className="min-w-0">
            <div className="font-semibold truncate">{user.display_name || user.email}</div>
            <div className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">{ROLE_LABEL[user.role] ?? user.role}</div>
            <div className="mt-2 inline-flex items-center gap-1.5 text-[11px] text-emerald-700 dark:text-emerald-300">
              <LockIcon size={12} />
              上次登录 {lastLogin}
            </div>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-3 flex-1">
          {stats.map((s) => (
            <div key={s.label} className="rounded-3xl glass-card p-4 flex flex-col justify-between">
              <div className={`w-8 h-8 rounded-xl bg-gradient-to-br ${s.tone} border flex items-center justify-center`}>
                {s.icon}
              </div>
              <div className="mt-3">
                <div className="text-[11px] text-slate-400">{s.label}</div>
                <div className="text-sm font-bold text-slate-900 dark:text-white mt-0.5">{s.value}</div>
                <div className="text-[10px] text-slate-400 dark:text-slate-500 mt-1 leading-snug">{s.desc}</div>
              </div>
            </div>
          ))}
        </div>
      </aside>

      <section className="xl:col-span-7 rounded-[28px] glass-card p-3 sm:p-4">
        <div className="px-2 py-2 text-sm font-semibold">业务入口</div>
        <div className="divide-y divide-slate-200/60 dark:divide-white/8">
          {quickActions.map((action) => (
            <Link
              key={action.to}
              to={action.to}
              className="flex items-center gap-4 px-2 py-3 no-underline text-inherit rounded-2xl hover:bg-violet-500/5"
            >
              <div className={`w-11 h-11 rounded-2xl bg-gradient-to-br ${action.accent} border flex items-center justify-center shrink-0`}>
                {action.icon}
              </div>
              <div className="min-w-0 flex-1">
                <div className="font-semibold text-sm">{action.title}</div>
                <div className="text-xs text-slate-500 dark:text-slate-400 truncate">{action.desc}</div>
              </div>
              <span className="hidden sm:inline text-[10px] font-mono text-slate-400">{action.tag}</span>
              <ArrowRightIcon size={16} className="text-slate-400" />
            </Link>
          ))}
        </div>
      </section>

      <section className="xl:col-span-5 rounded-[28px] glass-card p-5">
        <div className="flex items-center gap-2 mb-4">
          <ShieldIcon size={16} className="text-emerald-600 dark:text-emerald-300" />
          <h3 className="text-sm font-semibold">链路防护</h3>
        </div>
        <ol className="relative space-y-4 pl-4 border-l border-violet-400/30">
          {securityFeatures.map((f) => (
            <li key={f.title} className="relative">
              <span className="absolute -left-[21px] top-1.5 w-2 h-2 rounded-full brand-gradient" />
              <div className="text-xs font-semibold text-slate-800 dark:text-slate-100">{f.title}</div>
              <div className="text-[11px] text-slate-500 dark:text-slate-400 mt-0.5 leading-relaxed">{f.desc}</div>
            </li>
          ))}
        </ol>
      </section>
    </div>
  );
}
