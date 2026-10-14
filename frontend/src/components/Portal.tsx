import { createPortal } from "react-dom";
import type { ReactNode } from "react";

/** Render overlays at <body> so `fixed` isn't trapped by blurred/transformed ancestors. */
export function Portal({ children }: { children: ReactNode }) {
  if (typeof document === "undefined") return <>{children}</>;
  return createPortal(children, document.body);
}
