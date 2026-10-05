import React from "react";
import { Icon } from "../atoms/Icon.jsx";
const box = { borderRadius: "var(--radius-card)", padding: "var(--pad-card)", minHeight: 190, boxSizing: "border-box", display: "flex", flexDirection: "column", justifyContent: "space-between", gap: "var(--space-12)" };
export function DeviceCard({ variant = "default", title, subtitle, subtitleTone, children, onClick, style }) {
  if (variant === "add") return (
    <div onClick={onClick} style={{ ...box, background: "var(--fill-sunken)", alignItems: "center", justifyContent: "center", textAlign: "center", cursor: "pointer", ...style }}>
      <div style={{ width: 44, height: 44, borderRadius: "50%", background: "var(--fill-1)", boxShadow: "var(--elev-1)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name="add" size={22} color="var(--accent-text)" /></div>
      <span style={{ fontSize: "var(--fs-subheadline)" }}>{title || "Добавить устройство"}</span>
    </div>
  );
  if (variant === "loading") return (
    <div aria-busy="true" style={{ ...box, background: "var(--fill-1)", boxShadow: "var(--elev-1)", ...style }}>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-8)" }}><div style={{ height: 14, width: "70%", borderRadius: "var(--radius-pill)", background: "var(--fill-2)" }} /><div style={{ height: 10, width: "45%", borderRadius: "var(--radius-pill)", background: "var(--fill-2)" }} /></div>
      <div style={{ height: 44, width: "55%", borderRadius: "var(--radius-pill)", background: "var(--fill-2)" }} />
      <div style={{ height: 36, width: 64, borderRadius: "var(--radius-pill)", background: "var(--fill-2)" }} />
    </div>
  );
  const inv = variant === "inverse", off = variant === "offline";
  const subColor = subtitleTone === "error" || off ? "var(--status-error)" : subtitleTone === "secondary" ? "var(--text-secondary)" : inv ? "var(--on-inverse)" : "var(--accent-text)";
  return (
    <div onClick={onClick} style={{ ...box, background: inv ? "var(--fill-inverse)" : "var(--fill-1)", color: inv ? "var(--on-inverse)" : "var(--text-primary)", boxShadow: inv ? "none" : "var(--elev-1)", cursor: onClick ? "pointer" : "default", ...style }}>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
        <span style={{ fontSize: "var(--fs-title-3)", lineHeight: 1.15, color: off ? "var(--text-secondary)" : undefined }}>{title}</span>
        {subtitle && <span style={{ fontSize: "var(--fs-footnote)", color: subColor }}>{subtitle}</span>}
      </div>
      {children}
    </div>
  );
}