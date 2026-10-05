import React from "react";
import { Icon } from "../atoms/Icon.jsx";
const T = { neutral: ["var(--fill-2)", "var(--text-secondary)"], error: ["var(--error-subtle)", "var(--status-error)"], warning: ["var(--warning-subtle)", "var(--status-warning)"] };
export function EmptyState({ icon = "inbox", title, message, actionLabel, actionIcon, primary = false, onAction, tone = "neutral", card = false, style }) {
  const [bg, fg] = T[tone];
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: "var(--space-12)", textAlign: "center", padding: card ? "24px 20px" : "48px 12px",
      background: card ? "var(--fill-1)" : "transparent", boxShadow: card ? "var(--elev-1)" : "none", borderRadius: "var(--radius-card)", ...style }}>
      <div style={{ width: 52, height: 52, borderRadius: "50%", background: bg, display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={icon} color={fg} /></div>
      <span style={{ fontSize: "var(--fs-body)" }}>{title}</span>
      {message && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{message}</span>}
      {actionLabel && (
        <button type="button" onClick={onAction} style={{ border: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: "0 var(--space-20)", borderRadius: "var(--radius-pill)", display: "flex", alignItems: "center", gap: "var(--gap-cards)", fontSize: "var(--fs-subheadline)", marginTop: "var(--space-4)",
          background: primary ? "var(--accent)" : "var(--fill-2)", color: primary ? "var(--on-accent)" : "var(--text-primary)" }}>
          {actionIcon && <Icon name={actionIcon} size={18} />}{actionLabel}
        </button>
      )}
    </div>
  );
}