import type { ReactNode } from "react";
import { Navigate, useLocation } from "react-router-dom";
import { Spinner } from "@appica/ui-react/spinner";
import { useAuth } from "./AuthContext";

/**
 * Gates its children behind authentication. While the session is being
 * restored we show a spinner; unauthenticated users are redirected to /login
 * with the attempted location preserved for post-login redirect.
 */
export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { status } = useAuth();
  const location = useLocation();

  if (status === "loading") {
    return (
      <div style={{ display: "grid", placeItems: "center", height: "100dvh" }}>
        <Spinner aria-label="加载中" />
      </div>
    );
  }

  if (status === "anonymous") {
    return <Navigate to="/login" replace state={{ from: location }} />;
  }

  return <>{children}</>;
}
