import React from "react";
import { Icon } from "../atoms/Icon.jsx";
const COLS = "max(56px, calc(var(--fs-subheadline) * 3)) 24px minmax(0,1fr)";
export function Timeline({ items = [], nowLabel, style }) {
  return (
    <ol style={{ listStyle: "none", margin: 0, padding: 0, display: "flex", flexDirection: "column", ...style }}>
      {items.map((it, i) => {
        if (it.type === "gap") return (
          <li key={i} style={{ display: "grid", gridTemplateColumns: COLS, gap: "var(--space-12)", minHeight: 36, alignItems: "center" }}>
            <span /><span style={{ justifySelf: "center", width: 2, height: "100%", backgroundImage: "linear-gradient(var(--separator) 50%, transparent 0)", backgroundSize: "2px 6px" }} />
            <span style={{ fontSize: "var(--fs-footnote)", color: it.warn ? "var(--status-warning)" : "var(--text-secondary)" }}>{it.label}</span>
          </li>
        );
        if (it.type === "now") return (
          <li key={i} style={{ display: "grid", gridTemplateColumns: COLS, gap: "var(--space-12)", alignItems: "center", minHeight: 28 }}>
            <span style={{ fontSize: "var(--fs-footnote)", color: "var(--accent-text)", textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{it.time}</span>
            <span style={{ justifySelf: "center", width: 10, height: 10, borderRadius: "50%", background: "var(--accent)" }} />
            <span style={{ height: 2, background: "var(--accent)", borderRadius: 1 }} />
          </li>
        );
        const tone = it.tone === "done" ? ["var(--accent-subtle)", "var(--accent-subtle-text)"] : it.tone === "overdue" ? ["var(--error-subtle)", "var(--status-error)"] : it.tone === "waiting" ? ["var(--warning-subtle)", "var(--status-warning)"] : ["var(--fill-2)", "var(--text-primary)"];
        return (
          <li key={i} onClick={it.onClick} style={{ display: "grid", gridTemplateColumns: COLS, gap: "var(--space-12)", alignItems: "stretch", cursor: it.onClick ? "pointer" : "default", opacity: it.deleted ? 0.5 : 1 }}>
            <span style={{ fontSize: "var(--fs-subheadline)", color: "var(--text-secondary)", textAlign: "right", fontVariantNumeric: "tabular-nums", paddingTop: "var(--space-16)" }}>{it.time}</span>
            <span style={{ position: "relative", display: "flex", justifyContent: "center" }}>
              <span style={{ position: "absolute", top: 0, bottom: 0, width: 2, background: "var(--separator)" }} />
              <span style={{ position: "relative", marginTop: "var(--space-8)", width: 24, height: 24, borderRadius: "50%", background: tone[0], display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 0 0 3px var(--bg-primary)" }}><Icon name={it.icon} size={14} color={tone[1]} /></span>
            </span>
            <div style={{ padding: "var(--space-8) 0 var(--space-12)", display: "flex", flexDirection: "column", gap: "var(--space-4)", minWidth: 0 }}>
              <div style={{ background: "var(--fill-1)", borderRadius: "var(--radius-row)", padding: "var(--space-12) var(--space-16)", boxShadow: "var(--elev-1)", display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
                <span style={{ fontSize: "var(--fs-body)", textDecoration: it.deleted ? "line-through" : "none", overflowWrap: "break-word" }}>{it.title}</span>
                {(it.detail || it.who) && <span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)", overflowWrap: "break-word" }}>{[it.detail, it.who].filter(Boolean).join(" · ")}</span>}
              </div>
            </div>
          </li>
        );
      })}
    </ol>
  );
}