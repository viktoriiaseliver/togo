import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function MergeCard({ title = "Две записи об одном?", first, second, onMerge, onKeep, style }) {
  const Line = ({ e }) => <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: "var(--space-4) var(--space-8)", fontSize: "var(--fs-subheadline)" }}><span style={{ minWidth: 0, overflowWrap: "break-word" }}>{e.what} · {e.who}</span><span style={{ color: "var(--text-secondary)", fontVariantNumeric: "tabular-nums", flexShrink: 0 }}>{e.time}</span></div>;
  return (
    <Card gap={12} style={style}>
      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-12)" }}><Icon name="call_merge" color="var(--accent-text)" /><span style={{ fontSize: "var(--fs-headline)", fontWeight: 600 }}>{title}</span></div>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)", background: "var(--fill-2)", borderRadius: "var(--radius-inner)", padding: "var(--space-12) var(--space-16)" }}><Line e={first} /><div style={{ height: 1, background: "var(--separator)" }} /><Line e={second} /></div>
      <ActionRow><Button size="m" onClick={onMerge}>Объединить</Button><Button size="m" variant="secondary" onClick={onKeep}>Оставить обе</Button></ActionRow>
    </Card>
  );
}