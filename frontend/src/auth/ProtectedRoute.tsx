import type { ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { Spinner } from "../components/ui/spinner";
import { useAuth } from "./AuthContext";

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { status } = useAuth();
  const location = useLocation();

  if (status === "loading") {
    return (
      <div className="grid place-items-center h-dvh bg-[var(--admin-bg)] text-slate-500">
        <div className="flex flex-col items-center gap-3">
          <Spinner className="size-6 text-brand-600" aria-label="加载中" />
          <span className="text-xs">正在恢复会话…</span>
        </div>
      </div>
    );
  }

  if (status === "anonymous") {
    return <Navigate to="/login" replace state={{ from: location }} />;
  }

  return <>{children}</>;
}
