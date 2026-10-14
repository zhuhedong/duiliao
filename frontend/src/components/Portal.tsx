import { useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import type { ReactNode } from "react";

/**
 * Render overlays at <body> so `fixed` isn't trapped by blurred/transformed
 * ancestors. Pass `onClose` to close on Escape.
 */
export function Portal({ children, onClose }: { children: ReactNode; onClose?: () => void }) {
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  useEffect(() => {
    if (!onClose) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") closeRef.current?.();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [!onClose]); // eslint-disable-line react-hooks/exhaustive-deps
  if (typeof document === "undefined") return <>{children}</>;
  return createPortal(children, document.body);
}
