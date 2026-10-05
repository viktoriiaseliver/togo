import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
import { ActionRow } from "../molecules/ActionRow.jsx";
export function OnboardingStep({ step = 1, total = 3, icon = "pets", title, body, primary, onPrimary, secondary, onSecondary, children, style }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-20)", ...style }}>
      <div role="progressbar" aria-valuenow={step} aria-valuemin={1} aria-valuemax={total} aria-label={"Шаг " + step + " из " + total} style={{ display: "flex", gap: "var(--gap-cards)" }}>
        {Array.from({ length: total }, (_, i) => <span key={i} style={{ flex: 1, height: 4, borderRadius: 2, background: i < step ? "var(--accent)" : "var(--fill-2)" }} />)}
      </div>
      <span style={{ width: 64, height: 64, borderRadius: "50%", background: "var(--accent-subtle)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={icon} size={32} color="var(--accent-subtle-text)" /></span>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)" }}>
        <span style={{ fontSize: "var(--fs-title-1)", lineHeight: 1.15 }}>{title}</span>
        {body && <span style={{ fontSize: "var(--fs-body)", lineHeight: 1.4, color: "var(--text-secondary)" }}>{body}</span>}
      </div>
      {children}
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--gap-cards)" }}>
        <ActionRow><Button onClick={onPrimary}>{primary}</Button></ActionRow>
        {secondary && <Button variant="plain" size="m" onClick={onSecondary}>{secondary}</Button>}
      </div>
    </div>
  );
}