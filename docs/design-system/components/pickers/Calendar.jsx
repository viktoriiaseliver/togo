import React from "react";
import { Card } from "../molecules/Card.jsx";
import { IconButton } from "../atoms/IconButton.jsx";
const MONTHS = ["январь","февраль","март","апрель","май","июнь","июль","август","сентябрь","октябрь","ноябрь","декабрь"];
const WD = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"];
const same = (a, b) => a && b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
export function Calendar({ value, onChange, marks = {}, min, max, today = new Date(), style }) {
  const [view, setView] = React.useState(() => { const d = value || today; return new Date(d.getFullYear(), d.getMonth(), 1); });
  const y = view.getFullYear(), m = view.getMonth();
  const lead = (new Date(y, m, 1).getDay() + 6) % 7, days = new Date(y, m + 1, 0).getDate();
  const cells = [...Array(lead).fill(null), ...Array.from({ length: days }, (_, i) => new Date(y, m, i + 1))];
  const key = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  const off = (d) => (min && d < min) || (max && d > max);
  return (
    <Card pad={14} gap={10} style={style}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "var(--space-8)" }}>
        <span style={{ fontSize: "var(--fs-headline)", fontWeight: 600, paddingLeft: "var(--space-8)" }}>{MONTHS[m][0].toUpperCase() + MONTHS[m].slice(1)} {y}</span>
        <div style={{ display: "flex", gap: "var(--gap-cards)" }}><IconButton icon="chevron_left" label="Предыдущий месяц" size="m" onClick={() => setView(new Date(y, m - 1, 1))} /><IconButton icon="chevron_right" label="Следующий месяц" size="m" onClick={() => setView(new Date(y, m + 1, 1))} /></div>
      </div>
      <div role="grid" style={{ display: "grid", gridTemplateColumns: "repeat(7, minmax(0,1fr))", gap: "var(--space-4)" }}>
        {WD.map((w) => <span key={w} style={{ textAlign: "center", fontSize: "var(--fs-caption-1)", color: "var(--text-secondary)", padding: "var(--space-4) 0" }}>{w}</span>)}
        {cells.map((d, i) => {
          if (!d) return <span key={"e" + i} />;
          const sel = same(d, value), now = same(d, today), dis = off(d), mk = marks[key(d)];
          return (
            <button key={i} type="button" role="gridcell" aria-selected={sel} aria-label={d.getDate() + " " + MONTHS[m]} disabled={dis} onClick={() => onChange && onChange(d)}
              style={{ border: "none", cursor: dis ? "default" : "pointer", width: "100%", minWidth: 0, minHeight: "var(--size-hit)", borderRadius: "var(--radius-pill)", padding: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "var(--space-4)",
                fontSize: "var(--fs-subheadline)", fontVariantNumeric: "tabular-nums", background: sel ? "var(--accent)" : "transparent",
                color: dis ? "var(--text-disabled)" : sel ? "var(--on-accent)" : now ? "var(--accent-text)" : "var(--text-primary)", fontWeight: now || sel ? 600 : 400 }}>
              {d.getDate()}
              <span style={{ width: 5, height: 5, borderRadius: "50%", background: mk ? (mk === "overdue" ? "var(--status-error)" : sel ? "var(--on-accent)" : "var(--accent-text)") : "transparent" }} />
            </button>
          );
        })}
      </div>
    </Card>
  );
}