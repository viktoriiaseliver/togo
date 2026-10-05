import React from "react";
import { Icon } from "../atoms/Icon.jsx";
const TONE = { walk: ["var(--accent-subtle)", "var(--accent-subtle-text)"], incident: ["var(--error-subtle)", "var(--status-error)"], warning: ["var(--warning-subtle)", "var(--status-warning)"], default: ["var(--fill-2)", "var(--text-primary)"] };
// Строка ленты «Сегодня» / «День по часам»: кружок-иконка · заголовок · количество акцентом + «· кто» · время.
export function FeedRow({ icon, kind = "default", title, value, detail, who, time, last = false, onClick, style }) {
  const [bg, fg] = TONE[kind] || TONE.default;
  const rest = [detail, who].filter(Boolean).join(" · ");
  return (
    <div onClick={onClick} role={onClick ? "button" : undefined} style={{ display: "grid", gridTemplateColumns: "32px minmax(0,1fr) auto", gap: "var(--space-12)", cursor: onClick ? "pointer" : undefined, ...style }}>
      <span style={{ position: "relative", display: "flex", justifyContent: "center" }}>{!last && <span style={{ position: "absolute", top: 32, bottom: 0, width: 2, background: "var(--fill-3)" }} />}<span style={{ position: "relative", width: 32, height: 32, borderRadius: "50%", background: bg, color: fg, display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={icon} size={18} /></span></span>
      <span style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0, padding: "5px 0 var(--space-16)" }}><span style={{ fontSize: "var(--fs-callout)", color: kind === "incident" ? "var(--status-error)" : "var(--text-primary)" }}>{title}</span>{(value || rest) && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{value && <span style={{ fontFamily: "var(--font-rounded)", color: "var(--accent-text)" }}>{value} </span>}{rest}</span>}</span>
      <span style={{ paddingTop: 6, fontSize: "var(--fs-footnote)", color: "var(--text-secondary)", fontVariantNumeric: "tabular-nums" }}>{time}</span>
    </div>
  );
}