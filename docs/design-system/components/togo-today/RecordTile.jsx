import React from "react";
import { Icon } from "../atoms/Icon.jsx";
// Плитка шторки «Записать…». tone="incident" — первая строка во всю ширину.
export function RecordTile({ icon, title, sub, tone = "default", onPress, style }) {
  const inc = tone === "incident";
  return (
    <button type="button" onClick={onPress} style={{ border: "none", cursor: "pointer", textAlign: "left", minHeight: "var(--size-row)", padding: inc ? "0 var(--space-20)" : "0 var(--space-12)", borderRadius: "var(--radius-row)", boxSizing: "border-box",
      background: inc ? "var(--error-subtle)" : "var(--fill-1)", color: inc ? "var(--status-error)" : "var(--text-primary)", boxShadow: inc ? "none" : "var(--elev-1)", display: "flex", alignItems: "center", gap: "var(--space-12)", ...style }}>
      <span style={{ width: 40, height: 40, borderRadius: "50%", flexShrink: 0, background: inc ? "transparent" : "var(--fill-2)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={icon} size={22} /></span>
      <span style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0, flex: 1 }}><span style={{ fontSize: "var(--fs-callout)", fontWeight: inc ? "var(--fw-semibold)" : 400 }}>{title}</span>{sub && <span style={{ fontSize: "var(--fs-caption-1)", color: inc ? "var(--status-error)" : "var(--text-secondary)" }}>{sub}</span>}</span>
      {inc && <Icon name="chevron_right" size={20} />}
    </button>
  );
}