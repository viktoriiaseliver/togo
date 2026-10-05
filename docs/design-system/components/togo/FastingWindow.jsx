import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function FastingWindow({ phase = "before", minutesLeft, progress = 0, until, style }) {
  const title = phase === "before" ? "Окно натощак: не кормить" : "После дозы: подожди с едой";
  return (
    <div role="status" style={{ background: "var(--warning-subtle)", borderRadius: "var(--radius-row)", padding: "var(--pad-inner) var(--pad-row)", display: "flex", flexDirection: "column", gap: "var(--space-12)", ...style }}>
      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-12)" }}>
        <Icon name="hourglass_top" color="var(--status-warning)" />
        <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
          <span style={{ fontSize: "var(--fs-body)", color: "var(--text-primary)" }}>{title}</span>
          <span style={{ fontSize: "var(--fs-footnote)", color: "var(--status-warning)" }}>{minutesLeft != null ? `Ещё ${minutesLeft} мин` : ""}{until ? ` · до ${until}` : ""}</span>
        </div>
      </div>
      <div style={{ height: 8, borderRadius: "var(--radius-pill)", background: "var(--fill-1)", overflow: "hidden" }}><div style={{ width: Math.round(progress * 100) + "%", height: "100%", background: "var(--status-warning)", borderRadius: "var(--radius-pill)" }} /></div>
    </div>
  );
}