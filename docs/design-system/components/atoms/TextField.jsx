import React from "react";
import { Icon } from "./Icon.jsx";
export function TextField({ value, onChange, placeholder, error, disabled = false, clearable = true, autoFocus, style }) {
  const [focus, setFocus] = React.useState(false);
  const ring = error ? "var(--status-error)" : focus ? "var(--accent)" : "transparent";
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--gap-cards)", ...style }}>
      <div style={{ minHeight: "var(--size-button)", borderRadius: "var(--radius-pill)", display: "flex", alignItems: "center", padding: "0 var(--space-8) 0 var(--space-20)", gap: "var(--space-8)",
        background: disabled ? "var(--fill-sunken)" : focus ? "var(--fill-2)" : "var(--fill-1)", boxShadow: `inset 0 0 0 2px ${ring}` }}>
        <input value={value} disabled={disabled} placeholder={placeholder} autoFocus={autoFocus}
          onChange={(e) => onChange && onChange(e.target.value)} onFocus={() => setFocus(true)} onBlur={() => setFocus(false)}
          style={{ flex: 1, minWidth: 0, border: "none", outline: "none", background: "transparent", minHeight: 48,
            color: disabled ? "var(--text-disabled)" : "var(--text-primary)", fontSize: "var(--fs-body)", caretColor: "var(--accent)" }} />
        {clearable && value && !disabled && (
          <button type="button" aria-label="Очистить" onClick={() => onChange && onChange("")}
            style={{ border: "none", background: "none", width: 36, height: 36, padding: 0, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <Icon name="cancel" size={20} fill color="var(--text-secondary)" />
          </button>
        )}
      </div>
      {error && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--status-error)", paddingLeft: "var(--space-20)", display: "flex", gap: "var(--gap-cards)", alignItems: "center" }}><Icon name="error" size={16} />{error}</span>}
    </div>
  );
}