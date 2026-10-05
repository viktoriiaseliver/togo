import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function EditBar({ count = 0, onDelete, secondaryLabel, onSecondary, style }) {
  const on = count > 0;
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "var(--space-8)", background: "var(--glass)", backdropFilter: "blur(var(--blur-glass))", WebkitBackdropFilter: "blur(var(--blur-glass))",
      borderRadius: "var(--radius-pill)", minHeight: "var(--size-row)", padding: "var(--space-8)", boxSizing: "border-box", boxShadow: "var(--elev-2)", ...style }}>
      {secondaryLabel ? <button type="button" onClick={onSecondary} style={{ border: "none", background: "none", cursor: "pointer", minHeight: "var(--size-button)", padding: "0 var(--space-16)", fontSize: "var(--fs-body)", color: "var(--text-primary)" }}>{secondaryLabel}</button>
        : <span style={{ padding: "0 var(--space-16)", fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}>{on ? `Выбрано: ${count}` : "Ничего не выбрано"}</span>}
      <button type="button" disabled={!on} onClick={onDelete} style={{ border: "none", cursor: on ? "pointer" : "default", minHeight: "var(--size-button)", display: "flex", alignItems: "center", gap: "var(--gap-cards)", padding: "0 var(--space-20)", borderRadius: "var(--radius-pill)",
        background: on ? "var(--error-subtle)" : "var(--fill-sunken)", color: on ? "var(--status-error)" : "var(--text-disabled)", fontSize: "var(--fs-body)" }}>
        <Icon name="delete" size={20} />{on && secondaryLabel ? `Удалить (${count})` : "Удалить"}
      </button>
    </div>
  );
}