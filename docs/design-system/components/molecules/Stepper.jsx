import React from "react";
import { IconButton } from "../atoms/IconButton.jsx";
export function Stepper({ value, onChange, min = -Infinity, max = Infinity, step = 1, unit, label, style }) {
  return (
    <div role="group" aria-label={label} style={{ display: "inline-flex", alignItems: "center", gap: "var(--space-8)", ...style }}>
      <IconButton icon="remove" label="Меньше" size="m" disabled={value <= min} onClick={() => onChange && onChange(Math.max(min, value - step))} />
      <div style={{ display: "flex", alignItems: "flex-start", gap: "var(--space-4)", fontFamily: "var(--font-rounded)", fontWeight: 300, minWidth: 64, justifyContent: "center" }}>
        <span style={{ fontSize: "var(--fs-number-m)", lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>{value}</span>
        {unit && <span style={{ fontSize: "var(--fs-subheadline)" }}>{unit}</span>}
      </div>
      <IconButton icon="add" label="Больше" size="m" disabled={value >= max} onClick={() => onChange && onChange(Math.min(max, value + step))} />
    </div>
  );
}