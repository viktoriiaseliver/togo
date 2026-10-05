import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function EscalationLadder({ steps = [], current = 0, onAck, style }) {
  return (
    <Card gap={14} style={style}>
      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-12)" }}><Icon name="notifications_active" color="var(--status-error)" /><span style={{ fontSize: "var(--fs-headline)", fontWeight: 600 }}>Доза не отмечена</span></div>
      <ol style={{ listStyle: "none", margin: 0, padding: 0, display: "flex", flexDirection: "column", gap: 0 }}>
        {steps.map((s, i) => {
          const done = i < current, now = i === current;
          return (
            <li key={i} style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-4) var(--space-12)", alignItems: "flex-start", paddingBottom: i < steps.length - 1 ? 12 : 0 }}>
              <span style={{ width: 28, height: 28, flexShrink: 0, borderRadius: "50%", display: "flex", alignItems: "center", justifyContent: "center", fontSize: "var(--fs-footnote)",
                background: done ? "var(--fill-2)" : now ? "var(--status-error)" : "transparent", color: done ? "var(--text-secondary)" : now ? "var(--on-error)" : "var(--text-secondary)", boxShadow: done || now ? "none" : "inset 0 0 0 1.5px var(--text-disabled)" }}>{done ? <Icon name="check" size={16} /> : i + 1}</span>
              <span style={{ flex: "1 1 0", minWidth: "min(100%, calc(var(--fs-body) * 6))", display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
                <span style={{ fontSize: "var(--fs-body)", color: done ? "var(--text-secondary)" : "var(--text-primary)" }}>{s.who}</span>
                <span style={{ fontSize: "var(--fs-footnote)", color: now ? "var(--status-error)" : "var(--text-secondary)" }}>{s.how}</span>
              </span>
              <span style={{ marginLeft: "auto", fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)", fontVariantNumeric: "tabular-nums" }}>{s.time}</span>
            </li>
          );
        })}
      </ol>
      <ActionRow><Button onClick={onAck}>Я дал</Button></ActionRow>
    </Card>
  );
}