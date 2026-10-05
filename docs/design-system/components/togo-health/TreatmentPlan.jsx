import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { Card } from "../molecules/Card.jsx";
import { CardHeader } from "../molecules/CardHeader.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function TreatmentPlan({ drug, dose, times = [], since, fasting, history = [], onChangeDose, onPause, style }) {
  return (
    <Card style={style}>
      <CardHeader icon="medication" tone="accent" kicker={"Лечение · с " + since} title={drug} trailing={<span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: "var(--fs-number-m)", lineHeight: 1, whiteSpace: "nowrap" }}>{dose}</span>} />
      <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--gap-cards)" }}>
        {times.map((t) => <span key={t} style={{ minHeight: 36, padding: "0 var(--space-16)", borderRadius: "var(--radius-pill)", background: "var(--fill-2)", display: "inline-flex", alignItems: "center", gap: "var(--space-4)", fontSize: "var(--fs-subheadline)", fontVariantNumeric: "tabular-nums" }}><Icon name="schedule" size={16} />{t}</span>)}
        {fasting && <span style={{ minHeight: 36, padding: "0 var(--space-16)", borderRadius: "var(--radius-pill)", background: "var(--warning-subtle)", color: "var(--status-warning)", display: "inline-flex", alignItems: "center", gap: "var(--space-4)", fontSize: "var(--fs-subheadline)" }}><Icon name="hourglass_top" size={16} />{fasting}</span>}
      </div>
      {history.length > 0 && <div style={{ display: "flex", flexDirection: "column" }}>
        <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)", paddingBottom: "var(--space-8)" }}>История дозы</span>
        {history.map((h, i) => (
          <div key={i} style={{ display: "grid", gridTemplateColumns: "16px minmax(0,1fr)", gap: "var(--space-12)" }}>
            <span style={{ position: "relative", display: "flex", justifyContent: "center" }}>
              {i < history.length - 1 && <span style={{ position: "absolute", top: 14, bottom: -2, width: 2, background: "var(--separator)" }} />}
              <span style={{ marginTop: "var(--space-8)", width: 10, height: 10, borderRadius: "50%", background: i === 0 ? "var(--accent-text)" : "var(--text-disabled)" }} />
            </span>
            <div style={{ display: "flex", flexWrap: "wrap", gap: "0 var(--space-8)", paddingBottom: "var(--space-12)" }}>
              <span style={{ fontSize: "var(--fs-body)", fontVariantNumeric: "tabular-nums" }}>{h.dose}</span>
              <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}>{h.date}{h.reason ? " · " + h.reason : ""}</span>
            </div>
          </div>
        ))}
      </div>}
      <ActionRow><Button variant="secondary" icon="edit" onClick={onChangeDose}>Изменить дозу</Button>{onPause && <Button variant="plain" onClick={onPause}>Приостановить</Button>}</ActionRow>
    </Card>
  );
}