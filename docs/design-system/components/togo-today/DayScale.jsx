import React from "react";
// Шкала дня 6–22: выходы, дозы, натощак, инциденты, план. Для Истории и iPad.
const C = { outside: "var(--accent)", dose: "var(--text-primary)", fasting: "var(--status-warning)", incident: "var(--status-error)", plan: "var(--separator)" };
export function DayScale({ events = [], now, from = 6, to = 22, style }) {
  const x = (h) => ((h - from) / (to - from)) * 100 + "%";
  const ticks = []; for (let h = from; h <= to; h += 3) ticks.push(h);
  return (
    <div style={{ position: "relative", height: 104, borderRadius: "var(--radius-row)", background: "var(--fill-1)", boxShadow: "var(--elev-1)", overflow: "hidden", ...style }}>
      <div style={{ position: "absolute", left: 16, right: 16, top: 0, bottom: 0 }}>
        <div style={{ position: "absolute", left: 0, right: 0, top: 50, height: 2, borderRadius: 1, background: "var(--fill-2)" }} />
        {ticks.map((h) => <span key={h} style={{ position: "absolute", left: x(h), top: 68, transform: "translateX(-50%)", fontSize: "var(--fs-caption-1)", color: "var(--text-secondary)" }}>{h}</span>)}
        {events.map((e, i) => <span key={i} title={e.kind} style={{ position: "absolute", left: x(e.start), width: "calc(" + x(Math.max(e.end || e.start + 0.3, e.start + 0.3)) + " - " + x(e.start) + ")", minWidth: 12, top: e.kind === "fasting" ? 58 : 44, height: 12, borderRadius: "var(--radius-pill)", background: C[e.kind], boxShadow: e.kind === "plan" ? "inset 0 0 0 1.5px var(--text-secondary)" : "none" }} />)}
        {now != null && <span style={{ position: "absolute", left: x(now), top: 28, width: 2, height: 44, borderRadius: 1, background: "var(--text-primary)" }} />}
      </div>
    </div>
  );
}