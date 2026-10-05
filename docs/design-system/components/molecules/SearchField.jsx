import React from "react";
import { Icon } from "../atoms/Icon.jsx";

export function SearchField({ value, onChange, onCancel, placeholder = "Поиск", style }) {
  const [focus, setFocus] = React.useState(false);
  const active = focus || !!value;
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "var(--space-12)", ...style }}>
      <div style={{ flex: 1, minWidth: 0, display: "flex", alignItems: "center", gap: "var(--space-12)", minHeight: 48, borderRadius: "var(--radius-pill)", padding: "0 var(--space-8) 0 var(--space-16)",
        background: active ? "var(--fill-2)" : "var(--fill-1)", boxShadow: focus ? "inset 0 0 0 2px var(--accent)" : "none" }}>
        <Icon name="search" size={22} color="var(--text-secondary)" />
        <input value={value} placeholder={placeholder} onChange={(e) => onChange && onChange(e.target.value)} onFocus={() => setFocus(true)} onBlur={() => setFocus(false)}
          size={1} style={{ flex: 1, minWidth: 0, width: "100%", border: "none", outline: "none", background: "transparent", color: "var(--text-primary)", fontSize: "var(--fs-body)", minHeight: "var(--size-hit)" }} />
        {value && <button type="button" aria-label="Очистить" onClick={() => onChange && onChange("")} style={{ border: "none", background: "none", padding: 0, width: 36, height: 36, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name="cancel" size={20} fill color="var(--text-secondary)" /></button>}
      </div>
      {active && onCancel && <button type="button" onClick={onCancel} style={{ border: "none", background: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: 0, fontSize: "var(--fs-body)", color: "var(--accent-text)" }}>Отмена</button>}
    </div>
  );
}