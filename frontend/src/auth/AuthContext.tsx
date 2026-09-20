import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { api, authApi, type User } from "../lib/api";

type AuthStatus = "loading" | "authenticated" | "anonymous";

interface AuthContextValue {
  user: User | null;
  status: AuthStatus;
  login: (identifier: string, password: string) => Promise<void>;
  register: (input: {
    email?: string;
    phone?: string;
    username?: string;
    password: string;
    display_name?: string;
  }) => Promise<void>;
  bootstrap: (input: {
    email?: string;
    phone?: string;
    username?: string;
    password: string;
    display_name?: string;
  }) => Promise<void>;
  logout: (allDevices?: boolean) => Promise<void>;
  refreshUser: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [status, setStatus] = useState<AuthStatus>("loading");

  // Bootstrap: if a refresh token survived a reload, recover the session.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!api.hasRefreshToken()) {
        setStatus("anonymous");
        return;
      }
      try {
        const me = await authApi.me(); // api client auto-refreshes the access token
        if (!cancelled) {
          setUser(me);
          setStatus("authenticated");
        }
      } catch {
        api.clearTokens();
        if (!cancelled) setStatus("anonymous");
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const login = useCallback(async (identifier: string, password: string) => {
    const res = await authApi.login(identifier, password);
    api.setTokens(res.access_token, res.refresh_token);
    setUser(res.user);
    setStatus("authenticated");
  }, []);

  const register = useCallback<AuthContextValue["register"]>(async (input) => {
    const res = await authApi.register(input);
    api.setTokens(res.access_token, res.refresh_token);
    setUser(res.user);
    setStatus("authenticated");
  }, []);

  const bootstrap = useCallback<AuthContextValue["bootstrap"]>(async (input) => {
    const res = await authApi.bootstrap(input);
    api.setTokens(res.access_token, res.refresh_token);
    setUser(res.user);
    setStatus("authenticated");
  }, []);

  const logout = useCallback(async (allDevices = false) => {
    try {
      await authApi.logout(allDevices);
    } catch {
      // ignore network/expiry errors on logout
    }
    api.clearTokens();
    setUser(null);
    setStatus("anonymous");
  }, []);

  const refreshUser = useCallback(async () => {
    const me = await authApi.me();
    setUser(me);
  }, []);

  const value = useMemo(
    () => ({ user, status, login, register, bootstrap, logout, refreshUser }),
    [user, status, login, register, bootstrap, logout, refreshUser],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within <AuthProvider>");
  return ctx;
}
