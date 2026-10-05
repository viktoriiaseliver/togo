import React from "react";
export function Alert({ open = true, title, message, actions = [], inline = false, children, style }) {
  const row = React.useRef(null);
  const [tight, setTight] = React.useState(false);
  React.useLayoutEffect(() => { const el = row.current; if (!el || tight) return; if ([...el.children].some((b) => b.scrollWidth > b.clientWidth + 0.5)) setTight(true); });
  if (!open) return null;
  const stack = actions.length !== 2 || tight;
  const btn = (a, i) => (
    <button key={i} type="button" onClick={a.onPress} style={{ flex: 1, minWidth: 0, overflowWrap: "normal", border: "none", background: "none", cursor: "pointer", minHeight: 48, padding: "var(--space-12) var(--space-12)",
      fontSize: "var(--fs-body)", fontWeight: a.style === "cancel" ? 600 : 400, color: a.style === "destructive" ? "var(--status-error)" : "var(--accent-text)",
      borderTop: "1px solid var(--separator)", borderLeft: !stack && i > 0 ? "1px solid var(--separator)" : "none" }}>{a.label}</button>
  );
  const box = (
    <div role="alertdialog" aria-label={title} style={{ width: "min(300px, 100%)", background: "var(--fill-1)", borderRadius: "var(--radius-row)", overflow: "hidden", boxShadow: "var(--elev-2)", ...style }}>
      <div style={{ padding: "var(--space-20) var(--space-20) var(--space-16)", display: "flex", flexDirection: "column", gap: "var(--gap-cards)", textAlign: "center" }}>
        <span style={{ fontSize: "var(--fs-headline)", fontWeight: 600 }}>{title}</span>
        {message && <span style={{ fontSize: "var(--fs-footnote)", lineHeight: 1.35, color: "var(--text-secondary)" }}>{message}</span>}
        {children}
      </div>
      <div ref={row} style={{ display: "flex", flexDirection: stack ? "column" : "row" }}>{actions.map(btn)}</div>
    </div>
  );
  if (inline) return box;
  return <div style={{ position: "absolute", inset: 0, background: "var(--scrim)", display: "flex", alignItems: "center", justifyContent: "center", padding: "var(--space-20)", zIndex: 20 }}>{box}</div>;
}