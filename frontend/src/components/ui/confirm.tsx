import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { Portal } from "../Portal";
import { AlertIcon, TrashIcon } from "../icons";
import { Button } from "./button";

export interface ConfirmOptions {
  title: string;
  description?: ReactNode;
  confirmText?: string;
  cancelText?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: "danger" | "warning" | "primary";
}

type ConfirmFn = (options: ConfirmOptions) => Promise<boolean>;

const ConfirmContext = createContext<ConfirmFn | null>(null);

let externalConfirm: ConfirmFn | null = null;

export function confirmDialog(options: ConfirmOptions): Promise<boolean> {
  if (externalConfirm) return externalConfirm(options);
  const fallbackMsg =
    typeof options.description === "string"
      ? `${options.title}\n\n${options.description}`
      : options.title;
  return Promise.resolve(window.confirm(fallbackMsg));
}

export function useConfirm(): ConfirmFn {
  const ctx = useContext(ConfirmContext);
  return ctx ?? confirmDialog;
}

interface ActiveConfirm extends ConfirmOptions {
  resolve: (ok: boolean) => void;
}

export function ConfirmProvider({ children }: { children: ReactNode }) {
  const [active, setActive] = useState<ActiveConfirm | null>(null);
  const confirmBtnRef = useRef<HTMLButtonElement | null>(null);

  const confirm = useCallback<ConfirmFn>((options) => {
    return new Promise<boolean>((resolve) => {
      setActive({
        confirmText: options.confirmText ?? options.confirmLabel ?? "确认执行",
        cancelText: options.cancelText ?? options.cancelLabel ?? "取消",
        variant: "danger",
        ...options,
        resolve,
      });
    });
  }, []);

  useEffect(() => {
    externalConfirm = confirm;
    return () => {
      if (externalConfirm === confirm) externalConfirm = null;
    };
  }, [confirm]);

  useEffect(() => {
    if (active) {
      const id = window.setTimeout(() => confirmBtnRef.current?.focus(), 30);
      return () => window.clearTimeout(id);
    }
  }, [active]);

  const handleClose = (ok: boolean) => {
    if (!active) return;
    const r = active.resolve;
    setActive(null);
    r(ok);
  };

  const variant = active?.variant ?? "danger";
  const iconTone =
    variant === "danger"
      ? "bg-rose-500/12 text-rose-600 dark:bg-rose-500/20 dark:text-rose-300 border-rose-500/25"
      : variant === "warning"
        ? "bg-amber-500/12 text-amber-600 dark:bg-amber-500/20 dark:text-amber-300 border-amber-500/25"
        : "bg-indigo-500/12 text-indigo-600 dark:bg-indigo-500/20 dark:text-indigo-300 border-indigo-500/25";

  return (
    <ConfirmContext.Provider value={confirm}>
      {children}
      {active && (
        <Portal onClose={() => handleClose(false)}>
          <div
            role="alertdialog"
            aria-modal="true"
            aria-labelledby="confirm-dialog-title"
            className="fixed inset-0 z-[95] flex items-center justify-center p-4"
          >
            <div
              className="absolute inset-0 bg-slate-900/50 dark:bg-black/70 backdrop-blur-xs animate-overlay"
              onClick={() => handleClose(false)}
            />
            <div className="relative w-full max-w-md bento-card rounded-2xl p-5 sm:p-6 shadow-2xl animate-scale-in">
              <div className="flex items-start gap-3.5">
                <div
                  className={`w-10 h-10 rounded-xl border flex items-center justify-center shrink-0 ${iconTone}`}
                >
                  {variant === "danger" ? <TrashIcon size={18} /> : <AlertIcon size={18} />}
                </div>
                <div className="min-w-0 flex-1">
                  <h3
                    id="confirm-dialog-title"
                    className="text-base font-bold text-slate-900 dark:text-slate-100 tracking-tight"
                  >
                    {active.title}
                  </h3>
                  {active.description && (
                    <div className="mt-1.5 text-xs sm:text-[13px] text-slate-600 dark:text-slate-400 leading-relaxed whitespace-pre-line">
                      {active.description}
                    </div>
                  )}
                </div>
              </div>

              <div className="mt-6 flex items-center justify-end gap-2.5">
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() => handleClose(false)}
                >
                  {active.cancelText ?? "取消"}
                </Button>
                <Button
                  ref={confirmBtnRef}
                  type="button"
                  variant={variant === "danger" ? "destructive" : "default"}
                  size="sm"
                  onClick={() => handleClose(true)}
                >
                  {active.confirmText ?? "确认"}
                </Button>
              </div>
            </div>
          </div>
        </Portal>
      )}
    </ConfirmContext.Provider>
  );
}
