import React from "react";
const T = {
  accent: ["var(--accent-subtle)", "var(--accent-subtle-text)"],
  neutral: ["var(--fill-2)", "var(--text-primary)"],
  warning: ["var(--warning-subtle)", "var(--status-warning)"],
  error: ["var(--error-subtle)", "var(--status-error)"],
};
export function Badge({ tone = "neutral", children, style }) {
  const [bg, fg] = T[tone];
  return <span style={{ minHeight: 28, padding: "0 var(--space-12)", borderRadius: "var(--radius-pill)", background: bg, color: fg, display: "inline-flex", alignItems: "center", fontSize: "var(--fs-footnote)", ...style }}>{children}</span>;
}