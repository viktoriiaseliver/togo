import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
// Запас лекарства или корма. Полоса всегда акцентная — срочность передаёт StatusLine.
export function StockMeter({ icon = "medication", name, left, unit, until, perDay, pct = 0, onBought, style }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-12)", padding: "var(--space-20)", borderRadius: "var(--radius-card)", background: "var(--fill-1)", boxShadow: "var(--elev-1)", ...style }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: "var(--space-8)" }}><span style={{ display: "flex", alignItems: "center", gap: "var(--space-8)", fontSize: "var(--fs-headline)", fontWeight: "var(--fw-semibold)" }}><Icon name={icon} size={22} color="var(--accent-text)" />{name}</span>{perDay && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{perDay}</span>}</div>
      <div style={{ display: "flex", alignItems: "baseline", gap: "var(--space-8)" }}><span style={{ fontFamily: "var(--font-rounded)", fontWeight: "var(--fw-number)", fontSize: "var(--fs-number-l)", lineHeight: 1 }}>{left}</span><span style={{ fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}>{unit}{until ? " · до " + until : ""}</span></div>
      <div role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100} style={{ height: 8, borderRadius: "var(--radius-pill)", background: "var(--fill-2)", overflow: "hidden" }}><div style={{ width: pct + "%", height: "100%", borderRadius: "var(--radius-pill)", background: "var(--accent)" }} /></div>
      {onBought && <Button variant="secondary" edge icon="add_shopping_cart" onClick={onBought}>Купил</Button>}
    </div>
  );
}