import React from "react";
export function Slider({ value = 50, min = 0, max = 100, step = 1, onChange, label, format = (v) => v, marks, disabled = false, style }) {
  const p = ((value - min) / (max - min)) * 100;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)", ...style }}>
      {label && <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: "var(--space-8)", fontSize: "var(--fs-body)" }}><span>{label}</span><span style={{ color: "var(--accent-text)", fontVariantNumeric: "tabular-nums" }}>{format(value)}</span></div>}
      <div style={{ position: "relative", height: "var(--size-hit)", display: "flex", alignItems: "center" }}>
        <div style={{ position: "absolute", left: 0, right: 0, height: 8, borderRadius: "var(--radius-pill)", background: "var(--fill-track)" }} />
        <div style={{ position: "absolute", left: 0, width: p + "%", height: 8, borderRadius: "var(--radius-pill)", background: disabled ? "var(--text-disabled)" : "var(--accent)" }} />
        <div style={{ position: "absolute", left: "calc(" + p + "% - " + (p / 100) * 28 + "px)", width: 28, height: 28, borderRadius: "50%", background: "var(--control-knob)", boxShadow: "var(--shadow-knob)", pointerEvents: "none" }} />
        <input type="range" min={min} max={max} step={step} value={value} disabled={disabled} aria-label={label} onChange={(e) => onChange && onChange(Number(e.target.value))}
          style={{ position: "absolute", inset: 0, width: "100%", margin: 0, opacity: 0, cursor: disabled ? "default" : "pointer" }} />
      </div>
      {marks && <div style={{ display: "flex", justifyContent: "space-between", gap: "var(--space-8)", fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{marks.map((m) => <span key={m}>{m}</span>)}</div>}
    </div>
  );
}