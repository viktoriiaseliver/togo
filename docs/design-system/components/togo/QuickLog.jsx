import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function QuickLog({ items = [], onLog, style }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(max(88px, calc(var(--fs-body) * 5)), 1fr))", gap: "var(--gap-cards)", ...style }}>
      {items.map((it) => (
        <button key={it.value} type="button" onClick={() => onLog && onLog(it.value)} aria-label={it.since ? `${it.label}, ${it.since}` : it.label}
          style={{ border: "none", cursor: "pointer", minHeight: 104, borderRadius: "var(--radius-card)", padding: "var(--space-16) var(--space-12)", boxSizing: "border-box", textAlign: "left",
            display: "flex", flexDirection: "column", justifyContent: "space-between", gap: "var(--space-12)", background: it.active ? "var(--accent)" : "var(--fill-1)",
            color: it.active ? "var(--on-accent)" : "var(--text-primary)", boxShadow: it.active ? "none" : "var(--elev-1)" }}>
          <Icon name={it.icon} fill={!!it.active} />
          <span style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", minWidth: 0 }}>
            <span style={{ fontSize: "var(--fs-body)", overflowWrap: "break-word" }}>{it.label}</span>
            {it.since && <span style={{ fontSize: "var(--fs-footnote)", color: it.active ? "var(--on-accent)" : "var(--text-secondary)" }}>{it.since}</span>}
          </span>
        </button>
      ))}
    </div>
  );
}