import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function LiveActivity({ kind = "walk", title, elapsed, detail, island = false, style }) {
  const ic = kind === "walk" ? "directions_walk" : kind === "fast" ? "hourglass_top" : "school";
  const col = kind === "fast" ? "var(--status-warning)" : "var(--accent)";
  if (island) return (
    <div style={{ display: "inline-flex", alignItems: "center", justifyContent: "space-between", gap: "var(--space-16)", minHeight: 36, padding: "0 var(--space-16)", borderRadius: "var(--radius-pill)", background: "var(--system-island)", color: "var(--system-text)", ...style }}>
      <Icon name={ic} size={18} color={col} /><span style={{ fontSize: "var(--fs-subheadline)", fontVariantNumeric: "tabular-nums", color: col }}>{elapsed}</span>
    </div>
  );
  return (
    <div style={{ borderRadius: "var(--radius-row)", padding: "var(--pad-row)", background: "var(--system-surface)", color: "var(--system-text)", display: "flex", flexWrap: "wrap", gap: "var(--space-8) var(--space-12)", alignItems: "center", ...style }}>
      <span style={{ width: 44, height: 44, borderRadius: "50%", background: "var(--system-fill)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={ic} color={col} /></span>
      <span style={{ flex: "1 1 0", minWidth: "min(100%, calc(var(--fs-body) * 6))", display: "flex", flexDirection: "column", gap: "var(--space-4)" }}><span style={{ fontSize: "var(--fs-body)" }}>{title}</span>{detail && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--system-text-2)" }}>{detail}</span>}</span>
      <span style={{ marginLeft: "auto", fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: "var(--fs-number-s)", lineHeight: 1, fontVariantNumeric: "tabular-nums", color: col }}>{elapsed}</span>
    </div>
  );
}