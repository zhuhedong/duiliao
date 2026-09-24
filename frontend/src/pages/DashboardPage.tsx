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
    <div className="space-y-6">
      {/* 顶部玻璃全景横幅 */}
      <div className="relative overflow-hidden rounded-3xl glass-panel p-6 sm:p-8">
        {/* 内部氛围光 */}
        <div className="absolute -top-24 -right-24 w-80 h-80 bg-violet-500/20 dark:bg-violet-500/15 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute -bottom-24 left-1/4 w-72 h-72 bg-fuchsia-500/15 dark:bg-fuchsia-500/10 rounded-full blur-3xl pointer-events-none" />

        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="max-w-2xl">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-medium bg-violet-500/10 text-violet-700 dark:text-violet-300 border border-violet-400/40 dark:border-violet-400/25 backdrop-blur-md mb-3">
              <span className="w-1.5 h-1.5 rounded-full bg-violet-500 animate-pulse shadow-[0_0_6px_rgba(139,92,246,0.8)]" />
              <span>端到端加密安全工作台 · 已连接</span>
            </div>
            <h2 className="text-2xl sm:text-3xl font-bold tracking-tight text-slate-900 dark:text-white">
              {user.display_name ? (
                <>
                  {user.display_name}，<span className="text-gradient">欢迎回来</span>
                </>
              ) : (
                <>你好，<span className="text-gradient">欢迎回到对料工作台</span></>
              )}
            </h2>
            <p className="mt-2 text-sm text-slate-500 dark:text-slate-400 leading-relaxed">
              当前控制台所有 API 请求均受端到端混合加密与严格签名保护，数据在传输与存储全链路中保持安全密文。
            </p>
          </div>

          <div className="shrink-0 flex flex-col items-start md:items-end gap-1.5 text-xs text-slate-500 dark:text-slate-400 glass-subtle p-4 rounded-2xl">
            <div className="text-slate-800 dark:text-slate-200 font-medium flex items-center gap-1.5">
              <LockIcon size={14} className="text-emerald-500" />
              <span>会话安全凭证有效</span>
            </div>
            <span>上次登录：{lastLogin}</span>
            <span className="font-mono text-[11px] text-slate-400 dark:text-slate-500">UID: {user.id.slice(0, 12)}…</span>
          </div>
        </div>
      </div>

      {/* 核心指标统计卡片 */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map((s) => (
          <div
            key={s.label}
            className="p-5 rounded-3xl glass-card hover:-translate-y-0.5 hover:shadow-[0_16px_40px_-12px_rgba(139,92,246,0.25)] transition-all duration-200 flex flex-col justify-between"
          >
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-medium text-slate-500 dark:text-slate-400">{s.label}</span>
              <div className={`w-9 h-9 rounded-xl bg-gradient-to-br ${s.tone} border flex items-center justify-center backdrop-blur-sm`}>
                {s.icon}
              </div>
            </div>
            <div>
              <div className="text-xl font-bold text-slate-900 dark:text-white mb-1">
                {s.value}
              </div>
              <p className="text-xs text-slate-400 dark:text-slate-500 leading-tight">{s.desc}</p>
            </div>
          </div>
        ))}
      </div>

      {/* 业务快捷发射台 */}
      <div>
        <div className="flex items-center justify-between mb-3.5 px-1">
          <h3 className="text-base font-bold text-slate-900 dark:text-white tracking-tight">
            业务操作发射台
          </h3>
          <span className="text-xs text-slate-400 dark:text-slate-500">点击进入对应的业务管理流水线</span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {quickActions.map((action) => (
            <Link
              key={action.to}
              to={action.to}
              className="p-5 rounded-3xl glass-card hover:-translate-y-1 hover:shadow-[0_20px_44px_-14px_rgba(139,92,246,0.35)] hover:border-violet-400/40 dark:hover:border-violet-400/30 transition-all duration-200 group no-underline text-inherit flex flex-col justify-between relative overflow-hidden"
            >
              <div>
                <div className="flex items-center justify-between mb-3">
                  <div className={`w-10 h-10 rounded-xl bg-gradient-to-br ${action.accent} border flex items-center justify-center backdrop-blur-sm group-hover:scale-110 transition-transform`}>
                    {action.icon}
                  </div>
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded-md glass-subtle text-slate-500 dark:text-slate-400 font-semibold">
                    {action.tag}
                  </span>
                </div>
                <h4 className="text-base font-bold text-slate-900 dark:text-white group-hover:text-violet-600 dark:group-hover:text-violet-300 transition-colors">
                  {action.title}
                </h4>
                <p className="text-xs text-slate-500 dark:text-slate-400 mt-1 leading-relaxed">
                  {action.desc}
                </p>
              </div>

              <div className="mt-4 pt-3 border-t border-slate-200/50 dark:border-white/8 flex items-center justify-between text-xs font-medium text-slate-400 group-hover:text-violet-600 dark:group-hover:text-violet-300 transition-colors">
                <span>进入管理</span>
                <ArrowRightIcon size={14} className="group-hover:translate-x-1 transition-transform" />
              </div>
            </Link>
          ))}
        </div>
      </div>

      {/* 端到端加密架构安全图谱卡片 */}
      <div className="p-6 sm:p-7 rounded-3xl glass-card">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-gradient-to-br from-emerald-500/15 to-teal-500/10 text-emerald-600 dark:text-emerald-300 border border-emerald-400/30 flex items-center justify-center backdrop-blur-sm">
              <ShieldIcon size={18} />
            </div>
            <div>
              <h3 className="text-base font-bold text-slate-900 dark:text-white">
                六重全链路安全防御矩阵
              </h3>
              <span className="text-xs text-slate-400 dark:text-slate-500">已部署在当前的全部通信与数据存储链路</span>
            </div>
          </div>
          <span className="hidden sm:inline-block text-xs font-mono text-emerald-600 dark:text-emerald-300 font-semibold bg-emerald-500/10 px-2.5 py-1 rounded-full border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md">
            SECURE VERIFIED
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5 mt-4">
          {securityFeatures.map((f) => (
            <div
              key={f.title}
              className="p-3.5 rounded-2xl glass-subtle hover:border-violet-400/30 transition-colors"
            >
              <div className="text-xs font-bold text-slate-800 dark:text-slate-200 mb-1">
                {f.title}
              </div>
              <div className="text-xs text-slate-500 dark:text-slate-400 leading-relaxed">
                {f.desc}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
