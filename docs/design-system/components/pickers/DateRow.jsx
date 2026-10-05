import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function DateRow({ icon = "event", label, value, onClick, style }) {
  return (
    <button type="button" onClick={onClick} style={{ width: "100%", border: "none", cursor: "pointer", minHeight: "var(--size-row)", padding: "var(--pad-row-y) var(--pad-row)", borderRadius: "var(--radius-row)", background: "var(--fill-1)", boxShadow: "var(--elev-1)",
      display: "flex", flexWrap: "wrap", alignItems: "center", gap: "var(--space-4) var(--space-12)", textAlign: "left", color: "var(--text-primary)", ...style }}>
      <Icon name={icon} />
      <span style={{ flex: "1 0 auto", fontSize: "var(--fs-body)" }}>{label}</span>
      <span style={{ fontSize: "var(--fs-body)", color: "var(--accent-text)", fontVariantNumeric: "tabular-nums" }}>{value}</span>
    </button>
  );
}