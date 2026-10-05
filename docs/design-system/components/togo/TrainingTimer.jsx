import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function TrainingTimer({ skill, elapsed = "00:00", lastDelayMs, overLimit = false, reps = 0, onMarker, onFinish, style }) {
  const good = lastDelayMs != null && lastDelayMs <= 1000;
  return (
    <Card gap={14} style={style}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: "var(--space-8)" }}>
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", minWidth: 0 }}>
          <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>Занятие</span>
          <span style={{ fontSize: "var(--fs-title-3)", lineHeight: 1.2 }}>{skill}</span>
        </div>
        <span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: "var(--fs-number-m)", lineHeight: 1, fontVariantNumeric: "tabular-nums", color: overLimit ? "var(--text-disabled)" : undefined }}>{elapsed}</span>
      </div>
      <button type="button" onClick={onMarker} aria-label="Маркер" style={{ border: "none", cursor: "pointer", minHeight: 96, borderRadius: "var(--radius-pill)", background: "var(--accent)", color: "var(--on-accent)", fontSize: "var(--fs-title-2)" }}>Маркер</button>
      <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: "var(--space-4) var(--space-12)", fontSize: "var(--fs-subheadline)" }}>
        <span style={{ color: "var(--text-secondary)" }}>Повторов: {reps}</span>
        {lastDelayMs != null && <span style={{ color: good ? "var(--accent-text)" : "var(--status-warning)" }}>Задержка {lastDelayMs} мс{good ? "" : " · поздно"}</span>}
      </div>
      {overLimit && <span style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.35, color: "var(--text-secondary)" }}>Больше трёх минут — прогресс дальше не пишется. Закончи на удачном повторе.</span>}
      <ActionRow><Button variant="secondary" onClick={onFinish}>Закончить</Button></ActionRow>
    </Card>
  );
}