import React from "react";
import { Icon } from "../atoms/Icon.jsx";
const T = { accent: ["var(--accent-subtle)", "var(--accent-subtle-text)", "var(--accent-text)"], warning: ["var(--warning-subtle)", "var(--status-warning)", "var(--status-warning)"], error: ["var(--error-subtle)", "var(--status-error)", "var(--status-error)"], neutral: ["var(--fill-2)", "var(--text-primary)", "var(--text-secondary)"] };
export function CardHeader({ icon, avatar, tone = "neutral", kicker, title, subtitle, trailing, style }) {
  const [bg, fg, k] = T[tone] || T.neutral;
  return (
    <div style={{ display: "flex", flexWrap: "wrap", alignItems: "flex-start", gap: "var(--space-8) var(--space-12)", ...style }}>
      {(icon || avatar) && <span style={{ width: avatar ? 52 : 44, height: avatar ? 52 : 44, flexShrink: 0, borderRadius: "50%", background: bg, display: "flex", alignItems: "center", justifyContent: "center" }}>{avatar || <Icon name={icon} color={fg} />}</span>}
      <div lang="ru" style={{ flex: "1 1 0", minWidth: kicker ? "min(100%, calc(var(--fs-title-3) * 7))" : "min(100%, calc(var(--fs-body) * 6))", display: "flex", flexDirection: "column", gap: "var(--space-4)" }}>
        {kicker && <span style={{ fontSize: "var(--fs-footnote)", color: k }}>{kicker}</span>}
        <span style={{ fontSize: kicker ? "var(--fs-title-3)" : "var(--fs-headline)", fontWeight: kicker ? 400 : 600, lineHeight: 1.2, overflowWrap: "break-word", hyphens: "auto" }}>{title}</span>
        {subtitle && <span style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.4, color: "var(--text-secondary)" }}>{subtitle}</span>}
      </div>
      {trailing && <div style={{ marginLeft: "auto", flexShrink: 0 }}>{trailing}</div>}
    </div>
  );
}