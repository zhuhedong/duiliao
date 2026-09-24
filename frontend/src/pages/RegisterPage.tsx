import { useState, type FormEvent } from "react";
import { Link, Navigate, useNavigate } from "react-router-dom";
import { Button } from "@appica/ui-react/button";
import { Input } from "@appica/ui-react/input";
import { Field, FieldLabel, FieldDescription } from "@appica/ui-react/field";
import { Alert, AlertDescription } from "@appica/ui-react/alert";
import { Spinner } from "@appica/ui-react/spinner";
import { useAuth } from "../auth/AuthContext";
import { AuthShell } from "../components/AuthShell";
import { ApiError } from "../lib/api";
import { MailIcon, UserIcon, LockIcon, ArrowRightIcon } from "../components/icons";

export function RegisterPage() {
  const { status, register } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  if (status === "authenticated") return <Navigate to="/" replace />;

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (password !== confirm) {
      setError("两次输入的密码不一致，请核对后重试");
      return;
    }
    setSubmitting(true);
    try {
      await register({
        email: email.trim(),
        password,
        display_name: displayName.trim() || undefined,
      });
      navigate("/", { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "注册失败，请稍后重试");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AuthShell
      title="创建新账号"
      description="加入对料，开启端到端加密的安全对话之旅"
      footer={
        <div className="flex items-center justify-center gap-1.5 text-sm text-slate-500 dark:text-slate-400">
          <span>已经有账号了？</span>
          <Link to="/login" className="text-primary hover:underline font-semibold transition-colors">
            直接登录
          </Link>
        </div>
      }
    >
      <form onSubmit={onSubmit} className="flex flex-col gap-4 mt-1">
        {error && (
          <Alert variant="error" className="rounded-xl border border-rose-400/40 dark:border-rose-400/25 bg-rose-500/10 text-rose-700 dark:text-rose-300 backdrop-blur-md">
            <AlertDescription className="text-sm leading-relaxed">{error}</AlertDescription>
          </Alert>
        )}

        <Field className="space-y-1">
          <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">电子邮箱</FieldLabel>
          <Input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="your-name@example.com"
            autoComplete="email"
            required
            autoFocus
            inputSize="md"
            className="rounded-xl"
            startSlot={<MailIcon size={16} className="text-slate-400 dark:text-slate-500" />}
          />
        </Field>

        <Field className="space-y-1">
          <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">用户昵称（选填）</FieldLabel>
          <Input
            type="text"
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            placeholder="例如：技术负责人"
            autoComplete="name"
            inputSize="md"
            className="rounded-xl"
            startSlot={<UserIcon size={16} className="text-slate-400 dark:text-slate-500" />}
          />
        </Field>

        <Field className="space-y-1">
          <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">登录密码</FieldLabel>
          <Input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="设置高强度密码"
            autoComplete="new-password"
            required
            inputSize="md"
            className="rounded-xl"
            startSlot={<LockIcon size={16} className="text-slate-400 dark:text-slate-500" />}
          />
          <FieldDescription className="text-[11px] text-slate-400 dark:text-slate-500 mt-0.5">至少 8 位字符，建议混合数字与字母</FieldDescription>
        </Field>

        <Field className="space-y-1">
          <FieldLabel className="text-xs font-medium text-slate-700 dark:text-slate-300">确认登录密码</FieldLabel>
          <Input
            type="password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            placeholder="再次输入以确认密码"
            autoComplete="new-password"
            required
            inputSize="md"
            className="rounded-xl"
            startSlot={<LockIcon size={16} className="text-slate-400 dark:text-slate-500" />}
          />
        </Field>

        <Button
          type="submit"
          disabled={submitting}
          size="md"
          className="glow-button border-0 w-full rounded-xl mt-2 font-semibold text-sm tracking-wide shadow-sm hover:shadow-md transition-all duration-200 flex items-center justify-center gap-2 cursor-pointer h-10.5"
        >
          {submitting ? (
            <>
              <Spinner className="size-4" currentColor />
              <span>正在创建安全账户...</span>
            </>
          ) : (
            <>
              <span>立即注册</span>
              <ArrowRightIcon size={15} />
            </>
          )}
        </Button>
      </form>
    </AuthShell>
  );
}

