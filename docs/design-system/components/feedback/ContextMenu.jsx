import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function ContextMenu({ items, preview, style }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-12)", ...style }}>
      {preview && <div style={{ transform: "scale(1.02)", boxShadow: "var(--elev-2)", borderRadius: "var(--radius-row)" }}>{preview}</div>}
      <div role="menu" style={{ width: "min(250px, 100%)", background: "var(--glass)", backdropFilter: "blur(var(--blur-glass))", WebkitBackdropFilter: "blur(var(--blur-glass))", borderRadius: "var(--radius-row)", overflow: "hidden", boxShadow: "var(--elev-2)" }}>
        {items.map((it, i) => (
          <button key={it.label} type="button" role="menuitem" onClick={it.onPress} style={{ width: "100%", border: "none", background: "none", cursor: "pointer", minHeight: 48, padding: "var(--pad-row-y) var(--pad-row)",
            display: "flex", justifyContent: "space-between", alignItems: "center", gap: "var(--space-12)", textAlign: "left", fontSize: "var(--fs-body)",
            color: it.destructive ? "var(--status-error)" : "var(--text-primary)", borderTop: i ? (it.group ? "6px solid var(--separator)" : "1px solid var(--separator)") : "none" }}>
            <span style={{ minWidth: 0 }}>{it.label}</span>{it.icon && <Icon name={it.icon} size={20} />}
          </button>
        ))}
      </div>
    </div>
  );
}