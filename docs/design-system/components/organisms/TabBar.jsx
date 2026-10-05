import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function TabBar({ items, value, onChange, compact = false, style }) {
  return (
    <nav style={{ display: "flex", alignItems: "center", justifyContent: "space-between", background: "var(--glass-regular)", backdropFilter: "blur(var(--blur-glass)) saturate(var(--glass-saturate))", WebkitBackdropFilter: "blur(var(--blur-glass)) saturate(var(--glass-saturate))",
      borderRadius: "var(--radius-pill)", minHeight: "var(--size-row)", padding: "0 var(--space-8) 0 0", boxShadow: "var(--glass-shadow)", ...style }}>
      {items.map((it) => {
        const on = it.value === value;
        if (on) return (
          <div key={it.value} role="tab" aria-selected="true" aria-label={it.label} style={{ display: "flex", alignItems: "center", gap: "var(--space-8)", background: "var(--glass-tint-accent)", borderRadius: "var(--radius-pill)", paddingRight: compact ? 0 : 16 }}>
            <div style={{ width: 56, height: 56, borderRadius: "50%", background: "transparent", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={it.icon} fill color="var(--accent-text)" /></div>
            {!compact && <span style={{ fontSize: "var(--fs-body)", color: "var(--accent-text)" }}>{it.label}</span>}
          </div>
        );
        return (
          <button key={it.value} type="button" role="tab" aria-label={it.label} onClick={() => onChange && onChange(it.value)}
            style={{ border: "none", background: "none", padding: 0, width: 56, height: 56, cursor: "pointer", color: "var(--text-primary)", display: "flex", alignItems: "center", justifyContent: "center" }}>
            <Icon name={it.icon} />
          </button>
        );
      })}
    </nav>
  );
}