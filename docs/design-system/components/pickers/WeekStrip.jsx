import React from "react";
const WD = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"];
export function WeekStrip({ value, onChange, today = new Date(), marks = {}, style }) {
  const sel = value || today;
  const start = new Date(sel); start.setDate(sel.getDate() - ((sel.getDay() + 6) % 7));
  const days = Array.from({ length: 7 }, (_, i) => { const d = new Date(start); d.setDate(start.getDate() + i); return d; });
  const same = (a, b) => a.toDateString() === b.toDateString();
  const key = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  return (
    <div role="tablist" style={{ display: "grid", gridTemplateColumns: "repeat(7, minmax(0,1fr))", gap: "var(--space-4)", ...style }}>
      {days.map((d, i) => {
        const on = same(d, sel), now = same(d, today), fut = d > today && !now, mk = marks[key(d)];
        return (
          <button key={i} type="button" role="tab" aria-selected={on} disabled={fut} onClick={() => onChange && onChange(d)}
            style={{ border: "none", cursor: fut ? "default" : "pointer", minHeight: "var(--size-row)", borderRadius: "var(--radius-pill)", padding: "var(--space-8) 0", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "var(--space-4)",
              background: on ? "var(--accent)" : "var(--fill-1)", color: fut ? "var(--text-disabled)" : on ? "var(--on-accent)" : "var(--text-primary)", boxShadow: on ? "none" : "var(--elev-1)" }}>
            <span style={{ fontSize: "var(--fs-caption-1)", color: on ? "var(--on-accent)" : fut ? "var(--text-disabled)" : "var(--text-secondary)" }}>{WD[i]}</span>
            <span style={{ fontSize: "var(--fs-subheadline)", fontWeight: now ? 600 : 400, fontVariantNumeric: "tabular-nums" }}>{d.getDate()}</span>
            <span style={{ width: 5, height: 5, borderRadius: "50%", background: mk ? (mk === "overdue" ? "var(--status-error)" : on ? "var(--on-accent)" : "var(--accent-text)") : "transparent" }} />
          </button>
        );
      })}
    </div>
  );
}