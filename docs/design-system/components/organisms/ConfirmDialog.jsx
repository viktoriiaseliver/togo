import React from "react";
export function ConfirmDialog({ open = true, message, confirmLabel, onConfirm, onCancel, inline = false, style }) {
  if (!open) return null;
  const body = (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)", ...style }}>
      <div role="alertdialog" style={{ background: "var(--fill-1)", borderRadius: "var(--radius-row)", overflow: "hidden", display: "flex", flexDirection: "column" }}>
        <div style={{ padding: "var(--space-16) var(--space-20)", textAlign: "center", fontSize: "var(--fs-footnote)", color: "var(--text-secondary)", lineHeight: 1.35 }}>{message}</div>
        <div style={{ height: 1, background: "var(--separator)" }} />
        <button type="button" onClick={onConfirm} style={{ border: "none", background: "none", cursor: "pointer", minHeight: 56, fontSize: "var(--fs-body)", color: "var(--status-error)" }}>{confirmLabel}</button>
      </div>
      <button type="button" onClick={onCancel} style={{ border: "none", cursor: "pointer", background: "var(--fill-1)", borderRadius: "var(--radius-row)", minHeight: 56, fontSize: "var(--fs-body)", fontWeight: 600, color: "var(--text-primary)" }}>Отмена</button>
    </div>
  );
  if (inline) return body;
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--scrim)", display: "flex", flexDirection: "column", justifyContent: "flex-end", padding: "var(--space-12) var(--space-12) var(--space-28)", boxSizing: "border-box", zIndex: 11 }}>
      <div style={{ flex: 1 }} onClick={onCancel} />{body}
    </div>
  );
}