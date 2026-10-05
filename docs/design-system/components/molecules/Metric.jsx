import React from "react";
const S = { xl: "var(--fs-number-xl)", l: "var(--fs-number-l)", m: "var(--fs-number-m)" };
export function Metric({ value, unit, caption, size = "l", color, style }) {
  const empty = value === null || value === undefined || value === "";
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", ...style }}>
      <div style={{ display: "flex", alignItems: "flex-start", gap: "var(--space-4)", fontFamily: "var(--font-rounded)", fontWeight: 300, color: empty ? "var(--text-disabled)" : color }}>
        <span style={{ fontSize: S[size], lineHeight: 1, letterSpacing: "-.02em", fontVariantNumeric: "tabular-nums" }}>{empty ? "—" : value}</span>
        {!empty && unit && <span style={{ fontSize: "var(--fs-title-3)", marginTop: "var(--space-4)" }}>{unit}</span>}
      </div>
      {(caption || empty) && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{empty ? caption || "Нет данных" : caption}</span>}
    </div>
  );
}