import React from "react";
import { Icon } from "../atoms/Icon.jsx";
// Карточка показания «Сегодня» T5+ (полоса — мотив «косточка»): подпись · число · полоса до следующего · «дальше». collapse 0…1 — сжатие при прокрутке ленты.
export function ReadingCard({ icon = "directions_walk", label, parts = [], tone = "default", bar, next, collapse = 0, style }) {
  const p = Math.max(0, Math.min(1, collapse)), L = (a, b) => a + (b - a) * p;
  const numC = tone === "timer" ? "var(--accent-text)" : tone === "muted" ? "var(--text-secondary)" : "var(--text-primary)";
  const unitC = tone === "default" ? "var(--accent-text)" : "var(--text-secondary)";
  const err = next && next.tone === "error";
  const barC = { accent: "var(--accent)", warning: "var(--status-warning)", muted: "var(--text-secondary)" }[(bar && bar.tone) || "accent"];
  return (
    <div style={{ display: "flex", flexDirection: "column", padding: L(20, 12) + "px " + L(20, 16) + "px", borderRadius: "var(--radius-card)", background: tone === "alarm" ? "var(--error-subtle)" : "var(--fill-1)", boxShadow: "var(--elev-1)", ...style }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", gap: "var(--space-12)" }}>
        <span style={{ display: "flex", flexDirection: "column", gap: 4, minWidth: 0 }}>
          <span style={{ display: "flex", alignItems: "center", gap: 6, fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)" }}><Icon name={icon} size={18} />{label}</span>
          <span style={{ display: "flex", alignItems: "flex-start", gap: 2, lineHeight: 1, color: numC }}>
            {parts.map((x, i) => <React.Fragment key={i}>{i > 0 && <span style={{ width: 6 }} />}<span style={{ fontFamily: "var(--font-rounded)", fontWeight: "var(--fw-number)", fontSize: L(72, 34), letterSpacing: "-0.035em", fontVariantNumeric: "tabular-nums" }}>{x.v}</span>{x.u && <span style={{ fontFamily: "var(--font-rounded)", fontSize: L(20, 15), color: unitC, paddingTop: 5 }}>{x.u}</span>}</React.Fragment>)}
          </span>
        </span>
        {next && <span style={{ display: "flex", flexDirection: "column", alignItems: "flex-end", gap: 2, opacity: Math.max(0, (p - 0.5) * 2), flexShrink: 0 }}><span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>дальше</span><span style={{ display: "flex", alignItems: "center", gap: 6, fontSize: "var(--fs-callout)", fontWeight: "var(--fw-semibold)", color: err ? "var(--status-error)" : "var(--text-primary)" }}><Icon name={next.icon} size={18} />{next.short}</span></span>}
      </div>
      <div style={{ maxHeight: L(160, 0), opacity: Math.max(0, 1 - p * 1.8), overflow: "hidden" }}>
        {bar && <div style={{ display: "flex", flexDirection: "column", gap: 6, paddingTop: "var(--space-16)" }}>
          <div role="progressbar" aria-valuenow={bar.pct} aria-valuemin={0} aria-valuemax={100} style={{ position: "relative", height: 8, margin: "5px 7px" }}><span style={{ position: "absolute", inset: 0, borderRadius: "var(--radius-pill)", background: "var(--fill-3)" }} /><span style={{ position: "absolute", left: -7, top: -5, width: 10, height: 10, borderRadius: "50%", background: barC }} /><span style={{ position: "absolute", left: -7, top: 3, width: 10, height: 10, borderRadius: "50%", background: barC }} /><span style={{ position: "absolute", right: -7, top: -5, width: 10, height: 10, borderRadius: "50%", background: "var(--fill-3)" }} /><span style={{ position: "absolute", right: -7, top: 3, width: 10, height: 10, borderRadius: "50%", background: "var(--fill-3)" }} /><span style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: bar.pct + "%", borderRadius: "var(--radius-pill)", background: barC }} /></div>
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}><span>{bar.from}</span><span>{bar.to}</span></div>
        </div>}
        {next && <div style={{ display: "flex", alignItems: "center", gap: "var(--space-12)", marginTop: "var(--space-16)", paddingTop: "var(--space-12)", borderTop: "1px solid var(--separator)" }}>
          <span style={{ width: 40, height: 40, flexShrink: 0, borderRadius: "50%", background: err ? "var(--status-error)" : "var(--accent)", color: err ? "var(--on-error)" : "var(--on-accent)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={next.icon} size={22} /></span>
          <span style={{ flex: 1, display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}><span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>дальше</span><span style={{ fontSize: "var(--fs-callout)", fontWeight: "var(--fw-semibold)", color: err ? "var(--status-error)" : "var(--text-primary)" }}>{next.title}</span></span>
          <span style={{ fontFamily: "var(--font-rounded)", fontSize: "var(--fs-callout)", color: "var(--text-secondary)", whiteSpace: "nowrap" }}>{next.when}</span>
        </div>}
      </div>
    </div>
  );
}