import React from "react";
import { IconButton } from "../atoms/IconButton.jsx";
const p2 = (n) => String(n).padStart(2, "0");
export function TimeField({ value = "08:00", onChange, step = 5, quick = [], label, style }) {
  const [h, m] = value.split(":").map(Number);
  const set = (mins) => { const t = ((mins % 1440) + 1440) % 1440; onChange && onChange(p2(Math.floor(t / 60)) + ":" + p2(t % 60)); };
  const total = h * 60 + m;
  return (
    <div role="group" aria-label={label || "Время"} style={{ display: "flex", flexDirection: "column", gap: "var(--space-12)", ...style }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "var(--space-8)", background: "var(--fill-2)", borderRadius: "var(--radius-pill)", padding: "var(--space-4)" }}>
        <IconButton icon="remove" label={"Минус " + step + " минут"} size="m" onClick={() => set(total - step)} />
        <span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: "var(--fs-number-m)", lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>{p2(h)}:{p2(m)}</span>
        <IconButton icon="add" label={"Плюс " + step + " минут"} size="m" onClick={() => set(total + step)} />
      </div>
      {quick.length > 0 && <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--gap-cards)" }}>{quick.map((q) => (
        <button key={q.label} type="button" onClick={() => set(q.minutes)} style={{ border: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: "0 var(--space-16)", borderRadius: "var(--radius-pill)", background: "var(--fill-2)", color: "var(--text-primary)", fontSize: "var(--fs-subheadline)" }}>{q.label}</button>))}</div>}
    </div>
  );
}