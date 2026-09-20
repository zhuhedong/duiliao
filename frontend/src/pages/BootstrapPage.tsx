import { useEffect, useState, type FormEvent } from "react";
import { Navigate, useNavigate } from "react-router-dom";
import { Button } from "@appica/ui-react/button";
import { Input } from "@appica/ui-react/input";
import { Field, FieldLabel } from "@appica/ui-react/field";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { Spinner } from "@appica/ui-react/spinner";
import { useAuth } from "../auth/AuthContext";
import { AuthShell } from "../components/AuthShell";
import { ApiError, authApi } from "../lib/api";
import { UserIcon, LockIcon, ArrowRightIcon } from "../components/icons";
import { Link } from "react-router-dom";

const REASON_MESSAGE: Record<string, string> = {
  already_initialized: "已存在管理员账户，无需初始化。",
  production: "生产环境已禁用初始化入口，请使用命令行创建管理员。",
  not_local: "初始化仅允许在本机（回环地址）进行。",
  disabled: "初始化入口已被关闭。",
};

export function BootstrapPage() {
  const { status, bootstrap } = useAuth();
  const navigate = useNavigate();
  const [checking, setChecking] = useState(true);
  const [available, setAvailable] = useState(false);
  const [reason, setReason] = useState<string | null>(null);

  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;
    authApi
      .bootstrapStatus()
      .then((s) => {
        if (cancelled) return;
        setAvailable(s.available);
        setReason(s.reason);
      })
      .catch(() => {
        if (!cancelled) setAvailable(false);
      })
      .finally(() => {
        if (!cancelled) setChecking(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (status === "authenticated") return <Navigate to="/" replace />;

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (password !== confirm) {
      setError("两次输入的密码不一致");
      return;
    }
    setSubmitting(true);
    try {
      await bootstrap({ username: username.trim(), password, display_name: username.trim() });
      navigate("/", { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "初始化失败，请稍后重试");
    } finally {
      setSubmitting(false);
    }
  };

  if (checking) {
    return (
      <AuthShell title="初始化管理员账户" description="正在检查初始化状态…">
        <div style={{ display: "grid", placeItems: "center", padding: 24 }}>
          <Spinner aria-label="检查中" />
        </div>
      </AuthShell>
    );
  }

  if (!available) {
    return (
      <AuthShell
        title="初始化管理员账户"
        description="当前无法初始化管理员"
        footer={
          <>
            返回{" "}
            <Link to="/login" style={{ color: "var(--color-primary)", fontWeight: 600 }}>
              登录
            </Link>
          </>
        }
      >
        <Alert variant="warning">
          <AlertDescription>{(reason && REASON_MESSAGE[reason]) || "初始化入口不可用。"}</AlertDescription>
        </Alert>
      </AuthShell>
    );
  }

  return (
    <AuthShell
      title="初始化管理员账户"
      description="首次启动：配置初始超级管理员凭证，完成后将自动建立加密会话并登录。"
      footer={
        <div className="flex items-center justify-center gap-1.5 text-sm text-slate-500">
          <span>已有账户？</span>
          <Link to="/login" className="text-primary hover:underline font-semibold transition-colors">
            直接登录
          </Link>
        </div>
      }
    >
      <form onSubmit={onSubmit} className="flex flex-col gap-4 mt-1">
        {error && (
          <Alert variant="error" className="rounded-xl border border-red-200/80 bg-red-50/70 text-red-700">
            <AlertDescription className="text-sm leading-relaxed">{error}</AlertDescription>
          </Alert>
        )}

        <Field className="space-y-1">
          <FieldLabel className="text-xs font-medium text-slate-700">超级管理员用户名</FieldLabel>
          <Input
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="admin"
            autoComplete="username"
            required
            autoFocus
            inputSize="md"
            className="rounded-xl"
            startSlot={<UserIcon size={16} className="text-slate-400" />}
          />
        </Field>

        <Field className="space-y-1">
          <FieldLabel className="text-xs font-medium text-slate-700">管理员密码</FieldLabel>
          <Input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="设置高强度管理员密码"
            autoComplete="new-password"
            required
            inputSize="md"
            className="rounded-xl"
            startSlot={<LockIcon size={16} className="text-slate-400" />}
          />
        </Field>

        <Field className="space-y-1">
          <FieldLabel className="text-xs font-medium text-slate-700">确认管理员密码</FieldLabel>
          <Input
            type="password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            placeholder="再次输入密码"
            autoComplete="new-password"
            required
            inputSize="md"
            className="rounded-xl"
            startSlot={<LockIcon size={16} className="text-slate-400" />}
          />
        </Field>

        <Button
          type="submit"
          disabled={submitting}
          size="md"
          className="w-full rounded-xl mt-2 font-semibold text-sm tracking-wide shadow-sm hover:shadow-md transition-all duration-200 flex items-center justify-center gap-2 cursor-pointer h-10.5"
        >
          {submitting ? (
            <>
              <Spinner className="size-4" currentColor />
              <span>正在初始化并配置安全环境...</span>
            </>
          ) : (
            <>
              <span>立即初始化并登录</span>
              <ArrowRightIcon size={15} />
            </>
          )}
        </Button>
      </form>
    </AuthShell>
  );
}
