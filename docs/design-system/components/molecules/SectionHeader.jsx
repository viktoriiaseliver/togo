import React from "react";
export function SectionHeader({ title, action, onAction, style }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", flexWrap: "wrap", gap: "var(--space-4) var(--space-12)", padding: "0 var(--space-4) var(--space-4)", ...style }}>
      <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{title}</span>
      {action && <button type="button" onClick={onAction} style={{ border: "none", background: "none", padding: 0, minHeight: "var(--size-hit)", cursor: "pointer", fontSize: "var(--fs-footnote)", color: "var(--accent-text)" }}>{action}</button>}
    </div>
  );
}