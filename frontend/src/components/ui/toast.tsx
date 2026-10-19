import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { AlertIcon, CheckIcon, CloseIcon, SparklesIcon } from "../icons";

export type ToastVariant = "success" | "error" | "warning" | "info";

export interface ToastOptions {
  title: string;
  description?: string;
  variant?: ToastVariant;
  duration?: number;
}

interface ToastItem extends Required<Pick<ToastOptions, "title" | "variant" | "duration">> {
  id: string;
  description?: string;
}

interface ToastContextValue {
  push: (opts: ToastOptions) => string;
  dismiss: (id: string) => void;
  success: (title: string, description?: string) => string;
  error: (title: string, description?: string) => string;
  warning: (title: string, description?: string) => string;
  info: (title: string, description?: string) => string;
}

const ToastContext = createContext<ToastContextValue | null>(null);

// Imperative bridge so callers can also use `toast.success(...)` directly
let externalDispatcher: ToastContextValue | null = null;

export const toast = {
  push: (opts: ToastOptions) => externalDispatcher?.push(opts) ?? "",
  dismiss: (id: string) => externalDispatcher?.dismiss(id),
  success: (title: string, description?: string) =>
    externalDispatcher?.success(title, description) ?? "",
  error: (title: string, description?: string) =>
    externalDispatcher?.error(title, description) ?? "",
  warning: (title: string, description?: string) =>
    externalDispatcher?.warning(title, description) ?? "",
  info: (title: string, description?: string) =>
    externalDispatcher?.info(title, description) ?? "",
};

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) {
    return toast;
  }
  return ctx;
}

const VARIANT_STYLES: Record<
  ToastVariant,
  {
    iconBg: string;
    border: string;
    bar: string;
    icon: ReactNode;
  }
> = {
  success: {
    iconBg:
      "bg-emerald-500/12 text-emerald-600 dark:bg-emerald-500/20 dark:text-emerald-300 border border-emerald-500/25",
    border: "border-emerald-500/30 dark:border-emerald-400/25",
    bar: "bg-emerald-500",
    icon: <CheckIcon size={15} />,
  },
  error: {
    iconBg:
      "bg-rose-500/12 text-rose-600 dark:bg-rose-500/20 dark:text-rose-300 border border-rose-500/25",
    border: "border-rose-500/30 dark:border-rose-400/25",
    bar: "bg-rose-500",
    icon: <AlertIcon size={15} />,
  },
  warning: {
    iconBg:
      "bg-amber-500/12 text-amber-600 dark:bg-amber-500/20 dark:text-amber-300 border border-amber-500/25",
    border: "border-amber-500/30 dark:border-amber-400/25",
    bar: "bg-amber-500",
    icon: <AlertIcon size={15} />,
  },
  info: {
    iconBg:
      "bg-indigo-500/12 text-indigo-600 dark:bg-indigo-500/20 dark:text-indigo-300 border border-indigo-500/25",
    border: "border-indigo-500/30 dark:border-indigo-400/25",
    bar: "bg-indigo-500",
    icon: <SparklesIcon size={15} />,
  },
};

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);

  const dismiss = useCallback((id: string) => {
    setItems((prev) => prev.filter((item) => item.id !== id));
  }, []);

  const push = useCallback(
    ({ title, description, variant = "info", duration = 3600 }: ToastOptions) => {
      const id = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
      const item: ToastItem = { id, title, description, variant, duration };
      setItems((prev) => [...prev.slice(-4), item]);
      if (duration > 0) {
        window.setTimeout(() => {
          dismiss(id);
        }, duration);
      }
      return id;
    },
    [dismiss],
  );

  const api = useMemo<ToastContextValue>(
    () => ({
      push,
      dismiss,
      success: (title, description) => push({ title, description, variant: "success" }),
      error: (title, description) =>
        push({ title, description, variant: "error", duration: 4800 }),
      warning: (title, description) =>
        push({ title, description, variant: "warning", duration: 4200 }),
      info: (title, description) => push({ title, description, variant: "info" }),
    }),
    [push, dismiss],
  );

  useEffect(() => {
    externalDispatcher = api;
    return () => {
      if (externalDispatcher === api) externalDispatcher = null;
    };
  }, [api]);

  return (
    <ToastContext.Provider value={api}>
      {children}
      {typeof document !== "undefined" &&
        createPortal(
          <div
            aria-live="polite"
            aria-atomic="true"
            className="fixed top-4 right-4 z-[90] flex flex-col gap-2.5 w-[calc(100vw-2rem)] max-w-sm pointer-events-none"
          >
            {items.map((item) => {
              const s = VARIANT_STYLES[item.variant];
              return (
                <div
                  key={item.id}
                  role="status"
                  className={`pointer-events-auto relative overflow-hidden bento-panel rounded-2xl p-3.5 shadow-xl border ${s.border} animate-slide-right flex items-start gap-3`}
                >
                  <div
                    className={`w-7 h-7 rounded-xl flex items-center justify-center shrink-0 ${s.iconBg}`}
                  >
                    {s.icon}
                  </div>
                  <div className="min-w-0 flex-1 pt-0.5">
                    <div className="text-xs sm:text-[13px] font-semibold text-slate-900 dark:text-slate-100 leading-snug break-words">
                      {item.title}
                    </div>
                    {item.description && (
                      <div className="text-[11px] text-slate-500 dark:text-slate-400 mt-1 leading-relaxed break-words">
                        {item.description}
                      </div>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => dismiss(item.id)}
                    aria-label="关闭通知"
                    className="p-1 rounded-lg text-slate-400 hover:text-slate-700 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-white/10 transition-colors cursor-pointer shrink-0"
                  >
                    <CloseIcon size={13} />
                  </button>
                  <span
                    className={`absolute left-0 bottom-0 h-0.5 ${s.bar} opacity-75`}
                    style={{
                      width: "100%",
                      transformOrigin: "left",
                      animation: `grow-x ${item.duration}ms linear reverse forwards`,
                    }}
                  />
                </div>
              );
            })}
          </div>,
          document.body,
        )}
    </ToastContext.Provider>
  );
}
