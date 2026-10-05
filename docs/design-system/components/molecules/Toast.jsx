import React from "react";
import { Icon } from "../atoms/Icon.jsx";

export function Toast({ tone = "undo", text, actionLabel, onAction, style }) {
  const base = { display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "var(--space-12)", borderRadius: "var(--radius-pill)", minHeight: "var(--size-button)", padding: "var(--space-4) var(--space-4) var(--space-4) var(--space-20)", boxSizing: "border-box", ...style };
  if (tone === "info") return (
    <div role="status" style={{ ...base, justifyContent: "flex-start", padding: "var(--space-4) var(--space-20)", background: "var(--glass)", backdropFilter: "blur(var(--blur-glass))", WebkitBackdropFilter: "blur(var(--blur-glass))", boxShadow: "var(--elev-2)" }}>
      <Icon name="check_circle" size={20} fill color="var(--accent-text)" /><span style={{ fontSize: "var(--fs-subheadline)" }}>{text}</span>
    </div>
  );
  const err = tone === "error";
  return (
    <div role="status" style={{ ...base, background: err ? "var(--error-subtle)" : "var(--fill-inverse)", color: err ? "var(--status-error)" : "var(--on-inverse)", boxShadow: err ? "none" : "var(--elev-2)" }}>
      <span style={{ fontSize: "var(--fs-subheadline)", minWidth: 0 }}>{text}</span>
      {actionLabel && (
        <button type="button" onClick={onAction} style={{ border: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: "0 var(--space-16)", borderRadius: "var(--radius-pill)", flexShrink: 0, display: "flex", alignItems: "center", gap: "var(--gap-cards)", fontSize: "var(--fs-subheadline)",
          background: err ? "var(--fill-1)" : "var(--on-inverse)", color: err ? "var(--text-primary)" : "var(--fill-inverse)" }}>
          {!err && <Icon name="undo" size={18} />}{actionLabel}
        </button>
      )}
    </div>
  );
}