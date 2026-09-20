import { useEffect, useState, type FormEvent } from "react";
import { Button } from "@appica/ui-react/button";
import { Input } from "@appica/ui-react/input";
import { Field, FieldLabel } from "@appica/ui-react/field";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { Spinner } from "@appica/ui-react/spinner";
import { useAuth } from "../auth/AuthContext";
import { userApi, type SessionInfo } from "../lib/api";
import { DevicesIcon } from "../components/icons";

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

  const initial = (user?.display_name || user?.email || "用")?.charAt(0).toUpperCase();

  return (
    <div className="space-y-6 max-w-4xl">
      {/* 用户概览与基本资料卡片 */}
      <div className="p-6 sm:p-8 rounded-3xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 shadow-xs">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-6 border-b border-slate-100 dark:border-slate-800/80">
          <div className="flex items-center gap-4">
            <div className="w-14 h-14 rounded-2xl brand-gradient flex items-center justify-center text-white font-bold text-2xl shadow-md shadow-cyan-500/20">
              {initial}
            </div>
            <div>
              <div className="flex items-center gap-2.5">
                <h2 className="text-xl font-bold text-slate-900 dark:text-white">
                  {user?.display_name || "用户"}
                </h2>
                <span className="text-xs px-2.5 py-0.5 rounded-full bg-cyan-500/10 text-cyan-600 dark:text-cyan-400 font-semibold border border-cyan-500/20">
                  {user?.role === "admin" ? "超级管理员" : "标准用户"}
                </span>
              </div>
              <p className="text-xs text-slate-400 mt-1 font-mono">
                UID: {user?.id}
              </p>
            </div>
          </div>

          <div className="text-xs text-slate-400 font-mono flex items-center gap-1.5 self-start sm:self-auto bg-slate-50 dark:bg-slate-900/60 py-1.5 px-3 rounded-xl border border-slate-100 dark:border-slate-800">
            <span>账号状态：</span>
            <span className="text-emerald-500 font-semibold">正常运行中</span>
          </div>
        </div>

        <form onSubmit={onSave} className="mt-6 space-y-4 max-w-md">
          {savedMsg && (
            <Alert variant="success" className="rounded-xl border border-emerald-200 bg-emerald-50/80 text-emerald-800 py-2.5 px-3">
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
              className="rounded-xl bg-slate-50 dark:bg-slate-900/40 text-slate-500 cursor-not-allowed"
            />
            <span className="text-[11px] text-slate-400 block mt-0.5">
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
              className="rounded-xl"
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
              className="rounded-xl"
            />
          </Field>

          <Field className="space-y-1">
            <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
              语言偏好 (Locale)
            </FieldLabel>
            <select
              value={locale}
              onChange={(e) => setLocale(e.target.value)}
              className="w-full h-10 px-3 text-sm rounded-xl border border-slate-200 dark:border-slate-800 bg-transparent text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-primary/20"
            >
              <option value="zh-CN">zh-CN</option>
              <option value="en-US">en-US</option>
            </select>
          </Field>

          <Field className="space-y-1">
            <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">
              时区 (Timezone)
            </FieldLabel>
            <select
              value={timezone}
              onChange={(e) => setTimezone(e.target.value)}
              className="w-full h-10 px-3 text-sm rounded-xl border border-slate-200 dark:border-slate-800 bg-transparent text-slate-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-primary/20"
            >
              <option value="Asia/Shanghai">Asia/Shanghai</option>
              <option value="Asia/Hong_Kong">Asia/Hong_Kong</option>
              <option value="UTC">UTC</option>
              <option value="America/New_York">America/New_York</option>
              <option value="Europe/London">Europe/London</option>
            </select>
          </Field>

          <Button
            type="submit"
            disabled={saving}
            size="md"
            className="rounded-xl px-5 font-semibold text-xs tracking-wide shadow-sm hover:shadow-md cursor-pointer"
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
        <div className="mt-8 border-t border-slate-100 dark:border-slate-800/80 pt-6">
          <button
            type="button"
            className="flex items-center gap-2 text-sm font-semibold text-slate-700 dark:text-slate-300 hover:text-primary transition-colors cursor-pointer"
            onClick={() => setShowPasswordForm(!showPasswordForm)}
          >
            <span>修改密码</span>
            <span className="text-xs">{showPasswordForm ? "▲" : "▼"}</span>
          </button>
          
          {showPasswordForm && (
            <form onSubmit={onPasswordSubmit} className="mt-4 space-y-4 max-w-md">
              {passwordError && (
                <Alert variant="error" className="rounded-xl py-2.5 px-3">
                  <AlertDescription className="text-xs leading-relaxed font-medium">{passwordError}</AlertDescription>
                </Alert>
              )}
              {passwordSuccess && (
                <Alert variant="success" className="rounded-xl border border-emerald-200 bg-emerald-50/80 text-emerald-800 py-2.5 px-3">
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
                    className="rounded-xl pr-10"
                    required
                  />
                  <button type="button" onClick={() => setShowCurrent(!showCurrent)} className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-slate-400">
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
                    className="rounded-xl pr-10"
                    required
                  />
                  <button type="button" onClick={() => setShowNew(!showNew)} className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-slate-400">
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
                    className="rounded-xl pr-10"
                    required
                  />
                  <button type="button" onClick={() => setShowConfirm(!showConfirm)} className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-slate-400">
                    {showConfirm ? "隐藏" : "显示"}
                  </button>
                </div>
              </Field>

              <Button
                type="submit"
                disabled={passwordSaving}
                size="md"
                className="rounded-xl px-5 font-semibold text-xs tracking-wide shadow-sm hover:shadow-md cursor-pointer"
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
      <div className="p-6 sm:p-8 rounded-3xl bg-white dark:bg-[#0c1220] border border-slate-200/80 dark:border-slate-800/80 shadow-xs">
        <div className="mb-6">
          <div className="flex items-center gap-2 mb-1">
            <DevicesIcon size={18} className="text-primary" />
            <h3 className="text-base font-bold text-slate-900 dark:text-white">
              登录设备与加密会话管控
            </h3>
          </div>
          <p className="text-xs text-slate-500 dark:text-slate-400">
            基于分布式架构设计，每次登录均在独立节点建立加密握手，可随时单键撤销指定设备权限。
          </p>
        </div>

        {loadingSessions ? (
          <div className="py-12 flex flex-col items-center justify-center gap-3 text-slate-400 text-xs">
            <Spinner className="size-5" />
            <span>正在同步设备安全凭据...</span>
          </div>
        ) : sessions && sessions.length > 0 ? (
          <div className="space-y-3">
            {sessions.map((s) => (
              <div
                key={s.id}
                className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-4 rounded-2xl border border-slate-100 dark:border-slate-800 bg-slate-50/60 dark:bg-slate-900/40 hover:border-slate-200 dark:hover:border-slate-700 transition-colors"
              >
                <div className="flex items-start gap-3.5">
                  <div className="w-10 h-10 rounded-xl bg-slate-200/60 dark:bg-slate-800 flex items-center justify-center text-slate-600 dark:text-slate-300 shrink-0">
                    <DevicesIcon size={20} />
                  </div>
                  <div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm font-bold text-slate-900 dark:text-white">
                        {s.device_name || "未知设备终端"}
                      </span>
                      {s.platform && (
                        <span className="text-[11px] px-2 py-0.5 rounded-md bg-slate-200/80 dark:bg-slate-800 text-slate-600 dark:text-slate-300 font-medium">
                          {PLATFORM_LABEL[s.platform] ?? s.platform}
                        </span>
                      )}
                      {s.current && (
                        <span className="text-[11px] px-2 py-0.5 rounded-md bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 font-semibold border border-emerald-500/30">
                          当前会话
                        </span>
                      )}
                    </div>
                    <div className="text-xs text-slate-400 mt-1 flex items-center gap-2 flex-wrap">
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
                    className="rounded-xl text-xs text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-950/40 border-red-200 dark:border-red-900/60 cursor-pointer"
                    onClick={() => revoke(s.id)}
                  >
                    吊销凭据
                  </Button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="text-center py-8 text-xs text-slate-400">
            暂无活跃会话记录。
          </div>
        )}
      </div>
    </div>
  );
}

