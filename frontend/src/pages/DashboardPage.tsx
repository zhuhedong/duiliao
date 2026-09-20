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
    badgeVariant: "success" | "soft" | "primary";
    desc: string;
  }[] = [
    {
      icon: <CheckBadgeIcon size={20} />,
      label: "账号状态",
      value: STATUS_LABEL[user.status] ?? user.status,
      badgeVariant: "success",
      desc: "鉴权正常 · 具备完整会话权限",
    },
    {
      icon: <UserIcon size={20} />,
      label: "账号角色",
      value: ROLE_LABEL[user.role] ?? user.role,
      badgeVariant: "primary",
      desc: user.role === "admin" ? "系统最高控制权限" : "标准业务查询权限",
    },
    {
      icon: <GlobeIcon size={20} />,
      label: "接入渠道",
      value: SOURCE_LABEL[user.registration_source] ?? user.registration_source,
      badgeVariant: "soft",
      desc: "TLS 1.3 / WebSocket 接入",
    },
    {
      icon: <MailIcon size={20} />,
      label: "安全验证",
      value: user.email_verified ? "已双向验证" : "待邮箱验证",
      badgeVariant: user.email_verified ? "success" : "soft",
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
      accent: "from-cyan-500/10 to-blue-500/10 text-cyan-600 dark:text-cyan-400 border-cyan-500/20",
    },
    {
      to: "/collector/draws",
      title: "开奖管理",
      desc: "全周期历史开奖数据检索与管理",
      icon: <TrophyIcon size={22} />,
      tag: "RECORDS",
      accent: "from-amber-500/10 to-orange-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20",
    },
    {
      to: "/collector/consensus",
      title: "多源对照",
      desc: "智能交叉对比各来源一致性与异常差分",
      icon: <CompareIcon size={22} />,
      tag: "CONSENSUS",
      accent: "from-indigo-500/10 to-purple-500/10 text-indigo-600 dark:text-indigo-400 border-indigo-500/20",
    },
    {
      to: "/collector/monitor",
      title: "服务监控",
      desc: "节点吞吐率、抓取健康度与链路耗时",
      icon: <ActivityIcon size={22} />,
      tag: "HEALTH",
      accent: "from-emerald-500/10 to-teal-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20",
    },
    {
      to: "/collector/ratings",
      title: "源评级",
      desc: "多维度评估数据源稳定性及准确率",
      icon: <StarIcon size={22} />,
      tag: "RATING",
      accent: "from-pink-500/10 to-rose-500/10 text-pink-600 dark:text-pink-400 border-pink-500/20",
    },
    {
      to: "/collector/numbers",
      title: "号码资料",
      desc: "基础号码资料与属性分析检索",
      icon: <HashIcon size={22} />,
      tag: "DATA",
      accent: "from-fuchsia-500/10 to-violet-500/10 text-fuchsia-600 dark:text-fuchsia-400 border-fuchsia-500/20",
    },
  ];

  const lastLogin = user.last_login_at
    ? new Date(user.last_login_at).toLocaleString("zh-CN")
    : "首次建立会话";

  return (
    <div className="space-y-6">
      {/* 顶部全景工作台横幅 */}
      <div className="relative overflow-hidden rounded-3xl bg-gradient-to-r from-[#0b1220] via-[#0f172a] to-[#0a1120] text-white p-6 sm:p-8 border border-slate-800 shadow-xl">
        {/* 背景氛围辉光 */}
        <div className="absolute top-0 right-0 w-80 h-80 bg-cyan-500/10 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute bottom-0 left-1/3 w-60 h-60 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none" />

        <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="max-w-2xl">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-medium bg-cyan-500/15 text-cyan-300 border border-cyan-500/30 mb-3 backdrop-blur-sm">
              <span className="w-1.5 h-1.5 rounded-full bg-cyan-400 animate-pulse" />
              <span>端到端加密安全工作台 · 已连接</span>
            </div>
            <h2 className="text-2xl sm:text-3xl font-bold tracking-tight text-white">
              {user.display_name ? `${user.display_name}，欢迎回来` : "你好，欢迎回到对料工作台"}
            </h2>
            <p className="mt-2 text-sm text-slate-300 leading-relaxed">
              当前控制台所有 API 请求均受端到端混合加密与严格签名保护，数据在传输与存储全链路中保持安全密文。
            </p>
          </div>

          <div className="shrink-0 flex flex-col items-start md:items-end gap-1.5 text-xs text-slate-400 bg-white/[0.04] p-4 rounded-2xl border border-white/5 backdrop-blur-sm">
            <div className="text-slate-200 font-medium flex items-center gap-1.5">
              <LockIcon size={14} className="text-emerald-400" />
              <span>会话安全凭证有效</span>
            </div>
            <span>上次登录：{lastLogin}</span>
            <span className="font-mono text-[11px] text-slate-400">UID: {user.id.slice(0, 12)}…</span>
          </div>
        </div>
      </div>

      {/* 核心指标统计卡片 */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {stats.map((s) => (
          <div
            key={s.label}
            className="p-5 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 shadow-xs hover:shadow-md transition-all duration-200 flex flex-col justify-between"
          >
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-medium text-slate-500 dark:text-slate-400">{s.label}</span>
              <div className="w-9 h-9 rounded-xl bg-primary/10 text-primary flex items-center justify-center">
                {s.icon}
              </div>
            </div>
            <div>
              <div className="text-xl font-bold text-slate-900 dark:text-white mb-1">
                {s.value}
              </div>
              <p className="text-xs text-slate-400 leading-tight">{s.desc}</p>
            </div>
          </div>
        ))}
      </div>

      {/* 业务快捷发射台 */}
      <div>
        <div className="flex items-center justify-between mb-3.5">
          <h3 className="text-base font-bold text-slate-900 dark:text-white tracking-tight">
            业务操作发射台
          </h3>
          <span className="text-xs text-slate-400">点击进入对应的业务管理流水线</span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {quickActions.map((action) => (
            <Link
              key={action.to}
              to={action.to}
              className="p-5 rounded-2xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 hover:border-cyan-500/40 hover:shadow-lg transition-all duration-200 group no-underline text-inherit flex flex-col justify-between relative overflow-hidden"
            >
              <div>
                <div className="flex items-center justify-between mb-3">
                  <div className={`w-10 h-10 rounded-xl bg-gradient-to-br ${action.accent} border flex items-center justify-center group-hover:scale-105 transition-transform`}>
                    {action.icon}
                  </div>
                  <span className="text-[10px] font-mono px-2 py-0.5 rounded-md bg-slate-100 dark:bg-slate-800 text-slate-500 dark:text-slate-400 font-semibold">
                    {action.tag}
                  </span>
                </div>
                <h4 className="text-base font-bold text-slate-900 dark:text-white group-hover:text-primary transition-colors">
                  {action.title}
                </h4>
                <p className="text-xs text-slate-500 dark:text-slate-400 mt-1 leading-relaxed">
                  {action.desc}
                </p>
              </div>

              <div className="mt-4 pt-3 border-t border-slate-100 dark:border-slate-800/60 flex items-center justify-between text-xs font-medium text-slate-400 group-hover:text-primary transition-colors">
                <span>进入管理</span>
                <ArrowRightIcon size={14} className="group-hover:translate-x-1 transition-transform" />
              </div>
            </Link>
          ))}
        </div>
      </div>

      {/* 端到端加密架构安全图谱卡片 */}
      <div className="p-6 sm:p-7 rounded-3xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 shadow-xs">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 flex items-center justify-center">
              <ShieldIcon size={18} />
            </div>
            <div>
              <h3 className="text-base font-bold text-slate-900 dark:text-white">
                六重全链路安全防御矩阵
              </h3>
              <span className="text-xs text-slate-400">已部署在当前的全部通信与数据存储链路</span>
            </div>
          </div>
          <span className="hidden sm:inline-block text-xs font-mono text-emerald-600 dark:text-emerald-400 font-semibold bg-emerald-50 dark:bg-emerald-950/40 px-2.5 py-1 rounded-full border border-emerald-200/60 dark:border-emerald-800/60">
            SECURE VERIFIED
          </span>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3.5 mt-4">
          <div className="p-3.5 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-100 dark:border-slate-800">
            <div className="text-xs font-bold text-slate-800 dark:text-slate-200 mb-1">
              1. 混合信封加密
            </div>
            <div className="text-xs text-slate-500 dark:text-slate-400">
              RSA-4096 握手协商 + AES-256-GCM 动态信封，实现每次请求端侧加密。
            </div>
          </div>

          <div className="p-3.5 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-100 dark:border-slate-800">
            <div className="text-xs font-bold text-slate-800 dark:text-slate-200 mb-1">
              2. 防篡改与防重放
            </div>
            <div className="text-xs text-slate-500 dark:text-slate-400">
              HMAC-SHA256 请求级签名校验，结合微秒级时间戳与一次性 Nonce 检查。
            </div>
          </div>

          <div className="p-3.5 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-100 dark:border-slate-800">
            <div className="text-xs font-bold text-slate-800 dark:text-slate-200 mb-1">
              3. Argon2id 凭证保护
            </div>
            <div className="text-xs text-slate-500 dark:text-slate-400">
              抗 GPU / ASIC 硬件暴力破解的顶级口令哈希，绝不存储任何原始口令。
            </div>
          </div>

          <div className="p-3.5 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-100 dark:border-slate-800">
            <div className="text-xs font-bold text-slate-800 dark:text-slate-200 mb-1">
              4. 设备细粒度会话吊销
            </div>
            <div className="text-xs text-slate-500 dark:text-slate-400">
              多端独立 Refresh Token，支持随时随地远程一键吊销指定客户端。
            </div>
          </div>

          <div className="p-3.5 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-100 dark:border-slate-800">
            <div className="text-xs font-bold text-slate-800 dark:text-slate-200 mb-1">
              5. 速率限制与暴力防御
            </div>
            <div className="text-xs text-slate-500 dark:text-slate-400">
              基于令牌桶算法的接口级限流策略与异常 IP 临时静默阻断机制。
            </div>
          </div>

          <div className="p-3.5 rounded-xl bg-slate-50 dark:bg-slate-900/60 border border-slate-100 dark:border-slate-800">
            <div className="text-xs font-bold text-slate-800 dark:text-slate-200 mb-1">
              6. 零知识架构原则
            </div>
            <div className="text-xs text-slate-500 dark:text-slate-400">
              敏感业务与密钥仅掌握在终端节点手中，服务端不具备越权解密能力。
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

