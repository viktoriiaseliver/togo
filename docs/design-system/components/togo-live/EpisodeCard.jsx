import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { CardHeader } from "../molecules/CardHeader.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function EpisodeCard({ title = "Эпизод", started, count, signs = [], onAdd, onEnd, onCall, style }) {
  return (
    <Card tone="warning" gap={12} style={style}>
      <CardHeader icon="medical_services" tone="warning" kicker={"Идёт эпизод · с " + started} title={title} trailing={count != null && <span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: "var(--fs-number-m)", lineHeight: 1 }}>{count}</span>} />
      {signs.length > 0 && <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--gap-cards)" }}>{signs.map((s) => <span key={s} style={{ minHeight: 32, padding: "var(--space-4) var(--space-12)", borderRadius: "var(--radius-pill)", background: "var(--fill-1)", display: "inline-flex", alignItems: "center", fontSize: "var(--fs-footnote)" }}>{s}</span>)}</div>}
      <ActionRow><Button onClick={onAdd}>Ещё раз</Button>{onCall && <Button variant="destructive" icon="call" onClick={onCall}>Врачу</Button>}</ActionRow>
      {onEnd && <Button variant="plain" size="m" onClick={onEnd}>Эпизод закончился</Button>}
    </Card>
  );
}