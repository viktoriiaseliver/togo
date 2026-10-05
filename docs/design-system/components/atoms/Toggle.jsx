import React from "react";
export function Toggle({ checked, onChange, disabled = false, label, style }) {
  return (
    <button type="button" role="switch" aria-checked={checked} aria-label={label} disabled={disabled}
      onClick={() => onChange && onChange(!checked)}
      style={{ border: "none", cursor: disabled ? "default" : "pointer", width: 64, height: 36, borderRadius: "var(--radius-pill)", padding: "var(--space-4)", flexShrink: 0,
        boxSizing: "border-box", display: "flex", justifyContent: checked ? "flex-end" : "flex-start",
        background: checked ? "var(--accent)" : "var(--toggle-off)", opacity: disabled ? 0.4 : 1, ...style }}>
      <span style={{ width: 30, height: 30, borderRadius: "50%", background: checked ? "var(--accent-knob)" : "var(--toggle-off-knob)" }} />
    </button>
  );
}