import { useEffect, useState, type FormEvent } from "react";
import { Button } from "@appica/ui-react/button";
import { Input } from "@appica/ui-react/input";
import { Field, FieldLabel } from "@appica/ui-react/field";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { Spinner } from "@appica/ui-react/spinner";
import { useAuth } from "../auth/AuthContext";
import { userApi, type SessionInfo } from "../lib/api";
import { ChevronDownIcon, DevicesIcon } from "../components/icons";
import { UserAvatar } from "../components/UserAvatar";
import { Select } from "./collector/shared";
import { USER_ROLE_LABEL, USER_STATUS_LABEL, userStatusTone } from "../lib/userLabels";

const PLATFORM_LABEL: Record<string, string> = { web: "网页", ios: "iOS", android: "安卓" };

export function ProfilePage() {
  const { user, refreshUser } = useAuth();
  const [displayName, setDisplayName] = useState(user?.display_name ?? "");
  const [avatarUrl, setAvatarUrl] = useState(user?.avatar_url ?? "");
  const [locale, setLocale] = useState(user?.locale ?? "zh-CN");
  const [timezone, setTimezone] = useState(user?.timezone ?? "Asia/Shanghai");
  const [savedMsg, setSavedMsg] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const [showPasswordForm, setShowPasswordForm] = useState(false);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showCurrent, setShowCurrent] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [passwordError, setPasswordError] = useState<string | null>(null);
  const [passwordSuccess, setPasswordSuccess] = useState<string | null>(null);
  const [passwordSaving, setPasswordSaving] = useState(false);

  const [sessions, setSessions] = useState<SessionInfo[] | null>(null);
  const [loadingSessions, setLoadingSessions] = useState(true);

  const loadSessions = async () => {
    setLoadingSessions(true);
    try {
      setSessions(await userApi.sessions());
    } finally {
      setLoadingSessions(false);
    }
  };

  useEffect(() => {
    void loadSessions();
  }, []);

  const onSave = async (e: FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setSavedMsg(null);
    try {
      await userApi.update({
        display_name: displayName.trim() || null,
        avatar_url: avatarUrl.trim() || null,
        locale: locale.trim() || undefined,
        timezone: timezone.trim() || undefined,
      });
      await refreshUser();
      setSavedMsg("个人资料已成功更新");
    } finally {
      setSaving(false);
    }
  };

  const onPasswordSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setPasswordError(null);
    setPasswordSuccess(null);
    if (newPassword.length < 8) {
      setPasswordError("新密码长度至少为 8 位");
      return;
    }
    if (!/[A-Za-z]/.test(newPassword) || !/[0-9]/.test(newPassword)) {
      setPasswordError("新密码必须包含字母和数字");
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordError("两次输入的新密码不一致");
      return;
    }
    setPasswordSaving(true);
    try {
      await userApi.changePassword(currentPassword, newPassword);
      setPasswordSuccess("密码修改成功");
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
    } catch (err) {
      setPasswordError(err instanceof Error ? err.message : "修改密码失败");
    } finally {
      setPasswordSaving(false);
    }
  };

  const revoke = async (id: string) => {
    await userApi.revokeSession(id);
    await loadSessions();
  };

  const statusTone = userStatusTone(user?.status ?? "");
  const statusClass =
    statusTone === "success"
      ? "text-emerald-600 dark:text-emerald-300"
      : statusTone === "warning"
        ? "text-amber-600 dark:text-amber-300"
        : "text-rose-600 dark:text-rose-300";

  return (
    <div className="workspace-fill w-full grid grid-cols-1 xl:grid-cols-12 gap-3 items-stretch content-start">
      {/* 用户概览与基本资料卡片 */}
      <div className="xl:col-span-5 xl:sticky xl:top-[5rem] xl:self-start p-6 sm:p-8 rounded-3xl glass-card">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-6 border-b border-slate-200/50 dark:border-white/8">
          <div className="flex items-center gap-4">
            <UserAvatar
              name={displayName || user?.display_name || user?.email}
              url={avatarUrl || user?.avatar_url}
              className="h-14 w-14 shrink-0 rounded-2xl text-2xl shadow-[0_8px_24px_-6px_rgba(139,92,246,0.5)]"
            />
            <div>
              <div className="flex items-center gap-2.5">
                <h2 className="text-xl font-bold text-slate-900 dark:text-white">
                  {user?.display_name || "用户"}
                </h2>
                <span className="text-xs px-2.5 py-0.5 rounded-full bg-violet-500/10 text-violet-700 dark:text-violet-300 font-semibold border border-violet-400/40 dark:border-violet-400/25 backdrop-blur-md">
                  {USER_ROLE_LABEL[user?.role ?? ""] ?? user?.role ?? "普通用户"}
                </span>
              </div>
              <p className="text-xs text-slate-400 dark:text-slate-500 mt-1 font-mono">
                UID: {user?.id}
              </p>
            </div>
          </div>

          <div className="text-xs text-slate-500 dark:text-slate-400 font-mono flex items-center gap-1.5 self-start sm:self-auto glass-subtle py-1.5 px-3 rounded-xl">
            <span>账号状态：</span>
            <span className={`${statusClass} font-semibold`}>
              {USER_STATUS_LABEL[user?.status ?? ""] ?? user?.status ?? "未知"}
            </span>
          </div>
        </div>

        <form onSubmit={onSave} className="mt-6 space-y-4">
          {savedMsg && (
            <Alert variant="success" className="rounded-xl border border-emerald-400/40 dark:border-emerald-400/25 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 py-2.5 px-3 backdrop-blur-md">
              <AlertDescription className="text-xs leading-relaxed font-medium">{savedMsg}</AlertDescription>
            </Alert>
          )}

          <Field className="space-y-1">
            <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
              绑定的电子邮箱
            </FieldLabel>
            <Input
              type="email"
              value={user?.email ?? ""}
              disabled
              inputProps={{ readOnly: true }}
              inputSize="md"
              className="rounded-xl glass-input text-slate-500 dark:text-slate-400 cursor-not-allowed"
            />
            <span className="text-[11px] text-slate-400 dark:text-slate-500 block mt-0.5">
              邮箱作为底层主身份标识，不可直接更改
            </span>
          </Field>

          <Field className="space-y-1">
            <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
              显示昵称
            </FieldLabel>
            <Input
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder="请输入您的显示昵称"
              inputSize="md"
              className="rounded-xl glass-input text-slate-800 dark:text-slate-200"
            />
          </Field>

          <Field className="space-y-1">
            <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
              头像链接
            </FieldLabel>
            <Input
              type="text"
              value={avatarUrl}
              onChange={(e) => setAvatarUrl(e.target.value)}
              placeholder="请输入头像 URL"
              inputSize="md"
              className="rounded-xl glass-input text-slate-800 dark:text-slate-200"
            />
          </Field>

          <Field className="space-y-1">
            <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
              语言偏好 (Locale)
            </FieldLabel>
            <Select
              value={locale}
              onChange={setLocale}
              className="w-full"
              options={[
                { value: "zh-CN", label: "zh-CN" },
                { value: "en-US", label: "en-US" },
              ]}
            />
          </Field>

          <Field className="space-y-1">
            <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
              时区 (Timezone)
            </FieldLabel>
            <Select
              value={timezone}
              onChange={setTimezone}
              className="w-full"
              options={[
                { value: "Asia/Shanghai", label: "Asia/Shanghai" },
                { value: "Asia/Hong_Kong", label: "Asia/Hong_Kong" },
                { value: "UTC", label: "UTC" },
                { value: "America/New_York", label: "America/New_York" },
                { value: "Europe/London", label: "Europe/London" },
              ]}
            />
          </Field>

          <Button
            type="submit"
            disabled={saving}
            size="md"
            className="glow-button border-0 rounded-xl px-5 font-semibold text-xs tracking-wide cursor-pointer"
          >
            {saving ? (
              <>
                <Spinner className="size-3.5" currentColor />
                <span>保存中...</span>
              </>
            ) : (
              "保存修改"
            )}
          </Button>
        </form>

        {/* 修改密码折叠面板 */}
        <div className="mt-8 border-t border-slate-200/50 dark:border-white/8 pt-6">
          <button
            type="button"
            className="flex items-center gap-2 text-sm font-semibold text-slate-700 dark:text-slate-300 hover:text-violet-600 dark:hover:text-violet-300 transition-colors cursor-pointer"
            onClick={() => setShowPasswordForm(!showPasswordForm)}
          >
            <span>修改密码</span>
            <ChevronDownIcon size={14} className={showPasswordForm ? "rotate-180" : ""} />
          </button>
          
          {showPasswordForm && (
            <form onSubmit={onPasswordSubmit} className="mt-4 space-y-4 max-w-md p-5 rounded-2xl glass-subtle">
              {passwordError && (
                <Alert variant="error" className="rounded-xl border border-rose-400/40 dark:border-rose-400/25 bg-rose-500/10 text-rose-700 dark:text-rose-300 py-2.5 px-3 backdrop-blur-md">
                  <AlertDescription className="text-xs leading-relaxed font-medium">{passwordError}</AlertDescription>
                </Alert>
              )}
              {passwordSuccess && (
                <Alert variant="success" className="rounded-xl border border-emerald-400/40 dark:border-emerald-400/25 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 py-2.5 px-3 backdrop-blur-md">
                  <AlertDescription className="text-xs leading-relaxed font-medium">{passwordSuccess}</AlertDescription>
                </Alert>
              )}

              <Field className="space-y-1">
                <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
                  当前密码
                </FieldLabel>
                <div className="relative">
                  <Input
                    type={showCurrent ? "text" : "password"}
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    placeholder="请输入当前密码"
                    inputSize="md"
                    className="rounded-xl glass-input pr-10 text-slate-800 dark:text-slate-200"
                    required
                  />
                  <button type="button" onClick={() => setShowCurrent(!showCurrent)} className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-200 cursor-pointer">
                    {showCurrent ? "隐藏" : "显示"}
                  </button>
                </div>
              </Field>

              <Field className="space-y-1">
                <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
                  新密码
                </FieldLabel>
                <div className="relative">
                  <Input
                    type={showNew ? "text" : "password"}
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="请输入新密码"
                    inputSize="md"
                    className="rounded-xl glass-input pr-10 text-slate-800 dark:text-slate-200"
                    required
                  />
                  <button type="button" onClick={() => setShowNew(!showNew)} className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-200 cursor-pointer">
                    {showNew ? "隐藏" : "显示"}
                  </button>
                </div>
              </Field>

              <Field className="space-y-1">
                <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
                  确认新密码
                </FieldLabel>
                <div className="relative">
                  <Input
                    type={showConfirm ? "text" : "password"}
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="请再次输入新密码"
                    inputSize="md"
                    className="rounded-xl glass-input pr-10 text-slate-800 dark:text-slate-200"
                    required
                  />
                  <button type="button" onClick={() => setShowConfirm(!showConfirm)} className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-200 cursor-pointer">
                    {showConfirm ? "隐藏" : "显示"}
                  </button>
                </div>
              </Field>

              <Button
                type="submit"
                disabled={passwordSaving}
                size="md"
                className="glow-button border-0 rounded-xl px-5 font-semibold text-xs tracking-wide cursor-pointer"
              >
                {passwordSaving ? (
                  <>
                    <Spinner className="size-3.5" currentColor />
                    <span>提交中...</span>
                  </>
                ) : (
                  "确认修改"
                )}
              </Button>
            </form>
          )}
        </div>
      </div>

      {/* 登录设备与安全会话管控 */}
      <div className="xl:col-span-7 p-6 sm:p-8 rounded-3xl glass-card">
        <div className="mb-6">
          <div className="flex items-center gap-2 mb-1">
            <DevicesIcon size={18} className="text-violet-600 dark:text-violet-300" />
            <h3 className="text-base font-bold text-slate-900 dark:text-white">
              登录设备与加密会话管控
            </h3>
          </div>
          <p className="text-xs text-slate-500 dark:text-slate-400">
            基于分布式架构设计，每次登录均在独立节点建立加密握手，可随时单键撤销指定设备权限。
          </p>
        </div>

        {loadingSessions ? (
          <div className="py-12 flex flex-col items-center justify-center gap-3 text-slate-400 dark:text-slate-500 text-xs">
            <Spinner className="size-5" />
            <span>正在同步设备安全凭据...</span>
          </div>
        ) : sessions && sessions.length > 0 ? (
          <div className="space-y-3">
            {sessions.map((s) => (
              <div
                key={s.id}
                className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-4 rounded-2xl glass-subtle hover:border-violet-400/40 dark:hover:border-violet-400/30 transition-colors"
              >
                <div className="flex items-start gap-3.5">
                  <div className="w-10 h-10 rounded-xl bg-violet-500/10 text-violet-600 dark:text-violet-300 border border-violet-400/30 flex items-center justify-center shrink-0 backdrop-blur-sm">
                    <DevicesIcon size={20} />
                  </div>
                  <div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm font-bold text-slate-900 dark:text-white">
                        {s.device_name || "未知设备终端"}
                      </span>
                      {s.platform && (
                        <span className="text-[11px] px-2 py-0.5 rounded-md bg-slate-500/10 text-slate-600 dark:text-slate-300 font-medium border border-slate-400/30 dark:border-slate-400/20 backdrop-blur-md">
                          {PLATFORM_LABEL[s.platform] ?? s.platform}
                        </span>
                      )}
                      {s.current && (
                        <span className="text-[11px] px-2 py-0.5 rounded-md bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 font-semibold border border-emerald-400/40 dark:border-emerald-400/25 backdrop-blur-md">
                          当前会话
                        </span>
                      )}
                    </div>
                    <div className="text-xs text-slate-400 dark:text-slate-500 mt-1 flex items-center gap-2 flex-wrap">
                      <span>IP: {s.ip_address || "内网回环地址"}</span>
                      <span>·</span>
                      <span>
                        最近活跃：{s.last_used_at ? new Date(s.last_used_at).toLocaleString("zh-CN") : "刚刚"}
                      </span>
                    </div>
                  </div>
                </div>

                <div className="self-end sm:self-center shrink-0">
                  <Button
                    variant="outline"
                    size="sm"
                    className="rounded-xl text-xs text-rose-700 dark:text-rose-300 bg-rose-500/10 hover:bg-rose-500/20 border-rose-400/40 dark:border-rose-400/25 backdrop-blur-md cursor-pointer"
                    onClick={() => revoke(s.id)}
                  >
                    吊销凭据
                  </Button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-center py-8 text-xs text-slate-400 dark:text-slate-500">
            暂无活跃会话记录。
          </div>
        )}
      </div>
    </div>
  );
}

