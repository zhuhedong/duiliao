import { useEffect, useState, type FormEvent } from "react";
import { Navigate, useLocation, useNavigate } from "react-router-dom";
import { Button } from "@appica/ui-react/button";
import { Input } from "@appica/ui-react/input";
import { Field, FieldLabel } from "@appica/ui-react/field";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { Checkbox } from "@appica/ui-react/checkbox";
import { Spinner } from "@appica/ui-react/spinner";
import { useAuth } from "../auth/AuthContext";
import { AuthShell } from "../components/AuthShell";
import { ApiError, authApi } from "../lib/api";
import { UserIcon, LockIcon, EyeIcon, EyeOffIcon, ArrowRightIcon } from "../components/icons";

const REMEMBER_KEY = "duiliao_remembered_identifier";

export function LoginPage() {
  const { status, login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [identifier, setIdentifier] = useState(() => {
    try {
      return localStorage.getItem(REMEMBER_KEY) || "";
    } catch {
      return "";
    }
  });
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [rememberMe, setRememberMe] = useState(() => {
    try {
      return !!localStorage.getItem(REMEMBER_KEY);
    } catch {
      return false;
    }
  });
  const [showForgotPassword, setShowForgotPassword] = useState(false);

  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  // First run: if no admin exists yet and this is a local client, send the
  // operator to the admin-initialization flow instead of the login form.
  useEffect(() => {
    if (status !== "anonymous") return;
    let cancelled = false;
    authApi
      .bootstrapStatus()
      .then((s) => {
        if (!cancelled && s.available) navigate("/bootstrap", { replace: true });
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [status, navigate]);

  if (status === "authenticated") return <Navigate to="/" replace />;

  const from = (location.state as { from?: { pathname: string } } | null)?.from?.pathname || "/";

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      if (rememberMe) {
        try {
          localStorage.setItem(REMEMBER_KEY, identifier.trim());
        } catch {
          // ignore
        }
      } else {
        try {
          localStorage.removeItem(REMEMBER_KEY);
        } catch {
          // ignore
        }
      }

      await login(identifier.trim(), password);
      navigate(from, { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "登录失败，请检查账号密码后重试");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AuthShell
      title="欢迎回来"
      description="登录您的对料账号以进入加密工作台"
    >
      <form onSubmit={onSubmit} className="flex flex-col gap-3.5 mt-1">
        {error && (
          <Alert variant="error" className="rounded-xl border border-red-200/80 bg-red-50/80 text-red-700 py-2.5 px-3">
            <AlertDescription className="text-xs leading-relaxed">{error}</AlertDescription>
          </Alert>
        )}

        <Field className="space-y-1">
          <FieldLabel className="text-xs font-medium text-slate-700">
            账号 / 邮箱 / 手机号
          </FieldLabel>
          <Input
            type="text"
            value={identifier}
            onChange={(e) => setIdentifier(e.target.value)}
            placeholder="用户名 / 邮箱 / 手机号"
            autoComplete="username"
            required
            autoFocus={!identifier}
            clearable
            onClear={() => setIdentifier("")}
            inputSize="md"
            className="rounded-xl"
            startSlot={<UserIcon size={16} className="text-slate-400" />}
          />
        </Field>

        <Field className="space-y-1">
          <div className="flex items-center justify-between">
            <FieldLabel className="text-xs font-medium text-slate-700">
              登录密码
            </FieldLabel>
            <button
              type="button"
              onClick={() => setShowForgotPassword((prev) => !prev)}
              className="text-[11px] text-primary hover:underline font-medium transition-colors cursor-pointer"
              tabIndex={-1}
            >
              忘记密码？
            </button>
          </div>
          {showForgotPassword && (
            <div className="text-[11px] bg-blue-50/50 text-blue-600/90 p-2.5 rounded-lg border border-blue-100/50 leading-relaxed">
              本系统采用零知识端到端加密架构，密码仅在您的设备上解密，服务端无法恢复。如需重置密码，请联系系统管理员。
            </div>
          )}
          <Input
            type={showPassword ? "text" : "password"}
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="请输入密码"
            autoComplete="current-password"
            required
            autoFocus={!!identifier}
            inputSize="md"
            className="rounded-xl"
            startSlot={<LockIcon size={16} className="text-slate-400" />}
            endSlot={
              <button
                type="button"
                onClick={() => setShowPassword((prev) => !prev)}
                className="text-slate-400 hover:text-slate-700 transition-colors p-1 flex items-center justify-center cursor-pointer pointer-events-auto"
                title={showPassword ? "隐藏密码" : "显示密码"}
                tabIndex={-1}
              >
                {showPassword ? <EyeOffIcon size={16} /> : <EyeIcon size={16} />}
              </button>
            }
          />
        </Field>

        {/* 记住账号选项 */}
        <div className="flex items-center justify-between pt-0.5">
          <label className="inline-flex items-center gap-2 text-xs text-slate-600 hover:text-slate-900 cursor-pointer select-none">
            <Checkbox
              checked={rememberMe}
              onCheckedChange={(checked) => setRememberMe(!!checked)}
            />
            <span>记住账号</span>
          </label>
        </div>

        <Button
          type="submit"
          disabled={submitting}
          size="md"
          className="w-full rounded-xl mt-2 font-semibold text-sm tracking-wide shadow-sm hover:shadow-md transition-all duration-200 flex items-center justify-center gap-2 cursor-pointer h-10.5"
        >
          {submitting ? (
            <>
              <Spinner className="size-4" currentColor />
              <span>正在验证身份并建立会话...</span>
            </>
          ) : (
            <>
              <span>安全登录</span>
              <ArrowRightIcon size={15} />
            </>
          )}
        </Button>
      </form>
    </AuthShell>
  );
}

