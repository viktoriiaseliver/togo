import React from "react";
import { Skeleton } from "../atoms/Skeleton.jsx";
export function ListSkeleton({ rows = 3, icon = true, style }) {
  return (
    <div aria-busy="true" aria-label="Загрузка" style={{ display: "flex", flexDirection: "column", gap: "var(--gap-cards)", ...style }}>
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} style={{ minHeight: "var(--size-row)", padding: "var(--pad-row-y) var(--pad-row)", borderRadius: "var(--radius-row)", background: "var(--fill-1)", boxShadow: "var(--elev-1)", display: "flex", alignItems: "center", gap: "var(--space-12)", opacity: 1 - i * 0.18 }}>
          {icon && <Skeleton width={40} height={40} round style={{ background: "var(--fill-2)" }} />}
          <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "var(--space-8)" }}><Skeleton width={(60 - i * 8) + "%"} style={{ background: "var(--fill-2)" }} /><Skeleton width="35%" height={10} style={{ background: "var(--fill-2)" }} /></div>
        </div>
      ))}
    </div>
  );
}
export function RefreshIndicator({ state = "idle", updated, style }) {
  const t = { pulling: "Отпусти, чтобы обновить", loading: "Обновляю", idle: updated ? "Обновлено " + updated : "", error: "Не обновилось. Потяни ещё раз" }[state];
  return (
    <div role="status" style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: "var(--space-8)", minHeight: "var(--size-hit)", fontSize: "var(--fs-footnote)", color: state === "error" ? "var(--status-warning)" : "var(--text-secondary)", ...style }}>
      {state === "loading" && <span className="material-symbols-rounded" aria-hidden="true" style={{ fontSize: "var(--icon-size-s)" }}>progress_activity</span>}
      {state === "pulling" && <span className="material-symbols-rounded" aria-hidden="true" style={{ fontSize: "var(--icon-size-s)" }}>arrow_downward</span>}
      {t}
    </div>
  );
}