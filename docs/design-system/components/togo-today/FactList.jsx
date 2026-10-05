import React from "react";
import { Icon } from "../atoms/Icon.jsx";
// «Сегодня»: 1–2 последние записи. Строка 52, тап — изменить.
export function FactList({ items = [], onPress, style }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", borderRadius: "var(--radius-row)", background: "var(--fill-1)", boxShadow: "var(--elev-1)", overflow: "hidden", ...style }}>
      {items.map((it, i) => (
        <button key={i} type="button" onClick={() => onPress && onPress(it, i)} style={{ border: "none", background: "none", cursor: "pointer", color: "var(--text-primary)", textAlign: "left", minHeight: "var(--size-button)", padding: "0 var(--space-12) 0 var(--space-16)", display: "grid", gridTemplateColumns: "48px minmax(0,1fr) auto 20px", gap: "var(--space-8)", alignItems: "center", fontSize: "var(--fs-callout)", borderTop: i ? "1px solid var(--separator)" : "none" }}>
          <span style={{ color: "var(--text-secondary)", fontVariantNumeric: "tabular-nums" }}>{it.time}</span>
          <span style={{ minWidth: 0 }}>{it.what}</span>
          <span style={{ color: "var(--text-secondary)", fontSize: "var(--fs-subheadline)", display: "inline-flex", alignItems: "center", gap: 4 }}>{it.pending && <Icon name="cloud_off" size={16} />}{it.pending ? "не отправлено" : it.who}</span>
          <Icon name="chevron_right" size={20} color="var(--text-secondary)" />
        </button>
      ))}
    </div>
  );
}