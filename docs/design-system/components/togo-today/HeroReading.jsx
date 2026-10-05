import React from "react";
// Показание «Сегодня»: подпись · число SF Pro Rounded 300 · пояснение. VoiceOver читает одним элементом.
export function HeroReading({ label, value, sub, variant = "default", size = "phone", style }) {
  const fs = { phone: "var(--fs-number-hero)", pad: "var(--fs-number-hero-pad)", compact: "var(--fs-number-xl)" }[size];
  const color = variant === "night" || variant === "empty" ? "var(--text-secondary)" : variant === "timer" ? "var(--accent-text)" : "var(--text-primary)";
  return (
    <div role="text" aria-label={[label, value, sub].filter(Boolean).join(", ")} style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", ...style }}>
      {label && <span style={{ fontSize: "var(--fs-headline)", color: "var(--text-secondary)" }}>{label}</span>}
      <span style={{ fontFamily: "var(--font-rounded)", fontWeight: "var(--fw-number)", fontSize: fs, lineHeight: 1, letterSpacing: "-0.02em", fontVariantNumeric: "tabular-nums", color, whiteSpace: "nowrap" }}>{variant === "empty" ? "—" : value}</span>
      {sub && <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}>{sub}</span>}
    </div>
  );
}