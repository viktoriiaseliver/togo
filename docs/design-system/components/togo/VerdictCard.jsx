import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
const V = {
  urgent: { title: "Срочно просится", icon: "priority_high", bg: "var(--error-subtle)", fg: "var(--status-error)" },
  likely: { title: "Похоже на нужду", icon: "pets", bg: "var(--accent-subtle)", fg: "var(--accent-subtle-text)" },
  unclear: { title: "Непонятно", icon: "help", bg: "var(--fill-2)", fg: "var(--text-secondary)" },
  attention: { title: "Скорее хочет внимания", icon: "favorite", bg: "var(--fill-2)", fg: "var(--text-primary)" },
  episode: { title: "Похоже на эпизод", icon: "medical_services", bg: "var(--warning-subtle)", fg: "var(--status-warning)" },
};
export function VerdictCard({ outcome = "unclear", reason, onWalkOut, onLater, style }) {
  const v = V[outcome];
  return (
    <div role="region" aria-label={v.title} style={{ background: "var(--fill-1)", borderRadius: "var(--radius-card)", padding: "var(--pad-card)", display: "flex", flexDirection: "column", gap: "var(--space-16)", boxShadow: "var(--elev-1)", ...style }}>
      <div style={{ display: "flex", gap: "var(--space-12)", alignItems: "flex-start" }}>
        <div style={{ width: 44, height: 44, borderRadius: "50%", background: v.bg, flexShrink: 0, display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={v.icon} color={v.fg} /></div>
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", minWidth: 0 }}>
          <span style={{ fontSize: "var(--fs-title-3)", lineHeight: 1.2 }}>{v.title}</span>
          {reason && <span style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.35, color: "var(--text-secondary)", textWrap: "pretty" }}>{reason}</span>}
        </div>
      </div>
      <ActionRow><Button onClick={onWalkOut}>Вывожу</Button>{onLater && <Button variant="secondary" onClick={onLater}>Не сейчас</Button>}</ActionRow>
    </div>
  );
}