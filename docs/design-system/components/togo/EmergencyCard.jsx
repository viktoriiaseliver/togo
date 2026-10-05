import React from "react";
import { Card } from "../molecules/Card.jsx";
import { Icon } from "../atoms/Icon.jsx";
export function EmergencyCard({ vetName, phone, callNow = [], watch = [], onCall, onReport, style }) {
  const List = ({ title, items, tone }) => (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--gap-cards)" }}>
      <span style={{ fontSize: "var(--fs-footnote)", color: tone }}>{title}</span>
      {items.map((t) => <span key={t} style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.35, display: "flex", gap: "var(--space-8)" }}><span style={{ color: tone }}>•</span>{t}</span>)}
    </div>
  );
  return (
    <Card gap={16} style={style}>
      <a href={phone ? "tel:" + phone.replace(/\s/g, "") : undefined} onClick={onCall} style={{ textDecoration: "none", minHeight: "var(--size-row)", borderRadius: "var(--radius-pill)", background: "var(--status-error)", color: "var(--on-error)", display: "flex", alignItems: "center", gap: "var(--space-12)", padding: "var(--space-8) var(--space-20) var(--space-8) var(--space-8)" }}>
        <span style={{ width: 48, height: 48, borderRadius: "50%", background: "var(--fill-on-color)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}><Icon name="call" fill /></span>
        <span style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", minWidth: 0 }}><span style={{ fontSize: "var(--fs-body)" }}>Позвонить врачу</span><span style={{ fontSize: "var(--fs-footnote)" }}>{vetName}{phone ? " · " + phone : ""}</span></span>
      </a>
      {callNow.length > 0 && <List title="Звони сейчас, если" items={callNow} tone="var(--status-error)" />}
      {watch.length > 0 && <List title="Можно наблюдать, если" items={watch} tone="var(--text-secondary)" />}
      {onReport && <button type="button" onClick={onReport} style={{ border: "none", cursor: "pointer", minHeight: "var(--size-button)", borderRadius: "var(--radius-pill)", background: "var(--fill-2)", color: "var(--text-primary)", display: "flex", alignItems: "center", justifyContent: "center", gap: "var(--space-8)", fontSize: "var(--fs-body)" }}><Icon name="description" size={20} />Ответы врачу из дневника</button>}
    </Card>
  );
}