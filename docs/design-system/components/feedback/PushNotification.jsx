import React from "react";
import { Icon } from "../atoms/Icon.jsx";
export function PushNotification({ app = "Приложение", appIcon = "notifications", time = "сейчас", title, body, actions = [], style }) {
  return (
    <div style={{ background: "var(--glass)", backdropFilter: "blur(var(--blur-glass))", WebkitBackdropFilter: "blur(var(--blur-glass))", borderRadius: "var(--radius-row)", padding: "var(--pad-inner)", display: "flex", flexDirection: "column", gap: "var(--space-12)", boxShadow: "var(--elev-2)", ...style }}>
      <div style={{ display: "grid", gridTemplateColumns: "auto minmax(0,1fr)", gap: "var(--space-12)", alignItems: "start" }}>
        <div style={{ width: 40, height: 40, borderRadius: "calc(var(--radius-row) - var(--pad-inner))", background: "var(--accent)", display: "flex", alignItems: "center", justifyContent: "center" }}><Icon name={appIcon} size={22} color="var(--on-accent)" /></div>
        <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-4)", minWidth: 0 }}>
          <div style={{ display: "flex", justifyContent: "space-between", gap: "var(--space-8)", flexWrap: "wrap" }}><span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{app}</span><span style={{ fontSize: "var(--fs-footnote)", color: "var(--text-secondary)" }}>{time}</span></div>
          <span style={{ fontSize: "var(--fs-subheadline)", fontWeight: 600 }}>{title}</span>
          <span style={{ fontSize: "var(--fs-subheadline)", lineHeight: 1.35 }}>{body}</span>
        </div>
      </div>
      {actions.length > 0 && <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--gap-cards)" }}>{actions.map((a) => <button key={a.label} type="button" onClick={a.onPress} style={{ flex: "1 0 auto", border: "none", cursor: "pointer", minHeight: "var(--size-hit)", padding: "0 var(--space-16)", borderRadius: "var(--radius-pill)", background: "var(--fill-2)", color: a.destructive ? "var(--status-error)" : "var(--text-primary)", fontSize: "var(--fs-subheadline)" }}>{a.label}</button>)}</div>}
    </div>
  );
}