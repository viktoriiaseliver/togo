import React from "react";
import { Card } from "../molecules/Card.jsx";
const H = 96;
export function WeekChart({ data = [], unit = "", target, style }) {
  const max = Math.max(1, target || 0, ...data.map((d) => d.value || 0));
  return (
    <Card pad="var(--space-16)" gap={0} style={style}>
      <div role="img" aria-label={data.map((d) => d.label + " " + (d.value ?? "нет данных") + " " + unit).join(", ")}
        style={{ display: "grid", gridTemplateColumns: `repeat(${data.length}, minmax(0,1fr))`, columnGap: "var(--gap-cards)", rowGap: "var(--space-8)", alignItems: "end" }}>
        {data.map((d, i) => <span key={"v" + i} style={{ textAlign: "center", fontSize: "var(--fs-caption-1)", color: "var(--text-secondary)", fontVariantNumeric: "tabular-nums" }}>{d.value ?? "—"}</span>)}
        {data.map((d, i) => (
          <div key={"b" + i} style={{ position: "relative", height: H, display: "flex", alignItems: "flex-end", justifyContent: "center" }}>
            {target != null && <span aria-hidden="true" style={{ position: "absolute", left: "calc(var(--gap-cards) / -2)", right: "calc(var(--gap-cards) / -2)", bottom: (target / max) * H, borderTop: "1.5px dashed var(--text-disabled)" }} />}
            <div style={{ width: "100%", maxWidth: 28, height: d.value ? Math.max(8, (d.value / max) * H) : 8, borderRadius: "var(--radius-pill)", background: d.value == null ? "var(--fill-2)" : d.active ? "var(--accent)" : "var(--fill-3)" }} />
          </div>
        ))}
        {data.map((d, i) => <span key={"l" + i} style={{ textAlign: "center", fontSize: "var(--fs-caption-1)", color: d.active ? "var(--accent-text)" : "var(--text-secondary)" }}>{d.label}</span>)}
      </div>
    </Card>
  );
}
