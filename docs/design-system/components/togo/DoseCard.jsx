import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
const S = {
  due: { label: "Пора дать", fg: "var(--accent-text)" },
  taken: { label: "Дано", fg: "var(--accent-subtle-text)" },
  overdue: { label: "Пропущена", fg: "var(--status-error)" },
  waiting: { label: "Окно натощак", fg: "var(--status-warning)" },
};
export function DoseCard({ state = "due", name, dose, time, note, onGive, onUndo, style }) {
  const s = S[state];
  const bg = state === "taken" ? "var(--accent-subtle)" : state === "overdue" ? "var(--error-subtle)" : state === "waiting" ? "var(--warning-subtle)" : "var(--fill-1)";
  return (
    <div style={{ background: bg, borderRadius: "var(--radius-card)", padding: "var(--pad-card)", display: "flex", flexDirection: "column", gap: "var(--space-12)", boxShadow: state === "due" ? "var(--elev-1)" : "none", ...style }}>
      <div style={{ display: "flex", justifyContent: "space-between", gap: "var(--space-12)", alignItems: "flex-start", flexWrap: "wrap" }}>
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", minWidth: 0 }}>
          <span style={{ fontSize: "var(--fs-footnote)", color: s.fg, display: "flex", alignItems: "center", gap: "var(--gap-cards)" }}><Icon name={state === "taken" ? "check_circle" : state === "overdue" ? "error" : state === "waiting" ? "hourglass_top" : "medication"} size={16} fill={state === "taken"} />{s.label}</span>
          <span style={{ fontSize: "var(--fs-title-3)", lineHeight: 1.2, overflowWrap: "break-word" }}>{name}</span>
          <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}>{dose}</span>
        </div>
        <span style={{ fontFamily: "var(--font-rounded)", fontWeight: 300, fontSize: "var(--fs-number-m)", lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>{time}</span>
      </div>
      {note && <span style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.35, color: state === "waiting" ? "var(--status-warning)" : "var(--text-secondary)" }}>{note}</span>}
      {state === "taken" ? onUndo && <ActionRow><Button variant="secondary" size="m" onClick={onUndo}>Не давал</Button></ActionRow>
        : <ActionRow><Button variant={state === "overdue" ? "destructive-filled" : "primary"} onClick={onGive}>{state === "overdue" ? "Дал сейчас" : "Дал"}</Button></ActionRow>}
    </div>
  );
}