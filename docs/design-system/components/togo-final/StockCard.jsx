import React from "react";
import { Icon } from "../atoms/Icon.jsx";
import { Button } from "../atoms/Button.jsx";
const LV = { ok: ["var(--accent)", "var(--accent-text)", "event_available"], low: ["var(--stock-low)", "var(--stock-low)", "schedule"], out: ["var(--stock-out)", "var(--stock-out)", "error"] };
export function stockLevel(daysLeft) { return daysLeft <= 3 ? "out" : daysLeft <= 7 ? "low" : "ok"; }
// Запас: остаток · «хватит до» · пилюли по дням. Оранжевый ≤ 7 дней, красный ≤ 3. «Купил» — только у low/out.
export function StockCard({ icon = "medication", name, perDay, left, unit, until, daysLeft = 14, total = 14, status, onBought, style }) {
  const lv = stockLevel(daysLeft), [pill, txt, sIcon] = LV[lv];
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-12)", padding: "var(--space-20)", borderRadius: "var(--radius-card)", background: "var(--fill-1)", boxShadow: "var(--elev-1)", ...style }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: "var(--space-8)" }}><span style={{ display: "flex", alignItems: "center", gap: "var(--space-8)", fontSize: "var(--fs-headline)", fontWeight: "var(--fw-semibold)" }}><Icon name={icon} size={22} />{name}</span>{perDay && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{perDay}</span>}</div>
      <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
        <span style={{ display: "flex", alignItems: "flex-start", gap: 2 }}><span style={{ fontFamily: "var(--font-rounded)", fontWeight: "var(--fw-number)", fontSize: "var(--fs-number-m)", lineHeight: 0.95, color: lv === "ok" ? "var(--text-primary)" : txt }}>{left}</span><span style={{ fontFamily: "var(--font-rounded)", fontSize: "var(--fs-subheadline)", color: "var(--accent-text)" }}>{unit}</span></span>
        <span style={{ display: "flex", flexDirection: "column", alignItems: "flex-end" }}><span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>хватит до</span><span style={{ fontSize: "var(--fs-callout)", fontWeight: "var(--fw-semibold)", color: lv === "ok" ? "var(--text-primary)" : txt }}>{until}</span></span>
      </div>
      <div style={{ display: "flex", gap: 3 }} aria-label={"осталось дней: " + daysLeft}>{Array.from({ length: total }, (_, i) => <span key={i} style={{ flex: 1, height: 8, borderRadius: "var(--radius-pill)", background: i < daysLeft ? pill : "var(--fill-3)" }} />)}</div>
      {(status || (onBought && lv !== "ok")) && <div style={{ display: "flex", alignItems: "center", gap: "var(--space-12)", flexWrap: "wrap" }}>
        {status && <span style={{ flex: 1, display: "flex", alignItems: "center", gap: 6, fontSize: "var(--fs-subheadline)", fontWeight: lv === "ok" ? 400 : "var(--fw-semibold)", color: lv === "ok" ? "var(--text-secondary)" : txt }}>{lv !== "ok" && <Icon name={sIcon} size={18} />}{status}</span>}
        {onBought && lv !== "ok" && <Button size="m" edge icon="add_shopping_cart" onClick={onBought}>Купил</Button>}
      </div>}
    </div>
  );
}