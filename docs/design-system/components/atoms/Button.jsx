import React from "react";
import { Icon } from "./Icon.jsx";

const V = {
  primary: ["var(--accent)", "var(--on-accent)", "var(--accent-pressed)"],
  secondary: ["var(--fill-2)", "var(--text-primary)", "var(--fill-3)"],
  tinted: ["var(--accent-subtle)", "var(--accent-subtle-text)", "var(--fill-3)"],
  destructive: ["var(--fill-2)", "var(--status-error)", "var(--fill-3)"],
  "destructive-filled": ["var(--status-error)", "var(--on-error)", "var(--status-error)"],
  surface: ["var(--fill-1)", "var(--text-primary)", "var(--fill-3)"],
  plain: ["transparent", "var(--accent-text)", "transparent"],
};
const S = {
  s: { h: "var(--size-hit)", px: 12, fs: "var(--fs-footnote)", ic: 18 },
  m: { h: "var(--size-hit)", px: 16, fs: "var(--fs-subheadline)", ic: 18 },
  l: { h: "var(--size-button)", px: 20, fs: "var(--fs-body)", ic: 20 },
  xl: { h: "var(--size-button-xl)", px: 24, fs: "var(--fs-headline)", ic: 24 },
};
const EDGE = { primary: "var(--accent-edge)", secondary: "var(--fill-edge)", tinted: "var(--fill-edge)", surface: "var(--fill-edge)", destructive: "var(--fill-edge)", "destructive-filled": "var(--error-edge)" };
export function Button({ variant = "primary", size = "l", icon, iconPosition = "leading", label, selected = false, loading = false, disabled = false, fullWidth = false, edge = false, color, onClick, children, style }) {
  const [down, setDown] = React.useState(false);
  const s = S[size] || S.l;
  const iconOnly = !children && !!icon;
  const [bg, fg, pr] = V[variant] || V.primary;
  const off = disabled && !loading;
  const ink = off ? "var(--text-disabled)" : selected ? "var(--accent-text)" : color || fg;
  const fill = off ? (variant === "plain" ? "transparent" : "var(--fill-sunken)") : selected ? "var(--fill-selected)" : down ? pr : bg;
  const eh = size === "xl" ? "var(--edge-height)" : "var(--edge-height-s)";
  const hasEdge = edge && !off && EDGE[variant];
  const shadow = hasEdge ? (down ? "none" : `0 ${eh} 0 ${EDGE[variant]}`) : variant === "surface" && !off && !down ? (selected ? "inset 0 0 0 1px var(--separator)" : "var(--elev-1)") : "none";
  const ic = <Icon name={loading ? "progress_activity" : icon} size={iconOnly && size !== "s" ? s.ic + 2 : s.ic} weight={loading ? 400 : 300} fill={selected} />;
  return (
    <button type="button" aria-label={iconOnly ? label : undefined} aria-busy={loading || undefined} aria-pressed={selected || undefined} disabled={disabled || loading} onClick={onClick}
      onPointerDown={() => setDown(true)} onPointerUp={() => setDown(false)} onPointerLeave={() => setDown(false)}
      style={{ border: "none", cursor: off ? "default" : "pointer", boxSizing: "border-box", flexShrink: iconOnly ? 0 : undefined,
        minHeight: s.h, minWidth: s.h, width: iconOnly ? s.h : fullWidth ? "100%" : undefined, height: iconOnly ? s.h : undefined, maxWidth: "100%",
        padding: iconOnly ? 0 : variant === "plain" ? "0 var(--space-4)" : `var(--space-8) var(--space-${s.px})`, borderRadius: "var(--radius-pill)",
        display: "inline-flex", flexDirection: iconPosition === "trailing" ? "row-reverse" : "row", alignItems: "center", justifyContent: "center", gap: "var(--space-8)",
        fontSize: s.fs, lineHeight: 1.2, textAlign: "center", background: fill, color: ink, boxShadow: shadow,
        transform: down && !off ? (hasEdge ? `translateY(${eh})` : `scale(var(${iconOnly ? "--press-scale-icon" : "--press-scale"}))`) : "none", marginBottom: hasEdge ? eh : undefined, transition: "transform var(--dur-press)", ...style }}>
      {(icon || loading) && (iconOnly || loading || icon) ? ic : null}
      {iconOnly ? null : (loading && !icon ? <span style={{ opacity: 0.7 }}>{children}</span> : children)}
    </button>
  );
}