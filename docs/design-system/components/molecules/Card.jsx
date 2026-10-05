import React from "react";
export function Card({ tone = "default", pad, gap = 12, as = "div", children, style, ...rest }) {
  const T = { default: ["var(--fill-1)", "var(--elev-1)"], subtle: ["var(--accent-subtle)", "none"], warning: ["var(--warning-subtle)", "none"], error: ["var(--error-subtle)", "none"], inverse: ["var(--fill-inverse)", "none"] }[tone];
  return React.createElement(as, { ...rest, style: { background: T[0], boxShadow: T[1], borderRadius: "var(--radius-card)", padding: pad ?? "var(--pad-card)", display: "flex", flexDirection: "column", gap, minWidth: 0, color: tone === "inverse" ? "var(--on-inverse)" : undefined, ...style } }, children);
}