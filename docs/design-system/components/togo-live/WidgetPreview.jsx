import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function WidgetPreview({ size = "small", dog = "Стич", since, next, verdict, style }) {
  const S = { small: [158, 158], medium: [338, 158] }[size];
  return (
    <div aria-label={"Виджет " + dog} style={{ width: S[0], maxWidth: "100%", minHeight: S[1], boxSizing: "border-box", borderRadius: "var(--radius-row)", padding: "var(--pad-inner)", background: "var(--fill-1)", boxShadow: "var(--elev-2)",
      display: "flex", flexDirection: size === "medium" ? "row" : "column", justifyContent: "space-between", gap: "var(--space-12)", ...style }}>
      <div style={{ display: "flex", flexDirection: "column", justifyContent: "space-between", gap: "var(--space-8)", flex: 1, minWidth: 0 }}>
        <span style={{ fontSize: "var(--fs-footnote)", color: "var(--accent-text)", display: "flex", alignItems: "center", gap: "var(--gap-cards)" }}><Icon name="pets" size={16} />{dog}</span>
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
          <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>Выход</span>
          <span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: "var(--fs-number-s)", lineHeight: 1 }}>{since}</span>
        </div>
        {size === "small" && verdict && <span style={{ fontSize: "var(--fs-footnote)" }}>{verdict}</span>}
      </div>
      {size === "medium" && <div style={{ display: "flex", flexDirection: "column", gap: "var(--gap-cards)", flex: 1, minWidth: 0, justifyContent: "flex-end" }}>
        {verdict && <span style={{ fontSize: "var(--fs-subheadline)" }}>{verdict}</span>}
        {next && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{next}</span>}
        <span style={{ minHeight: 40, borderRadius: "var(--radius-pill)", background: "var(--accent)", color: "var(--on-accent)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "var(--fs-subheadline)" }}>Вывожу</span>
      </div>}
    </div>
  );
}