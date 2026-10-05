import React from "react";
import { Icon } from "../atoms/Icon.jsx";

const C = { ok: "var(--accent-text)", warning: "var(--status-warning)", error: "var(--status-error)", off: "var(--text-secondary)", empty: "var(--text-secondary)" };
export function StatusChip({ icon, title, status, tone = "ok", loading = false, onClick, style }) {
  const dim = tone === "off" || tone === "empty" || loading;
  return (
    <div onClick={onClick} style={{ display: "inline-flex", alignItems: "center", gap: "var(--space-12)", background: dim ? "var(--fill-1)" : "var(--fill-2)", borderRadius: "var(--radius-pill)",
      padding: "var(--space-12) var(--space-20) var(--space-12) var(--space-16)", minHeight: "var(--size-row)", boxSizing: "border-box", cursor: onClick ? "pointer" : "default", minWidth: loading ? 150 : undefined, ...style }}>
      {loading ? (<>
        <div style={{ width: 24, height: 24, borderRadius: "50%", background: "var(--fill-2)" }} />
        <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "var(--gap-cards)" }}><div style={{ height: 10, borderRadius: "var(--radius-pill)", background: "var(--fill-2)" }} /><div style={{ height: 8, width: "60%", borderRadius: "var(--radius-pill)", background: "var(--fill-2)" }} /></div>
      </>) : (<>
        <Icon name={icon} color={tone === "off" ? "var(--text-secondary)" : undefined} />
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
          <span style={{ fontSize: "var(--fs-body)", color: tone === "off" ? "var(--text-secondary)" : "var(--text-primary)" }}>{title}</span>
          <span style={{ fontSize: "var(--fs-footnote)", color: C[tone] }}>{status}</span>
        </div>
      </>)}
    </div>
  );
}