import React from "react";
import { Icon } from "../atoms/Icon.jsx";

export function ListRow({ icon, title, subtitle, value, trailing, chevron = false, leading, iconTone, subtitleTone, destructive = false, onClick, style }) {
  return (
    <div onClick={onClick} role={onClick ? "button" : undefined}
      style={{ display: "flex", flexWrap: "wrap", alignItems: "center", justifyContent: destructive ? "center" : undefined, gap: "var(--space-8) var(--space-12)", minHeight: "var(--size-row)", padding: "var(--pad-row-y) var(--pad-row)",
        background: "var(--fill-1)", borderRadius: "var(--radius-row)", boxSizing: "border-box", boxShadow: "var(--elev-1)", cursor: onClick ? "pointer" : "default", ...style }}>
      {leading}
      {icon && <div style={{ width: 40, height: 40, borderRadius: "50%", background: iconTone === "error" ? "var(--error-subtle)" : iconTone === "warning" ? "var(--warning-subtle)" : iconTone === "accent" ? "var(--accent-subtle)" : "var(--fill-2)", color: iconTone === "error" ? "var(--status-error)" : iconTone === "warning" ? "var(--status-warning)" : iconTone === "accent" ? "var(--accent-subtle-text)" : undefined, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}><Icon name={icon} size={22} /></div>}
      {destructive ? <span style={{ fontSize: "var(--fs-body)", color: "var(--status-error)" }}>{title}</span> : (
        <div style={{ flex: "1 1 0", minWidth: "min(100%, calc(var(--fs-body) * 6))", display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
          <span style={{ fontSize: "var(--fs-body)", overflowWrap: "break-word" }}>{title}</span>
          {subtitle && <span style={{ fontSize: "var(--fs-footnote)", color: subtitleTone === "accent" ? "var(--accent-text)" : "var(--text-secondary)", fontVariantNumeric: "tabular-nums" }}>{subtitle}</span>}
        </div>
      )}
      {(value || trailing || chevron) && <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: "var(--space-12)", flexShrink: 0 }}>
        {value && <span style={{ fontSize: "var(--fs-body)", color: "var(--text-secondary)" }}>{value}</span>}
        {trailing}
        {chevron && <Icon name="chevron_right" size={20} color="var(--text-secondary)" />}
      </div>}
    </div>
  );
}