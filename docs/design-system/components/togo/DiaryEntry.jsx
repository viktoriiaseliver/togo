import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function DiaryEntry({ time, icon, title, detail, who, tone, deleted = false, onClick, style }) {
  return (
    <div onClick={onClick} role={onClick ? "button" : undefined} style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "var(--space-8) var(--space-12)", minHeight: "var(--size-row)", padding: "var(--pad-row-y) var(--pad-row)",
      background: "var(--fill-1)", borderRadius: "var(--radius-row)", boxSizing: "border-box", boxShadow: "var(--elev-1)", opacity: deleted ? 0.5 : 1, cursor: onClick ? "pointer" : "default", ...style }}>
      <div style={{ width: 40, height: 40, borderRadius: "50%", background: tone === "done" ? "var(--accent-subtle)" : tone === "overdue" ? "var(--error-subtle)" : "var(--fill-2)", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <Icon name={icon} size={22} color={tone === "done" ? "var(--accent-subtle-text)" : tone === "overdue" ? "var(--status-error)" : undefined} />
      </div>
      <div style={{ flex: "1 1 0", minWidth: "min(100%, calc(var(--fs-body) * 6))", display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
        <span style={{ fontSize: "var(--fs-body)", textDecoration: deleted ? "line-through" : "none", overflowWrap: "break-word" }}>{title}</span>
        {(detail || who) && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)", overflowWrap: "break-word" }}>{[detail, who].filter(Boolean).join(" · ")}</span>}
      </div>
      <span style={{ marginLeft: "auto", fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)", fontVariantNumeric: "tabular-nums" }}>{time}</span>
    </div>
  );
}