import React from "react";
import { Icon } from "../atoms/Icon.jsx";
const T = {
  info: ["var(--fill-2)", "var(--text-primary)", "info"],
  success: ["var(--accent-subtle)", "var(--accent-subtle-text)", "check_circle"],
  warning: ["var(--warning-subtle)", "var(--status-warning)", "warning"],
  error: ["var(--error-subtle)", "var(--status-error)", "error"],
  neutral: ["var(--fill-sunken)", "var(--text-secondary)", "cloud_off"],
};
// StatusLine — одна строка состояния «Сегодня»: иконка · текст · действие-пилюля 44 справа.
export function StatusLine({ tone = "success", icon, text, actionLabel, actionIcon, onAction, style }) {
  const [bg, fg, ic] = T[tone];
  return (
    <div role={tone === "error" ? "alert" : "status"} style={{ background: bg, color: fg, borderRadius: "var(--radius-row)", minHeight: "var(--size-button)", padding: "var(--space-4) var(--space-4) var(--space-4) var(--space-16)", boxSizing: "border-box", display: "flex", alignItems: "center", gap: "var(--space-12)", ...style }}>
      <Icon name={icon || ic} size={22} color={fg} />
      <span style={{ flex: 1, minWidth: 0, padding: "var(--space-8) 0", fontSize: "var(--fs-subheadline)", lineHeight: "var(--lh-body)" }}>{text}</span>
      {actionLabel && <button type="button" onClick={onAction} style={{ border: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: "0 var(--space-16) 0 var(--space-12)", borderRadius: "var(--radius-pill)", background: tone === "success" ? "var(--glass-tint-accent)" : "var(--fill-1)", color: fg, display: "inline-flex", alignItems: "center", gap: "var(--space-8)", fontSize: "var(--fs-subheadline)", fontWeight: "var(--fw-semibold)", whiteSpace: "nowrap" }}>{actionIcon && <Icon name={actionIcon} size={18} color={fg} />}{actionLabel}</button>}
    </div>
  );
}
export function InlineAlert({ tone = "info", title, message, actionLabel, onAction, onClose, style }) {
  const [bg, fg, ic] = T[tone];
  return (
    <div role={tone === "error" || tone === "warning" ? "alert" : "status"} style={{ background: bg, borderRadius: "var(--radius-row)", padding: "var(--pad-inner) var(--pad-row)", display: "grid", gridTemplateColumns: "auto minmax(0,1fr) auto", gap: "var(--space-12)", alignItems: "start", ...style }}>
      <Icon name={ic} fill={tone === "success"} color={fg} />
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", minWidth: 0 }}>
        <span style={{ fontSize: "var(--fs-body)", color: "var(--text-primary)" }}>{title}</span>
        {message && <span style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.35, color: tone === "info" ? "var(--text-secondary)" : fg }}>{message}</span>}
        {actionLabel && <button type="button" onClick={onAction} style={{ alignSelf: "flex-start", border: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: "0 var(--space-16)", marginTop: "var(--space-4)", borderRadius: "var(--radius-pill)", background: "var(--fill-1)", color: "var(--text-primary)", fontSize: "var(--fs-subheadline)" }}>{actionLabel}</button>}
      </div>
      {onClose ? <button type="button" aria-label="Скрыть" onClick={onClose} style={{ border: "none", background: "none", cursor: "pointer", width: 44, height: 44, margin: "-12px -12px 0 0", display: "flex", alignItems: "center", justifyContent: "center", color: "var(--text-secondary)" }}><Icon name="close" size={20} /></button> : <span />}
    </div>
  );
}