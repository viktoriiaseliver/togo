import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function MorningBrief({ greeting = "Доброе утро", items = [], onOpen, onDismiss, style }) {
  return (
    <Card gap={12} style={style}>
      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-12)" }}><Icon name="wb_twilight" color="var(--accent-text)" /><span style={{ fontSize: "var(--fs-headline)", fontWeight: 600 }}>{greeting}</span></div>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)" }}>
        {items.map((t, i) => <div key={i} style={{ display: "grid", gridTemplateColumns: "auto minmax(0,1fr)", gap: "var(--space-12)", fontSize: "var(--fs-subheadline)", lineHeight: 1.35 }}><span style={{ color: "var(--text-secondary)" }}>•</span><span>{t}</span></div>)}
      </div>
      <ActionRow>{onOpen && <Button variant="secondary" size="m" onClick={onOpen}>Подробнее</Button>}{onDismiss && <Button variant="plain" size="m" onClick={onDismiss}>Понятно</Button>}</ActionRow>
    </Card>
  );
}