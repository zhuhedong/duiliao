import { useEffect, useState, type FormEvent } from "react";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Field, FieldLabel } from "../components/ui/field";
import { Alert, AlertDescription } from "../components/ui/alert";
import { Spinner } from "../components/ui/spinner";
import { useAuth } from "../auth/AuthContext";
import { userApi, type SessionInfo } from "../lib/api";
import { ChevronDownIcon, DevicesIcon, ShieldIcon } from "../components/icons";
import { UserAvatar } from "../components/UserAvatar";
import { PageWorkspace, Select, StatusPill } from "./collector/shared";
import { USER_ROLE_LABEL, USER_STATUS_LABEL, userStatusTone } from "../lib/userLabels";

const PLATFORM_LABEL: Record<string, string> = { web: "网页端", ios: "iOS", android: "Android" };

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
  const pillVariant =
    statusTone === "success" ? "success" : statusTone === "warning" ? "warning" : "danger";

  return (
    <PageWorkspace summary="管理您的个人身份信息、时区语言偏好、登录密码以及多终端加密会话凭据。">
      <div className="bento-grid items-start">
        {/* Left: User Profile & Password Bento Card */}
        <div className="bento-span-5 bento-card rounded-2xl p-6">
          <div className="flex items-center justify-between gap-4 pb-5 border-b border-slate-100 dark:border-white/[0.06] flex-wrap">
            <div className="flex items-center gap-3.5">
              <UserAvatar
                name={displayName || user?.display_name || user?.email}
                url={avatarUrl || user?.avatar_url}
                className="h-14 w-14 shrink-0 rounded-2xl text-xl shadow-sm"
              />
              <div>
                <div className="flex items-center gap-2 flex-wrap">
                  <h2 className="text-lg font-bold text-slate-900 dark:text-white">
                    {user?.display_name || "用户"}
                  </h2>
                  <span className="text-[11px] px-2 py-0.5 rounded-md bg-indigo-50 text-indigo-700 dark:bg-indigo-500/15 dark:text-indigo-300 font-semibold border border-indigo-200/70 dark:border-indigo-500/25">
                    {USER_ROLE_LABEL[user?.role ?? ""] ?? user?.role ?? "普通用户"}
                  </span>
                </div>
                <p className="text-xs text-slate-400 dark:text-slate-500 mt-1 font-mono">
                  UID: {user?.id}
                </p>
              </div>
            </div>

            <StatusPill variant={pillVariant}>
              {USER_STATUS_LABEL[user?.status ?? ""] ?? user?.status ?? "正常"}
            </StatusPill>
          </div>

          <form onSubmit={onSave} className="mt-5 space-y-4">
            {savedMsg && (
              <Alert variant="success">
                <AlertDescription className="text-xs font-medium">{savedMsg}</AlertDescription>
              </Alert>
            )}

            <Field>
              <FieldLabel>绑定的电子邮箱</FieldLabel>
              <Input
                type="email"
                value={user?.email ?? ""}
                disabled
                inputProps={{ readOnly: true }}
                className="opacity-70 cursor-not-allowed"
              />
              <span className="text-[11px] text-slate-400 dark:text-slate-500">
                邮箱作为底层主身份标识，不可直接更改
              </span>
            </Field>

            <Field>
              <FieldLabel>显示昵称</FieldLabel>
              <Input
                type="text"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder="请输入您的显示昵称"
              />
            </Field>

            <Field>
              <FieldLabel>头像链接 (URL)</FieldLabel>
              <Input
                type="text"
                value={avatarUrl}
                onChange={(e) => setAvatarUrl(e.target.value)}
                placeholder="https://..."
              />
            </Field>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <Field>
                <FieldLabel>语言偏好</FieldLabel>
                <Select
                  value={locale}
                  onChange={setLocale}
                  className="w-full"
                  options={[
                    { value: "zh-CN", label: "简体中文 (zh-CN)" },
                    { value: "en-US", label: "English (en-US)" },
                  ]}
                />
              </Field>

              <Field>
                <FieldLabel>时区设置</FieldLabel>
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
            </div>

            <div className="pt-1">
              <Button type="submit" disabled={saving} size="md">
                {saving ? (
                  <>
                    <Spinner className="size-3.5" currentColor />
                    <span>保存中...</span>
                  </>
                ) : (
                  "保存基本资料"
                )}
              </Button>
            </div>
          </form>

          {/* 修改密码折叠区 */}
          <div className="mt-6 pt-5 border-t border-slate-100 dark:border-white/[0.06]">
            <button
              type="button"
              className="flex items-center justify-between w-full text-sm font-semibold text-slate-700 dark:text-slate-200 hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors cursor-pointer"
              onClick={() => setShowPasswordForm(!showPasswordForm)}
            >
              <span className="flex items-center gap-2">
                <ShieldIcon size={16} className="text-indigo-600 dark:text-indigo-400" />
                <span>修改登录密码</span>
              </span>
              <ChevronDownIcon
                size={15}
                className={`transition-transform ${showPasswordForm ? "rotate-180" : ""}`}
              />
            </button>

            {showPasswordForm && (
              <form
                onSubmit={onPasswordSubmit}
                className="mt-4 space-y-3.5 p-4 rounded-2xl bg-slate-50/80 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/[0.06]"
              >
                {passwordError && (
                  <Alert variant="error">
                    <AlertDescription className="text-xs font-medium">
                      {passwordError}
                    </AlertDescription>
                  </Alert>
                )}
                {passwordSuccess && (
                  <Alert variant="success">
                    <AlertDescription className="text-xs font-medium">
                      {passwordSuccess}
                    </AlertDescription>
                  </Alert>
                )}

                <Field>
                  <FieldLabel>当前密码</FieldLabel>
                  <Input
                    type={showCurrent ? "text" : "password"}
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    placeholder="请输入当前密码"
                    required
                    endSlot={
                      <button
                        type="button"
                        onClick={() => setShowCurrent(!showCurrent)}
                        className="text-xs text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 cursor-pointer"
                      >
                        {showCurrent ? "隐藏" : "显示"}
                      </button>
                    }
                  />
                </Field>

                <Field>
                  <FieldLabel>新密码</FieldLabel>
                  <Input
                    type={showNew ? "text" : "password"}
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="至少 8 位，含字母与数字"
                    required
                    endSlot={
                      <button
                        type="button"
                        onClick={() => setShowNew(!showNew)}
                        className="text-xs text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 cursor-pointer"
                      >
                        {showNew ? "隐藏" : "显示"}
                      </button>
                    }
                  />
                </Field>

                <Field>
                  <FieldLabel>确认新密码</FieldLabel>
                  <Input
                    type={showConfirm ? "text" : "password"}
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    placeholder="请再次输入新密码"
                    required
                    endSlot={
                      <button
                        type="button"
                        onClick={() => setShowConfirm(!showConfirm)}
                        className="text-xs text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 cursor-pointer"
                      >
                        {showConfirm ? "隐藏" : "显示"}
                      </button>
                    }
                  />
                </Field>

                <Button type="submit" disabled={passwordSaving} size="sm">
                  {passwordSaving ? (
                    <>
                      <Spinner className="size-3.5" currentColor />
                      <span>提交中...</span>
                    </>
                  ) : (
                    "确认修改密码"
                  )}
                </Button>
              </form>
            )}
          </div>
        </div>

        {/* Right: Active Encrypted Sessions Bento Card */}
        <div className="bento-span-7 bento-card rounded-2xl p-6">
          <div className="pb-4 mb-4 border-b border-slate-100 dark:border-white/[0.06]">
            <div className="flex items-center gap-2">
              <DevicesIcon size={17} className="text-indigo-600 dark:text-indigo-400" />
              <h3 className="text-[15px] font-semibold text-slate-900 dark:text-white tracking-tight">
                登录设备与加密会话管控
              </h3>
            </div>
            <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">
              每次登录均在独立节点建立端到端加密握手，可随时单键吊销指定终端的访问权限。
            </p>
          </div>

          {loadingSessions ? (
            <div className="py-16 flex flex-col items-center justify-center gap-3 text-slate-400 dark:text-slate-500 text-xs">
              <Spinner className="size-5" />
              <span>正在同步设备安全凭据...</span>
            </div>
          ) : sessions && sessions.length > 0 ? (
            <div className="space-y-2.5">
              {sessions.map((s) => (
                <div
                  key={s.id}
                  className="flex flex-col sm:flex-row sm:items-center justify-between gap-3.5 p-4 rounded-xl bg-slate-50/80 dark:bg-white/[0.025] border border-slate-200/60 dark:border-white/[0.06] hover:border-indigo-500/30 transition-colors"
                >
                  <div className="flex items-start gap-3">
                    <div className="w-10 h-10 rounded-xl bg-indigo-50 text-indigo-600 dark:bg-indigo-500/15 dark:text-indigo-400 border border-indigo-200/60 dark:border-indigo-500/25 flex items-center justify-center shrink-0">
                      <DevicesIcon size={18} />
                    </div>
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-sm font-semibold text-slate-900 dark:text-white">
                          {s.device_name || "未知设备终端"}
                        </span>
                        {s.platform && (
                          <span className="text-[11px] px-2 py-0.5 rounded-md bg-slate-200/70 dark:bg-white/10 text-slate-600 dark:text-slate-300 font-medium">
                            {PLATFORM_LABEL[s.platform] ?? s.platform}
                          </span>
                        )}
                        {s.current && (
                          <span className="text-[11px] px-2 py-0.5 rounded-md bg-emerald-50 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300 font-semibold border border-emerald-200/80 dark:border-emerald-500/25">
                            当前设备
                          </span>
                        )}
                      </div>
                      <div className="text-xs text-slate-500 dark:text-slate-400 mt-1 flex items-center gap-2 flex-wrap font-mono">
                        <span>IP: {s.ip_address || "127.0.0.1"}</span>
                        <span>·</span>
                        <span>
                          活跃于{" "}
                          {s.last_used_at
                            ? new Date(s.last_used_at).toLocaleString("zh-CN")
                            : "刚刚"}
                        </span>
                      </div>
                    </div>
                  </div>

                  <div className="self-end sm:self-center shrink-0">
                    <Button
                      variant="outline"
                      size="sm"
                      className="text-rose-600 dark:text-rose-400 border-rose-200 dark:border-rose-500/25 hover:bg-rose-50 dark:hover:bg-rose-500/10"
                      onClick={() => revoke(s.id)}
                    >
                      吊销会话
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center py-12 text-xs text-slate-400 dark:text-slate-500">
              暂无活跃会话记录。
            </div>
          )}
        </div>
      </div>
    </PageWorkspace>
  );
}
