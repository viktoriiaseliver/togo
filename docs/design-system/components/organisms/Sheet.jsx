import React from "react";
import { FitHeader } from "./FitHeader.jsx";
export function Sheet({ open = true, title, onCancel, onDone, doneDisabled = false, children, inline = false, style }) {
  if (!open) return null;
  const panel = (
    <div role="dialog" aria-label={title} style={{ background: "var(--fill-1)", borderRadius: "var(--radius-sheet) var(--radius-sheet) 0 0", padding: "var(--space-8) var(--space-20) var(--space-32)", display: "flex", flexDirection: "column", gap: "var(--space-16)", ...style }}>
      <div style={{ width: 36, height: 5, borderRadius: 3, background: "var(--text-disabled)", alignSelf: "center" }} />
      <FitHeader leading={<button type="button" onClick={onCancel} style={{ border: "none", background: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: 0, fontSize: "var(--fs-body)", color: "var(--accent-text)" }}>Отмена</button>} title={title} trailing={<button type="button" onClick={doneDisabled ? undefined : onDone} style={{ border: "none", background: "none", cursor: doneDisabled ? "default" : "pointer", minHeight: "var(--size-hit)", padding: 0, fontSize: "var(--fs-body)", fontWeight: 600, color: doneDisabled ? "var(--text-disabled)" : "var(--accent-text)" }}>Готово</button>} />
      {children}
    </div>
  );
  if (inline) return panel;
  return (
    <div style={{ position: "absolute", inset: 0, background: "var(--scrim)", display: "flex", flexDirection: "column", justifyContent: "flex-end", zIndex: 10 }}>
      <div style={{ flex: 1 }} onClick={onCancel} />{panel}
    </div>
  );
}