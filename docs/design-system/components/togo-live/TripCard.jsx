import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { CardHeader } from "../molecules/CardHeader.jsx";
import { SelectCircle } from "../atoms/SelectCircle.jsx";
export function TripCard({ place, dates, daysLeft, checklist = [], onToggle, style }) {
  const done = checklist.filter((c) => c.done).length;
  return (
    <Card gap={12} style={style}>
      <CardHeader icon="luggage" tone="accent" kicker={"Поездка · " + dates} title={place} trailing={daysLeft != null && <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}>через {daysLeft} дн.</span>} />
      {checklist.length > 0 && <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
        <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>С собой · {done} из {checklist.length}</span>
        {checklist.map((c, i) => (
          <button key={c.label} type="button" role="checkbox" aria-checked={c.done} onClick={() => onToggle && onToggle(i)} style={{ border: "none", background: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: 0, display: "grid", gridTemplateColumns: "26px minmax(0,1fr)", gap: "var(--space-12)", alignItems: "center", textAlign: "left", color: "var(--text-primary)", fontSize: "var(--fs-body)" }}>
            <SelectCircle checked={c.done} style={{ pointerEvents: "none" }} />
            <span style={{ textDecoration: c.done ? "line-through" : "none", color: c.done ? "var(--text-secondary)" : undefined }}>{c.label}</span>
          </button>
        ))}
      </div>}
    </Card>
  );
}