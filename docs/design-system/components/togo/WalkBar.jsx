import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function WalkBar({ elapsed = "00:00", marks = [], onMark, onFinish, style }) {
  return (
    <div role="region" aria-label="Прогулка" style={{ background: "var(--fill-inverse)", color: "var(--on-inverse)", borderRadius: "var(--radius-card)", padding: "var(--pad-inner)", display: "flex", flexDirection: "column", gap: "var(--space-12)", boxShadow: "var(--elev-2)", ...style }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "var(--space-8)", flexWrap: "wrap" }}>
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
          <span style={{ fontSize: "var(--fs-footnote)" }}>Прогулка идёт</span>
          <span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: "var(--fs-number-m)", lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>{elapsed}</span>
        </div>
        <button type="button" onClick={onFinish} style={{ border: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: "0 var(--space-20)", borderRadius: "var(--radius-pill)", background: "var(--on-inverse)", color: "var(--fill-inverse)", fontSize: "var(--fs-subheadline)" }}>Закончить</button>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(max(84px, calc(var(--fs-subheadline) * 5.5)), 1fr))", gap: "var(--gap-cards)" }}>
        {marks.map((m) => (
          <button key={m.value} type="button" onClick={() => onMark && onMark(m.value)} style={{ border: "none", cursor: "pointer", minHeight: "var(--size-button)", borderRadius: "var(--radius-pill)", padding: "0 var(--space-12)",
            display: "flex", alignItems: "center", justifyContent: "center", flexWrap: "wrap", gap: "var(--gap-cards)", fontSize: "var(--fs-subheadline)", textAlign: "center",
            background: m.count ? "var(--accent)" : "var(--fill-on-inverse)", color: m.count ? "var(--on-accent)" : "var(--on-inverse)" }}>
            {m.label}{m.count ? <span style={{ fontVariantNumeric: "tabular-nums" }}>· {m.count}</span> : null}
          </button>
        ))}
      </div>
    </div>
  );
}